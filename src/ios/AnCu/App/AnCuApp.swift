import SwiftUI

@main
struct AnCuApp: App {
    /// Mock mặc định; `-Backend local` (DEBUG) hoặc `ANCU_SUPABASE_URL` → Supabase (`BackendConfig`).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: AppContainer
    private let push: PushNotificationService
    private let metrics: MetricKitReporter
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: SessionStore
    @State private var router: DeepLinkRouter
    @State private var connectivity = ConnectivityMonitor()

    init() {
        let container = AppContainer.make(BackendConfig.resolve())
        let router = DeepLinkRouter()
        let push = PushNotificationService(repository: container.pushTokens, router: router)
        self.container = container
        self.push = push
        metrics = MetricKitReporter(analytics: container.analytics)
        _router = State(initialValue: router)
        _session = State(initialValue: SessionStore(container: container, push: push))
    }

    var body: some Scene {
        WindowGroup {
            UpdateGate(repository: container.config) { root }
                .environment(\.container, container)
                .environment(session)
                .environment(router)
                .environment(connectivity)
                .environment(\.analytics, container.analytics)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: container.analytics.track(AnalyticsEvent(name: AnalyticsEvent.appOpen))
                    case .background: Task { await container.analytics.flush() }
                    default: break
                    }
                }
                .task {
                    if DebugLaunchOptions.signsInOnLaunch { _ = try? await session.signIn(with: .apple) }
                    await session.load()
                    if DebugLaunchOptions.seedsBookmarks, session.bookmarks.isEmpty,
                       let projects = try? await container.projects.projects(in: .mvpArea, filter: .all) {
                        for project in projects.prefix(4) { _ = try? await session.toggleSave(project.id) }
                        if let first = projects.first { _ = try? await session.setNote("Hỏi lại tiến độ; cách chỗ làm 5 km", for: first.id) }
                    }
                    if DebugLaunchOptions.seedsPlaces, session.savedPlaces.isEmpty {
                        for candidate in MockPlaceSearchService.fixtures.prefix(3) {
                            _ = try? await session.createPlace(SavedPlaceDraft(
                                name: candidate.name, address: candidate.address, location: candidate.location,
                                kind: candidate.id == "mock-picity" ? .socialHousing : .commercial,
                                note: candidate.id == "mock-vgp" ? "Giá ~45 tr/m², đã xem nhà mẫu. Xa chỗ làm 12 km." : nil,
                                externalRef: candidate.externalRef
                            ), source: "debug")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if DebugLaunchOptions.showsDesignSystemGallery {
            DesignSystemGallery()
        } else {
            RootTabView()
        }
        #else
        RootTabView()
        #endif
    }
}
