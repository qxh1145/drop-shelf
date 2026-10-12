import AppKit
import ImageIO
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

    func testResizeShrinksAndKeepsOriginal() throws {
        let source = try makeJPEG(width: 3000, height: 2000)
        let output = try ImageTools.apply(.resize(maxPixelSize: 1024), to: source)

        XCTAssertEqual(output.lastPathComponent, "photo (1024px).jpg")
        let properties = try imageProperties(of: output)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1024)
        XCTAssertEqual(try imageProperties(of: source)[kCGImagePropertyPixelWidth] as? Int, 3000)
        XCTAssertThrowsError(try ImageTools.apply(.resize(maxPixelSize: 4096), to: source)) {
            XCTAssertEqual($0 as? ImageToolError, .alreadySmaller(4096))
        }
    }

    func testRemoveMetadataDropsLocationButKeepsOrientation() throws {
        let source = try makeJPEG(
            width: 40,
            height: 20,
            properties: [
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 10.5,
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 106.7,
                    kCGImagePropertyGPSLongitudeRef: "E"
                ]
            ]
        )
        XCTAssertNotNil(try imageProperties(of: source)[kCGImagePropertyGPSDictionary])

        let output = try ImageTools.apply(.removeMetadata, to: source)

        let properties = try imageProperties(of: output)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int, 6)
    }

    func testCompressOnlyAcceptsLossyFormatsAndNeverOverwrites() throws {
        let source = try makeJPEG(width: 64, height: 64)
        let first = try ImageTools.apply(.compress, to: source)
        let second = try ImageTools.apply(.compress, to: source)
        XCTAssertEqual(first.lastPathComponent, "photo (compressed).jpg")
        XCTAssertEqual(second.lastPathComponent, "photo (compressed) 2.jpg")

        let png = directory.appendingPathComponent("image.png")
        try writeImage(to: png, type: "public.png", width: 8, height: 8, properties: [:])
        XCTAssertThrowsError(try ImageTools.apply(.compress, to: png))
    }

    func testSnappedFramePullsNearEdgesFlush() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let nearRight = NSRect(x: 680, y: 300, width: 300, height: 200)
        XCTAssertEqual(ShelfPanel.snappedFrame(nearRight, in: screen).origin, CGPoint(x: 692, y: 300))

        let offBottomLeft = NSRect(x: -40, y: -10, width: 300, height: 200)
        XCTAssertEqual(ShelfPanel.snappedFrame(offBottomLeft, in: screen).origin, CGPoint(x: 8, y: 8))

        let middle = NSRect(x: 300, y: 300, width: 300, height: 200)
        XCTAssertEqual(ShelfPanel.snappedFrame(middle, in: screen), middle)
    }

    private func makeJPEG(
        width: Int,
        height: Int,
        properties: [CFString: Any] = [:]
    ) throws -> URL {
        let url = directory.appendingPathComponent("photo.jpg")
        try writeImage(to: url, type: "public.jpeg", width: width, height: height, properties: properties)
        return url
    }

    private func writeImage(
        to url: URL,
        type: String,
        width: Int,
        height: Int,
        properties: [CFString: Any]
    ) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func imageProperties(of url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func testURLCommandsParse() {
        XCTAssertEqual(ShelfURLCommand(url: URL(string: "dropshelf://open")!), .open)
        XCTAssertEqual(ShelfURLCommand(url: URL(string: "dropshelf:")!), .open)
        XCTAssertEqual(ShelfURLCommand(url: URL(string: "DropShelf://NEW")!), .newShelf)
        XCTAssertEqual(ShelfURLCommand(url: URL(string: "dropshelf://history")!), .history)
        XCTAssertEqual(
            ShelfURLCommand(url: URL(string: "dropshelf://add?path=/tmp/a%20b.txt&path=/tmp/c")!),
            .add([URL(fileURLWithPath: "/tmp/a b.txt"), URL(fileURLWithPath: "/tmp/c")])
        )
        XCTAssertNil(ShelfURLCommand(url: URL(string: "dropshelf://delete")!))
        XCTAssertNil(ShelfURLCommand(url: URL(string: "https://open")!))
    }

    @MainActor
    func testReceiveAddsOnlyExistingFilesToActiveShelf() throws {
        let file = directory.appendingPathComponent("from-service.txt")
        try Data().write(to: file)
        let shelf = ShelfManager.active
        shelf.clearAndCloseShelf()
        defer { shelf.clearAndCloseShelf() }

        ShelfManager.receive([file, directory.appendingPathComponent("missing.txt")])

        XCTAssertEqual(shelf.items.map(\.url), [file.standardizedFileURL])
        XCTAssertTrue(shelf.isShelfVisible)
    }

    @MainActor
    func testSearchFiltersItemsSelectionAndHistory() throws {
        let manager = makeIsolatedManager()
        manager.add(urls: ["Invoice.pdf", "photo.jpg", "invoice-2.pdf"].map {
            URL(fileURLWithPath: "/tmp/\($0)")
        })
        manager.selectAllItems()

        manager.toggleSearch()
        manager.setSearchText("invoice")

        XCTAssertEqual(manager.visibleItems.map(\.url.lastPathComponent), ["Invoice.pdf", "invoice-2.pdf"])
        XCTAssertEqual(manager.selectedItemIDs, Set(manager.visibleItems.map(\.id)))
        XCTAssertEqual(manager.bulkActionItemCount, 2)

        manager.toggleSearch()
        XCTAssertEqual(manager.searchText, "")
        XCTAssertEqual(manager.visibleItems.count, 3)
    }

    @MainActor
    func testShelfPanelGrowsForSearchField() {
        let panel = ShelfPanel(manager: makeIsolatedManager())
        panel.updateLayout(itemCount: 1, selectionCount: 0, showingHistory: false, showingSearch: true, animated: false)
        XCTAssertEqual(panel.frame.size, NSSize(width: 310, height: 252))
    }

    func testUpdateVersionComparison() {
        XCTAssertTrue(UpdateVersion.isNewer("v1.10.0", than: "1.9.3"))
        XCTAssertTrue(UpdateVersion.isNewer("v2", than: "1.99.99"))
        XCTAssertFalse(UpdateVersion.isNewer("v1.8.0", than: "1.8.0"))
        XCTAssertFalse(UpdateVersion.isNewer("v1.8", than: "1.8.0"))
        XCTAssertFalse(UpdateVersion.isNewer("v1.7.9", than: "1.8.0"))
        XCTAssertFalse(UpdateVersion.isNewer("v1.8.0-beta", than: "1.8.0"))
        XCTAssertEqual(UpdateVersion.displayString("v1.8.0"), "1.8.0")
    }

    func testVietnameseAndEnglishPluralLocalizations() throws {
        let appBundle = Bundle(for: ShelfManager.self)
        let vi = try XCTUnwrap(appBundle.path(forResource: "vi", ofType: "lproj").flatMap(Bundle.init(path:)))
        XCTAssertEqual(vi.localizedString(forKey: "Recent Shelves", value: nil, table: nil), "Kệ gần đây")

        let en = try XCTUnwrap(appBundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        let format = en.localizedString(forKey: "%lld items", value: nil, table: nil)
        let english = Locale(identifier: "en")
        XCTAssertEqual(String(format: format, locale: english, 1), "1 item")
        XCTAssertEqual(String(format: format, locale: english, 3), "3 items")
    }

    func testItemAccessibilityValueStatesSelectionAndKind() throws {
        let file = directory.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)
        let kind = try XCTUnwrap(
            file.resourceValues(forKeys: [.localizedTypeDescriptionKey]).localizedTypeDescription
        )

        XCTAssertEqual(ShelfItemView.accessibilityValue(for: file, isSelected: false), kind)
        XCTAssertEqual(
            ShelfItemView.accessibilityValue(for: file, isSelected: true),
            "\(String(localized: "Selected")), \(kind)"
        )
    }
}
