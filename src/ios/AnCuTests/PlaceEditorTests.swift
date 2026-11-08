import Foundation
import Testing
@testable import AnCu

@MainActor
struct PlaceSearchTests {
    private func make() -> MapViewModel {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        return MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, debounce: .zero, placeSearch: container.placeSearch
        )
    }

    @Test func searchReturnsBothGroupsAndMarksOutsideArea() async {
        let viewModel = make()
        await viewModel.start()
        viewModel.searchQuery = "vinhomes"
        await viewModel.searchTask?.value

        let byName = Dictionary(uniqueKeysWithValues: viewModel.placeResults.map { ($0.candidate.name, $0) })
        #expect(byName["Vinhomes Grand Park"]?.area == .hcm)
        #expect(byName["Vinhomes Smart City"]?.isAvailable == false)   // Hà Nội
    }

    @Test func projectSearchStillWorksWithoutPlaceService() async {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let viewModel = MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, debounce: .zero
        )
        await viewModel.start()
        viewModel.searchQuery = "Hòa Bình"
        await viewModel.searchTask?.value
        #expect(!viewModel.searchResults.isEmpty)
        #expect(viewModel.placeResults.isEmpty)
    }

    @Test func clearingQueryClearsPlaces() async {
        let viewModel = make()
        await viewModel.start()
        viewModel.searchQuery = "masteri"
        await viewModel.searchTask?.value
        #expect(viewModel.placeResults.count == 1)
        viewModel.searchQuery = ""
        #expect(viewModel.placeResults.isEmpty)
    }

    @Test func serviceAreaAtUsesSameRuleAsServer() async {
        let viewModel = make()
        await viewModel.start()
        #expect(await viewModel.serviceArea(at: GeoPoint(latitude: 10.95, longitude: 106.83)) == .dongNai)
        #expect(await viewModel.serviceArea(at: GeoPoint(latitude: 10.346, longitude: 107.0843)) == .hcm)   // Vũng Tàu
        #expect(await viewModel.serviceArea(at: GeoPoint(latitude: 21.004, longitude: 105.747)) == nil)    // Hà Nội
    }
}

@MainActor
struct PlaceEditorViewModelTests {
    private let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)

    private func make(_ mode: PlaceEditorViewModel.Mode, session: SessionStore) -> PlaceEditorViewModel {
        let map = MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, debounce: .zero
        )
        return PlaceEditorViewModel(
            mode: mode, session: session, projects: container.projects, dataReports: container.dataReports,
            resolveArea: { point in
                await map.start()
                return await map.serviceArea(at: point)
            }
        )
    }

    private func signedInSession() async throws -> SessionStore {
        let session = SessionStore(container: container)
        try await session.signIn(with: .apple)
        return session
    }

    private func candidate(_ id: String) throws -> PlaceCandidate {
        try #require(MockPlaceSearchService.fixtures.first { $0.id == id })
    }

    @Test func createFromSearchSaves() async throws {
        let session = try await signedInSession()
        let editor = make(.create(.init(candidate: try candidate("mock-masteri"))), session: session)
        #expect(!editor.canSave)   // đang kiểm tra vùng
        await editor.load()
        #expect(editor.area == .hcm && editor.nearbyProject == nil && editor.canSave)

        editor.note = "  Giá 70 tr/m²  "
        #expect(await editor.save())
        #expect(session.savedPlaces.first?.name == "Masteri Thảo Điền")
        #expect(session.savedPlaces.first?.note == "Giá 70 tr/m²")
        #expect(session.savedPlaces.first?.externalRef == "mock-masteri")
    }

    @Test func outsideAreaCannotSave() async throws {
        let session = try await signedInSession()
        let editor = make(.create(.init(candidate: try candidate("mock-hanoi"))), session: session)
        await editor.load()
        #expect(editor.isOutsideServiceArea)
        #expect(!editor.canSave)
        #expect(await editor.save() == false)
    }

    /// Hòa Bình Xanh (NOXH trong An Cư) ở 10.842, 106.772 — điểm cách ~50 m phải được gợi ý.
    @Test func nearbySystemProjectIsSuggested() async throws {
        let session = try await signedInSession()
        let editor = make(.create(.init(candidate: try candidate("mock-hbx"))), session: session)
        await editor.load()
        #expect(editor.nearbyProject?.name == "NOXH Hòa Bình Xanh")
        // Vẫn cho lưu riêng nếu người dùng muốn.
        #expect(editor.canSave)
    }

    @Test func pinRequiresNameAndRespectsNoteLimit() async throws {
        let session = try await signedInSession()
        let editor = make(.create(.init(pin: GeoPoint(latitude: 10.80, longitude: 106.70))), session: session)
        await editor.load()
        #expect(!editor.canSave)
        editor.name = "Chỗ làm"
        editor.kind = .other
        #expect(editor.canSave)
        editor.note = String(repeating: "a", count: SavedPlace.maxNoteLength + 1)
        #expect(editor.isNoteTooLong && !editor.canSave)
    }

    @Test func suggestionOnlyForSocialHousingAndNeverSendsNote() async throws {
        let session = try await signedInSession()
        let editor = make(.create(.init(pin: GeoPoint(latitude: 10.85, longitude: 106.77))), session: session)
        await editor.load()
        editor.name = "NOXH Mới chưa có"
        editor.kind = .commercial
        #expect(!editor.canSuggest)
        editor.kind = .socialHousing
        #expect(editor.canSuggest)
        editor.suggestsToAnCu = true
        editor.note = "SĐT môi giới 0909…"
        #expect(await editor.save())
        #expect(editor.suggestionOutcome == .sent)

        let reports = try #require(container.dataReports as? MockDataReportRepository)
        let sent = await reports.suggestions
        #expect(sent.map(\.name) == ["NOXH Mới chưa có"])
        // Ghi chú không nằm trong bất kỳ trường nào được gửi.
        #expect(sent.allSatisfy { !($0.address ?? "").contains("0909") && !$0.name.contains("0909") })
    }

    @Test func editAndDelete() async throws {
        let session = try await signedInSession()
        let created = try await session.createPlace(
            SavedPlaceDraft(name: "Picity", address: nil, location: GeoPoint(latitude: 10.877, longitude: 106.672),
                            kind: .commercial, note: "cũ", externalRef: nil),
            source: "search"
        )
        let editor = make(.edit(created), session: session)
        await editor.load()
        #expect(editor.canSave && editor.note == "cũ")
        editor.note = "mới"
        #expect(await editor.save())
        #expect(session.savedPlaces.first?.note == "mới")

        let deleting = make(.edit(try #require(session.savedPlaces.first)), session: session)
        #expect(await deleting.delete())
        #expect(session.savedPlaces.isEmpty)
    }

    /// Lỗi khi lưu: giữ nguyên nội dung đã nhập để thử lại (không tự lưu tạm).
    @Test func failureKeepsInput() async throws {
        let session = SessionStore(container: container)   // khách: server sẽ từ chối
        let editor = make(.create(.init(pin: GeoPoint(latitude: 10.80, longitude: 106.70))), session: session)
        await editor.load()
        editor.name = "Chỗ làm"
        editor.note = "ghi chú dài"
        #expect(await editor.save() == false)
        #expect(editor.saveState == .failed(.unauthorized))
        #expect(editor.name == "Chỗ làm" && editor.note == "ghi chú dài")
    }
}

/// Chọn vị trí trước khi lưu: xem trên bản đồ, kéo bản đồ để chỉnh, kiểm tra vùng khi dừng.
@MainActor
struct PlacePickTests {
    private func make() async -> MapViewModel {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let viewModel = MapViewModel(
            projects: container.projects, infrastructure: container.infrastructure, lookup: container.lookup,
            location: container.location, debounce: .zero, placeSearch: container.placeSearch,
            reverseGeocoder: container.reverseGeocoder, geocodeDelay: .zero
        )
        await viewModel.start()
        return viewModel
    }

    private var masteri: PlaceCandidate { MockPlaceSearchService.fixtures.first { $0.id == "mock-masteri" }! }

    @Test func searchResultIsPreviewedNotSaved() async {
        let viewModel = await make()
        viewModel.searchQuery = "masteri"
        viewModel.startPick(from: masteri)
        #expect(viewModel.searchQuery.isEmpty)
        #expect(viewModel.cameraRequest?.region.center == masteri.location)
        #expect(viewModel.placePick?.isCheckingArea == true && viewModel.placePick?.canSave == false)

        await viewModel.pickAreaTaskForTesting?.value
        #expect(viewModel.placePick?.area == .hcm && viewModel.placePick?.canSave == true)
        let origin = viewModel.placePick?.editorOrigin
        #expect(origin?.name == "Masteri Thảo Điền" && origin?.externalRef == "mock-masteri" && origin?.source == "search")
    }

    @Test func draggingPinMovesPickAndRechecksArea() async {
        let viewModel = await make()
        viewModel.startPick(at: GeoPoint(latitude: 10.80, longitude: 106.70))
        await viewModel.pickAreaTaskForTesting?.value
        #expect(viewModel.placePick?.canSave == true)

        // Kéo ra khơi (Côn Đảo hướng, ngoài mọi ranh giới): đang kéo → khóa nút Lưu; dừng → báo ngoài vùng.
        let sea = GeoPoint(latitude: 9.60, longitude: 107.20)
        viewModel.movePick(to: sea)
        #expect(viewModel.placePick?.location == sea && viewModel.placePick?.canSave == false)
        viewModel.finishMovingPick()
        await viewModel.pickAreaTaskForTesting?.value
        #expect(viewModel.placePick?.isOutsideServiceArea == true)

        // Kéo lại vào Biên Hòa.
        viewModel.movePick(to: GeoPoint(latitude: 10.95, longitude: 106.83))
        viewModel.finishMovingPick()
        await viewModel.pickAreaTaskForTesting?.value
        #expect(viewModel.placePick?.area == .dongNai)
    }

    /// Dời ghim xa kết quả Apple Maps > 100 m → giữ tên, địa chỉ tra lại theo vị trí mới, bỏ mã Apple Maps.
    @Test func movingFarResolvesNewAddress() async {
        let viewModel = await make()
        viewModel.startPick(from: masteri)
        await viewModel.pickAddressTaskForTesting?.value
        #expect(viewModel.placePick?.currentAddress == masteri.address)   // chưa dời: địa chỉ của kết quả

        viewModel.movePick(to: GeoPoint(latitude: masteri.location.latitude + 0.0005, longitude: masteri.location.longitude))
        #expect(viewModel.placePick?.editorOrigin.externalRef == "mock-masteri")   // ~55 m: vẫn là địa điểm đó
        #expect(viewModel.placePick?.currentAddress == masteri.address)

        let moved = GeoPoint(latitude: masteri.location.latitude + 0.003, longitude: masteri.location.longitude)
        viewModel.movePick(to: moved)
        #expect(viewModel.placePick?.isResolvingAddress == true && viewModel.placePick?.currentAddress == nil)
        viewModel.finishMovingPick()
        await viewModel.pickAddressTaskForTesting?.value
        let origin = viewModel.placePick?.editorOrigin
        #expect(origin?.name == "Masteri Thảo Điền" && origin?.externalRef == nil)
        #expect(origin?.address == String(format: "Gần %.4f, %.4f", moved.latitude, moved.longitude))
    }

    /// Ghim tay: địa chỉ tra ngay; kéo tới chỗ khác → địa chỉ đổi theo khi dừng.
    @Test func pinAddressFollowsMap() async {
        let viewModel = await make()
        let vgp = MockPlaceSearchService.fixtures.first { $0.id == "mock-vgp" }!
        viewModel.startPick(at: vgp.location)
        await viewModel.pickAddressTaskForTesting?.value
        #expect(viewModel.placePick?.currentAddress == vgp.address)

        let other = GeoPoint(latitude: 10.80, longitude: 106.70)
        viewModel.movePick(to: other)
        viewModel.finishMovingPick()
        await viewModel.pickAddressTaskForTesting?.value
        #expect(viewModel.placePick?.currentAddress == "Gần 10.8000, 106.7000")
        #expect(viewModel.placePick?.editorOrigin.address == "Gần 10.8000, 106.7000")
    }

    /// Đang kéo tiếp trước khi tra xong → kết quả cũ không ghi đè vị trí mới.
    @Test func staleAddressIsIgnored() async {
        let viewModel = await make()
        viewModel.startPick(at: GeoPoint(latitude: 10.80, longitude: 106.70))
        viewModel.movePick(to: GeoPoint(latitude: 10.81, longitude: 106.71))
        viewModel.finishMovingPick()
        viewModel.movePick(to: GeoPoint(latitude: 10.82, longitude: 106.72))
        viewModel.finishMovingPick()
        await viewModel.pickAddressTaskForTesting?.value
        #expect(viewModel.placePick?.currentAddress == "Gần 10.8200, 106.7200")
    }

    /// Kéo / zoom bản đồ (camera đổi) KHÔNG đổi điểm chọn — ghim cố định theo tọa độ.
    @Test func panningMapKeepsPickInPlace() async {
        let viewModel = await make()
        let start = GeoPoint(latitude: 10.80, longitude: 106.70)
        viewModel.startPick(at: start)
        await viewModel.pickAreaTaskForTesting?.value
        await viewModel.pickAddressTaskForTesting?.value

        viewModel.regionDidChange(MapRegion(center: GeoPoint(latitude: 10.95, longitude: 106.85), latitudeDelta: 0.5, longitudeDelta: 0.5))
        viewModel.regionDidChange(MapRegion(center: GeoPoint(latitude: 10.81, longitude: 106.71), latitudeDelta: 0.01, longitudeDelta: 0.01))
        #expect(viewModel.placePick?.location == start)
        #expect(viewModel.placePick?.canSave == true && viewModel.placePick?.isResolvingAddress == false)
    }

    /// "Đưa ghim vào giữa": đặt ghim tại tâm khung nhìn hiện tại rồi kiểm tra lại.
    @Test func recenterMovesPickToVisibleCenter() async {
        let viewModel = await make()
        viewModel.startPick(at: GeoPoint(latitude: 10.80, longitude: 106.70))
        let visible = MapRegion(center: GeoPoint(latitude: 10.95, longitude: 106.83), latitudeDelta: 0.05, longitudeDelta: 0.05)
        viewModel.regionDidChange(visible)
        viewModel.movePick(to: viewModel.visibleRegion.center)
        viewModel.finishMovingPick()
        await viewModel.pickAreaTaskForTesting?.value
        #expect(viewModel.placePick?.location == visible.center && viewModel.placePick?.area == .dongNai)
    }

    @Test func startingPickClosesProjectSheetAndCancelClears() async throws {
        let viewModel = await make()
        viewModel.selectedProject = try #require(viewModel.projects.first)
        viewModel.startPick(at: GeoPoint(latitude: 10.80, longitude: 106.70))
        #expect(viewModel.selectedProject == nil)
        viewModel.cancelPick()
        #expect(viewModel.placePick == nil)
        // Camera đổi sau khi hủy không còn tác dụng.
        viewModel.movePick(to: GeoPoint(latitude: 10.9, longitude: 106.9))
        #expect(viewModel.placePick == nil)
    }
}
