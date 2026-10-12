import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private var closeHandler: (() -> Void)?

    init(
        manager: OnboardingManager,
        preferences: AppPreferences,
        onClose: @escaping () -> Void
    ) {
        closeHandler = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to DropShelf")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(
                preferences: preferences,
                finish: { [weak self, weak manager] in
                    manager?.markCompleted()
                    self?.close()
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showOnboarding() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        let handler = closeHandler
        closeHandler = nil
        DispatchQueue.main.async {
            handler?()
        }
    }
}
