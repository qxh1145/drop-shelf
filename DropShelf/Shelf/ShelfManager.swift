import AppKit
import Combine
import Darwin
import UniformTypeIdentifiers

@MainActor
final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedItemIDs: Set<UUID> = []
    @Published private(set) var isCreatingArchive = false

    private var panel: ShelfPanel?
    private var itemURLs: Set<URL> = []
    nonisolated private static let archiveQueue = DispatchQueue(
        label: "com.example.DropShelf.archive",
        qos: .utility
    )

    private init() {}

    var isShelfVisible: Bool {
        panel?.isVisible == true
    }

    func showShelf(near point: CGPoint) {
        if panel == nil {
            panel = ShelfPanel(manager: self)
        } else if panel?.contentView == nil {
            panel?.contentView = ShelfDropHostingView(manager: self)
        }

        panel?.position(near: point)
        panel?.orderFrontRegardless()
    }

    func clearAndCloseShelf() {
        items.removeAll(keepingCapacity: false)
        selectedItemIDs.removeAll(keepingCapacity: false)
        itemURLs.removeAll(keepingCapacity: false)
        ShelfIconCache.shared.removeAll()

        // Keep the lightweight NSPanel alive and reusable. Releasing a window
        // while AppKit is finishing a transform animation can crash. Its much
        // heavier SwiftUI tree is still detached after this button action ends.
        let panelToHide = panel
        panelToHide?.orderOut(nil)
        DispatchQueue.main.async { [weak self, weak panelToHide] in
            guard let self,
                  self.panel === panelToHide,
                  panelToHide?.isVisible == false else {
                return
            }
            panelToHide?.contentView = nil
        }
    }

    func removeItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        let removedURL = items[index].url
        items.remove(at: index)
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        }
        itemURLs.remove(removedURL)
        ShelfIconCache.shared.remove(urls: [removedURL])
    }

    func add(urls: [URL]) {
        var additions: [ShelfItem] = []
        additions.reserveCapacity(urls.count)

        for url in urls {
            let normalizedURL = url.standardizedFileURL
            guard normalizedURL.isFileURL,
                  itemURLs.insert(normalizedURL).inserted else {
                continue
            }
            additions.append(ShelfItem(url: normalizedURL))
        }

        guard !additions.isEmpty else { return }
        items.append(contentsOf: additions)
    }

    func selectItem(_ id: UUID, extendingSelection: Bool) {
        var newSelection = selectedItemIDs

        if extendingSelection {
            if newSelection.contains(id) {
                newSelection.remove(id)
            } else {
                newSelection.insert(id)
            }
        } else {
            newSelection = [id]
        }

        guard newSelection != selectedItemIDs else { return }
        selectedItemIDs = newSelection
    }

    func itemsForDrag(startingWith id: UUID, extendingSelection: Bool = false) -> [ShelfItem] {
        if !selectedItemIDs.contains(id) {
            selectItem(id, extendingSelection: extendingSelection)
        }

        return items.filter { selectedItemIDs.contains($0.id) }
    }

    func outboundDragDidSucceed(itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }

        let removedURLs = items.lazy
            .filter { itemIDs.contains($0.id) }
            .map(\.url)
        let removedURLArray = Array(removedURLs)

        items.removeAll { itemIDs.contains($0.id) }
        let newSelection = selectedItemIDs.subtracting(itemIDs)
        if newSelection != selectedItemIDs {
            selectedItemIDs = newSelection
        }
        itemURLs.subtract(removedURLArray)
        ShelfIconCache.shared.remove(urls: removedURLArray)
    }

    func airDropAllItems() {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }

        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            showAlert(
                title: "AirDrop is unavailable",
                message: "macOS could not start AirDrop for the files currently in the Shelf."
            )
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    func zipAllItems() {
        guard !items.isEmpty, !isCreatingArchive else { return }

        let sourceURLs = items.map(\.url)
        let savePanel = NSSavePanel()
        savePanel.title = "Zip All Shelf Items"
        savePanel.prompt = "Create ZIP"
        savePanel.nameFieldStringValue = "DropShelf.zip"
        savePanel.allowedContentTypes = [.zip]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first

        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK,
              let destinationURL = savePanel.url else {
            return
        }

        guard !Self.destination(destinationURL, overlaps: sourceURLs) else {
            showAlert(
                title: "Choose another location",
                message: "The ZIP cannot replace an item in the Shelf or be created inside a folder that is being zipped."
            )
            return
        }

        isCreatingArchive = true
        Self.archiveQueue.async { [weak self] in
            let result: ZipArchiveResult
            do {
                try ZipArchiver.createArchive(
                    from: sourceURLs,
                    at: destinationURL
                )
                result = .success(destinationURL)
            } catch {
                result = .failure(error.localizedDescription)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCreatingArchive = false

                switch result {
                case let .success(archiveURL):
                    NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
                case let .failure(message):
                    self.showAlert(
                        title: "Couldn’t create ZIP",
                        message: message
                    )
                }
            }
        }
    }

    private static func destination(_ destinationURL: URL, overlaps sourceURLs: [URL]) -> Bool {
        let destinationPath = destinationURL.standardizedFileURL.path

        for sourceURL in sourceURLs {
            let source = sourceURL.standardizedFileURL
            if source.path == destinationPath {
                return true
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               destinationPath.hasPrefix(source.path + "/") {
                return true
            }
        }

        return false
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum ZipArchiver {
    static func createArchive(from sourceURLs: [URL], at destinationURL: URL) throws {
        let fileManager = FileManager.default
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".DropShelf-\(UUID().uuidString).zip")

        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")

        // Change into each item's parent directory before adding it. This keeps
        // every item at the ZIP's top level instead of storing its full path,
        // while still allowing files from unrelated Finder folders.
        var arguments = ["--format", "zip", "-c", "-f", temporaryURL.path]
        arguments.reserveCapacity(5 + (sourceURLs.count * 3))
        for sourceURL in sourceURLs {
            arguments.append(contentsOf: [
                "-C",
                sourceURL.deletingLastPathComponent().path,
                "./\(sourceURL.lastPathComponent)"
            ])
        }
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = details.flatMap { $0.isEmpty ? nil : $0 }
                ?? "The archive tool exited with status \(process.terminationStatus)."
            throw ZipArchiveError.creationFailed(
                message
            )
        }

        var renameError: Int32 = 0
        temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let temporaryPath, let destinationPath else {
                    renameError = EINVAL
                    return
                }

                if Darwin.rename(temporaryPath, destinationPath) != 0 {
                    renameError = errno
                }
            }
        }

        if renameError != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: renameError) ?? .EIO)
        }
    }
}

private enum ZipArchiveResult: Sendable {
    case success(URL)
    case failure(String)
}

private enum ZipArchiveError: LocalizedError {
    case creationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .creationFailed(message):
            return message
        }
    }
}
