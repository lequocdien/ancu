import Foundation

/// Ranh giới một vùng phục vụ — highlight khi chọn vùng trên bản đồ (RPC `service_area_boundary`).
/// `polygons`: các vòng ngoài (không lặp điểm đóng); chưa hỗ trợ lỗ.
struct AreaBoundary: Hashable, Sendable {
    let area: ServiceArea
    let polygons: [[GeoPoint]]
    /// Đa giác giản lược để minh họa, không dùng xác định địa giới.
    let isMock: Bool

    /// Khung camera: nới 30% vì thanh tìm kiếm + chip + tab bar che mép trên/dưới bản đồ.
    var region: MapRegion? { MapRegion.bounding(polygons.flatMap { $0 }, padding: 0.3) }
}
