import CoreLocation
import MapKit

/// Địa chỉ tại điểm ghim (framework hệ thống, không thêm dependency). Tọa độ là điểm người dùng tự chọn,
/// không phải GPS của máy (compliance.md 2.1).
struct MapKitReverseGeocoder: ReverseGeocoder {
    private static let vietnamese = Locale(identifier: "vi_VN")

    func address(at point: GeoPoint) async throws -> String? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            // Địa chỉ VN luôn có dấu, kể cả khi máy để tiếng Anh ("Thống Nhất" thay vì "Thong Nhat").
            request.preferredLocale = Self.vietnamese
            do {
                let item = try await request.mapItems.first
                return UserText.cleaned(item?.address?.shortAddress ?? item?.address?.fullAddress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw RepositoryError.network
            }
        } else {
            do {
                let placemark = try await CLGeocoder()
                    .reverseGeocodeLocation(location, preferredLocale: Self.vietnamese)
                    .first
                return placemark.flatMap(Self.format)
            } catch {
                throw RepositoryError.network
            }
        }
    }

    /// "12 Đường D2, Phường X, TP Hồ Chí Minh" — bỏ phần trống/lặp.
    private static func format(_ placemark: CLPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        var parts: [String] = []
        for part in [street, placemark.subLocality, placemark.locality, placemark.administrativeArea] {
            guard let cleaned = UserText.cleaned(part), !parts.contains(cleaned) else { continue }
            parts.append(cleaned)
        }
        return parts.isEmpty ? UserText.cleaned(placemark.name) : parts.joined(separator: ", ")
    }
}
