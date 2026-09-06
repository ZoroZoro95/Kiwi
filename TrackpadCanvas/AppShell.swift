import AppKit
import WebKit
import Carbon

final class GlobalHotKey {
    enum RegistrationError: Error {
        case eventHandler(OSStatus)
        case hotKey(OSStatus)
    }

    private static let signature: OSType = 0x54504356 // TPCV
    private static let identifier: UInt32 = 1

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let action: () -> Void

    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_M),
        modifiers: UInt32 = UInt32(controlKey | optionKey),
        action: @escaping () -> Void
    ) throws {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr,
                      hotKeyID.signature == GlobalHotKey.signature,
                      hotKeyID.id == GlobalHotKey.identifier else {
                    return noErr
                }

                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                owner.action()
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerReference
        )

        guard handlerStatus == noErr else {
            throw RegistrationError.eventHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard registrationStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            throw RegistrationError.hotKey(registrationStatus)
        }
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }
}

final class EquationPreview: WKWebView, WKNavigationDelegate {
    private var pendingLatex = ""
    private var ready = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        guard let url = Bundle.main.url(forResource: "MathJax-tex-svg", withExtension: "js"),
              let script = try? String(contentsOf: url) else {
            loadHTMLString("Equation renderer is missing. Rebuild the app.", baseURL: nil)
            return
        }
        loadHTMLString("""
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
        <style>body{margin:0;background:#fff;color:#111;font:28px Georgia;}#equation{padding:14px;overflow:auto;text-align:center;} .hint{font:14px system-ui;color:#666}</style>
        <script>window.MathJax={startup:{typeset:false},tex:{packages:['base','ams','newcommand','noundefined']},svg:{fontCache:'none'},options:{enableMenu:false}};</script>
        <script>\(script)</script>
        </head><body><div id="equation" aria-live="polite"></div>
        <script>
        window.showEquation=function(latex){
          const area=document.getElementById('equation');
          area.replaceChildren();
          if(!latex){area.className='hint';area.textContent='Your formatted equation will appear here';return;}
          area.className='';
          try{MathJax.texReset();area.appendChild(MathJax.tex2svg(latex,{display:true}));}
          catch(e){area.className='hint';area.textContent='Unable to render this LaTeX. Check the expression below.';}
        };
        </script></body></html>
        """, baseURL: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ latex: String) {
        pendingLatex = latex
        guard ready, let data = try? JSONSerialization.data(withJSONObject: [latex]),
              let argument = String(data: data, encoding: .utf8) else { return }
        // Serialize user/model text as data, never interpolate it into HTML.
        evaluateJavaScript("MathJax.startup.promise.then(()=>window.showEquation(\(argument)[0]))", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        show(pendingLatex)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }
}

final class ComposerViewController: NSViewController, NSTextFieldDelegate {
    var onClose: (() -> Void)?

    private let recognitionService: RecognitionService
    private let clipboard: ClipboardWriting
    private let session = ComposerSession()

    private let canvasView = ComposerCanvasView()
    private let equationPreview = EquationPreview()
    private let latexField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "Write an equation to begin")
    private let touchModeButton = NSButton(title: "Start Trackpad", target: nil, action: nil)
    private let recognizeButton = NSButton(title: "Recognize", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy LaTeX", target: nil, action: nil)

    init(
        recognitionService: RecognitionService = GroqRecognitionService(),
        clipboard: ClipboardWriting = SystemClipboardWriter()
    ) {
        self.recognitionService = recognitionService
        self.clipboard = clipboard
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        configureInterface()
        connectActions()
        render(session.state)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(canvasView)
    }

    private func configureInterface() {
        let titleLabel = NSTextField(labelWithString: "Free Touch")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let shortcutLabel = NSTextField(
            labelWithString: "Draw: Control–K · Position: Space · Erase: hold E · Undo: ⌘Z · Stop: Escape"
        )
        shortcutLabel.textColor = .secondaryLabelColor

        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        touchModeButton.target = self
        touchModeButton.action = #selector(toggleDirectTouchMode)
        touchModeButton.bezelStyle = .rounded
        touchModeButton.keyEquivalent = "k"
        touchModeButton.keyEquivalentModifierMask = [.control]

        recognizeButton.target = self
        recognizeButton.action = #selector(recognizeEquation)
        recognizeButton.keyEquivalent = "\r"
        recognizeButton.bezelStyle = .rounded

        copyButton.target = self
        copyButton.action = #selector(copyLaTeX)
        copyButton.bezelStyle = .rounded

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearCanvas))
        clearButton.bezelStyle = .rounded

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeComposer))
        closeButton.bezelStyle = .rounded

        let settingsButton = NSButton(title: "Groq Settings…", target: self, action: #selector(showGroqSettings))
        settingsButton.bezelStyle = .rounded

        let buttonRow = NSStackView(
            views: [touchModeButton, clearButton, settingsButton, recognizeButton, copyButton, closeButton]
        )
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        statusLabel.isSelectable = true
        latexField.placeholderString = "LaTeX — edit here to correct the equation"
        latexField.delegate = self
        let stack = NSStackView(views: [titleLabel, shortcutLabel, canvasView, equationPreview, latexField, statusLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            canvasView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            canvasView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            equationPreview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            equationPreview.heightAnchor.constraint(equalToConstant: 100),
            latexField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func connectActions() {
        canvasView.onDocumentChange = { [weak self] document in
            self?.session.updateDocument(document)
        }
        canvasView.onDirectTouchModeChange = { [weak self] isActive in
            self?.renderDirectTouchMode(isActive)
        }
        session.onChange = { [weak self] state in
            self?.render(state)
            if case .failed(let message) = state, let window = self?.view.window,
               window.attachedSheet == nil {
                let alert = NSAlert()
                alert.messageText = "Recognition failed"
                alert.informativeText = message
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: window)
            }
        }
    }

    private func render(_ state: ComposerSession.State) {
        recognizeButton.isEnabled = session.canRecognize
        copyButton.isEnabled = session.canCopy
        if case .recognized(let result) = state {
            if latexField.stringValue != result.latex { latexField.stringValue = result.latex }
            latexField.isEnabled = true
            equationPreview.show(result.latex)
        } else {
            latexField.stringValue = ""
            latexField.isEnabled = false
            equationPreview.show("")
        }

        guard !canvasView.isDirectTouchModeActive else {
            statusLabel.stringValue = "Trackpad drawing is ON · Escape to release"
            return
        }

        switch state {
        case .empty:
            statusLabel.stringValue = "Write an equation to begin"
        case .drawing:
            statusLabel.stringValue = "Ready to recognize"
        case .recognizing:
            statusLabel.stringValue = "Recognizing…"
        case .recognized:
            statusLabel.stringValue = "Check the preview. Edit LaTeX below it to correct the equation."
        case .failed(let message):
            statusLabel.stringValue = "Error: \(message)"
        }
    }

    private func renderDirectTouchMode(_ isActive: Bool) {
        touchModeButton.title = isActive ? "Stop Trackpad" : "Start Trackpad"
        if isActive {
            statusLabel.stringValue = "Trackpad drawing is ON · Escape to release"
        } else {
            render(session.state)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        session.editLatex(latexField.stringValue)
    }

    @objc private func toggleDirectTouchMode() {
        canvasView.toggleDirectTouchMode()
    }

    @objc private func recognizeEquation() {
        canvasView.deactivateDirectTouchMode()
        var service = recognitionService
        if var groq = service as? GroqRecognitionService {
            groq.aspectRatio = Double(canvasView.bounds.width / max(1, canvasView.bounds.height))
            service = groq
        }
        Task { await session.recognize(using: service) }
    }

    @objc private func showGroqSettings() {
        deactivateDirectTouchMode()
        let alert = NSAlert()
        alert.messageText = "Groq recognition"
        alert.informativeText = "Get a key at console.groq.com/keys. Your key is stored in this Mac's Keychain. Clicking Recognize sends your drawing directly to Groq and uses your account's allowance. Internet access is required. Leave the field blank to keep your existing key."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "Paste a new Groq API key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove Saved Key")
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        defer { field.stringValue = "" }
        do {
            if response == .alertFirstButtonReturn {
                if !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try GroqKeyStore().save(field.stringValue)
                    statusLabel.stringValue = "Key saved. Draw an equation, then click Recognize."
                }
            } else if response == .alertThirdButtonReturn {
                try GroqKeyStore().remove()
                statusLabel.stringValue = "Groq key removed."
            }
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
        view.window?.makeFirstResponder(canvasView)
    }

    @objc private func copyLaTeX() {
        if session.copy(using: clipboard) {
            statusLabel.stringValue = "Copied LaTeX to clipboard"
        } else {
            NSSound.beep()
        }
    }

    @objc private func clearCanvas() {
        canvasView.clear()
    }

    @objc private func closeComposer() {
        deactivateDirectTouchMode()
        onClose?()
    }

    func deactivateDirectTouchMode() {
        canvasView.deactivateDirectTouchMode()
    }

    override func viewWillDisappear() {
        deactivateDirectTouchMode()
        super.viewWillDisappear()
    }
}

final class ComposerPanelController: NSWindowController, NSWindowDelegate {
    private let composerViewController: ComposerViewController

    init() {
        composerViewController = ComposerViewController()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 610),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Free Touch"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 720, height: 610)
        panel.contentViewController = composerViewController

        super.init(window: panel)
        panel.delegate = self
        composerViewController.onClose = { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showComposer() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func toggleComposer() {
        guard let window else { return }
        if window.isVisible {
            composerViewController.deactivateDirectTouchMode()
            window.orderOut(nil)
        } else {
            showComposer()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        composerViewController.deactivateDirectTouchMode()
        sender.orderOut(nil)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        composerViewController.deactivateDirectTouchMode()
    }
}
