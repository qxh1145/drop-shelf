import AppKit
import SwiftUI

@MainActor
final class ShelfIconCache {
    static let shared = ShelfIconCache()

    private struct Entry {
        let image: NSImage
        let cost: Int
        var lastAccess: UInt64
    }

    private static let thumbnailPointSize = NSSize(width: 50, height: 50)
    private static let thumbnailPixelSize = 100
    private static let maximumEntryCount = 64
    private static let maximumTotalCost = 3 * 1_024 * 1_024

    private var entries: [String: Entry] = [:]
    private var totalCost = 0
    private var accessCounter: UInt64 = 0

    private init() {}

    func image(for url: URL) -> NSImage {
        let key = cacheKey(for: url)

        if var entry = entries[key] {
            entry.lastAccess = nextAccessValue()
            entries[key] = entry
            return entry.image
        }

        let thumbnail = makeThumbnail(for: url)
        entries[key] = Entry(
            image: thumbnail.image,
            cost: thumbnail.cost,
            lastAccess: nextAccessValue()
        )
        totalCost += thumbnail.cost
        evictIfNeeded(preserving: key)
        return thumbnail.image
    }

    func remove(urls: [URL]) {
        for url in urls {
            if let entry = entries.removeValue(forKey: cacheKey(for: url)) {
                totalCost -= entry.cost
            }
        }
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
        totalCost = 0
        accessCounter = 0
    }

    private func cacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func nextAccessValue() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }

    private func evictIfNeeded(preserving preservedKey: String) {
        while entries.count > Self.maximumEntryCount || totalCost > Self.maximumTotalCost {
            var keyToEvict: String?
            var oldestAccess = UInt64.max

            for (key, entry) in entries where key != preservedKey && entry.lastAccess < oldestAccess {
                keyToEvict = key
                oldestAccess = entry.lastAccess
            }

            guard let keyToEvict,
                  let removedEntry = entries.removeValue(forKey: keyToEvict) else {
                break
            }

            totalCost -= removedEntry.cost
        }
    }

    private func makeThumbnail(for url: URL) -> (image: NSImage, cost: Int) {
        let pixelSize = Self.thumbnailPixelSize
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return (NSImage(size: Self.thumbnailPointSize), 1)
        }

        bitmap.size = Self.thumbnailPointSize
        let sourceImage = NSWorkspace.shared.icon(forFile: url.path)
        let bounds = NSRect(origin: .zero, size: Self.thumbnailPointSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSBezierPath(rect: bounds).fill()
        sourceImage.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let thumbnail = NSImage(size: Self.thumbnailPointSize)
        thumbnail.addRepresentation(bitmap)
        thumbnail.cacheMode = .never
        thumbnail.isTemplate = sourceImage.isTemplate

        return (thumbnail, bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}

struct ShelfItemView: View {
    let item: ShelfItem
    let isSelected: Bool
    let manager: ShelfManager

    private let icon: NSImage

    init(item: ShelfItem, isSelected: Bool, manager: ShelfManager) {
        self.item = item
        self.isSelected = isSelected
        self.manager = manager
        self.icon = ShelfIconCache.shared.image(for: item.url)
    }

    var body: some View {
        ZStack {
            ShelfItemLabel(item: item, icon: icon, isSelected: isSelected)
                .allowsHitTesting(false)

            ShelfItemDragOverlay(item: item, manager: manager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ShelfItemLabel: View {
    let item: ShelfItem
    let icon: NSImage
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 50, height: 50)

            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.75) : Color.clear,
                    lineWidth: 1.5
                )
        }
    }
}

private struct ShelfItemDragOverlay: NSViewRepresentable {
    let item: ShelfItem
    let manager: ShelfManager

    func makeNSView(context: Context) -> DraggableShelfItemView {
        DraggableShelfItemView(item: item, manager: manager)
    }

    func updateNSView(_ nsView: DraggableShelfItemView, context: Context) {
        nsView.update(item: item, manager: manager)
    }
}

final class DraggableShelfItemView: NSView, NSDraggingSource {
    private static let removeButtonHitArea = NSSize(width: 30, height: 30)

    private var item: ShelfItem
    private weak var manager: ShelfManager?
    private var dragStarted = false
    private var suppressClickSelection = false
    private var extendsSelectionOnClick = false
    private var draggedItemIDs: Set<UUID> = []

    init(item: ShelfItem, manager: ShelfManager) {
        self.item = item
        self.manager = manager
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let removeButtonRect = NSRect(
            x: max(bounds.maxX - Self.removeButtonHitArea.width, bounds.minX),
            y: bounds.minY,
            width: min(Self.removeButtonHitArea.width, bounds.width),
            height: min(Self.removeButtonHitArea.height, bounds.height)
        )

        return removeButtonRect.contains(point) ? nil : super.hitTest(point)
    }

    func update(item: ShelfItem, manager: ShelfManager) {
        guard self.item != item || self.manager !== manager else { return }
        self.item = item
        self.manager = manager
    }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        suppressClickSelection = false
        extendsSelectionOnClick = event.modifierFlags.contains(.command)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            suppressClickSelection = false
            extendsSelectionOnClick = false
        }
        guard !dragStarted, !suppressClickSelection else { return }

        manager?.selectItem(
            item.id,
            extendingSelection: extendsSelectionOnClick
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let manager else { return }
        dragStarted = true
        suppressClickSelection = true

        let draggedItems = manager.itemsForDrag(
            startingWith: item.id,
            extendingSelection: extendsSelectionOnClick
        )
        guard !draggedItems.isEmpty else {
            dragStarted = false
            suppressClickSelection = false
            return
        }

        draggedItemIDs = Set(draggedItems.map(\.id))
        let location = convert(event.locationInWindow, from: nil)

        let draggingItems = draggedItems.enumerated().map { index, shelfItem -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: shelfItem.url as NSURL)
            let icon = ShelfIconCache.shared.image(for: shelfItem.url)
            let offset = CGFloat(index) * 4
            let frame = NSRect(
                x: location.x - 24 + offset,
                y: location.y - 24 - offset,
                width: 48,
                height: 48
            )
            draggingItem.setDraggingFrame(frame, contents: icon)
            return draggingItem
        }

        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = draggedItems.count > 1 ? .pile : .none
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .move, .link]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        defer {
            draggedItemIDs.removeAll(keepingCapacity: false)
            dragStarted = false
            extendsSelectionOnClick = false
        }

        guard !operation.isEmpty else { return }
        manager?.outboundDragDidSucceed(itemIDs: draggedItemIDs)
    }
}
