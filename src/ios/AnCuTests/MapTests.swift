import Foundation
import Testing
@testable import AnCu

struct ProjectClustererTests {
    private func project(_ name: String, lat: Double, lon: Double) -> Project {
        Project(
            id: UUID(), name: name, address: "", wardCode: nil, serviceArea: .hcmOld,
            location: GeoPoint(latitude: lat, longitude: lon), status: .upcoming, legalStatus: .buildingPermit,
            applicationWindow: nil, price: nil, unitCount: nil, developer: nil,
            sourceURL: URL(string: "https://example.com")!, verifiedAt: .now
        )
    }

    private let wide = MapRegion(center: GeoPoint(latitude: 10.88, longitude: 106.80), latitudeDelta: 0.6, longitudeDelta: 0.6)

    @Test func nearbyProjectsMergeIntoCluster() {
        let items = ProjectClusterer.items(
            for: [project("A", lat: 10.801, lon: 106.701), project("B", lat: 10.802, lon: 106.702)],
            in: wide
        )
        #expect(items.count == 1)
        guard case .cluster(let cluster) = items.first else { Issue.record("Phải gom cụm"); return }
        #expect(cluster.projects.map(\.name) == ["A", "B"])
        #expect(cluster.boundingRegion.contains(cluster.projects[0].location))
    }

    @Test func distantProjectsStaySeparate() {
        let items = ProjectClusterer.items(
            for: [project("A", lat: 10.70, lon: 106.60), project("B", lat: 11.05, lon: 106.95)],
            in: wide
        )
        #expect(items.count == 2)
        #expect(items.allSatisfy { if case .project = $0 { true } else { false } })
    }

    @Test func zoomedInNeverClusters() {
        let close = MapRegion(center: GeoPoint(latitude: 10.80, longitude: 106.70), latitudeDelta: 0.02, longitudeDelta: 0.02)
        let items = ProjectClusterer.items(
            for: [project("A", lat: 10.801, lon: 106.701), project("B", lat: 10.802, lon: 106.702)],
            in: close
        )
        #expect(items.count == 2)
    }

    /// Kéo map / zoom nhẹ không được làm cụm xáo trộn (lưới neo tuyệt đối + kích thước ô theo nấc).
    @Test func clustersStableUnderSmallPanAndZoom() {
        let projects = [project("A", lat: 10.801, lon: 106.701), project("B", lat: 10.802, lon: 106.702)]
        let panned = MapRegion(center: GeoPoint(latitude: 10.90, longitude: 106.83), latitudeDelta: 0.62, longitudeDelta: 0.62)
        #expect(ProjectClusterer.items(for: projects, in: wide).map(\.id) == ProjectClusterer.items(for: projects, in: panned).map(\.id))
    }
}

@MainActor
struct MapViewModelTests {
    private static let fixedNow: @Sendable () -> Date = { MockDataStore.anchorDate.addingTimeInterval(12 * 3600) }

    private func makeViewModel(
        debounce: Duration = .zero,
        projects: (any ProjectRepository)? = nil,
        location: (any LocationService)? = nil
    ) -> MapViewModel {
        let container = AppContainer.mock(
            defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none, now: Self.fixedNow
        )
        return MapViewModel(
            projects: projects ?? container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: location ?? container.location, debounce: debounce
        )
    }

    @Test func startLoadsCatalogRoutesAndProjects() async {
        let viewModel = makeViewModel()
        await viewModel.start()

        #expect(viewModel.loadState == .loaded)
        #expect(!viewModel.catalog.items(in: .projectStatus).isEmpty)
        #expect(viewModel.routes.count == 11)
        #expect(viewModel.projects.count == 15)
        #expect(!viewModel.mapItems.isEmpty)
    }

    @Test func toggleRouteTypeHidesRoutesWithoutRefetch() async {
        let viewModel = makeViewModel()
        await viewModel.start()

        viewModel.toggleRouteType(.metro)
        #expect(!viewModel.visibleRoutes.contains { $0.type == .metro })
        #expect(viewModel.routes.contains { $0.type == .metro })

        viewModel.toggleRouteType(.metro)
        #expect(viewModel.visibleRoutes.contains { $0.type == .metro })
    }

    @Test func routesDrawPlannedBelowOperational() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        let statuses = viewModel.visibleRoutes.map(\.status)
        if let lastPlanned = statuses.lastIndex(of: .planned), let firstOperational = statuses.firstIndex(of: .operational) {
            #expect(lastPlanned < firstOperational)
        }
    }

    @Test func regionChangeLoadsOnlyProjectsNearRegion() async {
        let viewModel = makeViewModel()
        await viewModel.start()

        // Khung nhỏ quanh Biên Hòa – Đồng Nai.
        let bienHoa = MapRegion(center: GeoPoint(latitude: 10.95, longitude: 106.85), latitudeDelta: 0.1, longitudeDelta: 0.1)
        viewModel.regionDidChange(bienHoa)
        await viewModel.projectsTask?.value

        #expect(viewModel.projects.count < 15)
        #expect(viewModel.projects.allSatisfy { bienHoa.scaled(by: 1.5).contains($0.location) })
    }

    /// Kéo liên tục: chỉ khung cuối cùng được tải, kết quả của khung cũ không ghi đè.
    @Test func rapidRegionChangesKeepOnlyLatest() async {
        let viewModel = makeViewModel(debounce: .milliseconds(50))
        await viewModel.start()

        let empty = MapRegion(center: GeoPoint(latitude: 0, longitude: 0), latitudeDelta: 0.1, longitudeDelta: 0.1)
        viewModel.regionDidChange(empty)
        viewModel.regionDidChange(.mvpArea)
        await viewModel.projectsTask?.value

        #expect(viewModel.visibleRegion == .mvpArea)
        #expect(viewModel.projects.count == 15)
    }

    @Test func hidingProjectsClearsMapItems() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        viewModel.showsProjects = false
        #expect(viewModel.mapItems.isEmpty)
    }

    // MARK: 5.2 — tìm kiếm, vùng, bộ lọc, vị trí

    @Test func searchMatchesOldDistrictName() async {
        let viewModel = makeViewModel()
        await viewModel.start()

        viewModel.searchQuery = "thu duc"
        await viewModel.searchTask?.value

        #expect(!viewModel.searchResults.isEmpty)
        #expect(!viewModel.searchFailed)
    }

    @Test func searchOutsideMVPShowsComingSoon() async {
        let viewModel = makeViewModel()
        await viewModel.start()

        viewModel.searchQuery = "vung tau"
        await viewModel.searchTask?.value

        #expect(viewModel.comingSoonAreas.map(\.code).contains("ba_ria_vung_tau_cu"))
        // Phường/xã thuộc vùng ngoài MVP không được chọn để bay tới.
        for case .place(let unit) in viewModel.searchResults where unit.serviceArea == .baRiaVungTauOld {
            #expect(!viewModel.isAvailable(unit))
        }
    }

    @Test func shortQueryClearsResultsWithoutCallingRepository() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        viewModel.searchQuery = "thu duc"
        await viewModel.searchTask?.value

        viewModel.searchQuery = "t"
        #expect(viewModel.searchResults.isEmpty)
        #expect(!viewModel.isSearching)
    }

    @Test func searchFailureIsNotReportedAsNoResults() async {
        let viewModel = makeViewModel(projects: FailingProjectRepository())
        viewModel.searchQuery = "thu duc"
        await viewModel.searchTask?.value

        #expect(viewModel.searchFailed)
        #expect(viewModel.searchResults.isEmpty)
    }

    @Test func selectingProjectResultSelectsAndMovesCamera() async throws {
        let viewModel = makeViewModel()
        await viewModel.start()
        let project = try #require(viewModel.projects.first)

        viewModel.selectSearchResult(.project(project))

        #expect(viewModel.selectedProjectID == project.id)
        #expect(viewModel.cameraRequest?.region.center == project.location)
        #expect(viewModel.searchQuery.isEmpty)
    }

    @Test func focusingAreaTwiceReturnsToWholeMVP() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        #expect(viewModel.mvpAreas == [.hcmOld, .binhDuongOld, .dongNaiOld])

        viewModel.focus(on: .dongNaiOld)
        #expect(viewModel.focusedArea == .dongNaiOld)
        #expect(viewModel.cameraRequest?.region.center == viewModel.catalog.item(for: ServiceArea.dongNaiOld)?.center)

        viewModel.focus(on: .dongNaiOld)
        #expect(viewModel.focusedArea == nil)
        #expect(viewModel.cameraRequest?.region == .mvpArea)
    }

    @Test func acceptingFilterTogglesAndReloads() async {
        let viewModel = makeViewModel()
        await viewModel.start()

        viewModel.toggleAcceptingApplicationsFilter()
        await viewModel.projectsTask?.value
        #expect(viewModel.showsOnlyAcceptingApplications)
        #expect(viewModel.projects.count == 5)
        #expect(viewModel.projects.allSatisfy { $0.status == .acceptingApplications })

        viewModel.toggleAcceptingApplicationsFilter()
        await viewModel.projectsTask?.value
        #expect(viewModel.projects.count == 15)
    }

    @Test func locateUserMovesCamera() async {
        let viewModel = makeViewModel()
        await viewModel.locateUser()
        #expect(viewModel.userLocation != nil)
        #expect(viewModel.cameraRequest?.region.center == viewModel.userLocation)
    }

    @Test func locationPermissionDeniedSurfacesError() async {
        let viewModel = makeViewModel(location: MockLocationService(error: .permissionDenied, latency: .none))
        await viewModel.locateUser()
        #expect(viewModel.locationError == .permissionDenied)
        #expect(viewModel.cameraRequest == nil)
    }
}

private struct FailingProjectRepository: ProjectRepository {
    func projects(in region: MapRegion, filter: ProjectFilter) async throws -> [Project] { throw RepositoryError.network }
    func projects(ids: Set<Project.ID>) async throws -> [Project] { throw RepositoryError.network }
    func project(id: Project.ID) async throws -> ProjectDetail { throw RepositoryError.network }
    func search(_ query: String) async throws -> [SearchResult] { throw RepositoryError.network }
}

@MainActor
struct LocateUserOutsideAreaTests {
    @Test func locationOutsideServiceAreaDoesNotMoveCamera() async {
        let hanoi = MockLocationService(location: GeoPoint(latitude: 21.03, longitude: 105.85), latency: .none)
        let container = AppContainer.mock(
            defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none, location: hanoi
        )
        let viewModel = MapViewModel(container: container)
        await viewModel.locateUser()
        #expect(viewModel.locationError == .outsideServiceArea)
        #expect(viewModel.userLocation == nil && viewModel.cameraRequest == nil)
    }
}

/// Phase 1 bước 3.2: giản lược tuyến theo zoom.
struct RouteDetailTests {
    @Test(arguments: [(0.05, RouteDetail.full), (0.149, .full), (0.15, .medium), (0.59, .medium), (0.6, .coarse), (3, .coarse)])
    func thresholds(_ delta: Double, _ expected: RouteDetail) {
        #expect(RouteDetail.forLongitudeDelta(delta) == expected)
    }

    @Test func toleranceShrinksAsDetailGrows() {
        #expect(RouteDetail.coarse.toleranceDegrees > RouteDetail.medium.toleranceDegrees)
        #expect(RouteDetail.full.toleranceDegrees == 0)
    }

    @Test func supabaseSendsTolerance() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("routes", json: "[]")
        _ = try await SupabaseInfrastructureRepository(rpc: rpc).routes(types: [], detail: .coarse)
        #expect(rpc.lastParams("routes")?["tolerance_degrees"] as? Double == 0.002)
    }
}

private final class RecordingInfrastructureRepository: InfrastructureRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [RouteDetail] = []
    var requested: [RouteDetail] { lock.withLock { _requested } }

    func routes(types: Set<RouteType>, detail: RouteDetail) async throws -> [InfraRoute] {
        lock.withLock { _requested.append(detail) }
        return []
    }

    func nodes(routeID: InfraRoute.ID) async throws -> [InfraNode] { [] }
}

@MainActor
struct MapRouteDetailTests {
    @Test func zoomAcrossThresholdReloadsOnceThenUsesCache() async {
        let infra = RecordingInfrastructureRepository()
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let viewModel = MapViewModel(
            projects: container.projects, infrastructure: infra, lookup: container.lookup,
            location: container.location, initialRegion: .mvpArea, debounce: .zero
        )
        await viewModel.start()
        #expect(infra.requested == [.coarse])

        let close = MapRegion(center: MapRegion.mvpArea.center, latitudeDelta: 0.05, longitudeDelta: 0.05)
        viewModel.regionDidChange(close)
        await viewModel.routesTask?.value
        #expect(viewModel.routeDetail == .full)
        #expect(infra.requested == [.coarse, .full])

        // Zoom nhẹ trong cùng bậc: không gọi lại.
        viewModel.regionDidChange(MapRegion(center: close.center, latitudeDelta: 0.08, longitudeDelta: 0.08))
        // Quay lại bậc cũ: lấy từ cache.
        viewModel.regionDidChange(.mvpArea)
        await viewModel.routesTask?.value
        #expect(viewModel.routeDetail == .coarse)
        #expect(infra.requested == [.coarse, .full])
    }
}

/// Phase 1 bước 5.2: khung nhìn trống → gợi ý xem toàn vùng.
@MainActor
struct MapEmptyAreaTests {
    @Test func emptyViewportIsDetectedAndWholeAreaResets() async {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let viewModel = MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, initialRegion: .mvpArea, debounce: .zero
        )
        await viewModel.start()
        #expect(!viewModel.isVisibleAreaEmpty)

        // Rừng Cần Giờ phía nam: trong khung cho phép nhưng không có dự án mock.
        viewModel.regionDidChange(MapRegion(center: GeoPoint(latitude: 10.45, longitude: 106.9), latitudeDelta: 0.05, longitudeDelta: 0.05))
        await viewModel.projectsTask?.value
        #expect(viewModel.isVisibleAreaEmpty)

        viewModel.showWholeArea()
        #expect(viewModel.cameraRequest?.region == .mvpArea)

        viewModel.showsProjects = false   // tắt lớp dự án thì không coi là "trống"
        #expect(!viewModel.isVisibleAreaEmpty)
    }
}

/// Chọn vùng → highlight ranh giới + camera ôm trọn vùng.
@MainActor
struct MapAreaHighlightTests {
    private func make() -> MapViewModel {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        return MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, initialRegion: .mvpArea, debounce: .zero
        )
    }

    @Test func focusingLoadsBoundaryAndFitsCamera() async throws {
        let viewModel = make()
        await viewModel.start()
        viewModel.focus(on: .hcmOld)
        await viewModel.boundaryTask?.value

        let boundary = try #require(viewModel.focusedBoundary)
        #expect(boundary.area == .hcmOld && boundary.isMock)
        let region = try #require(boundary.region)
        #expect(viewModel.cameraRequest?.region == region)
        // Mọi dự án TP.HCM cũ nằm trong khung camera mới.
        #expect(viewModel.projects.filter { $0.serviceArea == .hcmOld }.allSatisfy { region.contains($0.location) })
    }

    @Test func switchingOrClearingDropsOldBoundary() async {
        let viewModel = make()
        await viewModel.start()
        viewModel.focus(on: .hcmOld)
        viewModel.focus(on: .dongNaiOld)        // đổi vùng trước khi ranh giới cũ tải xong
        await viewModel.boundaryTask?.value
        #expect(viewModel.focusedBoundary?.area == .dongNaiOld)

        viewModel.focus(on: .dongNaiOld)        // bấm lại → bỏ chọn
        #expect(viewModel.focusedBoundary == nil && viewModel.focusedArea == nil)

        viewModel.focus(on: .binhDuongOld)
        await viewModel.boundaryTask?.value
        viewModel.showWholeArea()
        #expect(viewModel.focusedBoundary == nil)
    }

    @Test func boundingRegionPadsExtent() throws {
        let region = try #require(MapRegion.bounding([GeoPoint(latitude: 10, longitude: 106), GeoPoint(latitude: 11, longitude: 107)], padding: 0.1))
        #expect(region.center == GeoPoint(latitude: 10.5, longitude: 106.5))
        #expect(abs(region.latitudeDelta - 1.1) < 1e-9)
        #expect(MapRegion.bounding([]) == nil)
    }

    @Test func supabaseBoundaryHandlesMissingAreaAndCaches() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("service_area_boundary", json: "null")
        let repository = SupabaseLookupRepository(rpc: rpc)
        #expect(try await repository.boundary(of: .baRiaVungTauOld) == nil)
        #expect(try await repository.boundary(of: .baRiaVungTauOld) == nil)
        #expect(rpc.callCount("service_area_boundary") == 1)
        #expect(rpc.lastParams("service_area_boundary")?["code"] as? String == "ba_ria_vung_tau_cu")
    }
}
