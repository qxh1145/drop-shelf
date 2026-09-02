import Foundation

struct ShelfItem: Identifiable, Hashable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
    }
}
