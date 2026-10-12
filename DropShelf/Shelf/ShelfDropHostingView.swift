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
            }
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
            manager.add(urls: urls)
            return true
        }
        return receivePromisedFiles(from: sender)
    }

    private func dropItemCount(from sender: NSDraggingInfo) -> Int {
        let urlCount = fileURLs(from: sender).count
        return urlCount > 0 ? urlCount : promiseReceivers(from: sender).count
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
              let destination = try? Self.makePromiseDestination() else {
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

    private static func makePromiseDestination() throws -> URL {
        // ponytail: received files are never pruned; add cleanup if disk use grows.
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("DropShelf/Received/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        return (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: Self.fileURLReadingOptions
        ) as? [NSURL])?.compactMap { $0 as URL } ?? []
    }

    private func isInternalDrag(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingSource is DraggableShelfItemView
    }

    private func resetDragAcceptance() {
        acceptedDragSequenceNumber = nil
        acceptedDragOperation = []
        manager.setDropTargetActive(false)
    }
}
