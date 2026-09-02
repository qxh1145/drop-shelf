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

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Keys {
        static let shakeSensitivity = "DropShelf.shakeSensitivity"
    }

    @Published private(set) var shakeSensitivity: Double
    @Published private(set) var loginItemStatus: SMAppService.Status
    @Published private(set) var loginItemError: String?

    private let defaults: UserDefaults
    private lazy var loginItemWorker = LoginItemServiceWorker()
    private var loginItemRequestID: UInt = 0

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.shakeSensitivity) == nil {
            shakeSensitivity = 0.5
        } else {
            shakeSensitivity = defaults.double(forKey: Keys.shakeSensitivity)
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
