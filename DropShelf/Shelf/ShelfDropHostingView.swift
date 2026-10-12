import AppKit
import SwiftUI

final class ShelfDropHostingView: NSView {
    private static let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private let manager: ShelfManager
    private let hostingView: NSHostingView<ShelfView>
    private var acceptedDragSequenceNumber: Int?
    private var acceptedDragOperation: NSDragOperation = []

    init(manager: ShelfManager) {
        self.manager = manager
        self.hostingView = NSHostingView(rootView: ShelfView(manager: manager))
        super.init(frame: .zero)

        registerForDraggedTypes(
            [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map {
                NSPasteboard.PasteboardType($0)
            } + ShelfPasteboardImporter.contentTypes
        )

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation: NSDragOperation

        if isInternalDrag(sender) {
            operation = []
        } else {
            operation = dropItemCount(from: sender) > 0 ? .copy : []
        }

        acceptedDragSequenceNumber = sender.draggingSequenceNumber
        acceptedDragOperation = operation
        manager.setDropTargetActive(
            !operation.isEmpty,
            itemCount: operation.isEmpty ? 0 : dropItemCount(from: sender)
        )
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptedDragSequenceNumber == sender.draggingSequenceNumber else { return [] }
        return acceptedDragOperation
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        resetDragAcceptance()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        resetDragAcceptance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { resetDragAcceptance() }

        guard acceptedDragSequenceNumber == sender.draggingSequenceNumber,
              !acceptedDragOperation.isEmpty,
              !isInternalDrag(sender) else {
            return false
        }

        let urls = fileURLs(from: sender)
        if !urls.isEmpty {
            (sender.draggingSource as? DraggableShelfItemView)?.wasDroppedOnShelf = true
            manager.add(urls: urls)
            return true
        }
        if receivePromisedFiles(from: sender) {
            return true
        }
        let materializedURLs = ShelfPasteboardImporter.materializeContent(
            from: sender.draggingPasteboard
        )
        manager.add(urls: materializedURLs)
        return !materializedURLs.isEmpty
    }

    private func dropItemCount(from sender: NSDraggingInfo) -> Int {
        let urlCount = fileURLs(from: sender).count
        if urlCount > 0 { return urlCount }
        let promiseCount = promiseReceivers(from: sender).count
        if promiseCount > 0 { return promiseCount }
        return ShelfPasteboardImporter.hasContent(sender.draggingPasteboard) ? 1 : 0
    }

    private func promiseReceivers(from sender: NSDraggingInfo) -> [NSFilePromiseReceiver] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self]
        ) as? [NSFilePromiseReceiver] ?? []
    }

    // Apps like Photos and Mail drag file promises instead of file URLs; the
    // file only exists after the source writes it into our directory.
    private func receivePromisedFiles(from sender: NSDraggingInfo) -> Bool {
        let receivers = promiseReceivers(from: sender)
        guard !receivers.isEmpty,
              let destination = try? ShelfPasteboardImporter.makeReceivedDirectory() else {
            return false
        }

        for receiver in receivers {
            receiver.receivePromisedFiles(
                atDestination: destination,
                options: [:],
                operationQueue: Self.promiseQueue
            ) { [weak manager] url, error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    manager?.add(urls: [url])
                }
            }
        }
        return true
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        return (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: Self.fileURLReadingOptions
        ) as? [NSURL])?.compactMap { $0 as URL } ?? []
    }

    /// Drags within this Shelf are ignored; drags from another Shelf move items.
    private func isInternalDrag(_ sender: NSDraggingInfo) -> Bool {
        (sender.draggingSource as? DraggableShelfItemView)?.owner === manager
    }

    private func resetDragAcceptance() {
        acceptedDragSequenceNumber = nil
        acceptedDragOperation = []
        manager.setDropTargetActive(false)
    }
}

/// Turns non-file pasteboard content (images, web links, text) into files so
/// the Shelf can hold it like any other item.
enum ShelfPasteboardImporter {
    static let contentTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .URL, .string]

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        return urls.isEmpty ? materializeContent(from: pasteboard) : urls
    }

    static func hasContent(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: contentTypes) != nil
    }

    static func materializeContent(
        from pasteboard: NSPasteboard,
        in directory: URL? = nil
    ) -> [URL] {
        guard let (data, fileName) = content(from: pasteboard),
              let directory = directory ?? (try? makeReceivedDirectory()) else {
            return []
        }
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .withoutOverwriting)
            return [url]
        } catch {
            return []
        }
    }

    /// Holds a folder per drop of content that has no file of its own.
    static func receivedRoot() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("DropShelf/Received", isDirectory: true)
    }

    static func makeReceivedDirectory() throws -> URL {
        let directory = try receivedRoot()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Deletes the received folders that no path in `referencedPaths` is
    /// inside and that are at least `minimumAge` old. The age is a grace
    /// period for drops still arriving and apps still reading a dropped
    /// file. Returns the deleted folders.
    @discardableResult
    static func pruneReceivedFolders(
        in root: URL,
        keeping referencedPaths: Set<String>,
        minimumAge: TimeInterval,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> [URL] {
        // Paths may name the root through a symlink or not.
        let rootPrefixes = Set([root.standardizedFileURL, root.resolvingSymlinksInPath()].map { $0.path + "/" })
        let referencedFolders = Set(referencedPaths.compactMap { path -> String? in
            guard let prefix = rootPrefixes.first(where: path.hasPrefix) else { return nil }
            return path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
        })
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey]
        let folders = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys
        )) ?? []

        return folders.filter { folder in
            guard !referencedFolders.contains(folder.lastPathComponent),
                  let values = try? folder.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true,
                  let created = values.creationDate,
                  now.timeIntervalSince(created) >= minimumAge else {
                return false
            }
            return (try? fileManager.removeItem(at: folder)) != nil
        }
    }

    private static func content(from pasteboard: NSPasteboard) -> (Data, String)? {
        let stamp = timestamp()

        if let png = pasteboard.data(forType: .png) {
            return (png, "Image \(stamp).png")
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return (png, "Image \(stamp).png")
        }
        if let link = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL,
           !link.isFileURL,
           let scheme = link.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            let plist: [String: String] = ["URL": link.absoluteString]
            guard let data = try? PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            ) else { return nil }
            return (data, "\(safeFileName(link.host ?? "Link")).webloc")
        }
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (Data(text.utf8), "Text \(stamp).txt")
        }
        return nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func safeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Link" : String(cleaned.prefix(80))
    }
}
