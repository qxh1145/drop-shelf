import Foundation
import ServiceManagement

private enum LoginItemCommand: Sendable {
    case refresh
    case setEnabled(Bool)
}

private struct LoginItemResult: Sendable {
    let status: SMAppService.Status
    let errorMessage: String?
}

private struct LoginItemServiceWorker: Sendable {
    private let queue = DispatchQueue(
        label: "com.example.DropShelf.login-item",
        qos: .utility
    )

    func perform(
        _ command: LoginItemCommand,
        completion: @escaping @Sendable (LoginItemResult) -> Void
    ) {
        queue.async {
            let result = autoreleasepool {
                let service = SMAppService.mainApp
                var errorMessage: String?

                if case let .setEnabled(enabled) = command {
                    do {
                        if enabled {
                            try service.register()
                        } else {
                            try service.unregister()
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                return LoginItemResult(
                    status: service.status,
                    errorMessage: errorMessage
                )
            }

            completion(result)
        }
    }
}

enum AppBehaviorPreferenceChange {
    case shakeGesture
    case activationShortcut
    case dockVisibility
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Keys {
        static let shakeSensitivity = "DropShelf.shakeSensitivity"
        static let closeShelfWhenEmpty = "DropShelf.closeShelfWhenEmpty"
        static let automaticallyHideAfterTenSeconds = "DropShelf.automaticallyHideAfterTenSeconds"
        static let shakeGestureEnabled = "DropShelf.shakeGestureEnabled"
        static let activationShortcut = "DropShelf.activationShortcut"
        static let showInDock = "DropShelf.showInDock"
    }

    @Published private(set) var shakeSensitivity: Double
    @Published private(set) var shakeGestureEnabled: Bool
    @Published private(set) var activationShortcut: ShelfActivationShortcut
    @Published private(set) var activationShortcutError: String?
    @Published private(set) var showInDock: Bool
    @Published private(set) var closeShelfWhenEmpty: Bool
    @Published private(set) var automaticallyHideAfterTenSeconds: Bool
    @Published private(set) var loginItemStatus: SMAppService.Status
    @Published private(set) var loginItemError: String?

    var shelfBehaviorDidChange: (() -> Void)?
    var appBehaviorDidChange: ((AppBehaviorPreferenceChange) -> Void)?

    private let defaults: UserDefaults
    private lazy var loginItemWorker = LoginItemServiceWorker()
    private var loginItemRequestID: UInt = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.shakeSensitivity) == nil {
            shakeSensitivity = 0.5
        } else {
            shakeSensitivity = defaults.double(forKey: Keys.shakeSensitivity)
        }

        if defaults.object(forKey: Keys.shakeGestureEnabled) == nil {
            shakeGestureEnabled = true
        } else {
            shakeGestureEnabled = defaults.bool(forKey: Keys.shakeGestureEnabled)
        }

        if let shortcutData = defaults.data(forKey: Keys.activationShortcut),
           let storedShortcut = try? JSONDecoder().decode(
               ShelfActivationShortcut.self,
               from: shortcutData
           ) {
            activationShortcut = storedShortcut
        } else {
            activationShortcut = .defaultShortcut
        }
        activationShortcutError = nil

        if defaults.object(forKey: Keys.showInDock) == nil {
            showInDock = false
        } else {
            showInDock = defaults.bool(forKey: Keys.showInDock)
        }

        if defaults.object(forKey: Keys.closeShelfWhenEmpty) == nil {
            closeShelfWhenEmpty = true
        } else {
            closeShelfWhenEmpty = defaults.bool(forKey: Keys.closeShelfWhenEmpty)
        }

        if defaults.object(forKey: Keys.automaticallyHideAfterTenSeconds) == nil {
            automaticallyHideAfterTenSeconds = false
        } else {
            automaticallyHideAfterTenSeconds = defaults.bool(
                forKey: Keys.automaticallyHideAfterTenSeconds
            )
        }

        loginItemStatus = .notRegistered
    }

    var launchAtLoginEnabled: Bool {
        switch loginItemStatus {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var loginItemStatusMessage: String? {
        if let loginItemError {
            return loginItemError
        }

        if loginItemStatus == .requiresApproval {
            return "Approval is required in System Settings → General → Login Items."
        }

        return nil
    }

    var sensitivityLabel: String {
        switch shakeSensitivity {
        case ..<0.34:
            return "Low"
        case 0.67...:
            return "High"
        default:
            return "Balanced"
        }
    }

    func setShakeSensitivity(_ value: Double) {
        let clampedValue = min(max(value, 0), 1)
        guard clampedValue != shakeSensitivity else { return }

        shakeSensitivity = clampedValue
        defaults.set(clampedValue, forKey: Keys.shakeSensitivity)
        ShakeDetector.shared.updateSensitivity(clampedValue)
    }

    func setShakeGestureEnabled(_ enabled: Bool) {
        guard enabled != shakeGestureEnabled else { return }

        shakeGestureEnabled = enabled
        defaults.set(enabled, forKey: Keys.shakeGestureEnabled)
        appBehaviorDidChange?(.shakeGesture)
    }

    func setActivationShortcut(_ shortcut: ShelfActivationShortcut) {
        guard shortcut != activationShortcut else { return }

        activationShortcut = shortcut
        activationShortcutError = nil
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Keys.activationShortcut)
        }
        appBehaviorDidChange?(.activationShortcut)
    }

    func setActivationShortcutRegistrationSucceeded(_ succeeded: Bool) {
        activationShortcutError = succeeded
            ? nil
            : "This shortcut is already used by macOS or another app. Choose a different one."
    }

    func setShowInDock(_ enabled: Bool) {
        guard enabled != showInDock else { return }

        showInDock = enabled
        defaults.set(enabled, forKey: Keys.showInDock)
        appBehaviorDidChange?(.dockVisibility)
    }

    func setCloseShelfWhenEmpty(_ enabled: Bool) {
        guard enabled != closeShelfWhenEmpty else { return }

        closeShelfWhenEmpty = enabled
        defaults.set(enabled, forKey: Keys.closeShelfWhenEmpty)
        shelfBehaviorDidChange?()
    }

    func setAutomaticallyHideAfterTenSeconds(_ enabled: Bool) {
        guard enabled != automaticallyHideAfterTenSeconds else { return }

        automaticallyHideAfterTenSeconds = enabled
        defaults.set(enabled, forKey: Keys.automaticallyHideAfterTenSeconds)
        shelfBehaviorDidChange?()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        loginItemStatus = enabled ? .enabled : .notRegistered
        enqueueLoginItemCommand(.setEnabled(enabled))
    }

    func refreshLoginItemStatus() {
        enqueueLoginItemCommand(.refresh)
    }

    private func enqueueLoginItemCommand(_ command: LoginItemCommand) {
        loginItemRequestID &+= 1
        let requestID = loginItemRequestID

        loginItemWorker.perform(command) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self, requestID == self.loginItemRequestID else { return }

                self.loginItemStatus = result.status
                if case .setEnabled = command {
                    self.loginItemError = result.errorMessage
                }
            }
        }
    }
}
