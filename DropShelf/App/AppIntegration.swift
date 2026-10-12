import AppIntents
import AppKit

extension ShelfManager {
    /// Adds files arriving from outside the app (Services, URL scheme,
    /// Open With, Shortcuts) to the active Shelf, showing it if hidden.
    static func receive(_ urls: [URL]) {
        let fileURLs = urls.filter {
            $0.isFileURL && FileManager.default.fileExists(atPath: $0.path)
        }
        guard !fileURLs.isEmpty else { return }

        let shelf = active
        if !shelf.isShelfVisible {
            shelf.showShelf(near: activationPoint)
        } else if shelf.isShowingHistory {
            shelf.hideHistory()
        }
        shelf.add(urls: fileURLs)
    }
}

/// `dropshelf://open`, `new`, `history`, and `add?path=/a&path=/b`.
enum ShelfURLCommand: Equatable {
    case open
    case newShelf
    case history
    case add([URL])

    init?(url: URL) {
        guard url.scheme?.lowercased() == "dropshelf" else { return nil }

        switch url.host?.lowercased() {
        case "open", nil:
            self = .open
        case "new":
            self = .newShelf
        case "history":
            self = .history
        case "add":
            let paths = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .filter { $0.name == "path" }
                .compactMap(\.value) ?? []
            self = .add(paths.map { URL(fileURLWithPath: $0) })
        default:
            return nil
        }
    }

    /// Files are added to the Shelf; `dropshelf:` links run their command.
    @MainActor
    static func handle(_ urls: [URL]) {
        ShelfManager.receive(urls.filter(\.isFileURL))

        for command in urls.compactMap(ShelfURLCommand.init(url:)) {
            switch command {
            case .open:
                ShelfManager.active.showShelf(near: ShelfManager.activationPoint)
            case .newShelf:
                ShelfManager.openNewShelf(near: NSEvent.mouseLocation)
            case .history:
                ShelfManager.active.showHistory(near: NSEvent.mouseLocation)
            case let .add(fileURLs):
                ShelfManager.receive(fileURLs)
            }
        }
    }
}

/// Backs the "Add to DropShelf" entries in the Services menu.
@MainActor
final class ShelfServicesProvider: NSObject {
    @objc func addToShelf(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = ShelfPasteboardImporter.fileURLs(from: pasteboard)
        guard !urls.isEmpty else {
            error.pointee = "DropShelf couldn’t read the selection." as NSString
            return
        }
        ShelfManager.receive(urls)
    }
}

// MARK: - Shortcuts

struct AddFilesToShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Files to DropShelf"
    static let description = IntentDescription("Puts files on the current Shelf.")

    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.item"])
    var files: [IntentFile]

    @MainActor
    func perform() async throws -> some IntentResult {
        var urls: [URL] = []
        var directory: URL?

        for file in files {
            if let url = file.fileURL, FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
                continue
            }
            // Files made inside a shortcut have no location; save their data.
            if directory == nil {
                directory = try ShelfPasteboardImporter.makeReceivedDirectory()
            }
            if let directory {
                let url = directory.appendingPathComponent(file.filename)
                try file.data.write(to: url, options: .withoutOverwriting)
                urls.append(url)
            }
        }

        ShelfManager.receive(urls)
        return .result()
    }
}

struct OpenShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Open DropShelf"
    static let description = IntentDescription("Shows the current Shelf.")

    @MainActor
    func perform() async throws -> some IntentResult {
        ShelfManager.active.showShelf(near: ShelfManager.activationPoint)
        return .result()
    }
}

struct NewShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "New DropShelf Shelf"
    static let description = IntentDescription("Opens an empty Shelf beside the current one.")

    @MainActor
    func perform() async throws -> some IntentResult {
        ShelfManager.openNewShelf(near: NSEvent.mouseLocation)
        return .result()
    }
}

struct DropShelfShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddFilesToShelfIntent(),
            phrases: ["Add files to \(.applicationName)"]
        )
        AppShortcut(
            intent: OpenShelfIntent(),
            phrases: ["Open \(.applicationName)"]
        )
        AppShortcut(
            intent: NewShelfIntent(),
            phrases: ["New \(.applicationName) Shelf"]
        )
    }
}
