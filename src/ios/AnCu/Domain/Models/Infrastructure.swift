import Foundation

struct InfraRoute: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let type: RouteType
    let status: RouteStatus
    let expectedYear: Int?
    let colorHex: String
    /// MultiLineString: một tuyến có thể gồm nhiều đoạn rời (vd Vành đai 3 khai thác từng đoạn).
    let segments: [[GeoPoint]]
    let sourceURL: URL
    let verifiedAt: Date
    var geometryAccuracy: GeometryAccuracy = .illustrative
}

struct InfraNode: Identifiable, Hashable, Sendable {
    let id: UUID
    /// `nil` cho điểm không thuộc tuyến nào (vd Sân bay Long Thành).
    let routeID: InfraRoute.ID?
    let name: String
    let type: NodeType
    let location: GeoPoint
    var geometryAccuracy: GeometryAccuracy = .illustrative
}

/// Độ chính xác hình học của tuyến/ga (data-strategy.md 2b). Thiếu/lạ → `.illustrative` (thận trọng nhất).
enum GeometryAccuracy: String, Sendable, Hashable {
    /// Đã xây, đối chiếu được (vd Metro 1).
    case exact = "chinh_xac"
    /// Theo hồ sơ dự án (đang thi công / chuẩn bị đầu tư).
    case approximate = "gan_dung"
    /// Chỉ có trong quy hoạch — hướng tuyến/vị trí ga mang tính minh họa.
    case illustrative = "minh_hoa"

    init(code: String?) {
        self = code.flatMap(GeometryAccuracy.init(rawValue:)) ?? .illustrative
    }
}
