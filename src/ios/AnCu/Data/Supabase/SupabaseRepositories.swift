import Foundation

// Repository đọc dữ liệu công khai qua RPC Supabase (contract: src/supabase/README.md).
// Dùng lại DTO + `DTOMapper` của mock; ngày là ngày thật nên `shift: .none`.
// Bookmark, Notification, DataReport, Auth: bước 2 (architecture.md 5.5).

// MARK: - Project

struct SupabaseProjectRepository: ProjectRepository {
    let rpc: any RPCClient

    private struct BBoxParams: Encodable, Sendable {
        let minLng, minLat, maxLng, maxLat: Double
        let statuses: [String]
        let serviceAreas: [String]

        enum CodingKeys: String, CodingKey {
            case minLng = "min_lng", minLat = "min_lat", maxLng = "max_lng", maxLat = "max_lat"
            case statuses, serviceAreas = "service_areas"
        }
    }

    private struct IDsParams: Encodable, Sendable { let ids: [UUID] }

    private struct DetailParams: Encodable, Sendable {
        let projectID: UUID
        enum CodingKeys: String, CodingKey { case projectID = "project_id" }
    }

    private struct SearchParams: Encodable, Sendable { let q: String }

    func projects(in region: MapRegion, filter: ProjectFilter) async throws -> [Project] {
        let params = BBoxParams(
            minLng: region.minLongitude, minLat: region.minLatitude,
            maxLng: region.maxLongitude, maxLat: region.maxLatitude,
            statuses: filter.statuses.map(\.rawValue).sorted(),
            serviceAreas: filter.serviceAreas.map(\.rawValue).sorted()
        )
        let dtos: [ProjectDTO] = try await rpc.call("projects_in_bbox", params: params)
        return try dtos.map { try DTOMapper.project($0, shift: .none) }
    }

    func projects(ids: Set<Project.ID>) async throws -> [Project] {
        guard !ids.isEmpty else { return [] }
        let dtos: [ProjectDTO] = try await rpc.call("projects_by_ids", params: IDsParams(ids: ids.sorted { $0.uuidString < $1.uuidString }))
        return try dtos.map { try DTOMapper.project($0, shift: .none) }
    }

    func project(id: Project.ID) async throws -> ProjectDetail {
        let dto: ProjectDetailDTO = try await rpc.call("project_detail", params: DetailParams(projectID: id))
        return try DTOMapper.projectDetail(dto)
    }

    func search(_ query: String) async throws -> [SearchResult] {
        // Cùng ngưỡng với server (`search_places`) — khỏi tốn round-trip cho 1 ký tự.
        guard SearchNormalizer.normalize(query).count >= 2 else { return [] }
        let dto: SearchResponseDTO = try await rpc.call("search_places", params: SearchParams(q: query))
        let projects = try dto.projects.map { try DTOMapper.project($0, shift: .none) }
        let places = try dto.places.map(DTOMapper.administrativeUnit)
        return Array((projects.map(SearchResult.project) + places.map(SearchResult.place)).prefix(20))
    }
}

// MARK: - Infrastructure

struct SupabaseInfrastructureRepository: InfrastructureRepository {
    let rpc: any RPCClient

    private struct RoutesParams: Encodable, Sendable {
        let types: [String]
        let toleranceDegrees: Double
        enum CodingKeys: String, CodingKey { case types, toleranceDegrees = "tolerance_degrees" }
    }

    private struct NodesParams: Encodable, Sendable { let route: UUID }

    func routes(types: Set<RouteType>, detail: RouteDetail) async throws -> [InfraRoute] {
        let params = RoutesParams(types: types.map(\.rawValue).sorted(), toleranceDegrees: detail.toleranceDegrees)
        let dtos: [RouteDTO] = try await rpc.call("routes", params: params)
        return try dtos.map { try DTOMapper.route($0, shift: .none) }
    }

    func nodes(routeID: InfraRoute.ID) async throws -> [InfraNode] {
        let dtos: [NodeDTO] = try await rpc.call("route_nodes", params: NodesParams(route: routeID))
        return try dtos.map(DTOMapper.node)
    }
}

// MARK: - Lookup

/// Danh mục ít đổi → cache trong phiên. Lỗi không cache để lần sau thử lại.
actor SupabaseLookupRepository: LookupRepository {
    private let rpc: any RPCClient
    private var cachedCatalog: LookupCatalog?
    private var cachedUnits: [AdministrativeUnit]?
    /// `Optional<AreaBoundary>` trong cache: vùng không có ranh giới cũng được nhớ, khỏi hỏi lại.
    private var cachedBoundaries: [ServiceArea: AreaBoundary?] = [:]

    private struct BoundaryParams: Encodable, Sendable {
        let code: String
        let toleranceDegrees: Double
        enum CodingKeys: String, CodingKey { case code, toleranceDegrees = "tolerance_degrees" }
    }

    init(rpc: any RPCClient) {
        self.rpc = rpc
    }

    func catalog() async throws -> LookupCatalog {
        if let cachedCatalog { return cachedCatalog }
        let dto: [String: [LookupItemDTO]] = try await rpc.call("lookup_catalog")
        var items: [LookupCategory: [LookupItem]] = [:]
        // Category lạ (server thêm trước app) bị bỏ qua thay vì làm hỏng cả danh mục.
        for category in LookupCategory.allCases {
            items[category] = try (dto[category.rawValue] ?? []).map(DTOMapper.lookupItem)
        }
        let catalog = LookupCatalog(items: items)
        cachedCatalog = catalog
        return catalog
    }

    func administrativeUnits() async throws -> [AdministrativeUnit] {
        if let cachedUnits { return cachedUnits }
        let dtos: [AdministrativeUnitDTO] = try await rpc.call("administrative_units_all")
        let units = try dtos.map(DTOMapper.administrativeUnit)
        cachedUnits = units
        return units
    }

    func boundary(of area: ServiceArea) async throws -> AreaBoundary? {
        if let cached = cachedBoundaries[area] { return cached }
        // 0,0005° ≈ 55 m: đủ mịn ở mức nhìn cả tỉnh, cắt bớt điểm khi ranh giới thật có hàng nghìn đỉnh.
        let dto: ServiceAreaBoundaryDTO? = try await rpc.call(
            "service_area_boundary", params: BoundaryParams(code: area.rawValue, toleranceDegrees: 0.0005)
        )
        let boundary = try dto.map(DTOMapper.boundary)
        cachedBoundaries[area] = .some(boundary)
        return boundary
    }
}

// MARK: - Eligibility

struct SupabaseEligibilityRepository: EligibilityRepository {
    let rpc: any RPCClient

    func currentRules() async throws -> [EligibilityRule] {
        let dtos: [EligibilityRuleDTO] = try await rpc.call("eligibility_rules_current")
        return try dtos.map(DTOMapper.eligibilityRule)
    }
}

// MARK: - Config

struct SupabaseConfigRepository: ConfigRepository {
    let rpc: any RPCClient

    private struct Params: Encodable, Sendable { let platform: String }

    func clientConfig() async throws -> ClientConfig {
        let dto: ClientConfigDTO = try await rpc.call("client_config", params: Params(platform: "ios"))
        return try DTOMapper.clientConfig(dto)
    }
}
