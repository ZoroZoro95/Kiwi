import AppKit
import CoreGraphics

final class ComposerCanvasView: NSView {
    private(set) var document = InkDocument() {
        didSet { needsDisplay = true }
    }

    var onDocumentChange: ((InkDocument) -> Void)?
    var onDirectTouchModeChange: ((Bool) -> Void)?

    private var activePoints: [InkPoint] = []
    private var fingerPoint: InkPoint?
    private(set) var isPositioning = false
    private(set) var isErasing = false
    private var undoHistory: [InkDocument] = []
    private var eraserGestureRecorded = false
    private let eraserRadius: CGFloat = 14
    private var activeTouchIdentity: (NSObjectProtocol & NSCopying)?
    private var cursorPositionBeforeDirectMode: CGPoint?
    private let minimumPointDistance = 0.002
    private(set) var isDirectTouchModeActive = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureInput()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureInput()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()
        draw(strokes: document.strokes.map(\.points), lineWidth: 2.2)
        draw(strokes: [activePoints], lineWidth: 2.2)

        if document.isEmpty && activePoints.isEmpty {
            drawEmptyHint()
        }
        if isDirectTouchModeActive, let fingerPoint {
            let center = viewPoint(from: fingerPoint)
            let color: NSColor = isPositioning ? .systemOrange : (isErasing ? .systemRed : .systemBlue)
            let radius: CGFloat = isErasing && !isPositioning ? eraserRadius : 6
            color.withAlphaComponent(0.2).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)).fill()
            color.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    override func touchesBegan(with event: NSEvent) {
        guard isDirectTouchModeActive else { return }
        let touches = event.touches(matching: .touching, in: self)
        guard touches.count == 1, let touch = touches.first else {
            cancelActiveStroke()
            return
        }

        activeTouchIdentity = touch.identity
        trackFinger(at: touch.normalizedPosition, timestamp: event.timestamp)
    }

    override func touchesMoved(with event: NSEvent) {
        guard isDirectTouchModeActive else { return }
        guard let activeTouchIdentity else { return }
        let touches = event.touches(matching: .touching, in: self)
        guard let touch = touches.first(where: { $0.identity.isEqual(activeTouchIdentity) }) else {
            return
        }

        trackFinger(at: touch.normalizedPosition, timestamp: event.timestamp)
    }

    override func touchesEnded(with event: NSEvent) {
        guard isDirectTouchModeActive else { return }
        guard let activeTouchIdentity else { return }
        let endedTouches = event.touches(matching: .ended, in: self)
        guard endedTouches.contains(where: { $0.identity.isEqual(activeTouchIdentity) }) else {
            return
        }

        finishActiveStroke()
        eraserGestureRecorded = false
        self.activeTouchIdentity = nil
        fingerPoint = nil
    }

    override func touchesCancelled(with event: NSEvent) {
        cancelActiveStroke()
    }

    override func keyDown(with event: NSEvent) {
        if isDirectTouchModeActive, event.keyCode == 14,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            setErasing(true, timestamp: event.timestamp)
            return
        }
        if isDirectTouchModeActive, event.keyCode == 49 {
            setPositioning(true, timestamp: event.timestamp)
            return
        }
        if event.keyCode == 53 {
            deactivateDirectTouchMode()
            return
        }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.control), key == "k" {
            toggleDirectTouchMode()
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if isDirectTouchModeActive, event.keyCode == 14 {
            setErasing(false, timestamp: event.timestamp)
            return
        }
        if isDirectTouchModeActive, event.keyCode == 49 {
            setPositioning(false, timestamp: event.timestamp)
            return
        }
        super.keyUp(with: event)
    }

    // Shared by touch delivery and deterministic input-transition tests.
    func trackFinger(at position: NSPoint, timestamp: TimeInterval) {
        let previous = fingerPoint
        fingerPoint = makePoint(from: position, timestamp: timestamp)
        needsDisplay = true
        guard !isPositioning else { return }
        if isErasing {
            if let point = fingerPoint { erase(from: previous ?? point, to: point) }
            return
        }
        if activePoints.isEmpty { startStroke(at: position, timestamp: timestamp) }
        else { appendPoint(at: position, timestamp: timestamp) }
    }

    func setPositioning(_ enabled: Bool, timestamp: TimeInterval) {
        guard enabled != isPositioning else { return }
        if enabled { finishActiveStroke() }
        isPositioning = enabled
        if !enabled, let point = fingerPoint {
            if isErasing { erase(from: point, to: point) }
            else { startStroke(at: NSPoint(x: point.x, y: point.y), timestamp: timestamp) }
        }
        needsDisplay = true
    }

    func setErasing(_ enabled: Bool, timestamp: TimeInterval) {
        guard enabled != isErasing else { return }
        if enabled { finishActiveStroke() }
        isErasing = enabled
        eraserGestureRecorded = false
        if !isPositioning, let point = fingerPoint {
            if enabled { erase(from: point, to: point) }
            else { startStroke(at: NSPoint(x: point.x, y: point.y), timestamp: timestamp) }
        }
        needsDisplay = true
    }

    @objc func undo(_ sender: Any?) {
        if !activePoints.isEmpty {
            cancelActiveStroke()
            return
        }
        cancelActiveStroke()
        guard let previous = undoHistory.popLast() else { return }
        document = previous
        publishDocumentChange()
    }

    private func recordUndo() {
        undoHistory.append(document)
        if undoHistory.count > 100 { undoHistory.removeFirst() }
    }

    private func erase(from start: InkPoint, to end: InkPoint) {
        let a = viewPoint(from: start)
        let b = viewPoint(from: end)
        let steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 3)))
        let samples = (0...steps).map { step in
            CGPoint(x: a.x + (b.x - a.x) * CGFloat(step) / CGFloat(steps),
                    y: a.y + (b.y - a.y) * CGFloat(step) / CGFloat(steps))
        }
        let retained = document.strokes.filter { stroke in
            guard let first = stroke.points.first else { return true }
            let origin = viewPoint(from: first)
            if stroke.points.count == 1 {
                return !samples.contains { hypot($0.x - origin.x, $0.y - origin.y) <= eraserRadius }
            }
            let path = CGMutablePath()
            path.move(to: origin)
            for point in stroke.points.dropFirst() { path.addLine(to: viewPoint(from: point)) }
            let hitArea = path.copy(strokingWithWidth: eraserRadius * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            return !samples.contains { hitArea.contains($0) }
        }
        guard retained.count != document.strokes.count else { return }
        if !eraserGestureRecorded {
            recordUndo()
            eraserGestureRecorded = true
        }
        document = InkDocument(strokes: retained)
        publishDocumentChange()
    }

    override func resignFirstResponder() -> Bool {
        deactivateDirectTouchMode()
        return super.resignFirstResponder()
    }

    func toggleDirectTouchMode() {
        if isDirectTouchModeActive {
            deactivateDirectTouchMode()
        } else {
            activateDirectTouchMode()
        }
    }

    func activateDirectTouchMode() {
        guard !isDirectTouchModeActive else { return }
        guard let canvasCursorPosition = canvasCenterInQuartzCoordinates() else { return }

        cursorPositionBeforeDirectMode = CGEvent(source: nil)?.location
        CGWarpMouseCursorPosition(canvasCursorPosition)
        isDirectTouchModeActive = true
        window?.makeFirstResponder(self)
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
        onDirectTouchModeChange?(true)
        needsDisplay = true
    }

    func deactivateDirectTouchMode() {
        guard isDirectTouchModeActive else { return }
        cancelActiveStroke()
        isPositioning = false
        isErasing = false
        isDirectTouchModeActive = false
        CGAssociateMouseAndMouseCursorPosition(1)
        if let cursorPositionBeforeDirectMode {
            CGWarpMouseCursorPosition(cursorPositionBeforeDirectMode)
        }
        cursorPositionBeforeDirectMode = nil
        NSCursor.unhide()
        onDirectTouchModeChange?(false)
        needsDisplay = true
    }

    func clear() {
        cancelActiveStroke()
        guard !document.isEmpty else { return }
        recordUndo()
        document.clear()
        publishDocumentChange()
    }

    private func configureInput() {
        wantsLayer = true
        layer?.cornerRadius = 8
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
    }

    private func startStroke(at normalizedPosition: NSPoint, timestamp: TimeInterval) {
        activePoints.removeAll(keepingCapacity: true)
        guard let point = makePoint(from: normalizedPosition, timestamp: timestamp) else { return }
        activePoints.append(point)
        needsDisplay = true
    }

    private func appendPoint(at normalizedPosition: NSPoint, timestamp: TimeInterval) {
        guard let point = makePoint(from: normalizedPosition, timestamp: timestamp) else { return }

        if let previous = activePoints.last {
            let deltaX = point.x - previous.x
            let deltaY = point.y - previous.y
            if hypot(deltaX, deltaY) < minimumPointDistance { return }
        }

        activePoints.append(point)
        needsDisplay = true
    }

    private func finishActiveStroke() {
        defer {
            activePoints.removeAll(keepingCapacity: true)
            needsDisplay = true
        }

        guard !activePoints.isEmpty else { return }
        recordUndo()
        document.append(InkStroke(points: activePoints))
        publishDocumentChange()
    }

    private func cancelActiveStroke() {
        eraserGestureRecorded = false
        activePoints.removeAll(keepingCapacity: true)
        activeTouchIdentity = nil
        fingerPoint = nil
        needsDisplay = true
    }

    private func publishDocumentChange() {
        onDocumentChange?(document)
    }

    private func makePoint(from point: NSPoint, timestamp: TimeInterval) -> InkPoint? {
        InkPoint(
            x: Double(point.x),
            y: Double(point.y),
            timestamp: timestamp
        )
    }

    private func canvasCenterInQuartzCoordinates() -> CGPoint? {
        guard let window, let screen = window.screen else { return nil }

        let centerInWindow = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        let centerOnScreen = window.convertPoint(toScreen: centerInWindow)
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let displayID = screen.deviceDescription[screenNumberKey] as? CGDirectDisplayID else {
            return nil
        }

        let displayBounds = CGDisplayBounds(displayID)
        return CGPoint(
            x: displayBounds.minX + centerOnScreen.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - centerOnScreen.y
        )
    }

    private func draw(strokes: [[InkPoint]], lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: viewPoint(from: first))
            for point in stroke.dropFirst() {
                path.line(to: viewPoint(from: point))
            }

            if stroke.count == 1 {
                let center = viewPoint(from: first)
                let dot = NSRect(x: center.x - lineWidth / 2, y: center.y - lineWidth / 2, width: lineWidth, height: lineWidth)
                NSBezierPath(ovalIn: dot).fill()
            }
        }

        path.stroke()
    }

    private func viewPoint(from point: InkPoint) -> NSPoint {
        NSPoint(
            x: bounds.minX + CGFloat(point.x) * bounds.width,
            y: bounds.minY + CGFloat(point.y) * bounds.height
        )
    }

    private func drawEmptyHint() {
        let text = isDirectTouchModeActive
            ? "Glide to draw · Hold Space to position · Escape to stop"
            : "Press Control–K or Start Trackpad to draw without clicking"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }

    deinit {
        guard isDirectTouchModeActive else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        if let cursorPositionBeforeDirectMode {
            CGWarpMouseCursorPosition(cursorPositionBeforeDirectMode)
        }
        NSCursor.unhide()
    }
}
