import Foundation

@MainActor
final class OnboardingManager {
    static let shared = OnboardingManager()

    private enum Constants {
        static let completedVersionKey = "DropShelf.onboarding.completedVersion"
        static let currentVersion = 1
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldPresentOnLaunch: Bool {
        defaults.integer(forKey: Constants.completedVersionKey)
            < Constants.currentVersion
    }

    func markCompleted() {
        defaults.set(
            Constants.currentVersion,
            forKey: Constants.completedVersionKey
        )
    }
}
