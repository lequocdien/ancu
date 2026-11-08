import Foundation
import Observation

/// Lý do yêu cầu đăng nhập — quyết định tiêu đề/mô tả của `SignInPromptView`.
enum SignInReason: String, Identifiable, Sendable {
    case savedLocally
    case notifications
    case savedLayer
    case tracking
    case report
    /// Lưu địa điểm ngoài hệ thống / ghi chú (PRD 4.6 — bắt buộc đăng nhập).
    case savePlace

    var id: String { rawValue }
}

/// Trạng thái phiên dùng chung cho cả 3 tab: người dùng hiện tại + danh sách đã lưu.
/// Lưu ở Bản đồ thì Theo dõi thấy ngay; đăng xuất ở Tài khoản thì Bản đồ cập nhật.
///
/// Không giữ cờ "đang hiện prompt đăng nhập" toàn cục: prompt thường bật khi một sheet khác đang mở,
/// sheet trình bày từ root sẽ bị SwiftUI bỏ qua. Hàm trả về kết quả, màn hình gọi tự trình bày prompt.
@MainActor
@Observable
final class SessionStore {
    enum SaveOutcome: Equatable {
        case saved
        case removed
        /// Khách lưu lần đầu → gợi ý đăng nhập (chỉ một lần mỗi phiên, tránh làm phiền).
        case savedLocallyNeedsPrompt
    }

    private(set) var user: AppUser?
    private(set) var bookmarks: [Bookmark] = []
    /// Dự án đang chờ phản hồi Lưu/Thông báo — UI khóa nút để tránh bấm đúp.
    private(set) var pendingProjectIDs: Set<Project.ID> = []
    /// Địa điểm ngoài hệ thống (PRD 4.6). Rỗng khi chưa đăng nhập. Mới sửa lên trên.
    private(set) var savedPlaces: [SavedPlace] = []

    var isSignedIn: Bool { user != nil }
    var savedProjectIDs: Set<Project.ID> { Set(bookmarks.map(\.projectID)) }

    private let auth: any AuthService
    private let bookmarkRepository: any BookmarkRepository
    private let savedPlaceRepository: any SavedPlaceRepository
    private let push: any PushRegistering
    private let analytics: any AnalyticsTracker
    private var hasPromptedAfterGuestSave = false

    init(
        auth: any AuthService,
        bookmarks: any BookmarkRepository,
        savedPlaces: any SavedPlaceRepository = UnavailableSavedPlaceRepository(),
        push: any PushRegistering = NoopPushRegistrar(),
        analytics: any AnalyticsTracker = NoopAnalytics()
    ) {
        self.auth = auth
        self.bookmarkRepository = bookmarks
        self.savedPlaceRepository = savedPlaces
        self.push = push
        self.analytics = analytics
    }

    convenience init(container: AppContainer, push: any PushRegistering = NoopPushRegistrar()) {
        self.init(
            auth: container.auth, bookmarks: container.bookmarks, savedPlaces: container.savedPlaces,
            push: push, analytics: container.analytics
        )
    }

    func load() async {
        user = await auth.currentUser
        await refreshBookmarks()
        await refreshSavedPlaces()
        if isSignedIn { await push.registerIfAuthorized() }
    }

    func isSaved(_ id: Project.ID) -> Bool {
        bookmarks.contains { $0.projectID == id }
    }

    func isNotifying(_ id: Project.ID) -> Bool {
        bookmarks.contains { $0.projectID == id && $0.notifyEnabled }
    }

    /// Khách vẫn lưu được (lưu tạm trên máy, prd.md mục 4.1).
    func toggleSave(_ id: Project.ID) async throws(RepositoryError) -> SaveOutcome {
        pendingProjectIDs.insert(id)
        defer { pendingProjectIDs.remove(id) }
        let saved: Bool
        do {
            saved = try await bookmarkRepository.toggle(projectID: id)
        } catch {
            throw Self.map(error)
        }
        await refreshBookmarks()
        guard saved else { return .removed }
        analytics.track(AnalyticsEvent(name: AnalyticsEvent.projectSaved, props: ["signed_in": String(isSignedIn)]))
        if !isSignedIn && !hasPromptedAfterGuestSave {
            hasPromptedAfterGuestSave = true
            return .savedLocallyNeedsPrompt
        }
        return .saved
    }

    /// Trả `false` khi chưa đăng nhập (caller hiện prompt `.notifications`).
    func setNotify(_ enabled: Bool, for id: Project.ID) async throws(RepositoryError) -> Bool {
        guard isSignedIn else { return false }
        pendingProjectIDs.insert(id)
        defer { pendingProjectIDs.remove(id) }
        do {
            try await bookmarkRepository.setNotify(enabled, projectID: id)
        } catch {
            throw Self.map(error)
        }
        await refreshBookmarks()
        // Xin quyền đúng lúc người dùng muốn nhận tin (không hỏi lúc mở app). Từ chối vẫn giữ lựa chọn:
        // thông báo vẫn vào hộp thư trong app.
        if enabled {
            let granted = await push.requestPermissionAndRegister()
            analytics.track(AnalyticsEvent(name: AnalyticsEvent.notifyEnabled, props: ["push_permission": String(granted)]))
        }
        return true
    }

    // MARK: Ghi chú + địa điểm riêng (PRD 4.6) — bắt buộc đăng nhập

    func note(for id: Project.ID) -> String? {
        bookmarks.first { $0.projectID == id }?.note
    }

    /// Ghi chú dự án trong hệ thống. Chưa lưu → tự lưu. Trả `false` khi chưa đăng nhập (caller hiện prompt `.savePlace`).
    func setNote(_ note: String?, for id: Project.ID) async throws(RepositoryError) -> Bool {
        guard isSignedIn else { return false }
        pendingProjectIDs.insert(id)
        defer { pendingProjectIDs.remove(id) }
        do {
            try await bookmarkRepository.setNote(note, projectID: id)
        } catch {
            throw Self.map(error)
        }
        await refreshBookmarks()
        analytics.track(AnalyticsEvent(name: AnalyticsEvent.noteEdited, props: ["target": "bookmark"]))
        return true
    }

    func createPlace(_ draft: SavedPlaceDraft, source: String) async throws(RepositoryError) -> SavedPlace {
        guard isSignedIn else { throw .unauthorized }
        let created: SavedPlace
        do {
            created = try await savedPlaceRepository.create(draft)
        } catch {
            throw Self.map(error)
        }
        savedPlaces.removeAll { $0.id == created.id }
        savedPlaces.insert(created, at: 0)
        analytics.track(AnalyticsEvent(name: AnalyticsEvent.placeSaved, props: ["kind": created.kind.rawValue, "source": source]))
        return created
    }

    func updatePlace(_ id: SavedPlace.ID, name: String, kind: PlaceKind, icon: String?, note: String?) async throws(RepositoryError) {
        guard isSignedIn else { throw .unauthorized }
        let updated: SavedPlace
        do {
            updated = try await savedPlaceRepository.update(id: id, name: name, kind: kind, icon: icon, note: note)
        } catch {
            throw Self.map(error)
        }
        savedPlaces.removeAll { $0.id == id }
        savedPlaces.insert(updated, at: 0)
        analytics.track(AnalyticsEvent(name: AnalyticsEvent.noteEdited, props: ["target": "place", "kind": kind.rawValue]))
    }

    func deletePlace(_ id: SavedPlace.ID) async throws(RepositoryError) {
        guard isSignedIn else { throw .unauthorized }
        do {
            try await savedPlaceRepository.delete(id: id)
        } catch {
            throw Self.map(error)
        }
        savedPlaces.removeAll { $0.id == id }
    }

    func refreshSavedPlaces() async {
        guard isSignedIn else {
            savedPlaces = []
            return
        }
        // Lỗi đọc không chặn UI; giữ danh sách cũ.
        if let latest = try? await savedPlaceRepository.all() {
            savedPlaces = latest
        }
    }

    var socialProviders: [AuthProvider] { auth.socialProviders }

    /// Đăng nhập rồi gộp danh sách khách đã lưu tạm vào tài khoản.
    /// Trả `false` khi người dùng tự hủy (đóng màn Apple/Google) — không phải lỗi.
    @discardableResult
    func signIn(with provider: AuthProvider) async throws(RepositoryError) -> Bool {
        let signedIn: AppUser
        do {
            signedIn = try await auth.signIn(with: provider)
        } catch is CancellationError {
            return false
        } catch {
            throw Self.map(error)
        }
        await didSignIn(signedIn)
        analytics.track(AnalyticsEvent(name: AnalyticsEvent.signInCompleted, props: ["method": provider.rawValue]))
        return true
    }

    func sendEmailCode(to email: String) async throws(RepositoryError) {
        do {
            try await auth.sendEmailCode(to: email)
        } catch {
            throw Self.map(error)
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws(RepositoryError) {
        let signedIn: AppUser
        do {
            signedIn = try await auth.verifyEmailCode(code, email: email)
        } catch {
            throw Self.map(error)
        }
        await didSignIn(signedIn)
        analytics.track(AnalyticsEvent(name: AnalyticsEvent.signInCompleted, props: ["method": "email"]))
    }

    private func didSignIn(_ signedIn: AppUser) async {
        user = signedIn
        await push.registerIfAuthorized()
        // Gộp thất bại không làm hỏng đăng nhập: bookmark vẫn nằm trên máy, lần sau gộp lại.
        try? await bookmarkRepository.mergeGuestBookmarks()
        await refreshBookmarks()
        await refreshSavedPlaces()
    }

    func signOut() async throws(RepositoryError) {
        await push.unregister()
        do {
            try await auth.signOut()
        } catch {
            throw Self.map(error)
        }
        user = nil
        await refreshBookmarks()
        await refreshSavedPlaces()
    }

    func deleteAccount() async throws(RepositoryError) {
        await push.unregister()
        do {
            try await auth.deleteAccount()
        } catch {
            throw Self.map(error)
        }
        user = nil
        hasPromptedAfterGuestSave = false
        await refreshBookmarks()
        await refreshSavedPlaces()
    }

    private func refreshBookmarks() async {
        // Lỗi đọc bookmark không chặn UI; giữ danh sách cũ.
        if let latest = try? await bookmarkRepository.all() {
            bookmarks = latest
        }
    }

    private static func map(_ error: any Error) -> RepositoryError {
        error as? RepositoryError ?? .network
    }
}
