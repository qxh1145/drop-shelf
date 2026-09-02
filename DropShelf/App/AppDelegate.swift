import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let icon = Bundle.main.image(forResource: "AppIcon") ?? NSImage(named: "AppIconImage") ?? (Bundle.main.bundlePath.isEmpty ? nil : NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)) {
            NSApp.applicationIconImage = icon
        }

        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        menuBarController = MenuBarController { [weak self] in
            self?.showSettings()
        }

        ShakeDetector.shared.updateSensitivity(AppPreferences.shared.shakeSensitivity)

        ShakeDetector.shared.start {
            ShelfManager.shared.showShelf(near: NSEvent.mouseLocation)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShakeDetector.shared.stop()

        settingsWindowController?.close()
        settingsWindowController = nil

        menuBarController?.invalidate()
        menuBarController = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showSettings() {
        let controller: SettingsWindowController

        if let settingsWindowController {
            controller = settingsWindowController
        } else {
            controller = SettingsWindowController(preferences: .shared) { [weak self] in
                self?.settingsWindowController = nil
            }
            settingsWindowController = controller
        }

        controller.showSettings()
    }
}
