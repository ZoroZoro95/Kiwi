//
//  AppDelegate.swift
//  TrackpadCanvas
//
//  Created by Siddharth Lalwani on 22/01/26.
//

import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var composerPanelController: ComposerPanelController?
    private var globalHotKey: GlobalHotKey?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()

        let panelController = ComposerPanelController()
        composerPanelController = panelController
        configureStatusItem()

        do {
            globalHotKey = try GlobalHotKey { [weak panelController] in
                panelController?.toggleComposer()
            }
        } catch {
            showShortcutRegistrationFailure(error)
        }

        panelController.showComposer()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func showComposer() {
        composerPanelController?.showComposer()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Free Touch")
        applicationMenu.addItem(withTitle: "Quit Free Touch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        // Nil targets route editing actions to the focused field, including
        // the secure field editor in the Groq settings dialog.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "function",
            accessibilityDescription: "Free Touch"
        )

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open Free Touch",
            action: #selector(showComposer),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Free Touch",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func showShortcutRegistrationFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Global shortcut unavailable"
        alert.informativeText = "Use the menu-bar icon to open Free Touch. \(error)"
        alert.runModal()
    }

}
