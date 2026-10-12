import AppKit
import Quartz

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
        setAccessibilityLabel(String(localized: "DropShelf Shelf"))
    }

    // Key only after the user clicks the Shelf (it is ordered front without
    // focus), so keyboard shortcuts work without stealing typing elsewhere.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func updateLayout(
        itemCount: Int,
        selectionCount: Int,
        showingHistory: Bool,
        showingSearch: Bool = false,
        animated: Bool
    ) {
        var targetSize: NSSize
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

        if showingSearch, !showingHistory {
            targetSize.height += 34
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
        case .keyDown:
            shelfManager?.shelfDidReceiveUserActivity()
            if handleKeyDown(event) { return }
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

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let manager = shelfManager else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            manager.toggleSearch()
            return true
        }
        // While the search field is being edited, keys belong to it.
        if firstResponder is NSText {
            return false
        }

        if flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": manager.selectAllItems()
            case "c": manager.copyItems()
            case "v": manager.pasteFromClipboard()
            case "o": manager.openItems()
            case "y": manager.toggleQuickLook()
            case "n": ShelfManager.openNewShelf()
            case "\u{7F}": manager.removeSelectedItems()
            default: return false
            }
            return true
        }

        guard flags.subtracting(.shift).isEmpty else { return false }
        switch Int(event.keyCode) {
        case 49: manager.toggleQuickLook() // Space
        case 51, 117: manager.removeSelectedItems() // Delete, Forward Delete
        case 53: manager.dismissShelf() // Escape
        case 36, 76: manager.openItems() // Return, Enter
        case 123: manager.moveSelection(by: -1, extendingSelection: flags == .shift)
        case 124: manager.moveSelection(by: 1, extendingSelection: flags == .shift)
        default: return false
        }
        return true
    }

    /// Pulls a frame dropped within `threshold` of a screen edge flush
    /// against it, keeping the usual 8 pt margin.
    static func snappedFrame(
        _ frame: NSRect,
        in visibleFrame: NSRect,
        threshold: CGFloat = 32,
        margin: CGFloat = 8
    ) -> NSRect {
        var result = frame
        if frame.minX - visibleFrame.minX < threshold {
            result.origin.x = visibleFrame.minX + margin
        } else if visibleFrame.maxX - frame.maxX < threshold {
            result.origin.x = visibleFrame.maxX - frame.width - margin
        }
        if frame.minY - visibleFrame.minY < threshold {
            result.origin.y = visibleFrame.minY + margin
        } else if visibleFrame.maxY - frame.maxY < threshold {
            result.origin.y = visibleFrame.maxY - frame.height - margin
        }
        return result
    }

    func userDidFinishMove() {
        shelfManager?.shelfPanelDidFinishMove()
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

extension ShelfPanel: QLPreviewPanelDataSource {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        shelfManager?.quickLookDidEnd()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        shelfManager?.quickLookURLs.count ?? 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        shelfManager?.quickLookURLs[index] as NSURL?
    }
}
