import Foundation

// Implementation mock của các protocol Domain. Khi có backend, viết Supabase*Repository tương ứng
// và đổi trong `AppContainer` — ViewModel không đổi.

// MARK: - Project

struct MockProjectRepository: ProjectRepository {
    let store: MockDataStore
    let latency: MockLatency

    func projects(in region: MapRegion, filter: ProjectFilter) async throws -> [Project] {
        try await latency.wait()
        return try await store.dataset().projects.filter { region.contains($0.location) && filter.matches($0) }
    }

    func projects(ids: Set<Project.ID>) async throws -> [Project] {
        try await latency.wait()
        return try await store.dataset().projects.filter { ids.contains($0.id) }
    }

    func project(id: Project.ID) async throws -> ProjectDetail {
        try await latency.wait()
        let data = try await store.dataset()
        guard let project = data.projects.first(where: { $0.id == id }) else { throw RepositoryError.notFound }
        // Bản Supabase đọc bảng tính sẵn `project_nearest_infra` (PostGIS KNN).
        return ProjectDetail(
            project: project,
            nearestInfra: NearestInfraCalculator.nearest(to: project.location, nodes: data.nodes, routes: data.routes),
            coverImageURL: data.coverImages[id]
        )
    }

    func search(_ query: String) async throws -> [SearchResult] {
        let needle = SearchNormalizer.normalize(query)
        guard needle.count >= 2 else { return [] }
        try await latency.wait()
        let data = try await store.dataset()

        let units = data.administrativeUnits.filter { unit in
            ([unit.name] + unit.oldNames).contains { SearchNormalizer.normalize($0).contains(needle) }
        }
        let unitCodes = Set(units.map(\.code))
        let projects = data.projects.filter { project in
            SearchNormalizer.normalize(project.name).contains(needle)
                || project.wardCode.map(unitCodes.contains) == true
        }
        return Array((projects.map(SearchResult.project) + units.map(SearchResult.place)).prefix(20))
    }
}

/// Bản mock của truy vấn "ga/nút giao gần nhất": 1 ga Metro, 1 nút giao, và điểm hạ tầng lớn trong bán kính.
enum NearestInfraCalculator {
    static let landmarkRadiusMeters: Double = 25_000

    static func nearest(to point: GeoPoint, nodes: [InfraNode], routes: [InfraRoute]) -> [NearestInfra] {
        let routesByID = Dictionary(routes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func make(_ node: InfraNode) -> NearestInfra {
            let route = node.routeID.flatMap { routesByID[$0] }
            return NearestInfra(
                node: node,
                routeName: route?.name,
                routeType: route?.type,
                routeStatus: route?.status,
                expectedYear: route?.expectedYear,
                distanceMeters: point.distance(to: node.location)
            )
        }

        func closest(_ type: NodeType) -> NearestInfra? {
            nodes.filter { $0.type == type }.map(make).min { $0.distanceMeters < $1.distanceMeters }
        }

        let landmarks = nodes.filter { $0.type == .keyLandmark }.map(make)
            .filter { $0.distanceMeters <= landmarkRadiusMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }

        return [closest(.metroStation), closest(.interchange)].compactMap { $0 } + landmarks
    }
}

// MARK: - Infrastructure

struct MockInfrastructureRepository: InfrastructureRepository {
    let store: MockDataStore
    let latency: MockLatency

    func routes(types: Set<RouteType>, detail: RouteDetail) async throws -> [InfraRoute] {
        try await latency.wait()
        let routes = try await store.dataset().routes
        return types.isEmpty ? routes : routes.filter { types.contains($0.type) }
    }

    func nodes(routeID: InfraRoute.ID) async throws -> [InfraNode] {
        try await latency.wait()
        return try await store.dataset().nodes.filter { $0.routeID == routeID }
    }
}

// MARK: - Lookup

struct MockLookupRepository: LookupRepository {
    let store: MockDataStore
    let latency: MockLatency

    func catalog() async throws -> LookupCatalog {
        try await latency.wait()
        return try await store.dataset().catalog
    }

    func administrativeUnits() async throws -> [AdministrativeUnit] {
        try await latency.wait()
        return try await store.dataset().administrativeUnits
    }

    func boundary(of area: ServiceArea) async throws -> AreaBoundary? {
        try await latency.wait()
        return try await store.dataset().boundaries.first { $0.area == area }
    }
}

// MARK: - Eligibility

struct MockEligibilityRepository: EligibilityRepository {
    let store: MockDataStore
    let latency: MockLatency

    func currentRules() async throws -> [EligibilityRule] {
        try await latency.wait()
        return try await store.dataset().eligibilityRules
    }
}

// MARK: - Auth

enum MockStorageKeys {
    static let user = "mock.auth.user"
    static let bookmarks = "mock.bookmarks"
    static let savedPlaces = "mock.saved_places"
}

/// `UserDefaults` không Sendable trong Swift 6 → truyền tên suite (Sendable), mỗi actor tự mở instance riêng.
/// Các instance cùng suite đọc/ghi chung một kho.
struct MockDefaultsSuite: Sendable {
    /// `nil` = `UserDefaults.standard`.
    let name: String?

    static let standard = MockDefaultsSuite(name: nil)

    func open() -> UserDefaults {
        name.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

/// Đăng nhập giả: provider nào cũng thành công ngay, trả về cùng một user. Trạng thái lưu trong UserDefaults.
actor MockAuthService: AuthService {
    static let demoUser = AppUser(
        id: UUID(uuidString: "0B9E2A4C-7D51-4F3A-9C2E-5A1B7C3D9E01")!,
        displayName: "Nguyễn Minh An",
        isPhoneVerified: true,
        maskedPhone: "••• 482"
    )

    /// Mã OTP mock luôn đúng.
    static let emailCode = "123456"

    nonisolated let socialProviders: [AuthProvider] = AuthProvider.allCases
    private let defaults: UserDefaults
    private let latency: MockLatency

    init(suite: MockDefaultsSuite, latency: MockLatency) {
        self.defaults = suite.open()
        self.latency = latency
    }

    func sendEmailCode(to email: String) async throws {
        guard EmailAddress.isPlausible(email) else { throw RepositoryError.decoding }
        try await latency.wait()
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AppUser {
        try await latency.wait()
        guard code == Self.emailCode else { throw RepositoryError.unauthorized }
        defaults.set(true, forKey: MockStorageKeys.user)
        return Self.demoUser
    }

    var currentUser: AppUser? {
        defaults.bool(forKey: MockStorageKeys.user) ? Self.demoUser : nil
    }

    func signIn(with provider: AuthProvider) async throws -> AppUser {
        // Bản thật: `SupabaseAuthService`.
        try await latency.wait()
        defaults.set(true, forKey: MockStorageKeys.user)
        return Self.demoUser
    }

    func signOut() async throws {
        defaults.removeObject(forKey: MockStorageKeys.user)
        // Bookmark của tài khoản nằm trên server; máy chỉ giữ bookmark lưu tạm của khách.
        try LocalBookmarkStorage(defaults: defaults).update { $0.removeAll { !$0.isLocalOnly } }
    }

    func deleteAccount() async throws {
        // Bản thật: RPC `delete_my_account`.
        try await latency.wait()
        defaults.removeObject(forKey: MockStorageKeys.user)
        defaults.removeObject(forKey: MockStorageKeys.bookmarks)
        // Server xóa theo cascade (saved_places.user_id on delete cascade).
        defaults.removeObject(forKey: MockStorageKeys.savedPlaces)
    }
}

// MARK: - Bookmark

/// Khách được lưu tạm trên máy (`isLocalOnly`); bật thông báo và gộp danh sách cần đăng nhập (prd.md mục 4.1).
actor MockBookmarkRepository: BookmarkRepository {
    private let storage: LocalBookmarkStorage
    private let auth: any AuthService
    private let now: @Sendable () -> Date

    init(suite: MockDefaultsSuite, auth: any AuthService, now: @escaping @Sendable () -> Date = { .now }) {
        self.storage = LocalBookmarkStorage(defaults: suite.open())
        self.auth = auth
        self.now = now
    }

    func all() async throws -> [Bookmark] {
        storage.load().sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func toggle(projectID: Project.ID) async throws -> Bool {
        let isGuest = await auth.currentUser == nil
        let createdAt = now()
        var isSaved = false
        try storage.update { bookmarks in
            if let index = bookmarks.firstIndex(where: { $0.projectID == projectID }) {
                bookmarks.remove(at: index)
            } else {
                bookmarks.append(Bookmark(projectID: projectID, notifyEnabled: false, createdAt: createdAt, isLocalOnly: isGuest))
                isSaved = true
            }
        }
        return isSaved
    }

    /// Bật thông báo cho dự án chưa lưu thì tự lưu luôn.
    func setNotify(_ enabled: Bool, projectID: Project.ID) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        let createdAt = now()
        try storage.update { bookmarks in
            if let index = bookmarks.firstIndex(where: { $0.projectID == projectID }) {
                bookmarks[index].notifyEnabled = enabled
            } else if enabled {
                bookmarks.append(Bookmark(projectID: projectID, notifyEnabled: true, createdAt: createdAt, isLocalOnly: false))
            }
        }
    }

    /// Như RPC `set_bookmark_note`: chưa lưu + có ghi chú → tự lưu; rỗng → xóa ghi chú (giữ bookmark).
    func setNote(_ note: String?, projectID: Project.ID) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        let cleaned = UserText.cleaned(note)
        guard (cleaned?.count ?? 0) <= SavedPlace.maxNoteLength else { throw RepositoryError.decoding }
        let createdAt = now()
        try storage.update { bookmarks in
            if let index = bookmarks.firstIndex(where: { $0.projectID == projectID }) {
                bookmarks[index].note = cleaned
            } else if let cleaned {
                bookmarks.append(Bookmark(projectID: projectID, notifyEnabled: false, createdAt: createdAt, isLocalOnly: false, note: cleaned))
            }
        }
    }

    func mergeGuestBookmarks() async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        // Bản thật: RPC `merge_guest_bookmarks(project_ids)`.
        try storage.update { bookmarks in
            for index in bookmarks.indices { bookmarks[index].isLocalOnly = false }
        }
    }
}

// MARK: - Notification

actor MockNotificationRepository: NotificationRepository {
    private let store: MockDataStore
    private let auth: any AuthService
    private let latency: MockLatency
    private var readIDs: Set<AppNotification.ID> = []

    init(store: MockDataStore, auth: any AuthService, latency: MockLatency) {
        self.store = store
        self.auth = auth
        self.latency = latency
    }

    func inbox() async throws -> [AppNotification] {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        try await latency.wait()
        return try await store.dataset().notifications
            .map { notification in
                var copy = notification
                if readIDs.contains(copy.id) { copy.isRead = true }
                return copy
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func markAsRead(id: AppNotification.ID) async throws {
        readIDs.insert(id)
    }

    private var storedPreferences = NotificationPreferences()

    func preferences() async throws -> NotificationPreferences {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        return storedPreferences
    }

    func setPreferences(_ preferences: NotificationPreferences) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        storedPreferences = preferences
    }
}

// MARK: - Data report

actor MockDataReportRepository: DataReportRepository {
    /// Khớp CHECK `data_reports.note` (≤ 500) và giới hạn ô nhập.
    static let maxNoteLength = 500

    private let auth: any AuthService
    private let latency: MockLatency
    private(set) var submitted: [(projectID: Project.ID, note: String)] = []

    init(auth: any AuthService, latency: MockLatency) {
        self.auth = auth
        self.latency = latency
    }

    func reportIncorrectData(projectID: Project.ID, note: String) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maxNoteLength else { throw RepositoryError.decoding }
        try await latency.wait()
        // Bản thật: RPC `report_data` (giới hạn 10/24h).
        submitted.append((projectID, trimmed))
    }

    private(set) var suggestions: [(name: String, address: String?, location: GeoPoint)] = []

    func suggestProject(name: String, address: String?, location: GeoPoint) async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
        guard let cleaned = UserText.cleaned(name), cleaned.count <= SavedPlace.maxNameLength else { throw RepositoryError.decoding }
        try await latency.wait()
        // Bản thật: RPC `suggest_project` (kiểm tra vùng MVP + chung giới hạn 10/24h).
        suggestions.append((cleaned, UserText.cleaned(address), location))
    }
}

// MARK: - Push

actor MockPushTokenRepository: PushTokenRepository {
    private(set) var tokens: [String: PushEnvironment] = [:]
    func register(token: String, environment: PushEnvironment) async throws { tokens[token] = environment }
    func unregister(token: String) async throws { tokens[token] = nil }
}

/// Không làm gì — cho test/Preview (không đụng UNUserNotificationCenter).
@MainActor
final class NoopPushRegistrar: PushRegistering {
    private(set) var permissionRequests = 0
    private(set) var unregisterCalls = 0
    var grants = true

    func requestPermissionAndRegister() async -> Bool {
        permissionRequests += 1
        return grants
    }

    func registerIfAuthorized() async {}
    func unregister() async { unregisterCalls += 1 }
}

// MARK: - Config

/// Mặc định không chặn. DEBUG `-ForceUpdate` giả lập server yêu cầu bản mới.
struct MockConfigRepository: ConfigRepository {
    var config = ClientConfig(minSupportedVersion: AppVersion(0, 1, 0), appStoreURL: nil)

    func clientConfig() async throws -> ClientConfig {
        if DebugLaunchOptions.forcesUpdate {
            return ClientConfig(minSupportedVersion: AppVersion(99, 0, 0), appStoreURL: URL(string: "https://apps.apple.com/vn/"))
        }
        return config
    }
}

// MARK: - Location

/// Vị trí cố định ở Thủ Đức — cho test/Preview. App dùng `CoreLocationService`.
struct MockLocationService: LocationService {
    var location = GeoPoint(latitude: 10.8494, longitude: 106.7718)
    var error: LocationError?
    let latency: MockLatency

    func currentLocation() async throws(LocationError) -> GeoPoint {
        try? await latency.wait()
        if let error { throw error }
        return location
    }
}
