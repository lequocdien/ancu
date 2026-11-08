import Foundation

/// Điểm thuộc vùng MVP nào — cùng quy tắc với `mvp_service_area_at` ở server (migration 13):
/// nằm trong ranh giới, hoặc cách ranh giới ≤ `toleranceMeters` (ranh giới đang là mock giản lược).
/// App dùng để làm mờ kết quả / báo sớm; server vẫn là chốt chặn.
enum ServiceAreaLocator {
    static let toleranceMeters: Double = 3000

    /// Nhiều vùng thỏa → vùng gần nhất (điểm nằm trong vùng có khoảng cách 0).
    static func area(at point: GeoPoint, in boundaries: [AreaBoundary], toleranceMeters: Double = toleranceMeters) -> ServiceArea? {
        boundaries
            .compactMap { boundary -> (ServiceArea, Double)? in
                let distance = boundary.polygons.map { distanceMeters(from: point, to: $0) }.min() ?? .infinity
                return distance <= toleranceMeters ? (boundary.area, distance) : nil
            }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rawValue < $1.0.rawValue }?
            .0
    }

    /// 0 nếu điểm nằm trong đa giác; ngược lại khoảng cách tới cạnh gần nhất (mét, phép chiếu phẳng cục bộ —
    /// sai số không đáng kể ở quy mô vài km).
    static func distanceMeters(from point: GeoPoint, to ring: [GeoPoint]) -> Double {
        guard ring.count >= 3 else { return .infinity }
        if contains(ring, point) { return 0 }
        let metersPerDegreeLat = 110_540.0
        let metersPerDegreeLng = 111_320.0 * cos(point.latitude * .pi / 180)
        func project(_ p: GeoPoint) -> (x: Double, y: Double) {
            ((p.longitude - point.longitude) * metersPerDegreeLng, (p.latitude - point.latitude) * metersPerDegreeLat)
        }
        var best = Double.infinity
        for index in ring.indices {
            let a = project(ring[index])
            let b = project(ring[(index + 1) % ring.count])
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : max(0, min(1, -(a.x * dx + a.y * dy) / lengthSquared))
            let cx = a.x + t * dx, cy = a.y + t * dy
            best = min(best, (cx * cx + cy * cy).squareRoot())
        }
        return best
    }

    /// Ray casting; vòng không cần lặp điểm đầu ở cuối.
    static func contains(_ ring: [GeoPoint], _ point: GeoPoint) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let pi = ring[i], pj = ring[j]
            if (pi.latitude > point.latitude) != (pj.latitude > point.latitude),
               point.longitude < (pj.longitude - pi.longitude) * (point.latitude - pi.latitude) / (pj.latitude - pi.latitude) + pi.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
