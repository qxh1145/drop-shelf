import XCTest
@testable import DropShelf

@MainActor
final class OnboardingManagerTests: XCTestCase {
    func testCompletionIsVersionedAndPersisted() throws {
        let suiteName = "OnboardingManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = OnboardingManager(defaults: defaults)
        XCTAssertTrue(manager.shouldPresentOnLaunch)

        manager.markCompleted()

        XCTAssertFalse(manager.shouldPresentOnLaunch)
        XCTAssertFalse(OnboardingManager(defaults: defaults).shouldPresentOnLaunch)
    }
}
