import Supabase
import SwiftUI

/// Composition root: nơi DUY NHẤT chọn implementation cho từng protocol.
/// Chuyển sang Supabase (hoặc .NET) = thêm factory mới ở đây, View/ViewModel giữ nguyên.
final class AppContainer: Sendable {
    let projects: any ProjectRepository
    let infrastructure: any InfrastructureRepository
    let lookup: any LookupRepository
    let bookmarks: any BookmarkRepository
    let notifications: any NotificationRepository
    let eligibility: any EligibilityRepository
    let dataReports: any DataReportRepository
    let auth: any AuthService
    let location: any LocationService
    let config: any ConfigRepository
    let pushTokens: any PushTokenRepository
    let analytics: any AnalyticsTracker
    /// Chip bản đồ đã chọn (UserDefaults, theo máy).
    let mapPreferences: any MapPreferencesStore
    /// Địa điểm ngoài hệ thống người dùng tự lưu (PRD 4.6).
    let savedPlaces: any SavedPlaceRepository
    let placeSearch: any PlaceSearchService
    let reverseGeocoder: any ReverseGeocoder

    init(
        projects: any ProjectRepository,
        infrastructure: any InfrastructureRepository,
        lookup: any LookupRepository,
        bookmarks: any BookmarkRepository,
        notifications: any NotificationRepository,
        eligibility: any EligibilityRepository,
        dataReports: any DataReportRepository,
        auth: any AuthService,
        location: any LocationService,
        config: any ConfigRepository,
        pushTokens: any PushTokenRepository,
        analytics: any AnalyticsTracker,
        mapPreferences: any MapPreferencesStore,
        savedPlaces: any SavedPlaceRepository,
        placeSearch: any PlaceSearchService,
        reverseGeocoder: any ReverseGeocoder
    ) {
        self.projects = projects
        self.infrastructure = infrastructure
        self.lookup = lookup
        self.bookmarks = bookmarks
        self.notifications = notifications
        self.eligibility = eligibility
        self.dataReports = dataReports
        self.auth = auth
        self.location = location
        self.config = config
        self.pushTokens = pushTokens
        self.analytics = analytics
        self.mapPreferences = mapPreferences
        self.savedPlaces = savedPlaces
        self.placeSearch = placeSearch
        self.reverseGeocoder = reverseGeocoder
    }

    static func mock(
        bundle: Bundle = .main,
        defaultsSuite: MockDefaultsSuite = .standard,
        latency: MockLatency = .standard,
        now: @escaping @Sendable () -> Date = { .now },
        location: (any LocationService)? = nil,
        placeSearch: (any PlaceSearchService)? = nil,
        reverseGeocoder: (any ReverseGeocoder)? = nil
    ) -> AppContainer {
        let store = MockDataStore(bundle: bundle, now: now)
        let auth = MockAuthService(suite: defaultsSuite, latency: latency)
        return AppContainer(
            projects: MockProjectRepository(store: store, latency: latency),
            infrastructure: MockInfrastructureRepository(store: store, latency: latency),
            lookup: MockLookupRepository(store: store, latency: latency),
            bookmarks: MockBookmarkRepository(suite: defaultsSuite, auth: auth, now: now),
            notifications: MockNotificationRepository(store: store, auth: auth, latency: latency),
            eligibility: MockEligibilityRepository(store: store, latency: latency),
            dataReports: MockDataReportRepository(auth: auth, latency: latency),
            auth: auth,
            location: location ?? MockLocationService(latency: latency),
            config: MockConfigRepository(),
            pushTokens: MockPushTokenRepository(),
            analytics: NoopAnalytics(),
            mapPreferences: UserDefaultsMapPreferencesStore(suite: defaultsSuite),
            savedPlaces: MockSavedPlaceRepository(suite: defaultsSuite, store: store, auth: auth, latency: latency, now: now),
            placeSearch: placeSearch ?? MockPlaceSearchService(latency: latency),
            reverseGeocoder: reverseGeocoder ?? MockReverseGeocoder(latency: latency)
        )
    }

    /// Toàn bộ dữ liệu qua Supabase (architecture.md 5.5–5.6). Vị trí luôn lấy từ máy.
    /// - `socialProviders`: đăng nhập bên thứ ba bật trong bản build (Info.plist `AnCuAuthProviders`); email OTP luôn có.
    /// - `sessionStorage`: nơi lưu phiên đăng nhập; `nil` = Keychain (app). Test truyền bộ nhớ tạm.
    static func supabase(
        url: URL,
        publishableKey: String,
        defaultsSuite: MockDefaultsSuite = .standard,
        socialProviders: [AuthProvider] = AuthProvider.parseList(Bundle.main.infoDictionary?["AnCuAuthProviders"] as? String),
        sessionStorage: (any AuthLocalStorage)? = nil
    ) -> AppContainer {
        let authOptions = sessionStorage.map {
            SupabaseClientOptions.AuthOptions(storage: $0, emitLocalSessionAsInitialSession: true)
        } ?? SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
        let rpc = SupabaseRPCClient(client: client)
        let auth = SupabaseAuthService(client: client, rpc: rpc, socialProviders: socialProviders)
        return AppContainer(
            projects: SupabaseProjectRepository(rpc: rpc),
            infrastructure: SupabaseInfrastructureRepository(rpc: rpc),
            lookup: SupabaseLookupRepository(rpc: rpc),
            bookmarks: SupabaseBookmarkRepository(rpc: rpc, auth: auth, suite: defaultsSuite),
            notifications: SupabaseNotificationRepository(rpc: rpc, auth: auth),
            eligibility: SupabaseEligibilityRepository(rpc: rpc),
            dataReports: SupabaseDataReportRepository(rpc: rpc, auth: auth),
            auth: auth,
            location: CoreLocationService(),
            config: SupabaseConfigRepository(rpc: rpc),
            pushTokens: SupabasePushTokenRepository(rpc: rpc),
            analytics: BatchingAnalytics(sink: SupabaseAnalyticsSink(rpc: rpc), suite: defaultsSuite),
            mapPreferences: UserDefaultsMapPreferencesStore(suite: defaultsSuite),
            savedPlaces: SupabaseSavedPlaceRepository(rpc: rpc, auth: auth),
            placeSearch: MapKitPlaceSearchService(),
            reverseGeocoder: MapKitReverseGeocoder()
        )
    }

    static func make(_ config: BackendConfig) -> AppContainer {
        switch config {
        // Mock dữ liệu nhưng vị trí thật: "Gần tôi" phải thử được trên máy/Simulator (simctl location set).
        case .mock: .mock(location: CoreLocationService(), placeSearch: MapKitPlaceSearchService(), reverseGeocoder: MapKitReverseGeocoder())
        case let .supabase(url, key): .supabase(url: url, publishableKey: key)
        }
    }

    /// Cho #Preview: không độ trễ, UserDefaults riêng để không đụng dữ liệu của app.
    static let preview: AppContainer = .mock(
        defaultsSuite: MockDefaultsSuite(name: "vn.ancu.preview"),
        latency: .none
    )
}

extension EnvironmentValues {
    @Entry var container: AppContainer = .preview
}
