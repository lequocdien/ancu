import Foundation
import Testing
@testable import AnCu

/// Ghi nhớ chip bản đồ (architecture.md 5.6): lớp tuyến, "Đang nhận hồ sơ", vùng.
@MainActor
struct MapPreferencesTests {
    private let container = AppContainer.mock(
        defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none
    )

    private func make(_ store: any MapPreferencesStore) -> MapViewModel {
        MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, debounce: .zero, preferences: store
        )
    }

    @Test func choicesSurviveRelaunch() async {
        let store = InMemoryMapPreferencesStore()
        let first = make(store)
        await first.start()
        first.toggleRouteType(.nationalHighway)
        first.toggleAcceptingApplicationsFilter()
        first.focus(on: .dongNaiOld)
        await first.boundaryTask?.value

        let second = make(store)
        // Lớp tuyến + bộ lọc có ngay từ init, trước lần tải đầu (không nhấp nháy).
        #expect(second.enabledRouteTypes == [.metro, .ringRoad, .expressway])
        #expect(second.showsOnlyAcceptingApplications)
        await second.start()
        await second.boundaryTask?.value
        #expect(second.focusedArea == .dongNaiOld)
        #expect(second.focusedBoundary?.area == .dongNaiOld)
        #expect(second.cameraRequest?.region == second.focusedBoundary?.region)
        #expect(second.projects.allSatisfy { $0.status == .acceptingApplications })
    }

    @Test func defaultsWhenNothingSaved() async {
        let viewModel = make(InMemoryMapPreferencesStore())
        await viewModel.start()
        #expect(viewModel.enabledRouteTypes == MapViewModel.allRouteTypes)
        #expect(!viewModel.showsOnlyAcceptingApplications)
        #expect(viewModel.focusedArea == nil && viewModel.cameraRequest == nil)
    }

    /// Tắt hết lớp tuyến là lựa chọn hợp lệ — mở lại vẫn tắt hết, không về mặc định.
    @Test func allLayersOffIsRemembered() {
        let store = InMemoryMapPreferencesStore()
        let first = make(store)
        for type in MapViewModel.allRouteTypes { first.toggleRouteType(type) }
        #expect(make(store).enabledRouteTypes.isEmpty)
    }

    @Test func unknownCodesAreIgnored() async {
        let store = InMemoryMapPreferencesStore(MapPreferences(
            disabledRouteTypes: ["metro", "tau_dien_tren_khong"], focusedArea: "ha_noi"
        ))
        let viewModel = make(store)
        #expect(viewModel.enabledRouteTypes == [.ringRoad, .expressway, .nationalHighway])
        await viewModel.start()
        #expect(viewModel.focusedArea == nil)
        // Vùng không hợp lệ bị bỏ khỏi bản lưu.
        #expect(store.load()?.focusedArea == nil)
    }

    /// Vùng ngoài MVP (vd Bình Phước cũ) không được khôi phục dù còn trong danh mục.
    @Test func areaOutsideMVPIsDropped() async {
        let store = InMemoryMapPreferencesStore(MapPreferences(focusedArea: "binh_phuoc_cu"))
        let viewModel = make(store)
        await viewModel.start()
        #expect(viewModel.focusedArea == nil)
        #expect(store.load()?.focusedArea == nil)
    }

    /// Mở app từ thông báo dự án: camera đi tới dự án, vùng đã lưu chỉ highlight, không kéo camera về.
    @Test func deepLinkWinsOverRestoredArea() async throws {
        let store = InMemoryMapPreferencesStore(MapPreferences(focusedArea: "hcm_cu"))
        let viewModel = make(store)
        let target = try #require(try await container.projects.projects(in: .mvpArea, filter: .all)
            .first { $0.serviceArea == .dongNaiOld })

        await viewModel.open(projectID: target.id)
        await viewModel.start()
        await viewModel.boundaryTask?.value

        #expect(viewModel.focusedArea == .hcmOld)
        #expect(viewModel.focusedBoundary?.area == .hcmOld)
        #expect(viewModel.cameraRequest?.region.center == target.location)
        #expect(store.load()?.focusedArea == "hcm_cu")
    }

    /// Ranh giới tải xong sau khi người dùng đã chọn dự án khác → không giật camera về khung vùng.
    @Test func boundaryDoesNotOverrideNewerCameraRequest() async throws {
        let viewModel = make(InMemoryMapPreferencesStore())
        await viewModel.start()
        let project = try #require(viewModel.projects.first)

        viewModel.focus(on: .hcmOld)
        viewModel.selectSearchResult(.project(project))
        await viewModel.boundaryTask?.value

        #expect(viewModel.focusedBoundary?.area == .hcmOld)
        #expect(viewModel.cameraRequest?.region.center == project.location)
    }

    /// Bỏ chọn vùng ("Xem toàn vùng" hoặc bấm lại chip) được lưu — mở lại không tự chọn vùng cũ.
    @Test func clearingAreaIsRemembered() async {
        let store = InMemoryMapPreferencesStore()
        let first = make(store)
        await first.start()
        first.focus(on: .binhDuongOld)
        first.showWholeArea()

        let second = make(store)
        await second.start()
        #expect(second.focusedArea == nil)
    }

    /// Đổi lớp tuyến trước khi danh mục tải xong không làm mất vùng đang chờ khôi phục.
    @Test func earlyToggleKeepsPendingArea() {
        let store = InMemoryMapPreferencesStore(MapPreferences(focusedArea: "dong_nai_cu"))
        let viewModel = make(store)
        viewModel.toggleRouteType(.metro)
        #expect(store.load() == MapPreferences(disabledRouteTypes: ["metro"], focusedArea: "dong_nai_cu"))
    }

    @Test func userDefaultsStoreRoundTripsAndToleratesBadData() throws {
        let suite = MockDefaultsSuite(name: "test.\(UUID().uuidString)")
        let store = UserDefaultsMapPreferencesStore(suite: suite)
        #expect(store.load() == nil)

        let prefs = MapPreferences(disabledRouteTypes: ["quoc_lo"], acceptingApplicationsOnly: true, focusedArea: "hcm_cu")
        store.save(prefs)
        #expect(store.load() == prefs)

        // Bản ghi thiếu khóa (định dạng cũ/mới) → giá trị mặc định cho khóa thiếu.
        suite.open().set(Data(#"{"focusedArea":"hcm_cu"}"#.utf8), forKey: UserDefaultsMapPreferencesStore.key)
        #expect(store.load() == MapPreferences(focusedArea: "hcm_cu"))

        // Hỏng định dạng → như chưa lưu, không crash.
        suite.open().set(Data("not json".utf8), forKey: UserDefaultsMapPreferencesStore.key)
        #expect(store.load() == nil)

        store.clear()
        #expect(store.load() == nil)
    }
}
