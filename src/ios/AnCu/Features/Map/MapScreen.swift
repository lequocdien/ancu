import MapKit
import SwiftUI

struct MapScreen: View {
    @State private var viewModel: MapViewModel
    @State private var camera: MapCameraPosition
    @State private var showsLegend = false
    @FocusState private var searchFocused: Bool
    @Namespace private var glassNamespace

    @State private var signInReason: SignInReason?
    @State private var detailDetent: PresentationDetent = DebugLaunchOptions.opensDetailLarge ? .large : .height(200)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.container) private var container
    @Environment(\.openURL) private var openURL
    @Environment(SessionStore.self) private var session
    @Environment(DeepLinkRouter.self) private var router
    @Environment(\.analytics) private var analytics
    @Environment(ConnectivityMonitor.self) private var connectivity

    init(viewModel: MapViewModel) {
        _viewModel = State(initialValue: viewModel)
        _camera = State(initialValue: .region(MKCoordinateRegion(viewModel.visibleRegion)))
    }

    var body: some View {
        map
            .overlay(alignment: .top) { topControls }
            .overlay(alignment: .bottomTrailing) { sideButtons }
            .task {
                await viewModel.start()
                if DebugLaunchOptions.selectsFirstProject {
                    viewModel.selectedProject = viewModel.projects.first { $0.status == .acceptingApplications }
                }
                if DebugLaunchOptions.locatesOnLaunch { await viewModel.locateUser() }
                // focus(on:) là toggle: vùng đã khôi phục từ lần trước thì giữ nguyên, không bỏ chọn.
                if let code = DebugLaunchOptions.focusArea, viewModel.focusedArea != ServiceArea(code: code) {
                    viewModel.focus(on: ServiceArea(code: code))
                }
                if let id = router.consume() { await viewModel.open(projectID: id) }
            }
            .onChange(of: viewModel.selectedProject?.id) { _, id in
                guard id != nil, let project = viewModel.selectedProject else { return }
                analytics.track(AnalyticsEvent(name: AnalyticsEvent.projectViewed, props: [
                    "status": project.status.rawValue, "service_area": project.serviceArea.rawValue,
                ]))
            }
            .onChange(of: connectivity.isOnline) { _, online in
                if online, case .failed = viewModel.loadState { Task { await viewModel.retry() } }
            }
            .onChange(of: router.pendingProjectID) { _, id in
                guard id != nil, let id = router.consume() else { return }
                Task { await viewModel.open(projectID: id) }
            }
            .onChange(of: viewModel.cameraRequest) { _, request in
                guard let request else { return }
                searchFocused = false
                move(to: request.region)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.selectedProject != nil },
                set: { if !$0 { viewModel.selectedProject = nil; detailDetent = .height(200) } }
            )) {
                if let project = viewModel.selectedProject {
                    ProjectDetailSheet(
                        viewModel: ProjectDetailViewModel(project: project, container: container),
                        catalog: viewModel.catalog
                    )
                    .id(project.id)
                    .presentationDetents([.height(200), .medium, .large], selection: $detailDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
                }
            }
            .signInPrompt($signInReason)
            .onChange(of: session.savedProjectIDs, initial: true) { _, ids in
                viewModel.savedProjectIDs = ids
            }
            .onChange(of: session.isSignedIn) { _, signedIn in
                if !signedIn { viewModel.showsSavedOnly = false }
            }
            .sheet(isPresented: $showsLegend) {
                LegendSheet(catalog: viewModel.catalog, routes: viewModel.routes)
                    .presentationDetents([.medium, .large])
            }
            .alert(
                viewModel.locationError == .outsideServiceArea ? "Bạn đang ở ngoài vùng hỗ trợ" : "Không lấy được vị trí",
                isPresented: Binding(
                    get: { viewModel.locationError != nil },
                    set: { if !$0 { viewModel.dismissLocationError() } }
                )
            ) {
                if viewModel.locationError == .permissionDenied {
                    Button("Mở Cài đặt") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
                Button("Đóng", role: .cancel) {}
            } message: {
                switch viewModel.locationError {
                case .permissionDenied: Text("Hãy cho phép An Cư dùng vị trí trong Cài đặt.")
                case .outsideServiceArea: Text("An Cư hiện có dữ liệu TP.HCM (gồm Bình Dương cũ) và Đồng Nai.")
                default: Text("Vui lòng thử lại sau.")
                }
            }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, bounds: MapCameraBounds(
            // MKMapRect thay vì MKCoordinateRegion: bản region làm MapKit (iOS 27) log liên tục
            // "GEOTilePointForCoordinate received invalid coordinate" (đảo lat/lng nội bộ).
            centerCoordinateBounds: MKMapRect(MapRegion.allowedArea),
            minimumDistance: MapRegion.minCameraDistance,
            maximumDistance: MapRegion.maxCameraDistance
        )) {
            // Vẽ trước để nằm dưới tuyến và ghim.
            if let boundary = viewModel.focusedBoundary {
                ForEach(Array(boundary.polygons.enumerated()), id: \.offset) { _, ring in
                    let coordinates = ring.map(\.coordinate)
                    // Viền trắng dày bên dưới làm "halo" → tách ranh giới khỏi nền bản đồ và các tuyến cùng tông màu.
                    MapPolygon(coordinates: coordinates)
                        .foregroundStyle(Color.brandPrimary.opacity(0.16))
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
                    MapPolygon(coordinates: coordinates)
                        .foregroundStyle(.clear)
                        .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 3, lineJoin: .round, dash: [10, 5]))
                }
            }
            ForEach(viewModel.visibleRoutes) { route in
                let style = viewModel.catalog.lineStyle(for: route.status)
                ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(route.displayColor.opacity(style.opacity), style: style.strokeStyle)
                }
            }

            ForEach(viewModel.mapItems) { item in
                switch item {
                case .project(let project):
                    Annotation(project.name, coordinate: project.location.coordinate, anchor: .center) {
                        ProjectPinView(
                            project: project,
                            catalog: viewModel.catalog,
                            isSelected: viewModel.selectedProjectID == project.id
                        )
                        .onTapGesture { viewModel.selectedProject = project }
                    }
                    .annotationTitles(.hidden)
                case .cluster(let cluster):
                    Annotation("", coordinate: cluster.center.coordinate, anchor: .center) {
                        ClusterView(cluster: cluster)
                            .onTapGesture { move(to: cluster.boundingRegion) }
                    }
                    .annotationTitles(.hidden)
                }
            }

            if let location = viewModel.userLocation {
                Annotation("Vị trí của bạn", coordinate: location.coordinate, anchor: .center) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.25), radius: 2)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.regionDidChange(MapRegion(context.region))
        }
        .onTapGesture { searchFocused = false }
    }

    // MARK: Lớp kính nổi

    private var topControls: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            MapSearchBar(query: $viewModel.searchQuery, isFocused: $searchFocused)
                .padding(.horizontal, Spacing.l)

            if viewModel.isSearchActive {
                MapSearchResults(
                    results: viewModel.searchResults,
                    comingSoonAreas: viewModel.comingSoonAreas,
                    isSearching: viewModel.isSearching,
                    failed: viewModel.searchFailed,
                    catalog: viewModel.catalog,
                    isAvailable: viewModel.isAvailable,
                    onSelect: viewModel.selectSearchResult
                )
                .padding(.horizontal, Spacing.l)
            } else {
                areaPicker
                    .padding(.horizontal, Spacing.l)
                layerChips
                statusBanner
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Spacing.s)
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: viewModel.isSearchActive)
    }

    /// Đổi nhanh vùng: TP.HCM / Bình Dương / Đồng Nai.
    private var areaPicker: some View {
        AdaptiveGlassContainer(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ForEach(viewModel.mvpAreas, id: \.self) { area in
                    MapChip(
                        title: Text(verbatim: viewModel.catalog.label(for: area)),
                        isOn: viewModel.focusedArea == area
                    ) {
                        viewModel.focus(on: area)
                    }
                    .adaptiveGlassID("area-\(area.rawValue)", in: glassNamespace)
                }
            }
        }
    }

    private var layerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            AdaptiveGlassContainer(spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    MapChip(
                        title: Text("Đang nhận hồ sơ"),
                        systemImage: "envelope.open.fill",
                        isOn: viewModel.showsOnlyAcceptingApplications
                    ) {
                        withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
                            viewModel.toggleAcceptingApplicationsFilter()
                        }
                    }
                    .adaptiveGlassID("filter-open", in: glassNamespace)

                    ForEach(viewModel.catalog.orderedCases(RouteType.self), id: \.self) { type in
                        MapChip(
                            title: Text(verbatim: viewModel.catalog.label(for: type)),
                            isOn: viewModel.enabledRouteTypes.contains(type)
                        ) {
                            withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
                                viewModel.toggleRouteType(type)
                            }
                        }
                        .adaptiveGlassID("route-\(type.rawValue)", in: glassNamespace)
                    }

                    MapChip(title: Text("Tất cả NOXH"), isOn: viewModel.showsProjects) {
                        withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
                            viewModel.showsProjects.toggle()
                        }
                    }
                    .adaptiveGlassID("projects", in: glassNamespace)

                    MapChip(title: Text("Đã lưu"), systemImage: "bookmark.fill", isOn: viewModel.showsSavedOnly) {
                        guard session.isSignedIn else {
                            signInReason = .savedLayer
                            return
                        }
                        withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
                            viewModel.showsSavedOnly.toggle()
                        }
                    }
                    .adaptiveGlassID("saved", in: glassNamespace)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.xxs)
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if !connectivity.isOnline {
            Label("Đang ngoại tuyến — dữ liệu có thể chưa mới", systemImage: "wifi.slash")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .adaptiveGlass(.regular, in: Capsule())
        } else if viewModel.isVisibleAreaEmpty {
            Button {
                viewModel.showWholeArea()
            } label: {
                Label(viewModel.showsOnlyAcceptingApplications || viewModel.showsSavedOnly
                      ? "Không có dự án phù hợp bộ lọc ở đây. Xem toàn vùng"
                      : "Không có dự án trong khu vực này. Xem toàn vùng",
                      systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.medium))
            }
            .adaptiveGlassButton()
        } else {
            loadStatus
        }
    }

    @ViewBuilder
    private var loadStatus: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView()
                .padding(Spacing.s)
                .adaptiveGlass(.regular, in: Circle())
        case .failed:
            Button {
                Task { await viewModel.retry() }
            } label: {
                Label("Không tải được dữ liệu. Thử lại", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .adaptiveGlassButton()
        case .idle, .loaded:
            EmptyView()
        }
    }

    /// Cụm nút tròn dọc bên phải: Gần tôi, Chú giải.
    private var sideButtons: some View {
        AdaptiveGlassContainer(spacing: Spacing.s) {
            VStack(spacing: Spacing.s) {
                Button {
                    Task { await viewModel.locateUser() }
                } label: {
                    Image(systemName: "location.fill").frame(width: 24, height: 24)
                }
                .accessibilityLabel(Text("Gần tôi"))
                .adaptiveGlassButton(.icon)

                Button {
                    showsLegend = true
                } label: {
                    Image(systemName: "info").frame(width: 24, height: 24)
                }
                .accessibilityLabel(Text("Chú giải"))
                .adaptiveGlassButton(.icon)
            }
        }
        .controlSize(.large)
        .padding(.trailing, Spacing.l)
        .padding(.bottom, Spacing.xxl)
    }

    private func move(to region: MapRegion) {
        withAnimation(Motion.resolve(Motion.sheet, reduceMotion: reduceMotion)) {
            // `.rect` buộc MapKit chứa trọn khung (`.region` ở màn dọc có thể cắt mép theo chiều ngang).
            camera = .rect(MKMapRect(region))
        }
    }
}

// MARK: - Chuyển đổi MapKit ↔ Domain (chỉ ở tầng UI; Domain không biết MapKit)

extension MapRegion {
    init(_ region: MKCoordinateRegion) {
        self.init(
            center: GeoPoint(latitude: region.center.latitude, longitude: region.center.longitude),
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta
        )
    }
}

extension MKMapRect {
    init(_ region: MapRegion) {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: region.maxLatitude, longitude: region.minLongitude))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: region.minLatitude, longitude: region.maxLongitude))
        self.init(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }
}

extension MKCoordinateRegion {
    init(_ region: MapRegion) {
        self.init(
            center: region.center.coordinate,
            span: MKCoordinateSpan(latitudeDelta: region.latitudeDelta, longitudeDelta: region.longitudeDelta)
        )
    }
}

#Preview {
    MapScreen(viewModel: MapViewModel(container: .preview))
        .environment(SessionStore(container: .preview))
        .environment(DeepLinkRouter())
        .environment(ConnectivityMonitor(startsMonitoring: false))
}
