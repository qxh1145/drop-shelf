import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var openSettingsHandler: (() -> Void)?
    private var openOnboardingHandler: (() -> Void)?
    private let pinnedShelvesMenu = NSMenu(title: String(localized: "Pinned Shelves"))
    private let recentShelvesMenu = NSMenu(title: String(localized: "Recent Shelves"))
    private let openShelvesMenu = NSMenu(title: String(localized: "Open Shelves"))
    private let undoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(
        openSettingsHandler: @escaping () -> Void,
        openOnboardingHandler: @escaping () -> Void
    ) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        self.openSettingsHandler = openSettingsHandler
        self.openOnboardingHandler = openOnboardingHandler
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "tray.and.arrow.down.fill",
                accessibilityDescription: "DropShelf"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DropShelf"
        }

        let menu = NSMenu()
        menu.delegate = self

        let newShelfItem = NSMenuItem(
            title: String(localized: "New Shelf"),
            action: #selector(openNewShelf),
            keyEquivalent: ""
        )
        newShelfItem.image = NSImage(
            systemSymbolName: "plus.rectangle.on.rectangle",
            accessibilityDescription: String(localized: "New Shelf")
        )
        newShelfItem.target = self
        menu.addItem(newShelfItem)

        undoItem.action = #selector(undo)
        undoItem.target = self
        undoItem.image = NSImage(
            systemSymbolName: "arrow.uturn.backward",
            accessibilityDescription: nil
        )
        menu.addItem(undoItem)

        let openShelvesItem = NSMenuItem(title: String(localized: "Open Shelves"), action: nil, keyEquivalent: "")
        openShelvesItem.image = NSImage(
            systemSymbolName: "tray.2",
            accessibilityDescription: String(localized: "Open Shelves")
        )
        openShelvesItem.submenu = openShelvesMenu
        menu.addItem(openShelvesItem)

        let recentShelvesItem = NSMenuItem(
            title: String(localized: "Recent Shelves"),
            action: nil,
            keyEquivalent: ""
        )
        recentShelvesItem.image = NSImage(
            systemSymbolName: "clock.arrow.circlepath",
            accessibilityDescription: String(localized: "Recent Shelves")
        )
        recentShelvesItem.submenu = recentShelvesMenu
        menu.addItem(recentShelvesItem)

        let pinnedShelvesItem = NSMenuItem(
            title: String(localized: "Pinned Shelves"),
            action: nil,
            keyEquivalent: ""
        )
        pinnedShelvesItem.image = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: String(localized: "Pinned Shelves")
        )
        pinnedShelvesItem.submenu = pinnedShelvesMenu
        menu.addItem(pinnedShelvesItem)
        menu.addItem(.separator())

        let onboardingItem = NSMenuItem(
            title: String(localized: "Getting Started…"),
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        onboardingItem.image = NSImage(
            systemSymbolName: "questionmark.circle",
            accessibilityDescription: "Getting Started"
        )
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        let updatesItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit DropShelf"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let undoManager = ShelfManager.undoManager
        undoItem.isHidden = !undoManager.canUndo
        undoItem.title = undoManager.undoMenuItemTitle
        ShelfManager.active.refreshHistory()
        rebuildPinnedShelvesMenu()
        rebuildRecentShelvesMenu()
        rebuildOpenShelvesMenu()
    }

    func invalidate() {
        guard let statusItem else { return }

        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        openSettingsHandler = nil
        openOnboardingHandler = nil
    }

    @objc private func openSettings() {
        openSettingsHandler?()
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.check(userInitiated: true)
    }

    @objc private func openOnboarding() {
        openOnboardingHandler?()
    }

    private func restorePinnedShelf(entryID: UUID) {
        ShelfManager.active.restoreHistoryEntry(id: entryID)
    }

    @objc private func undo() {
        ShelfManager.undoManager.undo()
    }

    @objc private func openNewShelf() {
        ShelfManager.openNewShelf(near: NSEvent.mouseLocation)
    }

    @objc private func showOpenShelf(_ sender: NSMenuItem) {
        guard let shelf = sender.representedObject as? ShelfManager else { return }
        shelf.showShelf(near: NSEvent.mouseLocation)
    }

    private func rebuildOpenShelvesMenu() {
        openShelvesMenu.removeAllItems()

        let shelves = ShelfManager.shelves.filter { !$0.items.isEmpty }
        guard !shelves.isEmpty else {
            let emptyItem = NSMenuItem(title: String(localized: "No open shelves"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            openShelvesMenu.addItem(emptyItem)
            return
        }

        for (index, shelf) in shelves.enumerated() {
            let count = shelf.items.count
            let item = NSMenuItem(
                title: "\(shelf.currentShelfName ?? String(localized: "Shelf \(index + 1)")) · "
                    + ShelfHistoryPresentation.itemCount(count),
                action: #selector(showOpenShelf(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = shelf
            item.state = shelf.isShelfVisible ? .on : .off
            openShelvesMenu.addItem(item)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    /// Every history entry, grouped like the Shelf's own Recent Shelves view.
    private func rebuildRecentShelvesMenu() {
        recentShelvesMenu.removeAllItems()

        let groups = ShelfHistoryPresentation.groups(for: ShelfManager.active.historyEntries)
        if groups.isEmpty {
            let emptyItem = NSMenuItem(
                title: String(localized: "No recent shelves"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            recentShelvesMenu.addItem(emptyItem)
        }

        for (index, group) in groups.enumerated() {
            if index > 0 {
                recentShelvesMenu.addItem(.separator())
            }
            let header = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            recentShelvesMenu.addItem(header)

            for entry in group.entries {
                let item = NSMenuItem(
                    title: ShelfHistoryPresentation.displayName(for: entry),
                    action: nil,
                    keyEquivalent: ""
                )
                item.view = PinnedShelfMenuItemView(
                    entry: entry,
                    symbol: entry.isPinned ? "pin.fill" : "tray.full.fill",
                    restore: { [weak self] in
                        self?.restorePinnedShelf(entryID: entry.id)
                    }
                )
                recentShelvesMenu.addItem(item)
            }
        }

        recentShelvesMenu.addItem(.separator())
        let showInShelfItem = NSMenuItem(
            title: String(localized: "Show in Shelf…"),
            action: #selector(showHistoryInShelf),
            keyEquivalent: ""
        )
        showInShelfItem.target = self
        recentShelvesMenu.addItem(showInShelfItem)
    }

    @objc private func showHistoryInShelf() {
        ShelfManager.active.showHistory(near: NSEvent.mouseLocation)
    }

    private func rebuildPinnedShelvesMenu() {
        pinnedShelvesMenu.removeAllItems()

        let entries = ShelfManager.active.pinnedHistoryEntries
        guard !entries.isEmpty else {
            let emptyItem = NSMenuItem(
                title: String(localized: "No pinned shelves"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            pinnedShelvesMenu.addItem(emptyItem)
            return
        }

        for entry in entries {
            let item = NSMenuItem(
                title: ShelfHistoryPresentation.displayName(for: entry),
                action: nil,
                keyEquivalent: ""
            )
            item.view = PinnedShelfMenuItemView(
                entry: entry,
                restore: { [weak self] in
                    self?.restorePinnedShelf(entryID: entry.id)
                }
            )
            pinnedShelvesMenu.addItem(item)
        }
    }
}

private final class PinnedShelfMenuItemView: NSView {
    private let restore: () -> Void
    private var trackingAreaReference: NSTrackingArea?

    init(entry: ShelfHistoryEntry, symbol: String = "pin.fill", restore: @escaping () -> Void) {
        self.restore = restore
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 76))

        wantsLayer = true
        layer?.cornerRadius = 6

        let iconView = NSImageView()
        iconView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(
            labelWithString: ShelfHistoryPresentation.displayName(for: entry)
        )
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.usesSingleLineMode = false
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.preferredMaxLayoutWidth = 363

        let detailLabel = NSTextField(
            labelWithString: ShelfHistoryPresentation.detailLine(for: entry)
        )
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        let filesLabel = NSTextField(
            labelWithString: ShelfHistoryPresentation.fileSummary(for: entry)
        )
        filesLabel.font = .systemFont(ofSize: 11)
        filesLabel.textColor = .secondaryLabelColor
        filesLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [titleLabel, detailLabel, filesLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labels)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let allFileNames = entry.paths
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .joined(separator: "\n")
        toolTip = [
            ShelfHistoryPresentation.displayName(for: entry),
            ShelfHistoryPresentation.detailLine(for: entry),
            allFileNames
        ].joined(separator: "\n")
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Restore \(ShelfHistoryPresentation.displayName(for: entry))"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor
            .withAlphaComponent(0.3)
            .cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        restore()
    }
}
