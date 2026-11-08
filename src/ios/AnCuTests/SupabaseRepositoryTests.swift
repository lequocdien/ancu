import Foundation
import Testing
@testable import AnCu

/// Fake `RPCClient`: trả JSON fixture theo tên hàm, ghi lại tham số đã gửi.
final class FakeRPCClient: RPCClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<Data, RepositoryError>]
    private(set) var calls: [(function: String, params: [String: Any])] = []

    init(_ responses: [String: Result<Data, RepositoryError>] = [:]) {
        self.responses = responses
    }

    func respond(_ function: String, json: String) {
        lock.withLock { responses[function] = .success(Data(json.utf8)) }
    }

    func fail(_ function: String, with error: RepositoryError) {
        lock.withLock { responses[function] = .failure(error) }
    }

    func call(_ function: String, params: some Encodable & Sendable) async throws -> Data {
        let encoded = try JSONEncoder().encode(params)
        let dictionary = (try JSONSerialization.jsonObject(with: encoded) as? [String: Any]) ?? [:]
        let response = lock.withLock {
            calls.append((function, dictionary))
            return responses[function]
        }
        guard let response else { Issue.record("Chưa khai báo fixture cho \(function)"); throw RepositoryError.network }
        return try response.get()
    }

    func callCount(_ function: String) -> Int {
        lock.withLock { calls.filter { $0.function == function }.count }
    }

    func lastParams(_ function: String) -> [String: Any]? {
        lock.withLock { calls.last { $0.function == function }?.params }
    }
}

enum RPCFixtures {
    static let projectID = UUID(uuidString: "ffe14cd8-75bb-5a59-b5dd-a91c233c5cfc")!

    static let project = """
    {"id": "ffe14cd8-75bb-5a59-b5dd-a91c233c5cfc", "name": "NOXH Hòa Bình Xanh", "address": "Phường Thủ Đức, TP.HCM",
     "ward_code": "hcm_thu_duc", "service_area": "tp_hcm", "location": {"lat": 10.842, "lng": 106.772},
     "status": "nhan_ho_so", "legal_status": "du_dieu_kien_ban", "application_start": "2026-11-01",
     "application_end": "2026-11-18", "price_min": 22.50, "price_max": 24.00, "price_is_estimated": false,
     "unit_count": 1240, "developer": null, "cover_image_url": null,
     "source_url": "https://mock.ancu.vn/nguon/du-an/hoa_binh_xanh", "verified_at": "2026-11-02"}
    """

    static let node = """
    {"id": "5bb6fb99-d6a2-5008-bffc-df22460939b8", "route_id": "114bfa70-5447-58b6-ac1e-59ae01daa9c2",
     "name": "Ga Bến Thành", "type": "ga_metro", "location": {"lat": 10.7721, "lng": 106.6983}}
    """

    static let place = """
    {"code": "hcm_thu_duc", "name": "Phường Thủ Đức", "province": "TP.HCM", "service_area": "tp_hcm",
     "old_names": ["TP Thủ Đức"], "center": {"lat": 10.85, "lng": 106.77}}
    """
}

struct SupabaseProjectRepositoryTests {
    @Test func bboxSendsContractParamsAndMapsProjects() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("projects_in_bbox", json: "[\(RPCFixtures.project)]")
        let repository = SupabaseProjectRepository(rpc: rpc)

        let filter = ProjectFilter(statuses: [.acceptingApplications], serviceAreas: [])
        let projects = try await repository.projects(in: .mvpArea, filter: filter)

        let params = try #require(rpc.lastParams("projects_in_bbox"))
        #expect(Set(params.keys) == ["min_lng", "min_lat", "max_lng", "max_lat", "statuses", "service_areas"])
        #expect(params["statuses"] as? [String] == ["nhan_ho_so"])
        #expect(params["service_areas"] as? [String] == [])
        #expect((params["min_lng"] as? Double).map { abs($0 - 106.35) < 1e-9 } == true)

        let project = try #require(projects.first)
        #expect(project.id == RPCFixtures.projectID)
        #expect(project.status == .acceptingApplications)
        #expect(project.price?.min == Decimal(string: "22.5"))
        // Ngày thật từ server: không dời như mock.
        #expect(Project.vietnamCalendar.dateComponents([.year, .month, .day], from: project.verifiedAt)
                == DateComponents(year: 2026, month: 11, day: 2))
    }

    @Test func emptyIDsSkipsNetwork() async throws {
        let rpc = FakeRPCClient()
        #expect(try await SupabaseProjectRepository(rpc: rpc).projects(ids: []).isEmpty)
        #expect(rpc.calls.isEmpty)
    }

    @Test func detailMapsNearestInfraAndCover() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("project_detail", json: """
        {"project": \(RPCFixtures.project), "cover_image_url": "https://cdn.ancu.vn/a.jpg",
         "nearest_infra": [{"node": \(RPCFixtures.node), "route_name": "Metro số 1", "route_type": "metro",
                            "route_status": "da_khai_thac", "expected_year": 2024, "distance_meters": 5210},
                           {"node": \(RPCFixtures.node), "route_name": null, "route_type": null,
                            "route_status": null, "expected_year": null, "distance_meters": 12000}]}
        """)
        let detail = try await SupabaseProjectRepository(rpc: rpc).project(id: RPCFixtures.projectID)

        #expect(rpc.lastParams("project_detail")?["project_id"] as? String == RPCFixtures.projectID.uuidString)
        #expect(detail.coverImageURL?.absoluteString == "https://cdn.ancu.vn/a.jpg")
        #expect(detail.nearestInfra.count == 2)
        #expect(detail.nearestInfra[0].routeType == .metro && detail.nearestInfra[0].distanceMeters == 5210)
        #expect(detail.nearestInfra[1].routeName == nil && detail.nearestInfra[1].routeType == nil)
    }

    @Test func notFoundPassesThrough() async {
        let rpc = FakeRPCClient()
        rpc.fail("project_detail", with: .notFound)
        await #expect(throws: RepositoryError.notFound) {
            try await SupabaseProjectRepository(rpc: rpc).project(id: UUID())
        }
    }

    @Test func malformedJSONIsDecodingError() async {
        let rpc = FakeRPCClient()
        rpc.respond("projects_in_bbox", json: #"[{"id": "khong-phai-uuid"}]"#)
        await #expect(throws: RepositoryError.decoding) {
            try await SupabaseProjectRepository(rpc: rpc).projects(in: .mvpArea, filter: .all)
        }
    }

    @Test func searchSkipsShortQueryAndListsProjectsBeforePlaces() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("search_places", json: #"{"projects": [\#(RPCFixtures.project)], "places": [\#(RPCFixtures.place)]}"#)
        let repository = SupabaseProjectRepository(rpc: rpc)

        #expect(try await repository.search(" đ ").isEmpty)
        #expect(rpc.calls.isEmpty)

        let results = try await repository.search("thu duc")
        #expect(rpc.lastParams("search_places")?["q"] as? String == "thu duc")
        #expect(results.map(\.id) == ["project-\(RPCFixtures.projectID.uuidString)", "place-hcm_thu_duc"])
    }
}

struct SupabaseOtherRepositoryTests {
    @Test func routesSendSortedTypes() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("routes", json: "[]")
        _ = try await SupabaseInfrastructureRepository(rpc: rpc).routes(types: [.metro, .expressway])
        let params = try #require(rpc.lastParams("routes"))
        #expect(params["types"] as? [String] == [RouteType.expressway.rawValue, RouteType.metro.rawValue].sorted())
        #expect(params["tolerance_degrees"] as? Double == 0)
    }

    @Test func catalogIgnoresUnknownCategoryAndIsCached() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("lookup_catalog", json: """
        {"project_statuses": [{"code": "nhan_ho_so", "label_vi": "Đang nhận hồ sơ", "sort_order": 1}],
         "category_moi_tren_server": [{"code": "x", "label_vi": "X", "sort_order": 1}]}
        """)
        let repository = SupabaseLookupRepository(rpc: rpc)

        let catalog = try await repository.catalog()
        #expect(catalog.label(for: ProjectStatus.acceptingApplications) == "Đang nhận hồ sơ")
        #expect(catalog.items(in: .routeType).isEmpty)

        _ = try await repository.catalog()
        #expect(rpc.callCount("lookup_catalog") == 1)
    }

    @Test func catalogFailureIsNotCached() async throws {
        let rpc = FakeRPCClient()
        rpc.fail("lookup_catalog", with: .network)
        let repository = SupabaseLookupRepository(rpc: rpc)
        await #expect(throws: RepositoryError.network) { try await repository.catalog() }

        rpc.respond("lookup_catalog", json: "{}")
        _ = try await repository.catalog()
        #expect(rpc.callCount("lookup_catalog") == 2)
    }

    @Test func eligibilityRulesDecodeStrippedNulls() async throws {
        let rpc = FakeRPCClient()
        // `jsonb_strip_nulls` bỏ hẳn key null phía server.
        rpc.respond("eligibility_rules_current", json: """
        [{"rule_key": "income_max_single_million", "value_type": "number", "value_number": 25,
          "legal_reference": "NĐ 136/2026", "effective_from": "2026-04-07", "is_mock": true}]
        """)
        let rules = try await SupabaseEligibilityRepository(rpc: rpc).currentRules()
        #expect(rules.first?.value == .number(25))
    }
}

struct SupabaseErrorMapperTests {
    @Test(arguments: [
        ("P0002", RepositoryError.notFound), ("PGRST116", .notFound),
        ("42501", .unauthorized), ("PGRST301", .unauthorized), ("XX000", .network),
    ])
    func postgrestCodes(_ code: String, _ expected: RepositoryError) {
        #expect(SupabaseErrorMapper.map(postgrestCode: code) == expected)
    }

    @Test(arguments: [(401, RepositoryError.unauthorized), (404, .notFound), (429, .rateLimited), (503, .network)])
    func httpStatuses(_ status: Int, _ expected: RepositoryError) {
        #expect(SupabaseErrorMapper.map(status: status) == expected)
    }

    @Test func cancellationIsPreserved() {
        #expect(SupabaseErrorMapper.map(CancellationError()) is CancellationError)
        #expect(SupabaseErrorMapper.map(URLError(.cancelled)) is CancellationError)
        #expect(SupabaseErrorMapper.map(URLError(.notConnectedToInternet)) as? RepositoryError == .network)
    }
}
