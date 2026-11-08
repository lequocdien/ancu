import MapKit
import SwiftUI

struct MapScreen: View {
    /// Tiện ích người mua nhà cần thấy quanh dự án (2026-11-08) — chỉ hiển thị, KHÔNG cho chọn (tránh đụng bấm tuyến /
    /// nhấn giữ ghim địa điểm). Apple tự lọc theo zoom: nhìn cả tỉnh chỉ còn sân bay/điểm lớn. TTTM nằm trong `.store`.
    static let amenityCategories = PointOfInterestCategories.including([
        .school, .university, .hospital, .airport, .publicTransport, .store, .foodMarket, .park,
    ])

    @State private var viewModel: MapViewModel
    @State private var camera: MapCameraPosition
    @State private var showsLegend = false
    @FocusState private var searchFocused: Bool
    @Namespace private var glassNamespace

    @State private var signInReason: SignInReason?
    /// Sheet lưu/sửa địa điểm riêng (PRD 4.6).
    @State private var placeEditor: PlaceEditorRequest?
    /// Điểm (toạ độ màn hình) của mũi ghim lúc bắt đầu kéo; `nil` = không kéo.
    @State private var pinDragStart: CGPoint?
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
            .overlay(alignment: .top) {
                if viewModel.placePick == nil { topControls } else { PlacePickHint().padding(.top, Spacing.s) }
            }
            .overlay(alignment: .bottomTrailing) {
                if viewModel.placePick == nil && viewModel.selectedRoute == nil { sideButtons }
            }
            .overlay(alignment: .bottom) {
                if let pick = viewModel.placePick {
                    PlacePickCard(
                        pick: pick,
                        catalog: viewModel.catalog,
                        onCancel: { viewModel.cancelPick() },
                        onRecenter: {
                            viewModel.movePick(to: viewModel.visibleRegion.center)
                            viewModel.finishMovingPick()
                        },
                        onSave: { openPlaceEditor(.create(pick.editorOrigin)) }
                    )
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let route = viewModel.selectedRoute {
                    RouteInfoCard(route: route, catalog: viewModel.catalog) { viewModel.clearRouteSelection() }
                        .padding(.horizontal, Spacing.l)
                        .padding(.bottom, Spacing.s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: viewModel.selectedRoute?.id)
            .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: viewModel.placePick == nil)
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
                if DebugLaunchOptions.showsSavedLayer { viewModel.showsSavedOnly = true }
                if let query = DebugLaunchOptions.searchQuery { viewModel.searchQuery = query }
                if let point = DebugLaunchOptions.pickAt { viewModel.startPick(at: point) }
                if let point = DebugLaunchOptions.selectRouteAt { viewModel.selectRoute(near: point, toleranceMeters: 300) }
                if DebugLaunchOptions.editsFirstPlace {
                    try? await Task.sleep(for: .seconds(1))   // chờ -SeedPlaces tạo xong
                    if let place = session.savedPlaces.first { openPlaceEditor(.edit(place)) }
                }
            }
            .onChange(of: viewModel.selectedProject?.id) { _, id in
                guard id != nil, let project = viewModel.selectedProject else { return }
                viewModel.clearRouteSelection()   // chạm ghim gần tuyến: ưu tiên dự án
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
            // Hủy trong sheet lưu → quay lại chế độ chọn vị trí (ghim vẫn ở đó); lưu xong → thoát chọn.
            .sheet(item: $placeEditor) { request in
                PlaceEditorSheet(
                    viewModel: PlaceEditorViewModel(
                        mode: request.mode, session: session, projects: container.projects, dataReports: container.dataReports,
                        resolveArea: { [viewModel] point in await viewModel.serviceArea(at: point) }
                    ),
                    catalog: viewModel.catalog,
                    onOpenProject: { project in
                        viewModel.cancelPick()
                        // Đợi sheet lưu đóng hẳn rồi mới mở sheet dự án (SwiftUI bỏ qua sheet trình bày lúc đang đóng).
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            viewModel.selectSearchResult(.project(project))
                        }
                    },
                    onSaved: { viewModel.cancelPick() }
                )
            }
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
                case .outsideServiceArea: Text("Vị trí của bạn nằm ngoài các tỉnh An Cư đang hỗ trợ.")
                default: Text("Vui lòng thử lại sau.")
                }
            }
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
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
                    // Viền mảnh nét đứt (1,5pt) + tô nhạt: đủ nhận ra vùng mà không lấn tuyến Metro/Vành đai.
                    MapPolygon(coordinates: coordinates)
                        .foregroundStyle(Color.brandPrimary.opacity(0.16))
                        .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [6, 4]))
                }
            }
            // Màu = loại tuyến, kiểu nét = trạng thái. Có tuyến đang chọn → các tuyến khác mờ đi.
            ForEach(viewModel.visibleRoutes) { route in
                let style = viewModel.catalog.lineStyle(for: route.status)
                let dimmed = viewModel.selectedRoute.map { $0.id != route.id } ?? false
                ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(
                            viewModel.catalog.color(for: route.type).opacity(style.opacity * (dimmed ? 0.3 : 1)),
                            style: style.strokeStyle
                        )
                }
            }
            if let route = viewModel.selectedRoute {
                let style = viewModel.catalog.lineStyle(for: route.status)
                ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(.white, style: StrokeStyle(lineWidth: style.lineWidth + 5, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(
                            viewModel.catalog.color(for: route.type),
                            style: StrokeStyle(
                                lineWidth: style.lineWidth + 1.5, lineCap: style.dash.isEmpty ? .round : .butt,
                                lineJoin: .round, dash: style.dash
                            )
                        )
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
                        .onTapGesture { if viewModel.placePick == nil { viewModel.selectedProject = project } }
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

            // Lớp "Đã lưu": địa điểm riêng ngoài hệ thống, ghim kiểu khác ghim dự án (PRD 4.6).
            if viewModel.showsSavedOnly {
                ForEach(session.savedPlaces) { place in
                    Annotation(place.name, coordinate: place.location.coordinate, anchor: .bottom) {
                        SavedPlacePinView(kind: place.kind, icon: place.icon, catalog: viewModel.catalog)
                            .onTapGesture { if viewModel.placePick == nil { openPlaceEditor(.edit(place)) } }
                            .accessibilityLabel(Text(verbatim: place.name))
                            .accessibilityHint(Text("Địa điểm bạn lưu. Chạm để xem ghi chú"))
                    }
                }
            }

            // Ghim đang chọn: cố định theo tọa độ (kéo/zoom map không đổi); kéo chính ghim để chỉnh.
            if let pick = viewModel.placePick {
                Annotation("Vị trí đã chọn", coordinate: pick.location.coordinate, anchor: .bottom) {
                    PlacePickPin(catalog: viewModel.catalog, isLifted: pinDragStart != nil)
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    // Bám theo MŨI ghim (không phải chỗ ngón tay chạm đầu ghim) → không giật khi bắt đầu kéo.
                                    if pinDragStart == nil {
                                        pinDragStart = proxy.convert(pick.location.coordinate, to: .global)
                                    }
                                    guard let start = pinDragStart,
                                          let coordinate = proxy.convert(
                                              CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                                              from: .global
                                          )
                                    else { return }
                                    viewModel.movePick(to: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
                                }
                                .onEnded { _ in
                                    pinDragStart = nil
                                    viewModel.finishMovingPick()
                                }
                        )
                        .sensoryFeedback(.impact(weight: .light), trigger: pinDragStart != nil)
                }
                .annotationTitles(.hidden)
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
        .mapStyle(.standard(pointsOfInterest: Self.amenityCategories))
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.regionDidChange(MapRegion(context.region))
        }
        .onTapGesture(coordinateSpace: .local) { location in
            searchFocused = false
            // Bán kính chạm 22pt quy ra mét theo mức zoom hiện tại.
            guard let tapped = proxy.convert(location, from: .local),
                  let edge = proxy.convert(CGPoint(x: location.x + MapViewModel.routeTapTolerancePoints, y: location.y), from: .local)
            else { return }
            let point = GeoPoint(latitude: tapped.latitude, longitude: tapped.longitude)
            let tolerance = point.distance(to: GeoPoint(latitude: edge.latitude, longitude: edge.longitude))
            viewModel.selectRoute(near: point, toleranceMeters: tolerance)
        }
        // Nhấn giữ → ghim tay (Apple Maps ở VN thiếu nhiều dự án mới). simultaneous: không chặn kéo/zoom bản đồ.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                .onEnded { value in
                    guard viewModel.placePick == nil, case .second(true, let drag?) = value,
                          let coordinate = proxy.convert(drag.location, from: .local)
                    else { return }
                    viewModel.startPick(at: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
                }
        )
        }
    }

    // MARK: Địa điểm riêng

    private func openPlaceEditor(_ mode: PlaceEditorViewModel.Mode) {
        guard session.isSignedIn else {
            signInReason = .savePlace
            return
        }
        placeEditor = PlaceEditorRequest(mode: mode)
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
                    places: viewModel.placeResults,
                    isSearching: viewModel.isSearching,
                    failed: viewModel.searchFailed,
                    catalog: viewModel.catalog,
                    isAvailable: viewModel.isAvailable,
                    onSelect: viewModel.selectSearchResult,
                    onSelectPlace: { candidate in
                        searchFocused = false
                        viewModel.startPick(from: candidate)
                    }
                )
                .padding(.horizontal, Spacing.l)
            } else {
                areaPicker
                layerChips
                statusBanner
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Spacing.s)
        .animation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion), value: viewModel.isSearchActive)
    }

    /// Đổi nhanh vùng: 5 tỉnh mới (TP.HCM, Đồng Nai, Tây Ninh, Đồng Tháp, Lâm Đồng). Cuộn ngang như hàng lớp —
    /// 5 chip không vừa bề ngang iPhone, để HStack co lại sẽ cắt chữ ("TP....").
    private var areaPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
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
                            .id(area)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.xxs)
                }
            }
            // Chip đang chọn luôn trong tầm nhìn — kể cả khi khôi phục vùng đã lưu / deep link lúc mở app.
            .onAppear { scrollToFocusedArea(proxy, animated: false) }
            .onChange(of: viewModel.focusedArea) { scrollToFocusedArea(proxy, animated: true) }
            .onChange(of: viewModel.mvpAreas) { scrollToFocusedArea(proxy, animated: false) }
        }
    }

    private func scrollToFocusedArea(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let area = viewModel.focusedArea, viewModel.mvpAreas.contains(area) else { return }
        withAnimation(animated ? Motion.resolve(Motion.snappy, reduceMotion: reduceMotion) : nil) {
            proxy.scrollTo(area, anchor: .center)
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

struct PlaceEditorRequest: Identifiable {
    let id = UUID()
    let mode: PlaceEditorViewModel.Mode
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
