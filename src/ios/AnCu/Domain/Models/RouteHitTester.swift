import Foundation

/// Chạm vào bản đồ trúng tuyến nào (MapPolyline không tự nhận chạm). Khoảng cách phẳng cục bộ — đủ chính xác ở
/// bán kính vài chục mét quanh ngón tay.
enum RouteHitTester {
    /// Tuyến gần điểm chạm nhất trong `toleranceMeters`; `nil` nếu không trúng tuyến nào.
    static func nearestRoute(to point: GeoPoint, in routes: [InfraRoute], toleranceMeters: Double) -> InfraRoute? {
        routes
            .map { ($0, distanceMeters(from: point, to: $0)) }
            .filter { $0.1 <= toleranceMeters }
            .min { $0.1 < $1.1 }?
            .0
    }

    static func distanceMeters(from point: GeoPoint, to route: InfraRoute) -> Double {
        let metersPerDegreeLat = 110_540.0
        let metersPerDegreeLng = 111_320.0 * cos(point.latitude * .pi / 180)
        func project(_ p: GeoPoint) -> (x: Double, y: Double) {
            ((p.longitude - point.longitude) * metersPerDegreeLng, (p.latitude - point.latitude) * metersPerDegreeLat)
        }
        var best = Double.infinity
        for segment in route.segments where !segment.isEmpty {
            if segment.count == 1 {
                let a = project(segment[0])
                best = min(best, (a.x * a.x + a.y * a.y).squareRoot())
                continue
            }
            for index in segment.indices.dropLast() {
                let a = project(segment[index]), b = project(segment[index + 1])
                let dx = b.x - a.x, dy = b.y - a.y
                let lengthSquared = dx * dx + dy * dy
                let t = lengthSquared == 0 ? 0 : max(0, min(1, -(a.x * dx + a.y * dy) / lengthSquared))
                let cx = a.x + t * dx, cy = a.y + t * dy
                best = min(best, (cx * cx + cy * cy).squareRoot())
            }
        }
        return best
    }
}
