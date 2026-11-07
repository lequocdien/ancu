import CoreLocation

/// Tọa độ WGS84 thuần Swift: Hashable/Codable được, không phụ thuộc kiểu của backend (GeoJSON, WKB…).
/// Dùng thay cho `CLLocationCoordinate2D` trong Domain vì kiểu đó không Hashable.
struct GeoPoint: Hashable, Sendable, Codable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Khoảng cách đường chim bay (mét). MVP chỉ dùng loại này — UI phải ghi rõ "Đường chim bay".
    func distance(to other: GeoPoint) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// Khung nhìn bản đồ. Repository nhận tham số này để chỉ tải dữ liệu trong bbox (architecture.md mục 5.2).
struct MapRegion: Hashable, Sendable {
    let center: GeoPoint
    let latitudeDelta: Double
    let longitudeDelta: Double

    var minLatitude: Double { center.latitude - latitudeDelta / 2 }
    var maxLatitude: Double { center.latitude + latitudeDelta / 2 }
    var minLongitude: Double { center.longitude - longitudeDelta / 2 }
    var maxLongitude: Double { center.longitude + longitudeDelta / 2 }

    func contains(_ point: GeoPoint) -> Bool {
        (minLatitude...maxLatitude).contains(point.latitude)
            && (minLongitude...maxLongitude).contains(point.longitude)
    }

    /// Khung TÂM camera được phép (Phase 1 bước 0.4, architecture.md mục 3): phủ vùng MVP + biên ~0,5°,
    /// kết hợp `maxCameraDistance` để không kéo/zoom ra Biển Đông (Hoàng Sa ~16°B 112°Đ, Trường Sa từ ~111,5°Đ).
    /// Thêm Hà Nội → nới khung này (hoặc đổi thành danh sách khung theo vùng).
    static let allowedArea = MapRegion(
        center: GeoPoint(latitude: 11.05, longitude: 106.95),
        latitudeDelta: 1.5,
        longitudeDelta: 1.5
    )

    /// Khoảng cách camera tối đa (mét). Đo trên iPhone dọc: 250 km chỉ thấy ~75 km bề ngang → không ôm nổi
    /// một tỉnh (TP.HCM cũ ~0,9° kể cả lề). 600 km ≈ 180 km ngang × 230 km dọc, vẫn cách Trường Sa gần nhất ~490 km.
    static let maxCameraDistance: Double = 600_000
    /// Tỉ lệ nửa đường chéo khung nhìn / khoảng cách camera (đo ~0,24; lấy dư 0,5 cho máy màn lớn / iPad).
    static let visibleHalfDiagonalRatio: Double = 0.5
    static let minCameraDistance: Double = 300

    /// Khung bao nhỏ nhất chứa mọi điểm, nới thêm `padding` (tỉ lệ) để viền không dính mép màn hình.
    static func bounding(_ points: [GeoPoint], padding: Double = 0.1) -> MapRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLng = first.longitude, maxLng = first.longitude
        for point in points.dropFirst() {
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLng = min(minLng, point.longitude); maxLng = max(maxLng, point.longitude)
        }
        return MapRegion(
            center: GeoPoint(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            latitudeDelta: max(maxLat - minLat, 0.01) * (1 + padding),
            longitudeDelta: max(maxLng - minLng, 0.01) * (1 + padding)
        )
    }

    /// Vùng MVP: TP.HCM cũ – Bình Dương cũ – Đồng Nai cũ.
    static let mvpArea = MapRegion(
        center: GeoPoint(latitude: 10.88, longitude: 106.80),
        latitudeDelta: 0.6,
        longitudeDelta: 0.6
    )
}
