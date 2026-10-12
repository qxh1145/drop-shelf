import AppKit
import Combine
import Darwin
import Quartz
import UniformTypeIdentifiers

@MainActor
final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedItemIDs: Set<UUID> = []
    @Published private(set) var isCreatingArchive = false
    @Published private(set) var conversionStates: [UUID: ConversionState] = [:]
    @Published private(set) var historyEntries: [ShelfHistoryEntry] {
        didSet { Self.shareHistory(historyEntries, from: self) }
    }
    @Published private(set) var isShowingHistory = false
    @Published private(set) var currentShelfName: String?
    @Published private(set) var isReceivingDrop = false
    @Published private(set) var pendingDropItemCount = 0
    /// Keeps this Shelf visible: no auto-hide, no Esc hide, no close-when-empty.
    @Published private(set) var isKeptOnScreen = false
    @Published private(set) var isSearching = false
    @Published private(set) var searchText = ""

    private var panel: ShelfPanel?
    private var currentHistoryEntryID: UUID?
    private var itemURLs: Set<URL> = []
    private var sessionURLs: [URL] = []
    private var sessionURLSet: Set<URL> = []
    /// Keyed by batch token; `conversionTokens` maps each item to its batch.
    private var conversionTasks: [UUID: Task<Void, Never>] = [:]
    private var conversionTokens: [UUID: UUID] = [:]
    private var autoHideTimer: (any DispatchSourceTimer)?
    private let historyStore: ShelfHistoryStore
    private let preferences: AppPreferences
    private let autoHideDelay: TimeInterval
    nonisolated private static let archiveQueue = DispatchQueue(
        label: "com.example.DropShelf.archive",
        qos: .utility
    )

    init(
        historyStore: ShelfHistoryStore = ShelfHistoryStore(),
        preferences suppliedPreferences: AppPreferences? = nil,
        autoHideDelay: TimeInterval = 10
    ) {
        let preferences = suppliedPreferences ?? .shared
        self.historyStore = historyStore
        self.preferences = preferences
        self.autoHideDelay = autoHideDelay
        self.historyEntries = historyStore.load()
        self.currentShelfName = nil

        preferences.shelfBehaviorDidChange = { [weak self] in
            self?.shelfBehaviorPreferencesDidChange()
        }
    }

    // MARK: - Multiple shelves

    /// Every Shelf the app manages. Closed shelves stay here and get reused,
    /// because releasing an NSPanel mid-animation can crash.
    private(set) static var shelves: [ShelfManager] = [shared]
    /// The Shelf that activation, Recent Shelves, and pinned restores target.
    private(set) static var active: ShelfManager = shared
    private static var isSharingHistory = false

    /// Shows an empty Shelf next to the active one, reusing a closed Shelf.
    static func openNewShelf(near point: CGPoint? = nil) {
        let current = active
        if current.items.isEmpty, current.isShelfVisible, !current.isShowingHistory {
            return
        }

        let shelf = shelves.first {
            $0 !== current && $0.items.isEmpty && !$0.isShelfVisible
        } ?? makeShelf()
        if shelf.canNameCurrentShelf {
            // An auto-hidden Shelf whose items were all dragged out still
            // owns a session; file it in history before reusing the Shelf.
            shelf.clearAndCloseShelf()
        }

        let location = point
            ?? current.panel.flatMap { panel in
                panel.isVisible
                    ? CGPoint(x: panel.frame.maxX + 170, y: panel.frame.midY)
                    : nil
            }
            ?? NSEvent.mouseLocation
        shelf.showShelf(near: location)
    }

    private static func makeShelf() -> ShelfManager {
        let shelf = ShelfManager()
        shelves.append(shelf)
        // Each init claims the single preferences callback; fan it out again.
        shelf.preferences.shelfBehaviorDidChange = {
            for shelf in ShelfManager.shelves {
                shelf.shelfBehaviorPreferencesDidChange()
            }
        }
        return shelf
    }

    private static func shareHistory(_ entries: [ShelfHistoryEntry], from source: ShelfManager) {
        guard !isSharingHistory, source.isRegistered else { return }
        isSharingHistory = true
        defer { isSharingHistory = false }
        for shelf in shelves where shelf !== source {
            shelf.historyEntries = entries
        }
    }

    private var isRegistered: Bool {
        Self.shelves.contains { $0 === self }
    }

    /// Where activation shows the Shelf, per the placement preference.
    static var activationPoint: CGPoint {
        let preferences = AppPreferences.shared
        if preferences.shelfPlacement == .lastPosition,
           let center = preferences.lastShelfCenter,
           NSScreen.screens.contains(where: { $0.frame.contains(center) }) {
            return center
        }
        return NSEvent.mouseLocation
    }

    private func markActive() {
        if isRegistered {
            Self.active = self
        }
    }

    var isShelfVisible: Bool {
        panel?.isVisible == true
    }

    var canNameCurrentShelf: Bool {
        !sessionURLs.isEmpty
    }

    var canPinCurrentShelf: Bool {
        !sessionURLs.isEmpty
    }

    var isCurrentShelfPinned: Bool {
        guard let currentHistoryEntryID else { return false }
        return historyEntries.first(where: { $0.id == currentHistoryEntryID })?.isPinned == true
    }

    var pinnedHistoryEntries: [ShelfHistoryEntry] {
        historyEntries.filter(\.isPinned)
    }

    var bulkActionItemCount: Int {
        selectedItemIDs.count > 1 ? selectedItemIDs.count : visibleItems.count
    }

    // MARK: - Search

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Items whose name matches the search; every item when not searching.
    var visibleItems: [ShelfItem] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return items }
        return items.filter { $0.url.lastPathComponent.localizedStandardContains(query) }
    }

    /// History entries whose name or file names match the search.
    var visibleHistoryEntries: [ShelfHistoryEntry] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return historyEntries }
        return historyEntries.filter { entry in
            ShelfHistoryPresentation.displayName(for: entry).localizedStandardContains(query)
                || entry.paths.contains {
                    URL(fileURLWithPath: $0).lastPathComponent.localizedStandardContains(query)
                }
        }
    }

    func toggleSearch() {
        isSearching.toggle()
        if isSearching {
            // The search field needs keyboard focus.
            panel?.makeKey()
        } else {
            setSearchText("")
        }
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func setSearchText(_ text: String) {
        guard text != searchText else { return }
        searchText = text
        // Hidden items must not ride along in drags or bulk actions.
        let visibleIDs = Set(visibleItems.map(\.id))
        if !selectedItemIDs.isSubset(of: visibleIDs) {
            selectedItemIDs.formIntersection(visibleIDs)
        }
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    var usesSelectionForBulkActions: Bool {
        selectedItemIDs.count > 1
    }

    func showShelf(near point: CGPoint) {
        isShowingHistory = false

        if panel == nil {
            panel = ShelfPanel(manager: self)
        } else if panel?.contentView == nil {
            panel?.contentView = ShelfDropHostingView(manager: self)
        }

        updatePanelLayout(animated: false)
        panel?.position(near: point)
        panel?.orderFrontRegardless()
        markActive()
        scheduleAutoHideIfNeeded()
    }

    func showHistory(near point: CGPoint? = nil) {
        refreshHistory()

        if panel?.isVisible != true {
            showShelf(near: point ?? NSEvent.mouseLocation)
        }
        isShowingHistory = true
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func hideHistory() {
        isShowingHistory = false
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func restoreHistoryEntry(id: UUID) {
        refreshHistory()
        guard let entry = historyEntries.first(where: { $0.id == id }) else {
            return
        }

        let availableURLs = entry.urls.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !availableURLs.isEmpty else {
            historyEntries = historyStore.removing(
                entryID: id,
                from: historyEntries
            )
            return
        }

        let wasVisible = isShelfVisible
        let wasEmpty = items.isEmpty
        let isOpenInAnotherShelf = Self.shelves.contains {
            $0 !== self && $0.currentHistoryEntryID == entry.id
        }
        if (wasEmpty && !isOpenInAnotherShelf) || currentHistoryEntryID == entry.id {
            currentHistoryEntryID = entry.id
        } else {
            // Restoring into a non-empty Shelf creates a merged session. It
            // must not overwrite either original history entry when closed.
            currentHistoryEntryID = nil
        }
        currentShelfName = entry.name
        add(urls: availableURLs)
        isShowingHistory = false
        updatePanelLayout(animated: true)
        if wasVisible {
            scheduleAutoHideIfNeeded()
        } else {
            showShelf(near: NSEvent.mouseLocation)
        }
    }

    func promptToNameCurrentShelf() {
        guard canNameCurrentShelf else { return }
        cancelAutoHide()

        let alert = NSAlert()
        alert.messageText = currentShelfName == nil ? String(localized: "Name this Shelf") : String(localized: "Rename this Shelf")
        alert.informativeText = String(localized: "This name will appear in Recent Shelves and the menu bar when pinned.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let nameField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 280, height: 24)
        )
        nameField.placeholderString = String(localized: "e.g. Design review")
        nameField.stringValue = currentShelfName ?? ""
        alert.accessoryView = nameField

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = nameField
        if alert.runModal() == .alertFirstButtonReturn {
            setCurrentShelfName(nameField.stringValue)
        }
        scheduleAutoHideIfNeeded()
    }

    func setCurrentShelfName(_ name: String?) {
        let normalizedName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        currentShelfName = normalizedName.flatMap { value in
            guard !value.isEmpty else { return nil }
            return String(value.prefix(80))
        }
        synchronizeCurrentHistoryEntryIfNeeded()
        scheduleAutoHideIfNeeded()
    }

    func toggleCurrentShelfPin() {
        guard canPinCurrentShelf else { return }
        refreshHistory()

        let entryID = currentHistoryEntryID ?? UUID()
        let isCurrentlyPinned = historyEntries
            .first(where: { $0.id == entryID })?
            .isPinned == true

        historyEntries = historyStore.updatingSnapshot(
            entryID: entryID,
            urls: sessionURLs,
            name: currentShelfName,
            isPinned: !isCurrentlyPinned,
            in: historyEntries
        )
        currentHistoryEntryID = historyEntries.contains(where: { $0.id == entryID })
            ? entryID
            : nil
        scheduleAutoHideIfNeeded()
    }

    func toggleHistoryPin(id: UUID) {
        refreshHistory()
        guard let entry = historyEntries.first(where: { $0.id == id }) else {
            return
        }

        historyEntries = historyStore.settingPinned(
            !entry.isPinned,
            entryID: id,
            in: historyEntries
        )
        if currentHistoryEntryID == id,
           !historyEntries.contains(where: { $0.id == id }) {
            currentHistoryEntryID = nil
        }
        scheduleAutoHideIfNeeded()
    }

    func clearAndCloseShelf() {
        cancelAutoHide()
        saveCurrentSessionToHistory()
        cancelAllConversions()
        ShelfIconCache.shared.remove(urls: Array(itemURLs))
        items.removeAll(keepingCapacity: false)
        selectedItemIDs.removeAll(keepingCapacity: false)
        itemURLs.removeAll(keepingCapacity: false)
        sessionURLs.removeAll(keepingCapacity: false)
        sessionURLSet.removeAll(keepingCapacity: false)
        currentHistoryEntryID = nil
        currentShelfName = nil
        isShowingHistory = false
        isReceivingDrop = false
        pendingDropItemCount = 0
        isKeptOnScreen = false
        isSearching = false
        searchText = ""
        if Self.active === self {
            Self.active = Self.shelves.last { $0 !== self && $0.isShelfVisible } ?? self
        }

        // Keep the lightweight NSPanel alive and reusable. Releasing a window
        // while AppKit is finishing a transform animation can crash. Its much
        // heavier SwiftUI tree is still detached after this button action ends.
        hidePanelAndDetachContent()
    }

    func removeItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        cancelConversion(for: id)
        let removedURL = items[index].url
        items.remove(at: index)
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        }
        itemURLs.remove(removedURL)
        ShelfIconCache.shared.remove(urls: [removedURL])

        if closeShelfIfNeeded() {
            return
        }
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func add(urls: [URL]) {
        var additions: [ShelfItem] = []
        additions.reserveCapacity(urls.count)

        for url in urls {
            let normalizedURL = url.standardizedFileURL
            guard normalizedURL.isFileURL,
                  itemURLs.insert(normalizedURL).inserted else {
                continue
            }
            additions.append(ShelfItem(url: normalizedURL))

            if sessionURLSet.insert(normalizedURL).inserted {
                sessionURLs.append(normalizedURL)
            }
        }

        guard !additions.isEmpty else { return }
        markActive()
        items.append(contentsOf: additions)
        synchronizeCurrentHistoryEntryIfNeeded()
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func prepareForTermination() {
        invalidateAutoHideTimer()
        saveCurrentSessionToHistory()
        cancelAllConversions()
    }

    func selectItem(_ id: UUID, extendingSelection: Bool) {
        var newSelection = selectedItemIDs

        if extendingSelection {
            if newSelection.contains(id) {
                newSelection.remove(id)
            } else {
                newSelection.insert(id)
            }
        } else {
            newSelection = [id]
        }

        guard newSelection != selectedItemIDs else { return }
        selectedItemIDs = newSelection
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func clearSelection() {
        guard !selectedItemIDs.isEmpty else { return }
        selectedItemIDs.removeAll(keepingCapacity: true)
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func setDropTargetActive(_ isActive: Bool, itemCount: Int = 0) {
        let normalizedCount = isActive ? max(0, itemCount) : 0
        guard isReceivingDrop != isActive || pendingDropItemCount != normalizedCount else {
            return
        }
        isReceivingDrop = isActive
        pendingDropItemCount = normalizedCount
        scheduleAutoHideIfNeeded()
    }

    func itemsForDrag(startingWith id: UUID, extendingSelection: Bool = false) -> [ShelfItem] {
        if !selectedItemIDs.contains(id) {
            selectItem(id, extendingSelection: extendingSelection)
        }

        return items.filter { selectedItemIDs.contains($0.id) }
    }

    func outboundDragDidSucceed(itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }

        for id in itemIDs {
            cancelConversion(for: id)
        }

        let removedURLs = items.lazy
            .filter { itemIDs.contains($0.id) }
            .map(\.url)
        let removedURLArray = Array(removedURLs)

        items.removeAll { itemIDs.contains($0.id) }
        let newSelection = selectedItemIDs.subtracting(itemIDs)
        if newSelection != selectedItemIDs {
            selectedItemIDs = newSelection
        }
        itemURLs.subtract(removedURLArray)
        ShelfIconCache.shared.remove(urls: removedURLArray)

        if closeShelfIfNeeded() {
            return
        }
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    // MARK: - Item actions

    /// The selection when `id` is part of it, otherwise just that item.
    func actionItems(for id: UUID? = nil) -> [ShelfItem] {
        if let id, !selectedItemIDs.contains(id) {
            return items.filter { $0.id == id }
        }
        return items.filter { selectedItemIDs.contains($0.id) }
    }

    func openItems(for id: UUID? = nil) {
        for item in actionItems(for: id) {
            NSWorkspace.shared.open(item.url)
        }
    }

    func revealItems(for id: UUID? = nil) {
        let urls = actionItems(for: id).map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyItems(for id: UUID? = nil) {
        let urls = actionItems(for: id).map { $0.url as NSURL }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
    }

    func copyPaths(for id: UUID? = nil) {
        let paths = actionItems(for: id).map(\.url.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func pasteFromClipboard() {
        add(urls: ShelfPasteboardImporter.fileURLs(from: .general))
    }

    func removeSelectedItems() {
        for id in selectedItemIDs {
            removeItem(id: id)
        }
    }

    func selectAllItems() {
        let allIDs = Set(visibleItems.map(\.id))
        guard allIDs != selectedItemIDs else { return }
        selectedItemIDs = allIDs
        updatePanelLayout(animated: true)
        scheduleAutoHideIfNeeded()
    }

    func moveSelection(by offset: Int, extendingSelection: Bool) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let currentIndex = items.lastIndex { selectedItemIDs.contains($0.id) }
        let nextIndex = currentIndex.map { min(max($0 + offset, 0), items.count - 1) }
            ?? (offset > 0 ? 0 : items.count - 1)
        let nextID = items[nextIndex].id
        if extendingSelection {
            guard !selectedItemIDs.contains(nextID) else { return }
            selectItem(nextID, extendingSelection: true)
        } else {
            selectItem(nextID, extendingSelection: false)
        }
    }

    private(set) var quickLookURLs: [URL] = []

    func toggleQuickLook(for id: UUID? = nil) {
        guard let previewPanel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), previewPanel.isVisible {
            previewPanel.orderOut(nil)
            return
        }

        var urls = actionItems(for: id).map(\.url)
        if urls.isEmpty, let first = items.first {
            urls = [first.url]
        }
        guard !urls.isEmpty else { return }
        quickLookURLs = urls
        cancelAutoHide()

        // QLPreviewPanel finds its controller through the key window's
        // responder chain, which ShelfPanel joins.
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
        previewPanel.makeKeyAndOrderFront(nil)
        previewPanel.reloadData()
    }

    func quickLookDidEnd() {
        quickLookURLs = []
        scheduleAutoHideIfNeeded()
    }

    /// Esc hides the Shelf but keeps its items, like an inactivity auto-hide.
    func dismissShelf() {
        if isSearching {
            toggleSearch()
        } else if isShowingHistory {
            hideHistory()
        } else if !selectedItemIDs.isEmpty {
            clearSelection()
        } else if !isKeptOnScreen {
            hideShelf()
        }
    }

    func toggleKeepOnScreen() {
        isKeptOnScreen.toggle()
        scheduleAutoHideIfNeeded()
    }

    /// Called after the user drags the Shelf by its handle.
    func shelfPanelDidFinishMove() {
        guard let panel else { return }
        var frame = panel.frame
        if preferences.snapToScreenEdges, let visibleFrame = panel.screen?.visibleFrame {
            frame = ShelfPanel.snappedFrame(frame, in: visibleFrame)
            if frame != panel.frame {
                panel.setFrame(frame, display: true, animate: true)
            }
        }
        preferences.lastShelfCenter = CGPoint(x: frame.midX, y: frame.midY)
        scheduleAutoHideIfNeeded()
    }

    // MARK: - Image tools

    func applyImageTool(_ operation: ImageToolOperation, to id: UUID) {
        let targets = actionItems(for: id).filter { conversionState(for: $0.id) != .converting }
        guard !targets.isEmpty else { return }
        for item in targets {
            conversionStates[item.id] = .converting
        }

        Task { [weak self] in
            var outputURLs: [URL] = []
            var failures: [String] = []
            for item in targets {
                let sourceURL = item.url
                do {
                    outputURLs.append(try await Task.detached(priority: .userInitiated) {
                        try ImageTools.apply(operation, to: sourceURL)
                    }.value)
                } catch {
                    failures.append(
                        targets.count == 1
                            ? error.localizedDescription
                            : "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
                    )
                }
                if self?.conversionStates[item.id] == .converting {
                    self?.conversionStates.removeValue(forKey: item.id)
                }
            }

            guard let self else { return }
            self.add(urls: outputURLs)
            if !failures.isEmpty {
                self.showAlert(
                    title: failures.count == 1
                        ? String(localized: "Couldn’t process image")
                        : String(localized: "Couldn’t process \(failures.count) images"),
                    message: failures.joined(separator: "\n")
                )
            }
        }
    }

    // MARK: - Rename

    func promptToRenameItems(for id: UUID? = nil) {
        let targets = actionItems(for: id)
        guard let first = targets.first else { return }
        cancelAutoHide()

        let alert = NSAlert()
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        if targets.count == 1 {
            alert.messageText = String(localized: "Rename “\(first.url.lastPathComponent)”")
            alert.informativeText = String(localized: "The file is renamed in place on disk.")
            nameField.stringValue = first.url.lastPathComponent
        } else {
            alert.messageText = String(localized: "Rename \(targets.count) Items")
            alert.informativeText = String(localized: "Files are renamed in place, numbered in Shelf order: “Name 1”, “Name 2”, … Extensions are kept.")
            nameField.stringValue = first.url.deletingPathExtension().lastPathComponent
        }
        alert.accessoryView = nameField

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = nameField
        if alert.runModal() == .alertFirstButtonReturn,
           let message = renameItems(targets, to: nameField.stringValue) {
            showAlert(title: String(localized: "Couldn’t rename"), message: message)
        }
        scheduleAutoHideIfNeeded()
    }

    /// Renames the files on disk and updates the Shelf. Returns an error
    /// message, leaving every file untouched, when any rename can't happen.
    @discardableResult
    func renameItems(_ requestedItems: [ShelfItem], to name: String) -> String? {
        let targets = items.filter { item in requestedItems.contains { $0.id == item.id } }
        guard !targets.isEmpty else { return nil }
        if let error = ShelfRenamePlanner.validationError(for: name) {
            return error
        }

        let fileManager = FileManager.default
        let plannedURLs = ShelfRenamePlanner.plannedURLs(
            for: targets.map(\.url),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        for (item, newURL) in zip(targets, plannedURLs)
            where newURL != item.url
                && fileManager.fileExists(atPath: newURL.path)
                && !ShelfRenamePlanner.isSameFile(item.url, newURL) {
            return String(localized: "“\(newURL.lastPathComponent)” already exists in that folder.")
        }

        var completed: [(from: URL, to: URL)] = []
        for (item, newURL) in zip(targets, plannedURLs) where newURL != item.url {
            do {
                try fileManager.moveItem(at: item.url, to: newURL)
                completed.append((item.url, newURL))
            } catch {
                for move in completed.reversed() {
                    try? fileManager.moveItem(at: move.to, to: move.from)
                }
                return error.localizedDescription
            }
        }

        let renamedURLs = Dictionary(uniqueKeysWithValues: completed.map { ($0.from, $0.to) })
        guard !renamedURLs.isEmpty else { return nil }
        items = items.map { item in
            renamedURLs[item.url].map { ShelfItem(id: item.id, url: $0) } ?? item
        }
        itemURLs = Set(items.map(\.url))
        sessionURLs = sessionURLs.map { renamedURLs[$0] ?? $0 }
        sessionURLSet = Set(sessionURLs)
        ShelfIconCache.shared.remove(urls: Array(renamedURLs.keys))
        synchronizeCurrentHistoryEntryIfNeeded()
        return nil
    }

    func shelfDidReceiveUserActivity() {
        markActive()
        scheduleAutoHideIfNeeded()
    }

    func conversionState(for itemID: UUID) -> ConversionState {
        conversionStates[itemID] ?? .idle
    }

    func requestConversion(of item: ShelfItem, using option: ConversionOption) {
        requestConversion(of: [item], using: option)
    }

    /// Converts every item to `option.targetFormat` into one chosen folder,
    /// one file at a time, then reveals all outputs together.
    func requestConversion(of requestedItems: [ShelfItem], using option: ConversionOption) {
        let targets = requestedItems.filter { item in
            items.contains(where: { $0.id == item.id })
                && conversionState(for: item.id) != .converting
        }
        guard !targets.isEmpty else { return }

        scheduleAutoHideIfNeeded()

        if let warning = option.warning {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = targets.count == 1
                ? String(localized: "Convert to \(option.targetFormat.displayName)?")
                : String(localized: "Convert \(targets.count) items to \(option.targetFormat.displayName)?")
            alert.informativeText = warning
            alert.addButton(withTitle: String(localized: "Continue"))
            alert.addButton(withTitle: String(localized: "Cancel"))

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let folderPanel = NSOpenPanel()
        folderPanel.title = String(localized: "Choose Destination Folder")
        folderPanel.prompt = String(localized: "Choose")
        folderPanel.canChooseFiles = false
        folderPanel.canChooseDirectories = true
        folderPanel.allowsMultipleSelection = false
        folderPanel.canCreateDirectories = true
        folderPanel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first

        NSApp.activate(ignoringOtherApps: true)
        guard let destinationDirectory = ConversionDestinationSelection.resolve(
            response: folderPanel.runModal(),
            selectedURL: folderPanel.url
        ) else {
            return
        }

        let token = UUID()
        for item in targets {
            conversionStates[item.id] = .converting
            conversionTokens[item.id] = token
        }

        let targetFormat = option.targetFormat
        conversionTasks[token] = Task { [weak self] in
            var outputURLs: [URL] = []
            var failures: [String] = []

            for item in targets {
                guard !Task.isCancelled else { break }
                guard self?.conversionTokens[item.id] == token else { continue }
                do {
                    let urls = try await ConversionService.shared.convertAll(
                        item.url,
                        to: targetFormat,
                        destinationDirectory: destinationDirectory
                    )
                    try Task.checkCancellation()
                    outputURLs += urls
                    self?.finishConversion(for: item.id, token: token, outputURLs: urls)
                } catch is CancellationError {
                    self?.finishConversion(for: item.id, token: token, outputURLs: nil)
                } catch {
                    NSLog("DropShelf conversion failed: %@", String(reflecting: error))
                    failures.append(
                        targets.count == 1
                            ? error.localizedDescription
                            : "\(item.url.lastPathComponent): \(error.localizedDescription)"
                    )
                    self?.finishConversion(
                        for: item.id,
                        token: token,
                        failure: error.localizedDescription
                    )
                }
            }

            guard let self, self.conversionTasks.removeValue(forKey: token) != nil else {
                return
            }
            if !outputURLs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(outputURLs)
            }
            if !failures.isEmpty {
                self.showAlert(
                    title: failures.count == 1
                        ? String(localized: "Couldn’t convert file")
                        : String(localized: "Couldn’t convert \(failures.count) files"),
                    message: failures.joined(separator: "\n")
                )
            }
        }
    }

    func airDropAllItems() {
        scheduleAutoHideIfNeeded()
        let urls = bulkActionItems.map(\.url)
        guard !urls.isEmpty else { return }

        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            showAlert(
                title: String(localized: "AirDrop is unavailable"),
                message: String(localized: "macOS could not start AirDrop for the files currently in the Shelf.")
            )
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    func zipAllItems() {
        guard !bulkActionItems.isEmpty, !isCreatingArchive else { return }

        scheduleAutoHideIfNeeded()

        let sourceURLs = bulkActionItems.map(\.url)
        let savePanel = NSSavePanel()
        savePanel.title = usesSelectionForBulkActions
            ? String(localized: "Zip Selected Shelf Items")
            : String(localized: "Zip All Shelf Items")
        savePanel.prompt = String(localized: "Create ZIP")
        savePanel.nameFieldStringValue = "DropShelf.zip"
        savePanel.allowedContentTypes = [.zip]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.directoryURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first

        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK,
              let destinationURL = savePanel.url else {
            return
        }

        guard !Self.destination(destinationURL, overlaps: sourceURLs) else {
            showAlert(
                title: String(localized: "Choose another location"),
                message: String(localized: "The ZIP cannot replace an item in the Shelf or be created inside a folder that is being zipped.")
            )
            return
        }

        isCreatingArchive = true
        Self.archiveQueue.async { [weak self] in
            let result: ZipArchiveResult
            do {
                try ZipArchiver.createArchive(
                    from: sourceURLs,
                    at: destinationURL
                )
                result = .success(destinationURL)
            } catch {
                result = .failure(error.localizedDescription)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCreatingArchive = false

                switch result {
                case let .success(archiveURL):
                    NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
                case let .failure(message):
                    self.showAlert(
                        title: String(localized: "Couldn’t create ZIP"),
                        message: message
                    )
                }
            }
        }
    }

    private static func destination(_ destinationURL: URL, overlaps sourceURLs: [URL]) -> Bool {
        let destinationPath = destinationURL.standardizedFileURL.path

        for sourceURL in sourceURLs {
            let source = sourceURL.standardizedFileURL
            if source.path == destinationPath {
                return true
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               destinationPath.hasPrefix(source.path + "/") {
                return true
            }
        }

        return false
    }

    private var bulkActionItems: [ShelfItem] {
        guard usesSelectionForBulkActions else { return visibleItems }
        return items.filter { selectedItemIDs.contains($0.id) }
    }

    private func updatePanelLayout(animated: Bool) {
        panel?.updateLayout(
            itemCount: visibleItems.count,
            selectionCount: selectedItemIDs.count,
            showingHistory: isShowingHistory,
            showingSearch: isSearching,
            animated: animated
        )
    }

    /// `outputURLs == nil` with no failure means the item was cancelled.
    private func finishConversion(
        for itemID: UUID,
        token: UUID,
        outputURLs: [URL]? = nil,
        failure: String? = nil
    ) {
        guard conversionTokens[itemID] == token else { return }
        conversionTokens.removeValue(forKey: itemID)

        if let failure {
            conversionStates[itemID] = .failed(failure)
        } else if let firstOutputURL = outputURLs?.first {
            conversionStates[itemID] = .success(firstOutputURL)
        } else if outputURLs != nil {
            conversionStates[itemID] = .failed(String(localized: "The conversion did not produce any files."))
        } else {
            conversionStates[itemID] = .idle
        }
    }

    private func cancelConversion(for itemID: UUID) {
        conversionStates.removeValue(forKey: itemID)
        guard let token = conversionTokens.removeValue(forKey: itemID) else { return }
        // A batch keeps running for its other items; it skips this one.
        if !conversionTokens.values.contains(token) {
            conversionTasks.removeValue(forKey: token)?.cancel()
        }
    }

    private func cancelAllConversions() {
        for task in conversionTasks.values {
            task.cancel()
        }
        conversionTasks.removeAll(keepingCapacity: false)
        conversionTokens.removeAll(keepingCapacity: false)
        conversionStates.removeAll(keepingCapacity: false)
    }

    private func shelfBehaviorPreferencesDidChange() {
        if preferences.closeShelfWhenEmpty,
           items.isEmpty,
           panel?.isVisible == true,
           !isShowingHistory {
            clearAndCloseShelf()
            return
        }

        scheduleAutoHideIfNeeded()
    }

    @discardableResult
    private func closeShelfIfNeeded() -> Bool {
        guard preferences.closeShelfWhenEmpty, items.isEmpty, !isKeptOnScreen else {
            return false
        }

        clearAndCloseShelf()
        return true
    }

    private func scheduleAutoHideIfNeeded() {
        cancelAutoHide()
        guard preferences.automaticallyHideAfterTenSeconds,
              !isKeptOnScreen,
              panel?.isVisible == true else {
            return
        }

        let leewayMilliseconds = min(
            250,
            max(1, Int(autoHideDelay * 100))
        )
        let deadline = DispatchTime.now() + autoHideDelay

        if let autoHideTimer {
            autoHideTimer.schedule(
                deadline: deadline,
                leeway: .milliseconds(leewayMilliseconds)
            )
        } else {
            let newTimer = DispatchSource.makeTimerSource(queue: .main)
            newTimer.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.autoHideTimerDidFire()
                }
            }
            newTimer.schedule(
                deadline: deadline,
                leeway: .milliseconds(leewayMilliseconds)
            )
            autoHideTimer = newTimer
            newTimer.resume()
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.schedule(deadline: .distantFuture)
    }

    private func invalidateAutoHideTimer() {
        autoHideTimer?.setEventHandler {}
        autoHideTimer?.cancel()
        autoHideTimer = nil
    }

    private func autoHideTimerDidFire() {
        guard preferences.automaticallyHideAfterTenSeconds,
              panel?.isVisible == true else {
            cancelAutoHide()
            return
        }
        hideShelf()
    }

    private func hideShelf() {
        cancelAutoHide()
        isShowingHistory = false
        hidePanelAndDetachContent()
    }

    private func hidePanelAndDetachContent() {
        let panelToHide = panel
        panelToHide?.orderOut(nil)
        DispatchQueue.main.async { [weak self, weak panelToHide] in
            guard let self,
                  self.panel === panelToHide,
                  panelToHide?.isVisible == false else {
                return
            }
            panelToHide?.contentView = nil
        }
    }

    func refreshHistory() {
        historyEntries = historyStore.load()
        if let currentHistoryEntryID,
           !historyEntries.contains(where: { $0.id == currentHistoryEntryID }) {
            self.currentHistoryEntryID = nil
        }
    }

    private func saveCurrentSessionToHistory() {
        guard !sessionURLs.isEmpty else {
            refreshHistory()
            return
        }

        if let currentHistoryEntryID,
           let entry = historyEntries.first(where: { $0.id == currentHistoryEntryID }) {
            historyEntries = historyStore.updatingSnapshot(
                entryID: currentHistoryEntryID,
                urls: sessionURLs,
                name: currentShelfName,
                isPinned: entry.isPinned,
                in: historyEntries
            )
        } else {
            historyEntries = historyStore.addingSnapshot(
                urls: sessionURLs,
                name: currentShelfName,
                to: historyEntries
            )
        }
    }

    private func synchronizeCurrentHistoryEntryIfNeeded() {
        guard let currentHistoryEntryID,
              let entry = historyEntries.first(where: { $0.id == currentHistoryEntryID }) else {
            return
        }

        historyEntries = historyStore.updatingSnapshot(
            entryID: currentHistoryEntryID,
            urls: sessionURLs,
            name: currentShelfName,
            isPinned: entry.isPinned,
            in: historyEntries
        )
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}

enum ConversionDestinationSelection {
    static func resolve(
        response: NSApplication.ModalResponse,
        selectedURL: URL?
    ) -> URL? {
        guard response == .OK else { return nil }
        return selectedURL
    }
}

enum ZipArchiver {
    static func createArchive(from sourceURLs: [URL], at destinationURL: URL) throws {
        let fileManager = FileManager.default
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".DropShelf-\(UUID().uuidString).zip")

        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")

        // Change into each item's parent directory before adding it. This keeps
        // every item at the ZIP's top level instead of storing its full path,
        // while still allowing files from unrelated Finder folders.
        var arguments = ["--format", "zip", "-c", "-f", temporaryURL.path]
        arguments.reserveCapacity(5 + (sourceURLs.count * 3))
        for sourceURL in sourceURLs {
            arguments.append(contentsOf: [
                "-C",
                sourceURL.deletingLastPathComponent().path,
                "./\(sourceURL.lastPathComponent)"
            ])
        }
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = details.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(localized: "The archive tool exited with status \(process.terminationStatus).")
            throw ZipArchiveError.creationFailed(
                message
            )
        }

        var renameError: Int32 = 0
        temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let temporaryPath, let destinationPath else {
                    renameError = EINVAL
                    return
                }

                if Darwin.rename(temporaryPath, destinationPath) != 0 {
                    renameError = errno
                }
            }
        }

        if renameError != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: renameError) ?? .EIO)
        }
    }
}

private enum ZipArchiveResult: Sendable {
    case success(URL)
    case failure(String)
}

private enum ZipArchiveError: LocalizedError {
    case creationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .creationFailed(message):
            return message
        }
    }
}

enum ShelfRenamePlanner {
    static func validationError(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String(localized: "Enter a name.") }
        if trimmed.contains("/") || trimmed.contains(":") {
            return String(localized: "Names can’t contain “/” or “:”.")
        }
        if trimmed.hasPrefix(".") { return String(localized: "Names can’t start with a period.") }
        if trimmed.count > 200 { return String(localized: "That name is too long.") }
        return nil
    }

    /// One URL: renamed to `name` exactly. Several: "name 1.ext", "name 2.ext",
    /// zero-padded so they sort in order, each staying in its own folder.
    static func plannedURLs(for urls: [URL], name: String) -> [URL] {
        guard urls.count > 1 else {
            return urls.map { $0.deletingLastPathComponent().appendingPathComponent(name) }
        }

        let width = String(urls.count).count
        return urls.enumerated().map { index, url in
            let number = String(index + 1)
            let padded = String(repeating: "0", count: width - number.count) + number
            let fileExtension = url.pathExtension
            let fileName = fileExtension.isEmpty
                ? "\(name) \(padded)"
                : "\(name) \(padded).\(fileExtension)"
            return url.deletingLastPathComponent().appendingPathComponent(fileName)
        }
    }

    /// True for a case-only rename on a case-insensitive volume.
    static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let left = try? lhs.resourceValues(forKeys: key).fileResourceIdentifier,
              let right = try? rhs.resourceValues(forKeys: key).fileResourceIdentifier else {
            return false
        }
        return left.isEqual(right)
    }
}
