import AppKit
import SwiftUI

final class ShelfDropHostingView: NSView {
    private static let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    private let manager: ShelfManager
    private let hostingView: NSHostingView<ShelfView>
    private var acceptedDragSequenceNumber: Int?
    private var acceptedDragOperation: NSDragOperation = []

    init(manager: ShelfManager) {
        self.manager = manager
        self.hostingView = NSHostingView(rootView: ShelfView(manager: manager))
        super.init(frame: .zero)

        registerForDraggedTypes([.fileURL])

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
            operation = sender.draggingPasteboard.canReadObject(
                forClasses: [NSURL.self],
                options: Self.fileURLReadingOptions
            ) ? .copy : []
        }

        acceptedDragSequenceNumber = sender.draggingSequenceNumber
        acceptedDragOperation = operation
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
        guard !urls.isEmpty else { return false }
        manager.add(urls: urls)
        return true
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
    }
}
