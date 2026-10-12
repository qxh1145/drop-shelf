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
}
