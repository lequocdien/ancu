import Foundation

/// Ranh giới một vùng phục vụ — highlight khi chọn vùng trên bản đồ (RPC `service_area_boundary`).
/// `polygons`: các vòng ngoài (không lặp điểm đóng); chưa hỗ trợ lỗ.
struct AreaBoundary: Hashable, Sendable {
    let area: ServiceArea
    let polygons: [[GeoPoint]]
    /// Đa giác giản lược để minh họa, không dùng xác định địa giới.
    let isMock: Bool

    /// Khung camera: ôm phần CHÍNH (đa giác lớn nhất), nới 30% vì thanh tìm kiếm + chip + tab bar che mép trên/dưới.
    /// Bỏ đảo xa: TP.HCM mới gồm Côn Đảo (~8,7°B) — ôm cả đảo thì camera phải lùi rất xa, vượt `maxCameraDistance`
    /// và khung tâm cho phép (test chủ quyền). Đường viền vẫn vẽ đủ mọi đa giác.
    var region: MapRegion? {
        guard let main = polygons.max(by: { Self.planarArea($0) < Self.planarArea($1) }) else { return nil }
        return MapRegion.bounding(main, padding: 0.3)
    }

    /// Diện tích phẳng theo độ² (shoelace) — chỉ để so sánh lớn/nhỏ giữa các đa giác cùng vùng.
    static func planarArea(_ ring: [GeoPoint]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var sum = 0.0
        for (a, b) in zip(ring, ring.dropFirst() + [ring[0]]) {
            sum += a.longitude * b.latitude - b.longitude * a.latitude
        }
        return abs(sum) / 2
    }
}
