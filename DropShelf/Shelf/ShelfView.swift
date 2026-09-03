import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var manager: ShelfManager
    
    var body: some View {
        VStack(spacing: 7) {
            dragHandle
            header
            
            if manager.isShowingHistory {
                ShelfHistoryView(manager: manager)
            } else if manager.items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(manager.items) { item in
                            ZStack(alignment: .top) {
                                ShelfItemView(
                                    item: item,
                                    isSelected: manager.selectedItemIDs.contains(item.id),
                                    manager: manager
                                )

                                HStack(spacing: 0) {
                                    ShelfItemActionsMenu(item: item, manager: manager)

                                    Spacer(minLength: 0)

                                    Button {
                                        manager.removeItem(id: item.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.62))
                                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                    }
                                    .buttonStyle(.borderless)
                                    .contentShape(Circle())
                                    .pointingHandCursor()
                                    .help("Remove \(item.url.lastPathComponent) from Shelf")
                                }
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .zIndex(1)
                            }
                            .frame(width: 86, height: 108)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        }
        .padding(1)
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
                Button {
                    manager.hideHistory()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Back to Shelf")
            }

            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.secondary)
            
            Text(
                manager.isShowingHistory
                    ? "Recent Shelves"
                    : (manager.currentShelfName ?? "DropShelf")
            )
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            
            Spacer()

            if !manager.isShowingHistory {
                Button {
                    manager.toggleCurrentShelfPin()
                } label: {
                    Image(systemName: manager.isCurrentShelfPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            manager.isCurrentShelfPinned ? Color.accentColor : Color.secondary
                        )
                }
                .buttonStyle(.plain)
                .disabled(!manager.canPinCurrentShelf)
                .pointingHandCursor()
                .help(manager.isCurrentShelfPinned ? "Unpin this Shelf" : "Pin this Shelf")
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
                        Text("AirDrop All")
                    } icon: {
                        Image(nsImage: Self.airDropMenuImage)
                    }
                }
                .disabled(manager.items.isEmpty)
                
                Button {
                    manager.zipAllItems()
                } label: {
                    Label("Zip All…", systemImage: "doc.zipper")
                }
                .disabled(manager.items.isEmpty || manager.isCreatingArchive)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointingHandCursor()
            .help(manager.isCreatingArchive ? "Creating ZIP…" : "Shelf actions")
            
            Button {
                manager.clearAndCloseShelf()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Close and clear Shelf")
        }
        .frame(height: 18)
    }
    
    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 24, weight: .light))
            Text("Drop files or folders here")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    LazyVStack(spacing: 6) {
                        ForEach(manager.historyEntries) { entry in
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
                    .padding(.horizontal, 1)
                }
            }
        }
    }
}

private struct ShelfHistoryEntryRow: View {
    let entry: ShelfHistoryEntry
    let restore: () -> Void
    let togglePin: () -> Void

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

            Button(action: togglePin) {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(entry.isPinned ? "Unpin Shelf" : "Pin Shelf")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
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
                    .frame(width: 18, height: 18)
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
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.62))
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointingHandCursor()
                .help("Actions for \(item.url.lastPathComponent)")
            }
        }
        .frame(width: 18, height: 18)
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

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
