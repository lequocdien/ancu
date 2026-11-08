import Foundation

/// Bookmark lưu trên máy (JSON trong UserDefaults). Mock dùng cho mọi bookmark; Supabase chỉ dùng cho khách
/// (`isLocalOnly`) tới khi đăng nhập và gộp lên server.
struct LocalBookmarkStorage {
    private struct Record: Codable {
        let projectID: UUID
        var notifyEnabled: Bool
        let createdAt: Date
        var isLocalOnly: Bool
        /// Bản ghi cũ không có khóa này → `nil`.
        var note: String?
    }

    let defaults: UserDefaults
    var key = MockStorageKeys.bookmarks

    func load() -> [Bookmark] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records.map {
            Bookmark(projectID: $0.projectID, notifyEnabled: $0.notifyEnabled, createdAt: $0.createdAt, isLocalOnly: $0.isLocalOnly, note: $0.note)
        }
    }

    func save(_ bookmarks: [Bookmark]) throws {
        let records = bookmarks.map {
            Record(projectID: $0.projectID, notifyEnabled: $0.notifyEnabled, createdAt: $0.createdAt, isLocalOnly: $0.isLocalOnly, note: $0.note)
        }
        do {
            defaults.set(try JSONEncoder().encode(records), forKey: key)
        } catch {
            throw RepositoryError.decoding
        }
    }

    func update(_ transform: (inout [Bookmark]) throws -> Void) throws {
        var bookmarks = load()
        try transform(&bookmarks)
        try save(bookmarks)
    }
}
