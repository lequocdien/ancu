import Foundation

// DTO dùng chung cho mock JSON và RPC Supabase (cùng shape, key snake_case — xem src/supabase/README.md).
// Decode bằng `.convertFromSnakeCase` nên tên thuộc tính là camelCase của key: `source_url` → `sourceUrl`.
// Ngày giữ dạng String; mapper tự parse để lỗi định dạng thành `RepositoryError.decoding`.

struct PointDTO: Decodable, Sendable {
    let lat: Double
    let lng: Double
}

struct LookupItemDTO: Decodable, Sendable {
    let code: String
    let labelVi: String
    let sortOrder: Int
    let colorHex: String?
    let sfSymbol: String?
    let attributes: [String: String]?
    let center: PointDTO?
}

struct AdministrativeUnitDTO: Decodable, Sendable {
    let code: String
    let name: String
    let province: String
    let serviceArea: String
    let oldNames: [String]
    let center: PointDTO
}

struct ProjectDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let wardCode: String?
    let serviceArea: String
    let location: PointDTO
    let status: String
    let legalStatus: String
    /// "yyyy-MM-dd", giờ Việt Nam.
    let applicationStart: String?
    let applicationEnd: String?
    let priceMin: Double?
    let priceMax: Double?
    let priceIsEstimated: Bool?
    let unitCount: Int?
    let developer: String?
    let coverImageUrl: String?
    let sourceUrl: String
    let verifiedAt: String
}

struct RouteDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let type: String
    let status: String
    let expectedYear: Int?
    let colorHex: String
    let segments: [[PointDTO]]
    let sourceUrl: String
    let verifiedAt: String
    /// Thêm ở migration 16; thiếu → minh họa.
    let geometryAccuracy: String?
}

struct NodeDTO: Decodable, Sendable {
    let id: UUID
    let routeId: UUID?
    let name: String
    let type: String
    let location: PointDTO
    let geometryAccuracy: String?
}

struct NotificationDTO: Decodable, Sendable {
    let id: UUID
    let type: String
    let projectId: UUID
    let title: String
    let body: String
    /// ISO 8601 có giờ.
    let createdAt: String
    let isRead: Bool
}

struct EligibilityRuleDTO: Decodable, Sendable {
    let ruleKey: String
    /// "number" | "text" | "codes"
    let valueType: String
    let valueNumber: Double?
    let valueText: String?
    let valueCodes: [String]?
    let legalReference: String
    let effectiveFrom: String
    let isMock: Bool
}

/// `service_area_boundaries.json` / RPC `service_area_boundary`.
struct ServiceAreaBoundaryDTO: Decodable, Sendable {
    let code: String
    let isMock: Bool
    let sourceUrl: String
    let verifiedAt: String
    let polygons: [[PointDTO]]
}

// MARK: - Chỉ có ở RPC (mock tự tính ở client)

/// RPC `client_config`.
struct ClientConfigDTO: Decodable, Sendable {
    let minSupportedVersion: String
    let appStoreUrl: String?
}

/// RPC `project_detail`.
struct ProjectDetailDTO: Decodable, Sendable {
    let project: ProjectDTO
    let coverImageUrl: String?
    let nearestInfra: [NearestInfraDTO]
}

struct NearestInfraDTO: Decodable, Sendable {
    let node: NodeDTO
    let routeName: String?
    let routeType: String?
    let routeStatus: String?
    let expectedYear: Int?
    let distanceMeters: Double
}

/// RPC `search_places`.
struct SearchResponseDTO: Decodable, Sendable {
    let projects: [ProjectDTO]
    let places: [AdministrativeUnitDTO]
}

/// RPC `my_bookmarks`.
struct BookmarkDTO: Decodable, Sendable {
    let projectId: UUID
    let notifyEnabled: Bool
    /// Thêm ở migration 13; server cũ không trả → `nil`.
    let note: String?
    /// ISO 8601 có giờ.
    let createdAt: String
}

/// RPC `my_saved_places`, `create_saved_place`, `update_saved_place`.
struct SavedPlaceDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let address: String?
    let location: PointDTO
    let kind: String
    /// Thêm ở migration 14; server cũ không trả → `nil`.
    let icon: String?
    let serviceArea: String
    let note: String?
    let externalRef: String?
    /// ISO 8601 có giờ.
    let createdAt: String
    let updatedAt: String
}

/// RPC `current_profile`.
struct ProfileDTO: Decodable, Sendable {
    let id: UUID
    let displayName: String
    let isPhoneVerified: Bool
    let maskedPhone: String?
}
