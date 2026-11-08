import MapKit

/// Tìm địa điểm ngoài hệ thống bằng Apple Maps (`MKLocalSearch`, framework hệ thống — không thêm dependency).
/// Không dùng Google Places: điều khoản cấm lưu kết quả và hiển thị trên bản đồ không phải Google (architecture.md 5.6).
/// Lưu ý: dữ liệu điểm của Apple Maps ở VN còn thiếu nhiều dự án mới → UI luôn có đường lui "ghim tay".
struct MapKitPlaceSearchService: PlaceSearchService {
    static let maxResults = 10

    func search(_ query: String, near region: MapRegion) async throws -> [PlaceCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(region)
        request.resultTypes = [.pointOfInterest, .address]

        let items: [MKMapItem]
        do {
            items = try await MKLocalSearch(request: request).start().mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RepositoryError.network
        }
        return items.prefix(Self.maxResults).compactMap(Self.candidate)
    }

    private static func candidate(from item: MKMapItem) -> PlaceCandidate? {
        let coordinate: CLLocationCoordinate2D
        let address: String?
        if #available(iOS 26.0, *) {
            coordinate = item.location.coordinate
            address = item.address?.shortAddress ?? item.address?.fullAddress
        } else {
            coordinate = item.placemark.coordinate
            address = item.placemark.title
        }
        guard CLLocationCoordinate2DIsValid(coordinate), let name = UserText.cleaned(item.name) else { return nil }
        var externalRef: String?
        if #available(iOS 18.0, *) { externalRef = item.identifier?.rawValue }
        let id = externalRef ?? "\(name)|\(coordinate.latitude),\(coordinate.longitude)"
        return PlaceCandidate(
            id: id,
            name: name,
            address: UserText.cleaned(address).flatMap { $0 == name ? nil : $0 },
            location: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            externalRef: externalRef
        )
    }
}
