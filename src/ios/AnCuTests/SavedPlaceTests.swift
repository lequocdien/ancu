import Foundation
import Testing
@testable import AnCu

/// Vùng MVP ở client — phải khớp quy tắc `mvp_service_area_at` ở server (migration 13).
struct ServiceAreaLocatorTests {
    private let square = AreaBoundary(
        area: .hcm,
        polygons: [[GeoPoint(latitude: 10.0, longitude: 106.0), GeoPoint(latitude: 10.0, longitude: 106.2),
                    GeoPoint(latitude: 10.2, longitude: 106.2), GeoPoint(latitude: 10.2, longitude: 106.0)]],
        isMock: true
    )

    @Test func insideHasZeroDistance() {
        #expect(ServiceAreaLocator.distanceMeters(from: GeoPoint(latitude: 10.1, longitude: 106.1), to: square.polygons[0]) == 0)
        #expect(ServiceAreaLocator.area(at: GeoPoint(latitude: 10.1, longitude: 106.1), in: [square]) == .hcm)
    }

    @Test func toleranceAroundBorder() {
        // 0,02° kinh độ ở vĩ độ 10 ≈ 2,19 km; 0,06° ≈ 6,6 km.
        let near = GeoPoint(latitude: 10.1, longitude: 105.98)
        let far = GeoPoint(latitude: 10.1, longitude: 105.94)
        let nearDistance = ServiceAreaLocator.distanceMeters(from: near, to: square.polygons[0])
        #expect(abs(nearDistance - 2192) < 30)
        #expect(ServiceAreaLocator.area(at: near, in: [square]) == .hcm)
        #expect(ServiceAreaLocator.area(at: far, in: [square]) == nil)
    }

    @Test func nearestAreaWins() {
        let east = AreaBoundary(
            area: .dongNai,
            polygons: [[GeoPoint(latitude: 10.0, longitude: 106.21), GeoPoint(latitude: 10.0, longitude: 106.4),
                        GeoPoint(latitude: 10.2, longitude: 106.4), GeoPoint(latitude: 10.2, longitude: 106.21)]],
            isMock: true
        )
        // Nằm trong Đồng Nai, cách TP.HCM ~1 km → Đồng Nai (khoảng cách 0).
        #expect(ServiceAreaLocator.area(at: GeoPoint(latitude: 10.1, longitude: 106.209), in: [square, east]) == .dongNai)
    }

    /// Dùng ranh giới mock thật (5 tỉnh mới): dự án mẫu + Vũng Tàu thuộc TP.HCM, Hà Nội ngoài vùng.
    @Test func realMockBoundaries() async throws {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        var boundaries: [AreaBoundary] = []
        for area in [ServiceArea.hcm, .dongNai, .tayNinh, .dongThap, .lamDong] {
            if let boundary = try await container.lookup.boundary(of: area) { boundaries.append(boundary) }
        }
        let fixtures = Dictionary(uniqueKeysWithValues: MockPlaceSearchService.fixtures.map { ($0.id, $0.location) })
        #expect(ServiceAreaLocator.area(at: try #require(fixtures["mock-vgp"]), in: boundaries) == .hcm)
        #expect(ServiceAreaLocator.area(at: try #require(fixtures["mock-vungtau"]), in: boundaries) == .hcm)
        #expect(ServiceAreaLocator.area(at: try #require(fixtures["mock-hanoi"]), in: boundaries) == nil)
    }
}

@MainActor
struct SavedPlaceSessionTests {
    private func make() -> (SessionStore, AppContainer) {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        return (SessionStore(container: container), container)
    }

    private func draft(_ name: String = "Masteri Thảo Điền", at location: GeoPoint = GeoPoint(latitude: 10.8027, longitude: 106.74),
                       kind: PlaceKind = .commercial, note: String? = " giá 70tr/m² ") -> SavedPlaceDraft {
        SavedPlaceDraft(name: name, address: "Thảo Điền", location: location, kind: kind, note: note, externalRef: "mock-masteri")
    }

    @Test func guestCannotSavePlaceOrNote() async throws {
        let (session, _) = make()
        await session.load()
        await #expect(throws: RepositoryError.unauthorized) { try await session.createPlace(draft(), source: "search") }
        let project = try #require(projectIDs.first)
        #expect(try await session.setNote("ghi chú", for: project) == false)
        #expect(session.savedPlaces.isEmpty)
    }

    @Test func signedInLifecycle() async throws {
        let (session, _) = make()
        try await session.signIn(with: .apple)

        let created = try await session.createPlace(draft(), source: "search")
        #expect(created.serviceArea == .hcm)
        #expect(created.note == "giá 70tr/m²")
        #expect(session.savedPlaces.map(\.id) == [created.id])

        try await session.updatePlace(created.id, name: "Masteri (đã xem nhà mẫu)", kind: .commercial, icon: "yeu_thich", note: "")
        #expect(session.savedPlaces.first?.name == "Masteri (đã xem nhà mẫu)")
        #expect(session.savedPlaces.first?.note == nil)
        #expect(session.savedPlaces.first?.icon == "yeu_thich")

        // Đăng xuất → ẩn; đăng nhập lại → thấy lại (dữ liệu vẫn trên "server").
        try await session.signOut()
        #expect(session.savedPlaces.isEmpty)
        try await session.signIn(with: .apple)
        #expect(session.savedPlaces.count == 1)

        try await session.deletePlace(created.id)
        #expect(session.savedPlaces.isEmpty)
    }

    @Test func outsideServiceAreaIsRejected() async throws {
        let (session, _) = make()
        try await session.signIn(with: .apple)
        await #expect(throws: RepositoryError.outsideServiceArea) {
            try await session.createPlace(draft("Vinhomes Smart City", at: GeoPoint(latitude: 21.004, longitude: 105.747)), source: "search")
        }
        await #expect(throws: RepositoryError.decoding) {
            try await session.createPlace(draft("   "), source: "pin")
        }
        await #expect(throws: RepositoryError.decoding) {
            try await session.createPlace(draft(note: String(repeating: "a", count: SavedPlace.maxNoteLength + 1)), source: "pin")
        }
    }

    @Test func limitOf200() async throws {
        let (session, _) = make()
        try await session.signIn(with: .apple)
        for index in 0..<SavedPlace.maxCount {
            _ = try await session.createPlace(draft("P\(index)", kind: .other, note: nil), source: "pin")
        }
        await #expect(throws: RepositoryError.limitReached) { try await session.createPlace(draft("P201"), source: "pin") }
    }

    @Test func bookmarkNoteAutoSavesAndClears() async throws {
        let (session, _) = make()
        try await session.signIn(with: .apple)
        let project = try #require(projectIDs.first)

        #expect(try await session.setNote(" gần chỗ làm ", for: project))
        #expect(session.isSaved(project))
        #expect(session.note(for: project) == "gần chỗ làm")

        #expect(try await session.setNote("  ", for: project))
        #expect(session.isSaved(project))
        #expect(session.note(for: project) == nil)
    }

    @Test func deletingAccountRemovesPlaces() async throws {
        let (session, container) = make()
        try await session.signIn(with: .apple)
        _ = try await session.createPlace(draft(), source: "search")
        try await session.deleteAccount()
        try await session.signIn(with: .apple)
        #expect(try await container.savedPlaces.all().isEmpty)
    }

    /// Id dự án mock cố định (projects.geojson) — dùng một id có thật để bookmark hợp lệ.
    private var projectIDs: [Project.ID] { [UUID(uuidString: "ffe14cd8-75bb-5a59-b5dd-a91c233c5cfc")!] }
}

/// Repository Supabase với fake RPC: tham số gửi đi (kể cả `null` tường minh) và giải mã.
struct SupabaseSavedPlaceRepositoryTests {
    private actor SignedIn: AuthService {
        nonisolated let socialProviders: [AuthProvider] = []
        var currentUser: AppUser? { MockAuthService.demoUser }
        func signIn(with provider: AuthProvider) async throws -> AppUser { MockAuthService.demoUser }
        func sendEmailCode(to email: String) async throws {}
        func verifyEmailCode(_ code: String, email: String) async throws -> AppUser { MockAuthService.demoUser }
        func signOut() async throws {}
        func deleteAccount() async throws {}
    }

    static let placeJSON = #"""
    {"id": "6f1c2a4e-1111-4a2b-9c3d-2e4f5a6b7c8d", "name": "Masteri Thảo Điền", "address": "Thảo Điền",
     "location": {"lat": 10.8027, "lng": 106.74}, "kind": "thuong_mai", "service_area": "tp_hcm", "note": null,
     "external_ref": "abc", "created_at": "2026-11-07T04:39:49.936656+00:00", "updated_at": "2026-11-07T04:39:49.936656+00:00"}
    """#

    @Test func createSendsAllParamsIncludingNulls() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("create_saved_place", json: Self.placeJSON)
        let repository = SupabaseSavedPlaceRepository(rpc: rpc, auth: SignedIn())

        let place = try await repository.create(SavedPlaceDraft(
            name: " Masteri Thảo Điền ", address: nil, location: GeoPoint(latitude: 10.8027, longitude: 106.74),
            kind: .commercial, note: "  ", externalRef: nil
        ))
        let params = try #require(rpc.lastParams("create_saved_place"))
        #expect(Set(params.keys) == ["name", "lat", "lng", "kind", "address", "note", "external_ref", "icon"])
        #expect(params["icon"] is NSNull)
        #expect(params["name"] as? String == "Masteri Thảo Điền")
        #expect(params["kind"] as? String == "thuong_mai")
        #expect(params["note"] is NSNull && params["address"] is NSNull)
        #expect(place.kind == .commercial && place.serviceArea == .hcm && place.note == nil)
    }

    @Test func bookmarkNoteSendsExplicitNullToClear() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("set_bookmark_note", json: "null")
        let repository = SupabaseBookmarkRepository(rpc: rpc, auth: SignedIn(), suite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"))
        try await repository.setNote("   ", projectID: RPCFixtures.projectID)
        let params = try #require(rpc.lastParams("set_bookmark_note"))
        #expect(params["note"] is NSNull)
        #expect(params["project_id"] as? String == RPCFixtures.projectID.uuidString)
    }

    @Test func myBookmarksDecodesNote() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("my_bookmarks", json: #"[{"project_id": "\#(RPCFixtures.projectID.uuidString)", "notify_enabled": false, "note": "gần chợ", "created_at": "2026-11-07T04:39:49.936656+00:00"}]"#)
        let repository = SupabaseBookmarkRepository(rpc: rpc, auth: SignedIn(), suite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"))
        #expect(try await repository.all().first?.note == "gần chợ")
    }

    @Test(arguments: [("AC403", RepositoryError.outsideServiceArea), ("AC409", .limitReached)])
    func serverCodesMap(code: String, expected: RepositoryError) {
        #expect(SupabaseErrorMapper.map(postgrestCode: code) == expected)
    }
}

/// Icon tự chọn (migration 14): chỉ nhận mã danh mục, `nil` = icon theo loại.
@MainActor
struct SavedPlaceIconTests {
    private let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)

    private var draft: SavedPlaceDraft {
        SavedPlaceDraft(name: "Chỗ làm", address: nil, location: GeoPoint(latitude: 10.80, longitude: 106.70),
                        kind: .other, note: nil, externalRef: nil, icon: "cho_lam")
    }

    @Test func catalogHasIconsWithSymbols() async throws {
        let catalog = try await container.lookup.catalog()
        #expect(catalog.items(in: .placeIcon).count == 16)
        #expect(catalog.placeIconSymbol("cho_lam") == "briefcase.fill")
        #expect(catalog.placeIconSymbol("khong_co") == nil && catalog.placeIconSymbol(nil) == nil)
    }

    @Test func iconIsSavedUpdatedAndCleared() async throws {
        let session = SessionStore(container: container)
        try await session.signIn(with: .apple)
        let created = try await session.createPlace(draft, source: "pin")
        #expect(created.icon == "cho_lam")

        try await session.updatePlace(created.id, name: "Chỗ làm", kind: .other, icon: "truong_hoc", note: nil)
        #expect(session.savedPlaces.first?.icon == "truong_hoc")
        try await session.updatePlace(created.id, name: "Chỗ làm", kind: .other, icon: nil, note: nil)
        #expect(session.savedPlaces.first?.icon == nil)

        // Tên SF Symbol thay cho mã → từ chối như server (22023 → .decoding).
        await #expect(throws: RepositoryError.decoding) {
            try await session.updatePlace(created.id, name: "Chỗ làm", kind: .other, icon: "briefcase.fill", note: nil)
        }
    }

    @Test func editorKeepsAndChangesIcon() async throws {
        let session = SessionStore(container: container)
        try await session.signIn(with: .apple)
        let created = try await session.createPlace(draft, source: "pin")
        let editor = PlaceEditorViewModel(
            mode: .edit(created), session: session, projects: container.projects, dataReports: container.dataReports,
            resolveArea: { _ in nil }
        )
        #expect(editor.icon == "cho_lam")
        editor.icon = "nha_bo_me"
        #expect(await editor.save())
        #expect(session.savedPlaces.first?.icon == "nha_bo_me")
    }

    @Test func supabaseSendsIconExplicitly() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("update_saved_place", json: SupabaseSavedPlaceRepositoryTests.placeJSON)
        rpc.respond("create_saved_place", json: SupabaseSavedPlaceRepositoryTests.placeJSON)
        let repository = SupabaseSavedPlaceRepository(rpc: rpc, auth: container.auth)
        try await container.auth.signIn(with: .apple)
        _ = try await repository.update(id: UUID(), name: "X", kind: .other, icon: nil, note: nil)
        #expect(rpc.lastParams("update_saved_place")?["icon"] is NSNull)
        _ = try await repository.create(draft)
        #expect(rpc.lastParams("create_saved_place")?["icon"] as? String == "cho_lam")
    }
}
