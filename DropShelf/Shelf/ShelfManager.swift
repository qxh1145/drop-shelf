import AppKit
import Combine
import Darwin
import UniformTypeIdentifiers

@MainActor
final class ShelfManager: ObservableObject {
    static let shared = ShelfManager()

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedItemIDs: Set<UUID> = []
    @Published private(set) var isCreatingArchive = false
    @Published private(set) var conversionStates: [UUID: ConversionState] = [:]
    @Published private(set) var historyEntries: [ShelfHistoryEntry]
    @Published private(set) var isShowingHistory = false
    @Published private(set) var currentShelfName: String?

    private var panel: ShelfPanel?
    private var currentHistoryEntryID: UUID?
    private var itemURLs: Set<URL> = []
    private var sessionURLs: [URL] = []
    private var sessionURLSet: Set<URL> = []
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

    func showShelf(near point: CGPoint) {
        isShowingHistory = false

        if panel == nil {
            panel = ShelfPanel(manager: self)
        } else if panel?.contentView == nil {
            panel?.contentView = ShelfDropHostingView(manager: self)
        }

        panel?.position(near: point)
        panel?.orderFrontRegardless()
        scheduleAutoHideIfNeeded()
    }

    func showHistory(near point: CGPoint? = nil) {
        refreshHistory()

        if panel?.isVisible != true {
            showShelf(near: point ?? NSEvent.mouseLocation)
        }
        isShowingHistory = true
        scheduleAutoHideIfNeeded()
    }

    func hideHistory() {
        isShowingHistory = false
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
        if wasEmpty || currentHistoryEntryID == entry.id {
            currentHistoryEntryID = entry.id
        } else {
            // Restoring into a non-empty Shelf creates a merged session. It
            // must not overwrite either original history entry when closed.
            currentHistoryEntryID = nil
        }
        currentShelfName = entry.name
        add(urls: availableURLs)
        isShowingHistory = false
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
        alert.messageText = currentShelfName == nil ? "Name this Shelf" : "Rename this Shelf"
        alert.informativeText = "This name will appear in Recent Shelves and the menu bar when pinned."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 280, height: 24)
        )
        nameField.placeholderString = "e.g. Design review"
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
        items.removeAll(keepingCapacity: false)
        selectedItemIDs.removeAll(keepingCapacity: false)
        itemURLs.removeAll(keepingCapacity: false)
        sessionURLs.removeAll(keepingCapacity: false)
        sessionURLSet.removeAll(keepingCapacity: false)
        currentHistoryEntryID = nil
        currentShelfName = nil
        isShowingHistory = false
        ShelfIconCache.shared.removeAll()

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
        items.append(contentsOf: additions)
        synchronizeCurrentHistoryEntryIfNeeded()
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
        scheduleAutoHideIfNeeded()
    }

    func shelfDidReceiveUserActivity() {
        scheduleAutoHideIfNeeded()
    }

    func conversionState(for itemID: UUID) -> ConversionState {
        conversionStates[itemID] ?? .idle
    }

    func requestConversion(of item: ShelfItem, using option: ConversionOption) {
        guard items.contains(where: { $0.id == item.id }),
              conversionState(for: item.id) != .converting else {
            return
        }

        scheduleAutoHideIfNeeded()

        if let warning = option.warning {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Convert to \(option.targetFormat.displayName)?"
            alert.informativeText = warning
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let folderPanel = NSOpenPanel()
        folderPanel.title = "Choose Destination Folder"
        folderPanel.prompt = "Choose"
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

        let itemID = item.id
        let token = UUID()
        conversionStates[itemID] = .converting
        conversionTokens[itemID] = token

        let task = Task { [weak self] in
            do {
                let outputURLs = try await ConversionService.shared.convertAll(
                    item.url,
                    to: option.targetFormat,
                    destinationDirectory: destinationDirectory
                )
                try Task.checkCancellation()
                self?.finishConversion(
                    for: itemID,
                    token: token,
                    result: .success(outputURLs)
                )
            } catch is CancellationError {
                self?.finishCancelledConversion(for: itemID, token: token)
            } catch {
                NSLog("DropShelf conversion failed: %@", String(reflecting: error))
                self?.finishConversion(
                    for: itemID,
                    token: token,
                    result: .failure(error.localizedDescription)
                )
            }
        }
        conversionTasks[itemID] = task
    }

    func airDropAllItems() {
        scheduleAutoHideIfNeeded()
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }

        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            showAlert(
                title: "AirDrop is unavailable",
                message: "macOS could not start AirDrop for the files currently in the Shelf."
            )
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    func zipAllItems() {
        guard !items.isEmpty, !isCreatingArchive else { return }

        scheduleAutoHideIfNeeded()

        let sourceURLs = items.map(\.url)
        let savePanel = NSSavePanel()
        savePanel.title = "Zip All Shelf Items"
        savePanel.prompt = "Create ZIP"
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
                title: "Choose another location",
                message: "The ZIP cannot replace an item in the Shelf or be created inside a folder that is being zipped."
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
                        title: "Couldn’t create ZIP",
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

    private func finishConversion(
        for itemID: UUID,
        token: UUID,
        result: ConversionResult
    ) {
        guard conversionTokens[itemID] == token else { return }

        conversionTasks.removeValue(forKey: itemID)
        conversionTokens.removeValue(forKey: itemID)

        switch result {
        case let .success(outputURLs):
            guard let firstOutputURL = outputURLs.first else {
                conversionStates[itemID] = .failed("The conversion did not produce any files.")
                return
            }
            conversionStates[itemID] = .success(firstOutputURL)
            NSWorkspace.shared.activateFileViewerSelecting(outputURLs)
        case let .failure(message):
            conversionStates[itemID] = .failed(message)
            showAlert(title: "Couldn’t convert file", message: message)
        }
    }

    private func finishCancelledConversion(for itemID: UUID, token: UUID) {
        guard conversionTokens[itemID] == token else { return }
        conversionTasks.removeValue(forKey: itemID)
        conversionTokens.removeValue(forKey: itemID)
        conversionStates[itemID] = .idle
    }

    private func cancelConversion(for itemID: UUID) {
        conversionTasks.removeValue(forKey: itemID)?.cancel()
        conversionTokens.removeValue(forKey: itemID)
        conversionStates.removeValue(forKey: itemID)
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
        guard preferences.closeShelfWhenEmpty, items.isEmpty else {
            return false
        }

        clearAndCloseShelf()
        return true
    }

    private func scheduleAutoHideIfNeeded() {
        cancelAutoHide()
        guard preferences.automaticallyHideAfterTenSeconds,
              panel?.isVisible == true else {
            return
        }

        let timer: any DispatchSourceTimer
        if let autoHideTimer {
            timer = autoHideTimer
        } else {
            let newTimer = DispatchSource.makeTimerSource(queue: .main)
            newTimer.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.autoHideTimerDidFire()
                }
            }
            newTimer.resume()
            autoHideTimer = newTimer
            timer = newTimer
        }
        timer.schedule(
            deadline: .now() + autoHideDelay,
            leeway: .milliseconds(250)
        )
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
        alert.addButton(withTitle: "OK")
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

private enum ConversionResult: Sendable {
    case success([URL])
    case failure(String)
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
                ?? "The archive tool exited with status \(process.terminationStatus)."
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
