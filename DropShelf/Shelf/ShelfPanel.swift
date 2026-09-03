import AppKit

final class ShelfPanel: NSPanel {
    private static let panelSize = NSSize(width: 390, height: 188)
    private weak var shelfManager: ShelfManager?

    init(manager: ShelfManager) {
        shelfManager = manager
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = ShelfDropHostingView(manager: manager)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown,
             .leftMouseUp,
             .leftMouseDragged,
             .rightMouseDown,
             .rightMouseUp,
             .rightMouseDragged,
             .otherMouseDown,
             .otherMouseUp,
             .otherMouseDragged,
             .scrollWheel:
            shelfManager?.shelfDidReceiveUserActivity()
        default:
            break
        }

        super.sendEvent(event)
    }

    func position(near cursor: CGPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        var origin = CGPoint(
            x: cursor.x - frame.width / 2,
            y: cursor.y - frame.height / 2
        )

        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - frame.width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - frame.height - 8)
        setFrameOrigin(origin)
    }
}
