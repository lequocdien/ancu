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
    /// Tuyến người dùng chạm vào: nổi bật + thẻ tên (các tuyến cùng loại giờ cùng màu nên cần cách này để phân biệt).
    private(set) var selectedRoute: InfraRoute?

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
    /// Nhóm "Địa điểm khác" (Apple Maps) — dự án ngoài hệ thống để lưu riêng (PRD 4.6).
    private(set) var placeResults: [PlaceResult] = []

    // MARK: Chọn vị trí trước khi lưu

    /// Đang chọn vị trí (từ kết quả tìm kiếm hoặc nhấn giữ): ghim nằm cố định trên bản đồ (kéo/zoom map
    /// không đổi điểm chọn); người dùng kéo chính cái ghim để chỉnh.
    private(set) var placePick: PlacePick?
    private var pickAreaTask: Task<Void, Never>?
    private var pickAddressTask: Task<Void, Never>?
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
    /// `nil` = không tìm địa điểm ngoài hệ thống (test cũ, Preview tối giản).
    private let placeSearch: (any PlaceSearchService)?
    /// `nil` = không tra địa chỉ khi chọn vị trí.
    private let reverseGeocoder: (any ReverseGeocoder)?
    /// Chờ một nhịp sau khi thả ghim rồi mới tra địa chỉ (Apple giới hạn tần suất geocoding; thả rồi kéo lại ngay → hủy).
    private let geocodeDelay: Duration
    /// Ranh giới vùng MVP — tải ở lần tìm địa điểm đầu tiên (không tốn request lúc mở app).
    private var mvpBoundaries: [AreaBoundary]?
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
        preferences: any MapPreferencesStore = InMemoryMapPreferencesStore(),
        placeSearch: (any PlaceSearchService)? = nil,
        reverseGeocoder: (any ReverseGeocoder)? = nil,
        geocodeDelay: Duration = .milliseconds(500)
    ) {
        projectRepository = projects
        infrastructureRepository = infrastructure
        lookupRepository = lookup
        locationService = location
        visibleRegion = initialRegion
        routeDetail = RouteDetail.forLongitudeDelta(initialRegion.longitudeDelta)
        self.debounce = debounce
        self.preferences = preferences
        self.placeSearch = placeSearch
        self.reverseGeocoder = reverseGeocoder
        self.geocodeDelay = geocodeDelay
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
            preferences: container.mapPreferences,
            placeSearch: container.placeSearch,
            reverseGeocoder: container.reverseGeocoder
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
            if selectedRoute?.type == type { selectedRoute = nil }
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
            placeResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            if let delay = self?.debounce, delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            // Hai nguồn chạy song song; Apple Maps lỗi không làm hỏng kết quả trong An Cư.
            async let places = self.searchPlaces(query)
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
            let placeResults = await places
            guard !Task.isCancelled else { return }
            self.searchResults = results
            self.placeResults = placeResults
            self.comingSoonAreas = self.catalog.items(in: .serviceArea).filter { item in
                item.attributes["in_mvp"] != "true" && SearchNormalizer.normalize(item.label).contains(needle)
            }
            self.isSearching = false
        }
    }

    /// Kết quả Apple Maps, gắn vùng MVP để UI làm mờ kết quả ngoài vùng. Trùng dự án trong An Cư được
    /// kiểm tra lúc lưu (≤ 300 m, `PlaceEditorViewModel`) — không lọc ở đây để người dùng vẫn thấy kết quả quen.
    private func searchPlaces(_ query: String) async -> [PlaceResult] {
        guard let placeSearch,
              let candidates = try? await placeSearch.search(query, near: .mvpArea)
        else { return [] }
        let boundaries = await loadMVPBoundaries()
        return candidates.map { PlaceResult(candidate: $0, area: ServiceAreaLocator.area(at: $0.location, in: boundaries)) }
    }

    // MARK: Chạm vào tuyến

    /// Bán kính chạm quanh ngón tay, tính theo điểm màn hình (caller đổi sang mét theo mức zoom).
    static let routeTapTolerancePoints: Double = 22

    /// Chạm bản đồ: trúng tuyến đang hiện → chọn tuyến đó; chạm chỗ trống → bỏ chọn. Trả `true` nếu trúng tuyến.
    @discardableResult
    func selectRoute(near point: GeoPoint, toleranceMeters: Double) -> Bool {
        guard placePick == nil else { return false }
        selectedRoute = RouteHitTester.nearestRoute(to: point, in: visibleRoutes, toleranceMeters: toleranceMeters)
        return selectedRoute != nil
    }

    func clearRouteSelection() {
        selectedRoute = nil
    }

    /// Bấm kết quả Apple Maps → xem trên bản đồ trước, chưa lưu.
    func startPick(from candidate: PlaceCandidate) {
        beginPick(PlacePick(
            location: candidate.location, name: candidate.name, address: candidate.address,
            externalRef: candidate.externalRef, start: candidate.location, source: "search"
        ))
    }

    /// Nhấn giữ trên bản đồ → ghim tạm tại điểm đó.
    func startPick(at point: GeoPoint) {
        beginPick(PlacePick(location: point, name: nil, address: nil, externalRef: nil, start: point, source: "pin"))
    }

    private func beginPick(_ pick: PlacePick) {
        selectedProject = nil
        selectedRoute = nil
        searchQuery = ""
        placePick = pick
        // Zoom cấp đường phố, tâm đúng điểm: ghim giữa màn hình trùng vị trí.
        requestCamera(MapRegion(center: pick.location, latitudeDelta: PlacePick.zoomDelta, longitudeDelta: PlacePick.zoomDelta))
        resolvePickArea()
        resolvePickAddress(delay: .zero)
    }

    /// Đang kéo ghim → cập nhật điểm chọn. Vùng + địa chỉ kiểm tra lại khi thả (`finishMovingPick`).
    func movePick(to point: GeoPoint) {
        guard var pick = placePick, pick.location != point else { return }
        pick.location = point
        pick.isCheckingArea = true
        if pick.needsResolvedAddress {
            pick.resolvedAddress = nil
            pick.isResolvingAddress = true
        }
        placePick = pick
        pickAddressTask?.cancel()
    }

    /// Thả ghim → kiểm tra vùng hỗ trợ + tra địa chỉ tại điểm mới.
    func finishMovingPick() {
        guard let pick = placePick else { return }
        if pick.isCheckingArea { resolvePickArea() }
        if pick.isResolvingAddress { resolvePickAddress(delay: geocodeDelay) }
    }

    func cancelPick() {
        pickAreaTask?.cancel()
        pickAddressTask?.cancel()
        placePick = nil
    }

    /// Địa chỉ của điểm đang chọn. Còn gần kết quả Apple Maps → giữ địa chỉ của kết quả, không tra lại.
    private func resolvePickAddress(delay: Duration) {
        pickAddressTask?.cancel()
        guard let pick = placePick, pick.needsResolvedAddress else {
            if var pick = placePick {
                pick.isResolvingAddress = false
                placePick = pick
            }
            return
        }
        guard let reverseGeocoder else {
            var unresolved = pick
            unresolved.isResolvingAddress = false
            placePick = unresolved
            return
        }
        let location = pick.location
        pickAddressTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            // Lỗi mạng / không có địa chỉ → để trống, vẫn lưu được (địa chỉ là tùy chọn).
            let address = try? await reverseGeocoder.address(at: location)
            guard !Task.isCancelled, let self, var current = self.placePick, current.location == location else { return }
            current.resolvedAddress = address ?? nil
            current.isResolvingAddress = false
            self.placePick = current
        }
    }

    /// Mở cho test `await`.
    var pickAddressTaskForTesting: Task<Void, Never>? { pickAddressTask }

    private func resolvePickArea() {
        pickAreaTask?.cancel()
        guard let location = placePick?.location else { return }
        pickAreaTask = Task { [weak self] in
            guard let self else { return }
            let area = await self.serviceArea(at: location)
            guard !Task.isCancelled, var pick = self.placePick, pick.location == location else { return }
            pick.area = area
            pick.isCheckingArea = false
            self.placePick = pick
        }
    }

    /// Mở cho test `await`.
    var pickAreaTaskForTesting: Task<Void, Never>? { pickAreaTask }

    /// Vùng MVP tại một điểm (cùng quy tắc server). Dùng cho ghim tay + kết quả tìm kiếm.
    func serviceArea(at point: GeoPoint) async -> ServiceArea? {
        ServiceAreaLocator.area(at: point, in: await loadMVPBoundaries())
    }

    private func loadMVPBoundaries() async -> [AreaBoundary] {
        if let mvpBoundaries { return mvpBoundaries }
        var loaded: [AreaBoundary] = []
        for area in mvpAreas {
            if let boundary = try? await lookupRepository.boundary(of: area) { loaded.append(boundary) }
        }
        // Lỗi mạng → không cache, lần sau thử lại.
        if loaded.count == mvpAreas.count { mvpBoundaries = loaded }
        return loaded
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

/// Vị trí đang chọn trước khi lưu (PRD 4.6). Tọa độ Apple Maps ở VN hay lệch → cho kéo bản đồ chỉnh.
struct PlacePick: Equatable, Sendable {
    /// Khung camera khi bắt đầu chọn (~1,3 km) — đủ thấy đường/ngõ để đặt ghim chính xác.
    static let zoomDelta = 0.012
    /// Kéo xa hơn khoảng này so với kết quả Apple Maps → địa chỉ của kết quả không còn đúng (tra lại), bỏ mã Apple Maps.
    static let keepsSourceWithinMeters: Double = 100

    var location: GeoPoint
    let name: String?
    let address: String?
    let externalRef: String?
    /// Điểm ban đầu (kết quả tìm kiếm / chỗ nhấn giữ).
    let start: GeoPoint
    let source: String
    var area: ServiceArea?
    var isCheckingArea = true
    /// Địa chỉ tra từ vị trí hiện tại (reverse geocoding) — dùng khi ghim tay hoặc đã dời xa kết quả Apple Maps.
    var resolvedAddress: String?
    var isResolvingAddress = true

    var isOutsideServiceArea: Bool { !isCheckingArea && area == nil }
    /// Ghim tay luôn cần tra; kết quả tìm kiếm chỉ cần khi đã dời xa.
    var needsResolvedAddress: Bool { address == nil || hasMovedFromSource }
    /// Địa chỉ hiển thị + lưu cho vị trí hiện tại.
    var currentAddress: String? { needsResolvedAddress ? resolvedAddress : address }
    var canSave: Bool { !isCheckingArea && area != nil }
    var hasMovedFromSource: Bool { location.distance(to: start) > Self.keepsSourceWithinMeters }

    /// Dữ liệu mở sheet lưu. Tên giữ lại (người dùng sửa được); địa chỉ theo vị trí hiện tại;
    /// mã Apple Maps bỏ nếu đã kéo xa (không còn là địa điểm đó).
    var editorOrigin: PlaceEditorViewModel.Origin {
        var origin = PlaceEditorViewModel.Origin(pin: location)
        origin.name = name ?? ""
        origin.source = source
        origin.address = currentAddress
        if !hasMovedFromSource { origin.externalRef = externalRef }
        return origin
    }
}

/// Một kết quả "Địa điểm khác". `area == nil` → ngoài vùng hỗ trợ, không lưu được.
struct PlaceResult: Identifiable, Hashable, Sendable {
    let candidate: PlaceCandidate
    let area: ServiceArea?
    var id: String { candidate.id }
    var isAvailable: Bool { area != nil }
}

extension MapRegion {
    func scaled(by factor: Double) -> MapRegion {
        MapRegion(center: center, latitudeDelta: latitudeDelta * factor, longitudeDelta: longitudeDelta * factor)
    }
}
