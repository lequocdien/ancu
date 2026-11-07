import SwiftUI

/// Khung 3 tab của app.
struct RootTabView: View {
    enum Tab: Hashable { case map, tracking, account }

    @Environment(\.container) private var container
    @Environment(DeepLinkRouter.self) private var router
    @State private var selection: Tab = Self.initialTab()

    var body: some View {
        TabView(selection: $selection) {
            MapScreen(viewModel: MapViewModel(container: container))
                .tabItem { Label("Bản đồ", systemImage: "map") }
                .tag(Tab.map)

            TrackingScreen(viewModel: TrackingViewModel(container: container))
                .tabItem { Label("Theo dõi", systemImage: "star") }
                .tag(Tab.tracking)

            AccountScreen()
                .tabItem { Label("Tài khoản", systemImage: "person.crop.circle") }
                .tag(Tab.account)
        }
        .adaptiveTabBarMinimizeOnScroll()
        // Bấm thông báo → về tab Bản đồ; MapScreen mở sheet dự án.
        .onChange(of: router.pendingProjectID) { _, id in
            if id != nil { selection = .map }
        }
    }
}

extension RootTabView {
    static func initialTab() -> Tab {
        switch DebugLaunchOptions.initialTab {
        case "tracking": .tracking
        case "account": .account
        default: .map
        }
    }
}

#Preview {
    RootTabView()
        .environment(SessionStore(container: .preview))
        .environment(DeepLinkRouter())
        .environment(ConnectivityMonitor(startsMonitoring: false))
}
