import Foundation

struct ShelfItem: Identifiable, Hashable, Codable {
    let id: UUID
    let url: URL
    // Follows the file when it is renamed or moved while on the Shelf.
    let bookmark: Data?

    init(id: UUID = UUID(), url: URL, bookmark: Data? = nil) {
        self.id = id
        self.url = url.standardizedFileURL
        self.bookmark = bookmark ?? (try? url.bookmarkData())
    }

    /// The item at its file's current location. A file deleted or moved to
    /// the Trash is missing; it keeps its old location so Put Back finds it.
    func located(
        resolvingBookmark: Bool = true,
        fileManager: FileManager = .default
    ) -> (item: ShelfItem, isMissing: Bool) {
        // A file still where it was skips the bookmark lookup.
        if fileManager.fileExists(atPath: url.path) {
            return (self, false)
        }

        var isStale = false
        guard resolvingBookmark,
              let bookmark,
              let resolved = try? URL(
                  resolvingBookmarkData: bookmark,
                  options: [.withoutUI, .withoutMounting],
                  bookmarkDataIsStale: &isStale
              ),
              fileManager.fileExists(atPath: resolved.path),
              !resolved.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) else {
            return (self, true)
        }
        return (ShelfItem(id: id, url: resolved, bookmark: isStale ? nil : bookmark), false)
    }
}

enum ShelfFileSize {
    /// Total bytes of the files, counting everything inside folders.
    static func bytes(of urls: [URL], fileManager: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        var total: Int64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            guard values.isDirectory == true else {
                total += Int64(values.fileSize ?? 0)
                continue
            }
            let contents = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys))
            while let file = contents?.nextObject() as? URL {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return total
    }

    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
