import Foundation

// Repository dữ liệu của người dùng đăng nhập (Phase 1 bước 4.2, 4.5, 3.6). Quyền do RLS + RPC phía server quyết định;
// kiểm tra "đã đăng nhập" ở đây chỉ để khách không tốn round-trip và nhận lỗi rõ ràng.

// MARK: - Bookmark

/// Khách: lưu tạm trên máy (`LocalBookmarkStorage`, `isLocalOnly`). Đăng nhập: server (`my_bookmarks`, `toggle_bookmark`…);
/// bookmark tạm chưa gộp được (lỗi mạng lúc đăng nhập) vẫn hiện và được gộp lại lần sau.
actor SupabaseBookmarkRepository: BookmarkRepository {
    static let guestStorageKey = "guest.bookmarks"

    private let rpc: any RPCClient
    private let auth: any AuthService
    private let guest: LocalBookmarkStorage
    private let now: @Sendable () -> Date

    private struct ProjectParams: Encodable, Sendable {
        let projectID: UUID
        enum CodingKeys: String, CodingKey { case projectID = "project_id" }
    }

    private struct NotifyParams: Encodable, Sendable {
        let projectID: UUID
        let enabled: Bool
        enum CodingKeys: String, CodingKey { case projectID = "project_id", enabled }
    }

    private struct MergeParams: Encodable, Sendable {
        let projectIDs: [UUID]
        enum CodingKeys: String, CodingKey { case projectIDs = "project_ids" }
    }

    init(rpc: any RPCClient, auth: any AuthService, suite: MockDefaultsSuite, now: @escaping @Sendable () -> Date = { .now }) {
        self.rpc = rpc
        self.auth = auth
        self.guest = LocalBookmarkStorage(defaults: suite.open(), key: Self.guestStorageKey)
        self.now = now
    }

    private var isSignedIn: Bool {
        get async { await auth.currentUser != nil }
    }

    func all() async throws -> [Bookmark] {
        let local = guest.load()
        guard await isSignedIn else { return local.sorted { $0.createdAt > $1.createdAt } }
        let dtos: [BookmarkDTO] = try await rpc.call("my_bookmarks")
        let remote = try dtos.map(DTOMapper.bookmark)
        let remoteIDs = Set(remote.map(\.projectID))
        return (remote + local.filter { !remoteIDs.contains($0.projectID) })
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func toggle(projectID: Project.ID) async throws -> Bool {
        guard await isSignedIn else {
            let createdAt = now()
            var isSaved = false
            try guest.update { bookmarks in
                if let index = bookmarks.firstIndex(where: { $0.projectID == projectID }) {
                    bookmarks.remove(at: index)
                } else {
                    bookmarks.append(Bookmark(projectID: projectID, notifyEnabled: false, createdAt: createdAt, isLocalOnly: true))
                    isSaved = true
                }
            }
            return isSaved
        }
        // Bookmark tạm chưa gộp: bỏ lưu = xóa bản trên máy.
        if guest.load().contains(where: { $0.projectID == projectID }) {
            try guest.update { $0.removeAll { $0.projectID == projectID } }
            return false
        }
        return try await rpc.call("toggle_bookmark", params: ProjectParams(projectID: projectID))
    }

    func setNotify(_ enabled: Bool, projectID: Project.ID) async throws {
        guard await isSignedIn else { throw RepositoryError.unauthorized }
        let _: Data = try await rpc.call("set_bookmark_notify", params: NotifyParams(projectID: projectID, enabled: enabled))
    }

    func mergeGuestBookmarks() async throws {
        guard await isSignedIn else { throw RepositoryError.unauthorized }
        let ids = guest.load().map(\.projectID)
        guard !ids.isEmpty else { return }
        let _: Int = try await rpc.call("merge_guest_bookmarks", params: MergeParams(projectIDs: ids))
        // Chỉ xóa bản trên máy khi server đã nhận (id dự án đã bị gỡ thì server bỏ qua — cũng không cần giữ).
        try guest.save([])
    }
}

// MARK: - Notification

struct SupabaseNotificationRepository: NotificationRepository {
    let rpc: any RPCClient
    let auth: any AuthService

    private struct ReadParams: Encodable, Sendable {
        let notificationID: UUID
        enum CodingKeys: String, CodingKey { case notificationID = "notification_id" }
    }

    func inbox() async throws -> [AppNotification] {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        let dtos: [NotificationDTO] = try await rpc.call("inbox")
        return try dtos.map { try DTOMapper.notification($0, shift: .none) }
    }

    func markAsRead(id: AppNotification.ID) async throws {
        let _: Data = try await rpc.call("mark_notification_read", params: ReadParams(notificationID: id))
    }

    private struct PrefsParams: Encodable, Sendable { let prefs: [String: Bool] }

    func preferences() async throws -> NotificationPreferences {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        let json: [String: Bool] = try await rpc.call("my_notification_prefs")
        return NotificationPreferences(json: json)
    }

    func setPreferences(_ preferences: NotificationPreferences) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        let _: Data = try await rpc.call("set_notification_prefs", params: PrefsParams(prefs: preferences.json))
    }
}

// MARK: - Data report

struct SupabaseDataReportRepository: DataReportRepository {
    let rpc: any RPCClient
    let auth: any AuthService

    private struct Params: Encodable, Sendable {
        let projectID: UUID
        let note: String
        enum CodingKeys: String, CodingKey { case projectID = "project_id", note }
    }

    func reportIncorrectData(projectID: Project.ID, note: String) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= MockDataReportRepository.maxNoteLength else { throw RepositoryError.decoding }
        let _: Data = try await rpc.call("report_data", params: Params(projectID: projectID, note: trimmed))
    }
}

// MARK: - Push token

struct SupabasePushTokenRepository: PushTokenRepository {
    let rpc: any RPCClient

    private struct RegisterParams: Encodable, Sendable { let token: String; let environment: String }
    private struct TokenParams: Encodable, Sendable { let token: String }

    func register(token: String, environment: PushEnvironment) async throws {
        let _: Data = try await rpc.call("register_push_token", params: RegisterParams(token: token, environment: environment.rawValue))
    }

    func unregister(token: String) async throws {
        let _: Data = try await rpc.call("unregister_push_token", params: TokenParams(token: token))
    }
}
