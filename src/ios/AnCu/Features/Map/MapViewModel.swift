import Foundation
import Observation

@MainActor
@Observable
final class MapViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(RepositoryError)
    }

    /// Yêu cầu di chuyển camera. ViewModel không giữ camera; View quyết định animation.
    struct CameraRequest: Equatable {
        let id = UUID()
        let region: MapRegion
    }

    // MARK: Trạng thái hiển thị

    private(set) var catalog: LookupCatalog = .empty
    private(set) var routes: [InfraRoute] = []
    /// Mức chi tiết của `routes` đang hiển thị; đổi khi zoom qua ngưỡng (`RouteDetail.forLongitudeDelta`).
    private(set) var routeDetail: RouteDetail
    private var routeCache: [RouteDetail: [InfraRoute]] = [:]
    private(set) var routesTask: Task<Void, Never>?
    private(set) var projects: [Project] = []
    private(set) var visibleRegion: MapRegion
    private(set) var loadState: LoadState = .idle

    static let allRouteTypes: Set<RouteType> = [.metro, .ringRoad, .expressway, .nationalHighway]

    /// Lớp tuyến đang bật. Mặc định bật hết; khôi phục từ `MapPreferencesStore`.
    var enabledRouteTypes: Set<RouteType> = MapViewModel.allRouteTypes {
        didSet { if enabledRouteTypes != oldValue { persistPreferences() } }
    }
    /// Chip "Tất cả NOXH".
    var showsProjects = true
    /// Giữ cả `Project` (không chỉ id): chọn từ tìm kiếm khi dự án chưa nằm trong khung đã tải vẫn mở được sheet.
    var selectedProject: Project?
    var selectedProjectID: Project.ID? { selectedProject?.id }

    /// Chip "Đã lưu": chỉ hiện dự án đã lưu. Danh sách id do `SessionStore` cung cấp.
    var showsSavedOnly = false
    var savedProjectIDs: Set<Project.ID> = []

    private(set) var cameraRequest: CameraRequest?
    /// Vùng đang chọn ở segmented. `nil` khi đang xem toàn vùng MVP.
    private(set) var focusedArea: ServiceArea? {
        didSet { if focusedArea != oldValue { persistPreferences() } }
    }
    /// Ranh giới vùng đang chọn — tô nhạt + viền trên bản đồ. Tải sau khi chọn; lỗi thì chỉ không highlight.
    private(set) var focusedBoundary: AreaBoundary?
    private(set) var boundaryTask: Task<Void, Never>?
    private(set) var userLocation: GeoPoint?
    private(set) var locationError: LocationError?

    // MARK: Tìm kiếm

    var searchQuery = "" {
        didSet { if searchQuery != oldValue { scheduleSearch() } }
    }
    private(set) var searchResults: [SearchResult] = []
    /// Vùng ngoài MVP khớp từ khóa (vd "Vũng Tàu") → UI hiện "Sắp có".
    private(set) var comingSoonAreas: [LookupItem] = []
    private(set) var isSearching = false
    private(set) var searchFailed = false

    var isSearchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Vùng phục vụ trong MVP, theo `sort_order` (TP.HCM · Bình Dương · Đồng Nai).
    var mvpAreas: [ServiceArea] {
        catalog.orderedCases(ServiceArea.self).filter { catalog.isInMVP($0) }
    }

    var showsOnlyAcceptingApplications: Bool { filter == .acceptingApplications }

    func isAvailable(_ unit: AdministrativeUnit) -> Bool {
        catalog.isInMVP(unit.serviceArea)
    }

    /// Tuyến cần vẽ, theo thứ tự: quy hoạch → thi công → đã khai thác (nét đậm nằm trên).
    var visibleRoutes: [InfraRoute] {
        routes
            .filter { enabledRouteTypes.contains($0.type) }
            .sorted { Self.drawOrder($0.status) < Self.drawOrder($1.status) }
    }

    var mapItems: [MapItem] {
        guard showsProjects else { return [] }
        let shown = showsSavedOnly ? projects.filter { savedProjectIDs.contains($0.id) } : projects
        return ProjectClusterer.items(for: shown, in: visibleRegion)
    }

    /// Đã tải xong nhưng khung nhìn không có dự án nào (theo bộ lọc đang bật) → UI gợi ý xem toàn vùng.
    var isVisibleAreaEmpty: Bool {
        guard loadState == .loaded, showsProjects else { return false }
        let shown = showsSavedOnly ? projects.filter { savedProjectIDs.contains($0.id) } : projects
        return !shown.contains { visibleRegion.contains($0.location) }
    }

    func showWholeArea() {
        clearFocus()
        requestCamera(.mvpArea)
    }

    // MARK: Phụ thuộc

    private let projectRepository: any ProjectRepository
    private let infrastructureRepository: any InfrastructureRepository
    private let lookupRepository: any LookupRepository
    private let locationService: any LocationService
    private let debounce: Duration
    private let preferences: any MapPreferencesStore
    /// Vùng đã lưu lần trước — áp dụng sau khi có danh mục (cần tâm vùng + kiểm tra còn trong MVP).
    private var areaToRestore: String?
    private var filter: ProjectFilter = .all {
        didSet { if filter != oldValue { persistPreferences() } }
    }

    /// Task đang chạy. Mở cho test `await`.
    private(set) var projectsTask: Task<Void, Never>?
    private(set) var searchTask: Task<Void, Never>?

    init(
        projects: any ProjectRepository,
        infrastructure: any InfrastructureRepository,
        lookup: any LookupRepository,
        location: any LocationService,
        initialRegion: MapRegion = .mvpArea,
        debounce: Duration = .milliseconds(300),
        preferences: any MapPreferencesStore = InMemoryMapPreferencesStore()
    ) {
        projectRepository = projects
        infrastructureRepository = infrastructure
        lookupRepository = lookup
        locationService = location
        visibleRegion = initialRegion
        routeDetail = RouteDetail.forLongitudeDelta(initialRegion.longitudeDelta)
        self.debounce = debounce
        self.preferences = preferences
        // Khôi phục đồng bộ, trước lần tải đầu: không tải 2 lần / không nhấp nháy lớp tuyến.
        // Gán trong init không chạy `didSet` → không ghi lại ngay.
        if let saved = preferences.load() {
            let disabled = Set(saved.disabledRouteTypes.map(RouteType.init(code:)))
            enabledRouteTypes = Self.allRouteTypes.subtracting(disabled)
            filter = saved.acceptingApplicationsOnly ? .acceptingApplications : .all
            areaToRestore = saved.focusedArea
        }
    }

    convenience init(container: AppContainer) {
        if DebugLaunchOptions.resetsMapPreferences { container.mapPreferences.clear() }
        self.init(
            projects: container.projects,
            infrastructure: container.infrastructure,
            lookup: container.lookup,
            location: container.location,
            preferences: container.mapPreferences
        )
    }

    // MARK: Hành động

    /// Tải danh mục + tuyến (một lần) rồi dự án trong khung nhìn ban đầu.
    func start() async {
        guard loadState == .idle else { return }
        loadState = .loading
        do {
            async let catalog = lookupRepository.catalog()
            // Ít tuyến → tải mọi loại một lần cho mỗi mức chi tiết, bật/tắt lớp lọc ở client.
            async let routes = infrastructureRepository.routes(types: [], detail: routeDetail)
            (self.catalog, self.routes) = try await (catalog, routes)
            routeCache[routeDetail] = self.routes
        } catch {
            loadState = .failed(error as? RepositoryError ?? .network)
            return
        }
        restoreFocusedArea()
        scheduleProjectsLoad(delay: .zero)
        await projectsTask?.value
    }

    func retry() async {
        if catalog.items(in: .projectStatus).isEmpty {
            loadState = .idle
            await start()
        } else {
            scheduleProjectsLoad(delay: .zero)
            await projectsTask?.value
        }
    }

    /// Gọi khi người dùng dừng kéo/zoom. Debounce + hủy lần tải trước để kết quả cũ không ghi đè kết quả mới.
    func regionDidChange(_ region: MapRegion) {
        visibleRegion = region
        scheduleProjectsLoad(delay: debounce)
        updateRouteDetail(for: region)
    }

    /// Zoom qua ngưỡng → đổi hình học tuyến. Đang tải thì vẫn giữ tuyến cũ trên bản đồ; lỗi thì giữ nguyên.
    private func updateRouteDetail(for region: MapRegion) {
        let detail = RouteDetail.forLongitudeDelta(region.longitudeDelta)
        guard detail != routeDetail, loadState == .loaded else { return }
        routeDetail = detail
        routesTask?.cancel()
        if let cached = routeCache[detail] {
            routes = cached
            return
        }
        routesTask = Task { [infrastructureRepository] in
            guard let loaded = try? await infrastructureRepository.routes(types: [], detail: detail),
                  !Task.isCancelled, detail == routeDetail
            else { return }
            routeCache[detail] = loaded
            routes = loaded
        }
    }

    func setFilter(_ newFilter: ProjectFilter) {
        guard newFilter != filter else { return }
        filter = newFilter
        scheduleProjectsLoad(delay: .zero)
    }

    func toggleAcceptingApplicationsFilter() {
        setFilter(showsOnlyAcceptingApplications ? .all : .acceptingApplications)
    }

    /// Segmented vùng. Bấm lại vùng đang chọn → quay về toàn vùng MVP.
    func focus(on area: ServiceArea) {
        if focusedArea == area {
            clearFocus()
            requestCamera(.mvpArea)
            return
        }
        select(area, movesCamera: true)
    }

    /// Chọn vùng + tải ranh giới. `movesCamera == false`: chỉ chip + highlight, camera giữ nguyên.
    private func select(_ area: ServiceArea, movesCamera: Bool) {
        boundaryTask?.cancel()
        guard let center = catalog.item(for: area)?.center else { return }
        focusedArea = area
        focusedBoundary = nil
        if movesCamera {
            requestCamera(MapRegion(center: center, latitudeDelta: 0.22, longitudeDelta: 0.22))
        }
        let ownRequest = movesCamera ? cameraRequest?.id : nil
        boundaryTask = Task { [lookupRepository] in
            guard let boundary = try? await lookupRepository.boundary(of: area),
                  !Task.isCancelled, focusedArea == area
            else { return }
            focusedBoundary = boundary
            // Có ranh giới → khung camera ôm trọn vùng thay vì ô cố định quanh tâm. Chỉ khi chưa có
            // yêu cầu camera mới hơn: mở dự án từ thông báo, tìm kiếm, "Gần tôi" thắng việc chỉnh khung.
            if let ownRequest, let region = boundary.region, cameraRequest?.id == ownRequest {
                requestCamera(region)
            }
        }
    }

    /// Chọn lại vùng đã lưu lần trước. Vùng không còn trong MVP → bỏ (và lưu lại). Camera đã được yêu cầu
    /// đi nơi khác (deep link tới trước) → vẫn chọn chip + highlight nhưng không kéo camera về vùng.
    private func restoreFocusedArea() {
        guard let code = areaToRestore else { return }
        areaToRestore = nil
        let area = ServiceArea(code: code)
        guard area != .unknown, catalog.isInMVP(area), catalog.item(for: area)?.center != nil else {
            persistPreferences()
            return
        }
        guard focusedArea == nil else { return }
        select(area, movesCamera: cameraRequest == nil)
    }

    private func clearFocus() {
        boundaryTask?.cancel()
        focusedArea = nil
        focusedBoundary = nil
    }

    func locateUser() async {
        locationError = nil
        do {
            let location = try await locationService.currentLocation()
            guard MapRegion.allowedArea.contains(location) else {
                locationError = .outsideServiceArea
                return
            }
            userLocation = location
            requestCamera(MapRegion(center: location, latitudeDelta: 0.08, longitudeDelta: 0.08))
        } catch {
            locationError = error
        }
    }

    func dismissLocationError() {
        locationError = nil
    }

    /// Mở sheet dự án theo id (bấm thông báo). Dự án có thể nằm ngoài khung đang tải → hỏi repository.
    func open(projectID: Project.ID) async {
        guard let project = try? await projectRepository.projects(ids: [projectID]).first else { return }
        selectedProject = project
        requestCamera(MapRegion(center: project.location, latitudeDelta: 0.03, longitudeDelta: 0.03))
    }

    func selectSearchResult(_ result: SearchResult) {
        switch result {
        case .project(let project):
            selectedProject = project
            requestCamera(MapRegion(center: project.location, latitudeDelta: 0.03, longitudeDelta: 0.03))
        case .place(let unit):
            guard isAvailable(unit) else { return }
            requestCamera(MapRegion(center: unit.center, latitudeDelta: 0.08, longitudeDelta: 0.08))
        }
        searchQuery = ""
    }

    func toggleRouteType(_ type: RouteType) {
        if enabledRouteTypes.contains(type) {
            enabledRouteTypes.remove(type)
        } else {
            enabledRouteTypes.insert(type)
        }
    }

    // MARK: Nội bộ

    private func persistPreferences() {
        preferences.save(MapPreferences(
            disabledRouteTypes: Self.allRouteTypes.subtracting(enabledRouteTypes).map(\.rawValue).sorted(),
            acceptingApplicationsOnly: filter == .acceptingApplications,
            focusedArea: focusedArea?.rawValue ?? areaToRestore
        ))
    }

    private func scheduleProjectsLoad(delay: Duration) {
        projectsTask?.cancel()
        // Lấy rộng hơn khung nhìn để ghim không "bật ra" ở mép khi kéo nhẹ.
        let fetchRegion = visibleRegion.scaled(by: 1.5)
        let filter = filter
        projectsTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            await self.loadProjects(in: fetchRegion, filter: filter)
        }
    }

    private func requestCamera(_ region: MapRegion) {
        cameraRequest = CameraRequest(region: region)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let needle = SearchNormalizer.normalize(query)
        guard needle.count >= 2 else {
            searchResults = []
            comingSoonAreas = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            if let delay = self?.debounce, delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            let results: [SearchResult]
            do {
                results = try await self.projectRepository.search(query)
                self.searchFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                // Phân biệt "lỗi" với "không có kết quả" để UI không báo sai.
                results = []
                self.searchFailed = true
            }
            guard !Task.isCancelled else { return }
            self.searchResults = results
            self.comingSoonAreas = self.catalog.items(in: .serviceArea).filter { item in
                item.attributes["in_mvp"] != "true" && SearchNormalizer.normalize(item.label).contains(needle)
            }
            self.isSearching = false
        }
    }

    private func loadProjects(in region: MapRegion, filter: ProjectFilter) async {
        if projects.isEmpty { loadState = .loading }
        do {
            let result = try await projectRepository.projects(in: region, filter: filter)
            guard !Task.isCancelled else { return }
            projects = result
            // Không bỏ chọn khi dự án ra khỏi khung: sheet đang mở không được tự đóng khi người dùng kéo map.
            loadState = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            // Giữ ghim cũ trên map khi lỗi; UI hiện banner thử lại.
            loadState = .failed(error as? RepositoryError ?? .network)
        }
    }

    private static func drawOrder(_ status: RouteStatus) -> Int {
        switch status {
        case .planned, .unknown: 0
        case .underConstruction: 1
        case .operational: 2
        }
    }
}

extension MapRegion {
    func scaled(by factor: Double) -> MapRegion {
        MapRegion(center: center, latitudeDelta: latitudeDelta * factor, longitudeDelta: longitudeDelta * factor)
    }
}
