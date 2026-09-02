import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var manager: ShelfManager
    
    var body: some View {
        VStack(spacing: 7) {
            dragHandle
            header
            
            if manager.items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(manager.items) { item in
                            ZStack(alignment: .topTrailing) {
                                ShelfItemView(
                                    item: item,
                                    isSelected: manager.selectedItemIDs.contains(item.id),
                                    manager: manager
                                )
                                
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
                                .padding(4)
                                .zIndex(1)
                                .pointingHandCursor()
                                .help("Remove \(item.url.lastPathComponent) from Shelf")
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
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.secondary)
            
            Text("DropShelf")
                .font(.system(size: 13, weight: .semibold))
            
            Spacer()
            
            Menu {
                Button {
                    manager.airDropAllItems()
                } label: {
                    Label {
                        Text("AirDrop All")
                    } icon: {
                        Image(nsImage: Self.airDropMenuImage)
                    }
                }
                
                Button {
                    manager.zipAllItems()
                } label: {
                    Label("Zip All…", systemImage: "doc.zipper")
                }
                .disabled(manager.isCreatingArchive)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(manager.items.isEmpty)
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
