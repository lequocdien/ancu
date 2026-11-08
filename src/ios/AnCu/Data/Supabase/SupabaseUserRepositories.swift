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

    private struct NoteParams: Encodable, Sendable {
        let projectID: UUID
        let note: String?
        enum CodingKeys: String, CodingKey { case projectID = "project_id", note }
        // Gửi `"note": null` tường minh (mặc định Encodable bỏ khóa nil → PostgREST không khớp chữ ký hàm).
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(projectID, forKey: .projectID)
            try container.encode(note, forKey: .note)
        }
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

    func setNote(_ note: String?, projectID: Project.ID) async throws {
        guard await isSignedIn else { throw RepositoryError.unauthorized }
        let cleaned = UserText.cleaned(note)
        guard (cleaned?.count ?? 0) <= SavedPlace.maxNoteLength else { throw RepositoryError.decoding }
        let _: Data = try await rpc.call("set_bookmark_note", params: NoteParams(projectID: projectID, note: cleaned))
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

    private struct SuggestParams: Encodable, Sendable {
        let name: String
        let lat: Double
        let lng: Double
        let address: String?
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(lat, forKey: .lat)
            try container.encode(lng, forKey: .lng)
            try container.encode(address, forKey: .address)
        }
        enum CodingKeys: String, CodingKey { case name, lat, lng, address }
    }

    func suggestProject(name: String, address: String?, location: GeoPoint) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        guard let cleaned = UserText.cleaned(name), cleaned.count <= SavedPlace.maxNameLength else { throw RepositoryError.decoding }
        let _: Data = try await rpc.call("suggest_project", params: SuggestParams(
            name: cleaned, lat: location.latitude, lng: location.longitude, address: UserText.cleaned(address)
        ))
    }
}

// MARK: - Saved places

/// Địa điểm riêng (PRD 4.6). Không có bản lưu tạm cho khách — mọi hàm cần đăng nhập.
/// Kiểm tra độ dài ở client chỉ để báo lỗi sớm; vùng MVP + giới hạn 200 do server quyết định.
struct SupabaseSavedPlaceRepository: SavedPlaceRepository {
    let rpc: any RPCClient
    let auth: any AuthService

    private struct CreateParams: Encodable, Sendable {
        let name: String
        let lat: Double
        let lng: Double
        let kind: String
        let address: String?
        let note: String?
        let externalRef: String?
        let icon: String?
        enum CodingKeys: String, CodingKey { case name, lat, lng, kind, address, note, externalRef = "external_ref", icon }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(lat, forKey: .lat)
            try container.encode(lng, forKey: .lng)
            try container.encode(kind, forKey: .kind)
            try container.encode(address, forKey: .address)
            try container.encode(note, forKey: .note)
            try container.encode(externalRef, forKey: .externalRef)
            try container.encode(icon, forKey: .icon)
        }
    }

    private struct UpdateParams: Encodable, Sendable {
        let id: UUID
        let name: String
        let kind: String
        let note: String?
        let icon: String?
        enum CodingKeys: String, CodingKey { case id, name, kind, note, icon }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(kind, forKey: .kind)
            try container.encode(note, forKey: .note)
            try container.encode(icon, forKey: .icon)
        }
    }

    private struct IDParams: Encodable, Sendable { let id: UUID }

    private func requireSignIn() async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
    }

    func all() async throws -> [SavedPlace] {
        try await requireSignIn()
        let dtos: [SavedPlaceDTO] = try await rpc.call("my_saved_places")
        return try dtos.map(DTOMapper.savedPlace)
    }

    func create(_ draft: SavedPlaceDraft) async throws -> SavedPlace {
        try await requireSignIn()
        let validated = try SavedPlaceValidation.validate(name: draft.name, kind: draft.kind, note: draft.note)
        let dto: SavedPlaceDTO = try await rpc.call("create_saved_place", params: CreateParams(
            name: validated.name, lat: draft.location.latitude, lng: draft.location.longitude, kind: draft.kind.rawValue,
            address: UserText.cleaned(draft.address).map { String($0.prefix(SavedPlace.maxAddressLength)) },
            note: validated.note, externalRef: draft.externalRef, icon: draft.icon
        ))
        return try DTOMapper.savedPlace(dto)
    }

    func update(id: SavedPlace.ID, name: String, kind: PlaceKind, icon: String?, note: String?) async throws -> SavedPlace {
        try await requireSignIn()
        let validated = try SavedPlaceValidation.validate(name: name, kind: kind, note: note)
        let dto: SavedPlaceDTO = try await rpc.call("update_saved_place", params: UpdateParams(
            id: id, name: validated.name, kind: kind.rawValue, note: validated.note, icon: icon
        ))
        return try DTOMapper.savedPlace(dto)
    }

    func delete(id: SavedPlace.ID) async throws {
        try await requireSignIn()
        let _: Bool = try await rpc.call("delete_saved_place", params: IDParams(id: id))
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
