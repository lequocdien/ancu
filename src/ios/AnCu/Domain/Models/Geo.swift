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

    /// Khung TÂM camera được phép (Phase 1 bước 0.4, architecture.md mục 3) — 5 tỉnh mới (2026-11-08):
    /// vĩ 10,0–12,6 · kinh 105,3–108,5 (Đồng Tháp → Lâm Đồng). Mép đông DỪNG ở 108,5 dù Bình Thuận cũ ra tới ~108,95:
    /// góc gần Trường Sa nhất (10,0°B 108,5°Đ) cách đảo Trường Sa (8,6°B 111,9°Đ) ~404 km > nửa đường chéo khung nhìn
    /// ở zoom tối đa (750 km × 0,5 = 375 km) → không kéo/zoom ra được Biển Đông. Côn Đảo nằm ngoài (không có dự án).
    static let allowedArea = MapRegion(
        center: GeoPoint(latitude: 11.3, longitude: 106.9),
        latitudeDelta: 2.6,
        longitudeDelta: 3.2
    )

    /// Khoảng cách camera tối đa (mét). 600 km ≈ 180 km ngang × 230 km dọc — không ôm nổi Lâm Đồng mới (~250 km cao)
    /// → 750 km. Giới hạn trên do test chủ quyền (`MapBoundsTests`) quyết định cùng `allowedArea`.
    static let maxCameraDistance: Double = 750_000
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

    /// Khung mặc định ("Xem toàn vùng", mở app): lõi TP.HCM mới + Biên Hòa — nơi tập trung dự án. 5 tỉnh không vừa
    /// một màn hình ở zoom tối đa → chọn tỉnh bằng chip.
    static let mvpArea = MapRegion(
        center: GeoPoint(latitude: 10.9, longitude: 106.8),
        latitudeDelta: 0.9,
        longitudeDelta: 0.9
    )
}
