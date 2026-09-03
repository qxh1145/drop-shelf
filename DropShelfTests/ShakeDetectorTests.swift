import XCTest
@testable import DropShelf

@MainActor
final class ShakeDetectorTests: XCTestCase {
    func testThreeFastDirectionChangesTriggerShake() {
        let detector = ShakeDetector()
        let points: [CGFloat] = [500, 540, 500, 540, 500]

        let results = points.enumerated().map { index, x in
            detector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: Double(index) * 0.1
            )
        }

        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertTrue(results.last == true)
    }

    func testSlowMovementOutsideWindowDoesNotTriggerShake() {
        let detector = ShakeDetector()
        let points: [CGFloat] = [500, 540, 500, 540, 500]

        let results = points.enumerated().map { index, x in
            detector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: Double(index) * 0.3
            )
        }

        XCTAssertFalse(results.contains(true))
    }

    func testSmallJitterDoesNotTriggerShake() {
        let detector = ShakeDetector()
        let points: [CGFloat] = [500, 510, 499, 509, 500, 508, 501]

        let results = points.enumerated().map { index, x in
            detector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: Double(index) * 0.06
            )
        }

        XCTAssertFalse(results.contains(true))
    }

    func testHigherSensitivityRecognizesShorterShake() {
        let highSensitivityDetector = ShakeDetector(
            configuration: .init(sensitivity: 1)
        )
        let lowSensitivityDetector = ShakeDetector(
            configuration: .init(sensitivity: 0)
        )
        let points: [CGFloat] = [500, 524, 500, 524, 500]

        let highSensitivityResults = points.enumerated().map { index, x in
            highSensitivityDetector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: Double(index) * 0.1
            )
        }
        let lowSensitivityResults = points.enumerated().map { index, x in
            lowSensitivityDetector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: Double(index) * 0.1
            )
        }

        XCTAssertTrue(highSensitivityResults.contains(true))
        XCTAssertFalse(lowSensitivityResults.contains(true))
    }

    func testCooldownEventsDoNotSeedTheNextGesture() {
        let detector = ShakeDetector()
        let points: [CGFloat] = [500, 540, 500, 540, 500]

        let firstGesture = points.enumerated().map { index, x in
            detector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: Double(index) * 0.1
            )
        }
        let cooldownGesture = points.enumerated().map { index, x in
            detector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: 0.5 + (Double(index) * 0.1)
            )
        }
        let laterGesture = points.enumerated().map { index, x in
            detector.process(
                point: CGPoint(x: x, y: 300),
                timestamp: 1.3 + (Double(index) * 0.1)
            )
        }

        XCTAssertEqual(firstGesture.filter { $0 }.count, 1)
        XCTAssertFalse(cooldownGesture.contains(true))
        XCTAssertEqual(laterGesture.filter { $0 }.count, 1)
    }

    func testOutOfOrderTimestampResetsCandidate() {
        let detector = ShakeDetector()

        XCTAssertFalse(detector.process(point: CGPoint(x: 500, y: 300), timestamp: 1.0))
        XCTAssertFalse(detector.process(point: CGPoint(x: 540, y: 300), timestamp: 1.1))
        XCTAssertFalse(detector.process(point: CGPoint(x: 500, y: 300), timestamp: 0.9))
        XCTAssertFalse(detector.process(point: CGPoint(x: 540, y: 300), timestamp: 1.2))
        XCTAssertFalse(detector.process(point: CGPoint(x: 500, y: 300), timestamp: 1.3))
    }

    func testDenseInputRemainsStableAndDoesNotTurnMonotonicMotionIntoShake() {
        let detector = ShakeDetector()
        var didTrigger = false

        for index in 0..<100_000 {
            didTrigger = detector.process(
                point: CGPoint(x: CGFloat(index), y: 300),
                timestamp: Double(index) * 0.001
            ) || didTrigger
        }

        XCTAssertFalse(didTrigger)
    }
}

@MainActor
final class ShelfManagerTests: XCTestCase {
    func testIndividualRemovalAndClearBehaviors() throws {
        let manager = ShelfManager.shared
        manager.clearAndCloseShelf()
        manager.add(urls: [
            URL(fileURLWithPath: "/tmp/first.txt"),
            URL(fileURLWithPath: "/tmp/second.txt")
        ])

        XCTAssertEqual(manager.items.count, 2)

        let firstItemID = try XCTUnwrap(manager.items.first?.id)
        manager.removeItem(id: firstItemID)

        XCTAssertEqual(manager.items.count, 1)
        XCTAssertEqual(manager.items.first?.url.lastPathComponent, "second.txt")

        let lastItemID = try XCTUnwrap(manager.items.first?.id)
        manager.removeItem(id: lastItemID)

        XCTAssertTrue(manager.items.isEmpty)

        manager.add(urls: [URL(fileURLWithPath: "/tmp/third.txt")])
        manager.clearAndCloseShelf()

        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertTrue(manager.selectedItemIDs.isEmpty)
    }

    func testDuplicateURLsAreStoredOnceAndCanBeAddedAgainAfterRemoval() throws {
        let manager = ShelfManager.shared
        manager.clearAndCloseShelf()
        let url = URL(fileURLWithPath: "/tmp/duplicate.txt")

        manager.add(urls: [url, url, url.standardizedFileURL])
        XCTAssertEqual(manager.items.count, 1)

        manager.removeItem(id: try XCTUnwrap(manager.items.first?.id))
        XCTAssertTrue(manager.items.isEmpty)

        manager.add(urls: [url])
        XCTAssertEqual(manager.items.count, 1)

        manager.clearAndCloseShelf()
    }

    func testCommandSelectionIsPreservedWhenDraggingSelectedItem() throws {
        let manager = ShelfManager.shared
        manager.clearAndCloseShelf()
        manager.add(urls: [
            URL(fileURLWithPath: "/tmp/first.txt"),
            URL(fileURLWithPath: "/tmp/second.txt"),
            URL(fileURLWithPath: "/tmp/third.txt")
        ])
        defer { manager.clearAndCloseShelf() }

        let firstID = manager.items[0].id
        let secondID = manager.items[1].id
        let thirdID = manager.items[2].id

        manager.selectItem(firstID, extendingSelection: false)
        manager.selectItem(secondID, extendingSelection: true)

        let selectedDrag = manager.itemsForDrag(startingWith: secondID)
        XCTAssertEqual(Set(selectedDrag.map(\.id)), [firstID, secondID])
        XCTAssertEqual(manager.selectedItemIDs, [firstID, secondID])

        let extendedDrag = manager.itemsForDrag(
            startingWith: thirdID,
            extendingSelection: true
        )
        XCTAssertEqual(Set(extendedDrag.map(\.id)), [firstID, secondID, thirdID])
    }

    func testShelfCanBeClosedAndShownAgainWithoutTerminatingTheApp() {
        let manager = ShelfManager.shared
        manager.clearAndCloseShelf()

        manager.showShelf(near: CGPoint(x: 200, y: 200))
        XCTAssertTrue(manager.isShelfVisible)

        manager.clearAndCloseShelf()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(manager.isShelfVisible)

        manager.showShelf(near: CGPoint(x: 220, y: 220))
        XCTAssertTrue(manager.isShelfVisible)

        manager.clearAndCloseShelf()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    func testClosingTheLastWindowDoesNotQuitDropShelf() {
        let delegate = AppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    func testSingleInstancePolicyOnlyTerminatesOlderProcesses() {
        let currentLaunchDate = Date(timeIntervalSince1970: 200)

        XCTAssertTrue(
            SingleInstancePolicy.shouldTerminate(
                otherPID: 100,
                otherLaunchDate: Date(timeIntervalSince1970: 100),
                currentPID: 200,
                currentLaunchDate: currentLaunchDate
            )
        )
        XCTAssertFalse(
            SingleInstancePolicy.shouldTerminate(
                otherPID: 300,
                otherLaunchDate: Date(timeIntervalSince1970: 300),
                currentPID: 200,
                currentLaunchDate: currentLaunchDate
            )
        )
        XCTAssertFalse(
            SingleInstancePolicy.shouldTerminate(
                otherPID: 200,
                otherLaunchDate: currentLaunchDate,
                currentPID: 200,
                currentLaunchDate: currentLaunchDate
            )
        )
        XCTAssertTrue(
            SingleInstancePolicy.shouldTerminate(
                otherPID: 199,
                otherLaunchDate: currentLaunchDate,
                currentPID: 200,
                currentLaunchDate: currentLaunchDate
            )
        )
    }
}

final class ZipArchiverTests: XCTestCase {
    func testArchiveContainsFilesAndFoldersAndReplacesExistingDestination() throws {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("DropShelfZipTests-\(UUID().uuidString)")
        let sourceDirectory = testDirectory.appendingPathComponent("Sources")
        let folderURL = sourceDirectory.appendingPathComponent("Folder")
        let fileURL = sourceDirectory.appendingPathComponent("first.txt")
        let nestedFileURL = folderURL.appendingPathComponent("nested.txt")
        let archiveURL = testDirectory.appendingPathComponent("DropShelf.zip")
        let extractionURL = testDirectory.appendingPathComponent("Extracted")

        defer { try? fileManager.removeItem(at: testDirectory) }

        try fileManager.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        try Data("first".utf8).write(to: fileURL)
        try Data("nested".utf8).write(to: nestedFileURL)
        try Data("old archive".utf8).write(to: archiveURL)

        try ZipArchiver.createArchive(
            from: [fileURL, folderURL],
            at: archiveURL
        )

        try fileManager.createDirectory(
            at: extractionURL,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extractionURL.path]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: extractionURL.appendingPathComponent("first.txt").path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: extractionURL
                    .appendingPathComponent("Folder/nested.txt")
                    .path
            )
        )
    }
}

final class SettingsViewTests: XCTestCase {
    func testAppIconCanBeResolved() {
        let icon = NSImage(named: "AppIconImage") ?? Bundle.main.image(forResource: "AppIcon") ?? Bundle(for: AppDelegate.self).image(forResource: "AppIcon")
        XCTAssertNotNil(icon)
        XCTAssertTrue(icon?.isValid == true)
    }

    @MainActor
    func testSettingsViewCanBeInstantiated() {
        let view = SettingsView(preferences: .shared)
        _ = view.body
    }
}
