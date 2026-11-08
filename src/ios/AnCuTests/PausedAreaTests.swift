import Foundation
import Testing
@testable import AnCu

/// Admin tạm ngừng một tỉnh (`ingest.set_service_area_active(code, false, lý do)` → in_mvp = false): app đọc lại danh mục
/// là đủ — không cần phát hành bản mới.
@MainActor
struct PausedAreaTests {
    /// Bọc lookup mock, đặt in_mvp = false cho các vùng chỉ định (giả lập danh mục server sau khi admin tắt).
    struct PausingLookup: LookupRepository {
        let base: any LookupRepository
        let paused: Set<ServiceArea>

        func catalog() async throws -> LookupCatalog {
            let catalog = try await base.catalog()
            var items: [LookupCategory: [LookupItem]] = [:]
            for category in LookupCategory.allCases {
                items[category] = catalog.items(in: category).map { item in
                    guard category == .serviceArea, let area = ServiceArea(rawValue: item.code), paused.contains(area) else {
                        return item
                    }
                    var attributes = item.attributes
                    attributes["in_mvp"] = "false"
                    attributes["paused_reason"] = "chưa có dự án"
                    return LookupItem(code: item.code, label: item.label, sortOrder: item.sortOrder, colorHex: item.colorHex,
                                      symbolName: item.symbolName, attributes: attributes, center: item.center)
                }
            }
            return LookupCatalog(items: items)
        }
        func administrativeUnits() async throws -> [AdministrativeUnit] { try await base.administrativeUnits() }
        func boundary(of area: ServiceArea) async throws -> AreaBoundary? { try await base.boundary(of: area) }
    }

    private let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)

    private func make(paused: Set<ServiceArea>, store: any MapPreferencesStore = InMemoryMapPreferencesStore()) -> MapViewModel {
        MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure,
            lookup: PausingLookup(base: container.lookup, paused: paused),
            location: container.location, debounce: .zero, preferences: store
        )
    }

    @Test func pausedAreasLoseChips() async {
        let viewModel = make(paused: [.dongThap, .lamDong])
        await viewModel.start()
        #expect(viewModel.mvpAreas == [.hcm, .dongNai, .tayNinh])
    }

    /// Người dùng đã chọn Lâm Đồng ở lần mở trước → admin tắt → mở lại app không khôi phục vùng đó.
    @Test func pausedAreaIsNotRestored() async {
        let store = InMemoryMapPreferencesStore(MapPreferences(focusedArea: "lam_dong"))
        let viewModel = make(paused: [.lamDong], store: store)
        await viewModel.start()
        #expect(viewModel.focusedArea == nil)
        #expect(store.load()?.focusedArea == nil)
    }

    @Test func pausedAreaShowsComingSoonInSearch() async {
        let viewModel = make(paused: [.lamDong])
        await viewModel.start()
        viewModel.searchQuery = "lam dong"
        await viewModel.searchTask?.value
        #expect(viewModel.comingSoonAreas.map(\.code) == ["lam_dong"])
    }
    // Ẩn dự án của tỉnh tạm ngừng do server làm (projects_in_bbox / search_places) — test ở pgTAP service_area_toggle.
}
