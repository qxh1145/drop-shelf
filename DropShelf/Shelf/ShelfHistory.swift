import Foundation

struct ShelfHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let name: String?
    let isPinned: Bool
    let paths: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String? = nil,
        isPinned: Bool = false,
        urls: [URL]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.isPinned = isPinned
        self.paths = urls.map { $0.standardizedFileURL.path }
    }

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case name
        case isPinned
        case paths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        paths = try container.decode([String].self, forKey: .paths)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(paths, forKey: .paths)
    }
}

enum ShelfHistoryPresentation {
    static func displayName(for entry: ShelfHistoryEntry) -> String {
        entry.name ?? dateTitle(for: entry.createdAt)
    }

    static func detailLine(
        for entry: ShelfHistoryEntry,
        relativeTo now: Date = Date()
    ) -> String {
        let count = entry.paths.count
        return "\(dateTitle(for: entry.createdAt, relativeTo: now)) · \(count) item\(count == 1 ? "" : "s")"
    }

    static func fileSummary(
        for entry: ShelfHistoryEntry,
        maximumVisibleNames: Int = 3
    ) -> String {
        let visibleNames = entry.paths.prefix(maximumVisibleNames).map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
        let remainingCount = entry.paths.count - visibleNames.count
        let names = visibleNames.joined(separator: ", ")
        return remainingCount > 0 ? "\(names) +\(remainingCount) more" : names
    }

    static func dateTitle(
        for date: Date,
        relativeTo now: Date = Date()
    ) -> String {
        let day: String
        if Calendar.current.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if Calendar.current.isDate(
            date,
            inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        ) {
            day = "Yesterday"
        } else {
            day = dayFormatter.string(from: date)
        }

        let relative = relativeFormatter.localizedString(for: date, relativeTo: now)
        return "\(day) · \(relative)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

struct ShelfHistoryStore {
    static let retentionInterval: TimeInterval = 72 * 60 * 60
    static let maximumEntryCount = 100
    static let maximumURLsPerEntry = 200

    private static let defaultStorageKey = "DropShelf.ShelfHistory.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private let fileManager: FileManager

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = Self.defaultStorageKey,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.fileManager = fileManager
    }

    func load(now: Date = Date()) -> [ShelfHistoryEntry] {
        guard let data = defaults.data(forKey: storageKey),
              let storedEntries = try? JSONDecoder().decode(
                  [ShelfHistoryEntry].self,
                  from: data
              ) else {
            return []
        }

        let entries = sanitized(storedEntries, now: now)
        if entries != storedEntries {
            persist(entries)
        }
        return entries
    }

    func addingSnapshot(
        urls: [URL],
        name: String? = nil,
        isPinned: Bool = false,
        entryID: UUID = UUID(),
        to entries: [ShelfHistoryEntry],
        now: Date = Date()
    ) -> [ShelfHistoryEntry] {
        let availableURLs = uniqueAvailableURLs(urls)
        guard !availableURLs.isEmpty else {
            let currentEntries = sanitized(entries, now: now)
            if currentEntries != entries {
                persist(currentEntries)
            }
            return currentEntries
        }

        let snapshot = ShelfHistoryEntry(
            id: entryID,
            createdAt: now,
            name: name,
            isPinned: isPinned,
            urls: Array(availableURLs.prefix(Self.maximumURLsPerEntry))
        )
        let updatedEntries = sanitized([snapshot] + entries, now: now)
        persist(updatedEntries)
        return updatedEntries
    }

    func updatingSnapshot(
        entryID: UUID,
        urls: [URL],
        name: String?,
        isPinned: Bool,
        in entries: [ShelfHistoryEntry],
        now: Date = Date()
    ) -> [ShelfHistoryEntry] {
        let availableURLs = uniqueAvailableURLs(urls)
        guard !availableURLs.isEmpty else {
            return removing(entryID: entryID, from: entries, now: now)
        }

        let createdAt = entries.first(where: { $0.id == entryID })?.createdAt ?? now
        let snapshot = ShelfHistoryEntry(
            id: entryID,
            createdAt: createdAt,
            name: name,
            isPinned: isPinned,
            urls: Array(availableURLs.prefix(Self.maximumURLsPerEntry))
        )
        let updatedEntries = sanitized(
            [snapshot] + entries.filter { $0.id != entryID },
            now: now
        )
        persist(updatedEntries)
        return updatedEntries
    }

    func removing(
        entryID: UUID,
        from entries: [ShelfHistoryEntry],
        now: Date = Date()
    ) -> [ShelfHistoryEntry] {
        let updatedEntries = sanitized(
            entries.filter { $0.id != entryID },
            now: now
        )
        persist(updatedEntries)
        return updatedEntries
    }

    func settingPinned(
        _ isPinned: Bool,
        entryID: UUID,
        in entries: [ShelfHistoryEntry],
        now: Date = Date()
    ) -> [ShelfHistoryEntry] {
        let changedEntries = entries.map { entry in
            guard entry.id == entryID else { return entry }
            return ShelfHistoryEntry(
                id: entry.id,
                createdAt: entry.createdAt,
                name: entry.name,
                isPinned: isPinned,
                urls: entry.urls
            )
        }
        let updatedEntries = sanitized(changedEntries, now: now)
        persist(updatedEntries)
        return updatedEntries
    }

    private func sanitized(
        _ entries: [ShelfHistoryEntry],
        now: Date
    ) -> [ShelfHistoryEntry] {
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        let latestAllowedDate = now.addingTimeInterval(5 * 60)

        let validEntries = entries
            .filter {
                ($0.isPinned || $0.createdAt >= cutoff)
                    && $0.createdAt <= latestAllowedDate
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { entry -> ShelfHistoryEntry? in
                let availableURLs = uniqueAvailableURLs(entry.urls)
                guard !availableURLs.isEmpty else { return nil }
                return ShelfHistoryEntry(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    name: entry.name,
                    isPinned: entry.isPinned,
                    urls: Array(availableURLs.prefix(Self.maximumURLsPerEntry))
                )
            }

        var unpinnedCount = 0
        return validEntries.filter { entry in
            guard !entry.isPinned else { return true }
            guard unpinnedCount < Self.maximumEntryCount else { return false }
            unpinnedCount += 1
            return true
        }
    }

    private func uniqueAvailableURLs(_ urls: [URL]) -> [URL] {
        var seenURLs: Set<URL> = []
        var result: [URL] = []
        result.reserveCapacity(min(urls.count, Self.maximumURLsPerEntry))

        for url in urls {
            let normalizedURL = url.standardizedFileURL
            guard normalizedURL.isFileURL,
                  fileManager.fileExists(atPath: normalizedURL.path),
                  seenURLs.insert(normalizedURL).inserted else {
                continue
            }
            result.append(normalizedURL)

            if result.count == Self.maximumURLsPerEntry {
                break
            }
        }
        return result
    }

    private func persist(_ entries: [ShelfHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
