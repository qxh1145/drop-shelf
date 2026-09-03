import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var manager: ShelfManager
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var hasAppeared = false
    
    var body: some View {
        VStack(spacing: 9) {
            dragHandle
            header

            if !manager.isShowingHistory, manager.selectedItemIDs.count > 1 {
                selectionBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if manager.isShowingHistory {
                ShelfHistoryView(manager: manager)
            } else if manager.items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(manager.items) { item in
                            ShelfItemCard(item: item, manager: manager)
                                .transition(
                                    .scale(scale: 0.92).combined(with: .opacity)
                                )
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)

                if manager.isReceivingDrop {
                    dropTargetOverlay
                        .transition(.opacity)
                }
            }
        }
        .padding(1)
        .scaleEffect(hasAppeared ? 1 : 0.98)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.16)) {
                hasAppeared = true
            }
        }
        .animation(.easeOut(duration: 0.18), value: manager.items.map(\.id))
        .animation(.easeOut(duration: 0.16), value: manager.selectedItemIDs.count)
        .animation(.easeOut(duration: 0.14), value: manager.isReceivingDrop)
    }
    
    private var dragHandle: some View {
        WindowDragHandle()
            .frame(width: 60, height: 12)
            .overlay {
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 42, height: 4)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                (isHovering ? NSCursor.openHand : NSCursor.arrow).set()
            }
            .help("Drag to move Shelf")
    }
    
    private var header: some View {
        HStack(spacing: 8) {
            if manager.isShowingHistory {
                ShelfToolbarButton(
                    symbol: "chevron.left",
                    help: "Back to Shelf",
                    action: manager.hideHistory
                )
            }

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.85))
            
            Text(
                manager.isShowingHistory
                    ? "Recent Shelves"
                    : (manager.currentShelfName ?? "DropShelf")
            )
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .help(manager.currentShelfName ?? "DropShelf")
            
            Spacer()

            if !manager.isShowingHistory {
                ShelfToolbarButton(
                    symbol: manager.isCurrentShelfPinned ? "pin.fill" : "pin",
                    help: manager.isCurrentShelfPinned ? "Unpin this Shelf" : "Pin this Shelf",
                    tint: manager.isCurrentShelfPinned ? .accentColor : .secondary,
                    isDisabled: !manager.canPinCurrentShelf,
                    action: manager.toggleCurrentShelfPin
                )
            }
            
            Menu {
                Button {
                    manager.promptToNameCurrentShelf()
                } label: {
                    Label(
                        manager.currentShelfName == nil ? "Name Shelf…" : "Rename Shelf…",
                        systemImage: "pencil"
                    )
                }
                .disabled(!manager.canNameCurrentShelf || manager.isShowingHistory)

                Divider()

                Button {
                    manager.showHistory()
                } label: {
                    Label("Recent Shelves…", systemImage: "clock.arrow.circlepath")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button {
                    manager.airDropAllItems()
                } label: {
                    Label {
                        Text(
                            manager.usesSelectionForBulkActions
                                ? "AirDrop \(manager.bulkActionItemCount) Selected"
                                : "AirDrop All"
                        )
                    } icon: {
                        Image(nsImage: Self.airDropMenuImage)
                    }
                }
                .disabled(manager.items.isEmpty)
                
                Button {
                    manager.zipAllItems()
                } label: {
                    Label(
                        manager.usesSelectionForBulkActions
                            ? "Zip \(manager.bulkActionItemCount) Selected…"
                            : "Zip All…",
                        systemImage: "doc.zipper"
                    )
                }
                .disabled(manager.items.isEmpty || manager.isCreatingArchive)
            } label: {
                ShelfToolbarIconLabel(symbol: "ellipsis")
            }
            .labelStyle(.titleAndIcon)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointingHandCursor()
            .help(manager.isCreatingArchive ? "Creating ZIP…" : "Shelf actions")
            .accessibilityLabel("Shelf actions")
            
            ShelfToolbarButton(
                symbol: "xmark",
                help: "Close and clear Shelf",
                action: manager.clearAndCloseShelf
            )
        }
        .frame(height: 28)
    }

    private var selectionBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("\(manager.selectedItemIDs.count) items selected")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Button("Clear") {
                manager.clearSelection()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            Color.accentColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .symbolRenderingMode(.hierarchical)
            Text("Drop files or folders here")
                .font(.system(size: 12, weight: .semibold))
            Text(emptyStateHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateHint: String {
        if preferences.shakeGestureEnabled {
            return "Shake the pointer or press \(preferences.activationShortcut.displayName)"
        }
        return "Press \(preferences.activationShortcut.displayName) to open"
    }

    private var dropTargetOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))

            Label(dropTargetMessage, systemImage: "plus.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .allowsHitTesting(false)
    }

    private var dropTargetMessage: String {
        let count = manager.pendingDropItemCount
        return count > 0
            ? "Drop to add \(count) item\(count == 1 ? "" : "s")"
            : "Drop to add items"
    }

    private static let airDropMenuImage: NSImage = {
        let size = NSSize(width: 14, height: 14)
        guard let sourceImage = NSImage(named: "AirDropIcon") else {
            return NSImage(size: size)
        }

        let menuImage = NSImage(size: size, flipped: false) { bounds in
            sourceImage.draw(
                in: bounds.insetBy(dx: 0.5, dy: 0.5),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        menuImage.isTemplate = true
        return menuImage
    }()
}

private struct ShelfItemCard: View {
    let item: ShelfItem
    @ObservedObject var manager: ShelfManager
    @State private var isHovered = false

    private var isSelected: Bool {
        manager.selectedItemIDs.contains(item.id)
    }

    private var showsControls: Bool {
        isHovered || isSelected || manager.conversionState(for: item.id) == .converting
    }

    var body: some View {
        ZStack(alignment: .top) {
            ShelfItemView(
                item: item,
                isSelected: isSelected,
                isHovered: isHovered,
                manager: manager
            )

            HStack(spacing: 0) {
                ShelfItemActionsMenu(item: item, manager: manager)

                Spacer(minLength: 0)

                Button {
                    manager.removeItem(id: item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 20, height: 20)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                }
                .buttonStyle(.borderless)
                .contentShape(Circle())
                .pointingHandCursor()
                .help("Remove \(item.url.lastPathComponent) from Shelf")
            }
            .padding(5)
            .frame(maxWidth: .infinity, alignment: .top)
            .opacity(showsControls ? 1 : 0)
            .allowsHitTesting(showsControls)
            .animation(.easeOut(duration: 0.12), value: showsControls)
            .zIndex(1)
        }
        .frame(width: 98, height: 120)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct ShelfToolbarButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(
                    Color.primary.opacity(isHovered ? 0.1 : 0.035),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .onHover { hovering in
            isHovered = hovering
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ShelfToolbarIconLabel: View {
    let symbol: String
    @State private var isHovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 27, height: 27)
            .background(
                Color.primary.opacity(isHovered ? 0.1 : 0.035),
                in: Circle()
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .accessibilityLabel("Shelf actions")
    }
}

private struct ShelfHistoryView: View {
    @ObservedObject var manager: ShelfManager

    var body: some View {
        Group {
            if manager.historyEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .light))
                    Text("No recent shelves")
                        .font(.system(size: 12, weight: .medium))
                    Text("Unpinned shelves are kept for 72 hours.")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(historyGroups) { group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 5)

                                ForEach(group.entries) { entry in
                                    ShelfHistoryEntryRow(
                                        entry: entry,
                                        restore: {
                                            manager.restoreHistoryEntry(id: entry.id)
                                        },
                                        togglePin: {
                                            manager.toggleHistoryPin(id: entry.id)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private var historyGroups: [ShelfHistoryGroup] {
        let pinned = manager.historyEntries.filter(\.isPinned)
        let unpinned = manager.historyEntries.filter { !$0.isPinned }
        let calendar = Calendar.current
        var groups: [ShelfHistoryGroup] = []

        if !pinned.isEmpty {
            groups.append(ShelfHistoryGroup(title: "Pinned", entries: pinned))
        }

        let today = unpinned.filter { calendar.isDateInToday($0.createdAt) }
        if !today.isEmpty {
            groups.append(ShelfHistoryGroup(title: "Today", entries: today))
        }

        let yesterday = unpinned.filter { calendar.isDateInYesterday($0.createdAt) }
        if !yesterday.isEmpty {
            groups.append(ShelfHistoryGroup(title: "Yesterday", entries: yesterday))
        }

        let earlier = unpinned.filter {
            !calendar.isDateInToday($0.createdAt)
                && !calendar.isDateInYesterday($0.createdAt)
        }
        if !earlier.isEmpty {
            groups.append(ShelfHistoryGroup(title: "Earlier", entries: earlier))
        }

        return groups
    }
}

private struct ShelfHistoryGroup: Identifiable {
    let title: String
    let entries: [ShelfHistoryEntry]

    var id: String { title }
}

private struct ShelfHistoryEntryRow: View {
    let entry: ShelfHistoryEntry
    let restore: () -> Void
    let togglePin: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Button(action: restore) {
                HStack(spacing: 9) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ShelfHistoryPresentation.displayName(for: entry))
                            .font(.system(size: 11, weight: .semibold))

                        Text(
                            entry.name == nil
                                ? "\(entry.paths.count) item\(entry.paths.count == 1 ? "" : "s") · "
                                    + ShelfHistoryPresentation.fileSummary(for: entry)
                                : "\(ShelfHistoryPresentation.detailLine(for: entry)) · "
                                    + ShelfHistoryPresentation.fileSummary(for: entry)
                        )
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 6)

                    Text("\(entry.paths.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Restore this Shelf")
            .accessibilityLabel("Restore \(ShelfHistoryPresentation.displayName(for: entry))")

            Button(action: togglePin) {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(entry.isPinned ? "Unpin Shelf" : "Pin Shelf")
            .accessibilityLabel(entry.isPinned ? "Unpin Shelf" : "Pin Shelf")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            Color.primary.opacity(isHovered ? 0.1 : 0.055),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

}

private struct ShelfItemActionsMenu: View {
    let item: ShelfItem
    @ObservedObject var manager: ShelfManager

    @State private var options: [ConversionOption] = []
    @State private var isAnalyzing = true

    var body: some View {
        Group {
            if manager.conversionState(for: item.id) == .converting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
                    .help("Converting \(item.url.lastPathComponent)…")
            } else {
                Menu {
                    if isAnalyzing {
                        Button("Checking formats…") {}
                            .disabled(true)
                    } else if options.isEmpty {
                        Button("No conversions available") {}
                            .disabled(true)
                    } else {
                        Menu {
                            ForEach(options) { option in
                                Button {
                                    manager.requestConversion(of: item, using: option)
                                } label: {
                                    Label(
                                        option.targetFormat.displayName,
                                        systemImage: option.warning == nil
                                            ? "doc.badge.arrow.up"
                                            : "exclamationmark.triangle"
                                    )
                                }
                            }
                        } label: {
                            Label("Convert to", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 20, height: 20)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointingHandCursor()
                .help("Actions for \(item.url.lastPathComponent)")
            }
        }
        .frame(width: 20, height: 20)
        .task(id: item.url) {
            isAnalyzing = true
            let detectedOptions = await ConversionService.shared
                .supportedOutputFormats(for: item.url)
            guard !Task.isCancelled else { return }
            options = detectedOptions
            isAnalyzing = false
        }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleView {
        WindowDragHandleView()
    }
    
    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}

private final class WindowDragHandleView: NSView {
    private var trackingArea: NSTrackingArea?
    private var isDraggingWindow = false
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
    
    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let newTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
        super.updateTrackingAreas()
    }
    
    override func mouseEntered(with event: NSEvent) {
        if !isDraggingWindow {
            NSCursor.openHand.set()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isDraggingWindow {
            NSCursor.arrow.set()
        }
    }
    
    override func cursorUpdate(with event: NSEvent) {
        (isDraggingWindow ? NSCursor.closedHand : NSCursor.openHand).set()
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        
        isDraggingWindow = true
        NSCursor.closedHand.set()
        window.performDrag(with: event)
        isDraggingWindow = false
        
        let currentLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        (bounds.contains(currentLocation) ? NSCursor.openHand : NSCursor.arrow).set()
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            (isHovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
