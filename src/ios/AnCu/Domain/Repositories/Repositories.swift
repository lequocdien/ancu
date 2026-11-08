import Foundation

// Contract giữa ViewModel và nguồn dữ liệu. Phase prototype: Mock*; sau đó Supabase*, có thể .NET*.
// Quy ước: mọi hàm chỉ ném `RepositoryError`; implementation chọn ở `AppContainer`.

protocol ProjectRepository: Sendable {
    /// Dự án trong khung nhìn (RPC `projects_in_bbox`).
    func projects(in region: MapRegion, filter: ProjectFilter) async throws -> [Project]
    /// Dự án theo danh sách id (tab Theo dõi). Id không còn tồn tại thì bỏ qua, không ném lỗi.
    func projects(ids: Set<Project.ID>) async throws -> [Project]
    /// Chi tiết + ga/nút giao gần nhất (RPC `project_detail`).
    func project(id: Project.ID) async throws -> ProjectDetail
    /// Tìm theo tên dự án, phường/xã — cả tên mới lẫn tên cũ (RPC `search_places`).
    func search(_ query: String) async throws -> [SearchResult]
}

protocol InfrastructureRepository: Sendable {
    /// Tuyến theo loại; `types` rỗng = mọi loại (RPC `routes(types, tolerance_degrees)`). Mock bỏ qua `detail`.
    func routes(types: Set<RouteType>, detail: RouteDetail) async throws -> [InfraRoute]
    func nodes(routeID: InfraRoute.ID) async throws -> [InfraNode]
}

extension InfrastructureRepository {
    func routes(types: Set<RouteType>) async throws -> [InfraRoute] {
        try await routes(types: types, detail: .full)
    }
}

protocol LookupRepository: Sendable {
    /// Toàn bộ danh mục. Gọi 1 lần lúc khởi động; implementation tự cache.
    func catalog() async throws -> LookupCatalog
    func administrativeUnits() async throws -> [AdministrativeUnit]
    /// Ranh giới vùng (RPC `service_area_boundary`); `nil` = vùng chưa có dữ liệu ranh giới.
    func boundary(of area: ServiceArea) async throws -> AreaBoundary?
}

protocol BookmarkRepository: Sendable {
    func all() async throws -> [Bookmark]
    /// Lưu / bỏ lưu. Trả về trạng thái mới (`true` = đang lưu).
    @discardableResult
    func toggle(projectID: Project.ID) async throws -> Bool
    func setNotify(_ enabled: Bool, projectID: Project.ID) async throws
    /// Ghi chú cho dự án (RPC `set_bookmark_note`). Chưa lưu + có ghi chú → tự lưu; `nil`/rỗng → xóa ghi chú.
    /// Chỉ khi đăng nhập (khách không có ghi chú — PRD 4.1).
    func setNote(_ note: String?, projectID: Project.ID) async throws
    /// Gộp bookmark lưu tạm của khách vào tài khoản sau khi đăng nhập (RPC `merge_guest_bookmarks`).
    func mergeGuestBookmarks() async throws
}

protocol NotificationRepository: Sendable {
    func inbox() async throws -> [AppNotification]
    func markAsRead(id: AppNotification.ID) async throws
    /// Loại thông báo muốn nhận, theo tài khoản (RPC `my_notification_prefs` / `set_notification_prefs`).
    func preferences() async throws -> NotificationPreferences
    func setPreferences(_ preferences: NotificationPreferences) async throws
}

protocol EligibilityRepository: Sendable {
    /// Luật hiện hành (RPC `eligibility_rules_current`). Câu trả lời của người dùng KHÔNG đi qua đây.
    func currentRules() async throws -> [EligibilityRule]
}

protocol DataReportRepository: Sendable {
    /// Nút "Báo thông tin sai" (RPC `report_data`).
    func reportIncorrectData(projectID: Project.ID, note: String) async throws
    /// "Đề xuất An Cư thêm dự án này" (RPC `suggest_project`) — chỉ tên/địa chỉ/vị trí, KHÔNG gửi ghi chú riêng.
    /// Chung giới hạn 10/24h với báo sai.
    func suggestProject(name: String, address: String?, location: GeoPoint) async throws
}

/// Địa điểm ngoài hệ thống người dùng tự lưu (PRD 4.6). Mọi hàm cần đăng nhập → khách nhận `.unauthorized`.
protocol SavedPlaceRepository: Sendable {
    /// Mới sửa lên trên (RPC `my_saved_places`).
    func all() async throws -> [SavedPlace]
    /// Ngoài vùng MVP → `.outsideServiceArea`; quá 200 → `.limitReached`.
    func create(_ draft: SavedPlaceDraft) async throws -> SavedPlace
    /// Sửa tên/loại/icon/ghi chú; vị trí không đổi. `icon == nil` → về icon theo loại. Không phải của mình → `.notFound`.
    func update(id: SavedPlace.ID, name: String, kind: PlaceKind, icon: String?, note: String?) async throws -> SavedPlace
    func delete(id: SavedPlace.ID) async throws
}

/// Địa chỉ của một điểm người dùng tự chọn (ghim) — Apple reverse geocoding. Không có địa chỉ → `nil`.
/// Apple giới hạn tần suất: chỉ gọi khi người dùng dừng kéo bản đồ.
protocol ReverseGeocoder: Sendable {
    func address(at point: GeoPoint) async throws -> String?
}

/// Tìm địa điểm ngoài hệ thống (Apple Maps). Từ khóa do Apple xử lý, không lưu ở server An Cư.
protocol PlaceSearchService: Sendable {
    /// Ưu tiên kết quả trong `region`. Không có kết quả → mảng rỗng (không ném lỗi).
    func search(_ query: String, near region: MapRegion) async throws -> [PlaceCandidate]
}

protocol AuthService: Sendable {
    var currentUser: AppUser? { get async }
    /// Đăng nhập bên thứ ba bật trong bản build này, theo thứ tự hiển thị (cấu hình `AnCuAuthProviders`).
    /// Email OTP luôn có.
    var socialProviders: [AuthProvider] { get }
    /// Apple / Google / Facebook. Người dùng tự hủy → `CancellationError` (UI không báo lỗi).
    func signIn(with provider: AuthProvider) async throws -> AppUser
    /// Gửi mã 6 số tới email (tạo tài khoản nếu chưa có).
    func sendEmailCode(to email: String) async throws
    /// Mã sai/hết hạn → `RepositoryError.unauthorized`.
    func verifyEmailCode(_ code: String, email: String) async throws -> AppUser
    func signOut() async throws
    /// Bắt buộc với App Store (Edge Function `delete-account`).
    func deleteAccount() async throws
}

/// Môi trường APNs của bản build: Debug (chạy từ Xcode) → sandbox, TestFlight/App Store → production.
enum PushEnvironment: String, Sendable {
    case sandbox, production

    static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

protocol PushTokenRepository: Sendable {
    /// RPC `register_push_token` — token chuyển chủ nếu máy đổi tài khoản.
    func register(token: String, environment: PushEnvironment) async throws
    func unregister(token: String) async throws
}

/// Xin quyền + đăng ký APNs (Phase 1 bước 4.4). `SessionStore` gọi theo ngữ cảnh: bật thông báo dự án, đăng nhập, đăng xuất.
@MainActor
protocol PushRegistering: AnyObject {
    /// Xin quyền (lần đầu hiện hộp thoại hệ thống) rồi đăng ký APNs. `false` = người dùng từ chối.
    func requestPermissionAndRegister() async -> Bool
    /// Đã có quyền từ trước → đăng ký lại (token có thể đổi sau khi cài lại/khôi phục máy).
    func registerIfAuthorized() async
    /// Gỡ token của máy khỏi tài khoản — gọi TRƯỚC khi bỏ phiên đăng nhập.
    func unregister() async
}

protocol ConfigRepository: Sendable {
    /// RPC `client_config`. Lỗi → caller dùng `ClientConfig.permissive` (không chặn app vì lỗi mạng).
    func clientConfig() async throws -> ClientConfig
}

/// Vị trí người dùng cho nút "Gần tôi". Chỉ xin quyền "khi dùng app" (compliance.md mục 2).
protocol LocationService: Sendable {
    func currentLocation() async throws(LocationError) -> GeoPoint
}

enum LocationError: Error, Equatable, Sendable {
    case permissionDenied
    case unavailable
    /// Lấy được vị trí nhưng nằm ngoài vùng app hỗ trợ (`MapRegion.allowedArea`) — camera không tới được.
    case outsideServiceArea
}
