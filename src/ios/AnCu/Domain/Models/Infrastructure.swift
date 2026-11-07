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
}

struct InfraNode: Identifiable, Hashable, Sendable {
    let id: UUID
    /// `nil` cho điểm không thuộc tuyến nào (vd Sân bay Long Thành).
    let routeID: InfraRoute.ID?
    let name: String
    let type: NodeType
    let location: GeoPoint
}
