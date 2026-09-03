import AppKit
import QuartzCore

final class ShelfPanel: NSPanel {
    private static let initialPanelSize = NSSize(width: 310, height: 204)
    private static let minimumShelfWidth: CGFloat = 310
    private static let maximumShelfWidth: CGFloat = 640
    private static let itemWidth: CGFloat = 98
    private static let itemSpacing: CGFloat = 10
    private weak var shelfManager: ShelfManager?

    init(manager: ShelfManager) {
        shelfManager = manager
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.initialPanelSize),
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

    func updateLayout(
        itemCount: Int,
        selectionCount: Int,
        showingHistory: Bool,
        animated: Bool
    ) {
        let targetSize: NSSize
        if showingHistory {
            targetSize = NSSize(width: 470, height: 340)
        } else {
            let visibleItemCount = max(1, min(itemCount, 6))
            let contentWidth = CGFloat(visibleItemCount) * Self.itemWidth
                + CGFloat(max(0, visibleItemCount - 1)) * Self.itemSpacing
                + 36
            targetSize = NSSize(
                width: min(
                    max(contentWidth, Self.minimumShelfWidth),
                    Self.maximumShelfWidth
                ),
                height: itemCount > 0
                    ? (selectionCount > 1 ? 252 : 218)
                    : 204
            )
        }

        guard frame.size != targetSize else { return }

        var targetFrame = frame
        targetFrame.origin.x -= (targetSize.width - frame.width) / 2
        targetFrame.origin.y -= (targetSize.height - frame.height) / 2
        targetFrame.size = targetSize
        targetFrame = constrainedFrame(targetFrame)

        if animated, isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(targetFrame, display: true)
            }
        } else {
            setFrame(targetFrame, display: isVisible)
        }
    }

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

    private func constrainedFrame(_ proposedFrame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(proposedFrame) } ?? self.screen
        guard let visibleFrame = screen?.visibleFrame else { return proposedFrame }

        var result = proposedFrame
        result.origin.x = min(
            max(result.origin.x, visibleFrame.minX + 8),
            visibleFrame.maxX - result.width - 8
        )
        result.origin.y = min(
            max(result.origin.y, visibleFrame.minY + 8),
            visibleFrame.maxY - result.height - 8
        )
        return result
    }
}
