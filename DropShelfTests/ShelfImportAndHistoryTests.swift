import AppKit
import XCTest
@testable import DropShelf

final class ShelfImportAndHistoryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfImportAndHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testHistoryFollowsRenamedFile() throws {
        let suiteName = "ShelfImportAndHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = directory.appendingPathComponent("Report.txt")
        try Data("hi".utf8).write(to: original)
        let store = ShelfHistoryStore(defaults: defaults)
        _ = store.addingSnapshot(urls: [original], to: [])

        let renamed = directory.appendingPathComponent("Report Final.txt")
        try FileManager.default.moveItem(at: original, to: renamed)

        let entries = store.load()
        XCTAssertEqual(entries.first?.urls.map(\.lastPathComponent), ["Report Final.txt"])
    }

    func testTextBecomesTextFile() throws {
        let pasteboard = NSPasteboard(name: .init("ShelfImportTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("hello shelf", forType: .string)

        let urls = ShelfPasteboardImporter.materializeContent(from: pasteboard, in: directory)

        XCTAssertEqual(urls.first?.pathExtension, "txt")
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(urls.first)), "hello shelf")
    }

    func testWebLinkBecomesWebloc() throws {
        let pasteboard = NSPasteboard(name: .init("ShelfImportTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(string: "https://example.com/page")! as NSURL])

        let urls = ShelfPasteboardImporter.materializeContent(from: pasteboard, in: directory)

        let url = try XCTUnwrap(urls.first)
        XCTAssertEqual(url.lastPathComponent, "example.com.webloc")
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
                as? [String: String]
        )
        XCTAssertEqual(plist["URL"], "https://example.com/page")
    }

    func testRenamePlannerNumbersAndKeepsExtensions() {
        let urls = (1...10).map { URL(fileURLWithPath: "/tmp/folder/file\($0).jpg") }
        let planned = ShelfRenamePlanner.plannedURLs(for: urls, name: "Trip")
        XCTAssertEqual(planned.first?.lastPathComponent, "Trip 01.jpg")
        XCTAssertEqual(planned.last?.lastPathComponent, "Trip 10.jpg")
        XCTAssertEqual(planned.first?.deletingLastPathComponent().path, "/tmp/folder")

        let single = ShelfRenamePlanner.plannedURLs(
            for: [URL(fileURLWithPath: "/tmp/a.txt")],
            name: "b.md"
        )
        XCTAssertEqual(single.map(\.lastPathComponent), ["b.md"])
        XCTAssertNotNil(ShelfRenamePlanner.validationError(for: "a/b"))
        XCTAssertNotNil(ShelfRenamePlanner.validationError(for: "  "))
        XCTAssertNil(ShelfRenamePlanner.validationError(for: "Report"))
    }

    @MainActor
    func testBatchRenameMovesFilesAndUpdatesShelf() throws {
        let first = directory.appendingPathComponent("a.png")
        let second = directory.appendingPathComponent("b.txt")
        try Data("1".utf8).write(to: first)
        try Data("2".utf8).write(to: second)
        let manager = makeIsolatedManager()
        manager.add(urls: [first, second])

        XCTAssertNil(manager.renameItems(manager.items, to: "Doc"))

        XCTAssertEqual(manager.items.map(\.url.lastPathComponent), ["Doc 1.png", "Doc 2.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(try String(contentsOf: manager.items[1].url), "2")
    }

    @MainActor
    func testRenameCollisionLeavesEveryFileUntouched() throws {
        let first = directory.appendingPathComponent("a.txt")
        let second = directory.appendingPathComponent("b.txt")
        let taken = directory.appendingPathComponent("Doc 2.txt")
        for url in [first, second, taken] {
            try Data().write(to: url)
        }
        let manager = makeIsolatedManager()
        manager.add(urls: [first, second])

        XCTAssertNotNil(manager.renameItems(manager.items, to: "Doc"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(manager.items.map(\.url), [first, second].map(\.standardizedFileURL))
    }

    @MainActor
    func testNewShelfOpensBesideActiveShelfAndSharesHistory() throws {
        let file = directory.appendingPathComponent("shared.txt")
        try Data().write(to: file)
        let primary = ShelfManager.shared
        primary.clearAndCloseShelf()
        primary.showShelf(near: CGPoint(x: 300, y: 300))
        primary.add(urls: [file])

        ShelfManager.openNewShelf()
        let second = ShelfManager.active
        defer {
            second.clearAndCloseShelf()
            primary.clearAndCloseShelf()
        }

        XCTAssertFalse(second === primary)
        XCTAssertTrue(second.isShelfVisible)
        XCTAssertTrue(primary.isShelfVisible)
        XCTAssertTrue(second.items.isEmpty)

        // Opening again while the new Shelf is still empty reuses it.
        ShelfManager.openNewShelf()
        XCTAssertTrue(ShelfManager.active === second)

        primary.toggleCurrentShelfPin()
        XCTAssertEqual(second.historyEntries, primary.historyEntries)
        primary.toggleCurrentShelfPin()
    }

    @MainActor
    private func makeIsolatedManager() -> ShelfManager {
        let suiteName = "ShelfImportAndHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return ShelfManager(historyStore: ShelfHistoryStore(defaults: defaults))
    }
}
