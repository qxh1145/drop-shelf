import AppKit

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var openSettingsHandler: (() -> Void)?

    init(openSettingsHandler: @escaping () -> Void) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        self.openSettingsHandler = openSettingsHandler
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "tray.and.arrow.down.fill",
                accessibilityDescription: "DropShelf"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DropShelf"
        }

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit DropShelf",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func invalidate() {
        guard let statusItem else { return }

        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        openSettingsHandler = nil
    }

    @objc private func openSettings() {
        openSettingsHandler?()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
