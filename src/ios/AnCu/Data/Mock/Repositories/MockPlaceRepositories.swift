import Foundation

// MARK: - Saved places

/// Địa điểm riêng lưu trong UserDefaults (theo suite) — hành xử như RPC thật: cần đăng nhập, chỉ vùng MVP
/// (cùng quy tắc `ServiceAreaLocator`), tối đa 200, mới sửa lên trên.
actor MockSavedPlaceRepository: SavedPlaceRepository {
    private struct Record: Codable {
        let id: UUID
        var name: String
        let address: String?
        let latitude: Double
        let longitude: Double
        var kind: String
        var icon: String?
        let serviceArea: String
        var note: String?
        let externalRef: String?
        let createdAt: Date
        var updatedAt: Date

        var place: SavedPlace {
            SavedPlace(
                id: id, name: name, address: address, location: GeoPoint(latitude: latitude, longitude: longitude),
                kind: PlaceKind(code: kind), icon: icon, serviceArea: ServiceArea(code: serviceArea), note: note,
                externalRef: externalRef, createdAt: createdAt, updatedAt: updatedAt
            )
        }
    }

    private let suite: MockDefaultsSuite
    private let store: MockDataStore
    private let auth: any AuthService
    private let latency: MockLatency
    private let now: @Sendable () -> Date

    init(
        suite: MockDefaultsSuite, store: MockDataStore, auth: any AuthService, latency: MockLatency,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.suite = suite
        self.store = store
        self.auth = auth
        self.latency = latency
        self.now = now
    }

    private func load() -> [Record] {
        guard let data = suite.open().data(forKey: MockStorageKeys.savedPlaces),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records
    }

    private func save(_ records: [Record]) throws {
        do {
            suite.open().set(try JSONEncoder().encode(records), forKey: MockStorageKeys.savedPlaces)
        } catch {
            throw RepositoryError.decoding
        }
    }

    private func requireSignIn() async throws {
        guard await auth.currentUser != nil else { throw RepositoryError.unauthorized }
    }

    func all() async throws -> [SavedPlace] {
        try await requireSignIn()
        try await latency.wait()
        return load().map(\.place).sorted { $0.updatedAt > $1.updatedAt }
    }

    func create(_ draft: SavedPlaceDraft) async throws -> SavedPlace {
        try await requireSignIn()
        let validated = try SavedPlaceValidation.validate(name: draft.name, kind: draft.kind, note: draft.note)
        try await latency.wait()
        let dataset = try await store.dataset()
        try Self.validateIcon(draft.icon, in: dataset.catalog)
        let mvpBoundaries = dataset.boundaries.filter { dataset.catalog.isInMVP($0.area) }
        guard let area = ServiceAreaLocator.area(at: draft.location, in: mvpBoundaries) else {
            throw RepositoryError.outsideServiceArea
        }
        var records = load()
        guard records.count < SavedPlace.maxCount else { throw RepositoryError.limitReached }
        let timestamp = now()
        let record = Record(
            id: UUID(), name: validated.name,
            address: UserText.cleaned(draft.address).map { String($0.prefix(SavedPlace.maxAddressLength)) },
            latitude: draft.location.latitude, longitude: draft.location.longitude, kind: draft.kind.rawValue,
            icon: draft.icon, serviceArea: area.rawValue, note: validated.note, externalRef: draft.externalRef,
            createdAt: timestamp, updatedAt: timestamp
        )
        records.append(record)
        try save(records)
        return record.place
    }

    func update(id: SavedPlace.ID, name: String, kind: PlaceKind, icon: String?, note: String?) async throws -> SavedPlace {
        try await requireSignIn()
        let validated = try SavedPlaceValidation.validate(name: name, kind: kind, note: note)
        try Self.validateIcon(icon, in: try await store.dataset().catalog)
        try await latency.wait()
        var records = load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw RepositoryError.notFound }
        records[index].name = validated.name
        records[index].kind = kind.rawValue
        records[index].icon = icon
        records[index].note = validated.note
        records[index].updatedAt = now()
        try save(records)
        return records[index].place
    }

    /// Như server: chỉ nhận mã có trong danh mục `place_icons`.
    private static func validateIcon(_ icon: String?, in catalog: LookupCatalog) throws {
        guard let icon else { return }
        guard catalog.placeIconSymbol(icon) != nil else { throw RepositoryError.decoding }
    }

    func delete(id: SavedPlace.ID) async throws {
        try await requireSignIn()
        try await latency.wait()
        try save(load().filter { $0.id != id })
    }
}

// MARK: - Place search

/// Kết quả tìm kiếm cố định thay cho Apple Maps (Preview, test, Simulator không mạng).
/// Có cả địa điểm ngoài vùng MVP để thử nhãn "Ngoài khu vực hỗ trợ".
struct MockPlaceSearchService: PlaceSearchService {
    static let fixtures: [PlaceCandidate] = [
        PlaceCandidate(id: "mock-vgp", name: "Vinhomes Grand Park", address: "Long Bình, Thủ Đức, TP.HCM",
                       location: GeoPoint(latitude: 10.8423, longitude: 106.8287), externalRef: "mock-vgp"),
        PlaceCandidate(id: "mock-masteri", name: "Masteri Thảo Điền", address: "159 Xa lộ Hà Nội, Thảo Điền, TP.HCM",
                       location: GeoPoint(latitude: 10.8027, longitude: 106.7400), externalRef: "mock-masteri"),
        PlaceCandidate(id: "mock-picity", name: "Picity High Park", address: "Thạnh Xuân, Quận 12, TP.HCM",
                       location: GeoPoint(latitude: 10.8770, longitude: 106.6720), externalRef: "mock-picity"),
        PlaceCandidate(id: "mock-hbx", name: "Hòa Bình Xanh (gần dự án NOXH có sẵn)", address: "Thủ Đức, TP.HCM",
                       location: GeoPoint(latitude: 10.8425, longitude: 106.7725), externalRef: "mock-hbx"),
        PlaceCandidate(id: "mock-vungtau", name: "Vung Tau Pearl", address: "Thắng Tam, Vũng Tàu",
                       location: GeoPoint(latitude: 10.3460, longitude: 107.0843), externalRef: "mock-vungtau"),
        PlaceCandidate(id: "mock-hanoi", name: "Vinhomes Smart City", address: "Tây Mỗ, Nam Từ Liêm, Hà Nội",
                       location: GeoPoint(latitude: 21.0040, longitude: 105.7470), externalRef: "mock-hanoi"),
    ]

    let latency: MockLatency

    func search(_ query: String, near region: MapRegion) async throws -> [PlaceCandidate] {
        try await latency.wait()
        let needle = SearchNormalizer.normalize(query)
        guard needle.count >= 2 else { return [] }
        // "vinhomes" → mọi dự án Vinhomes; ngoài ra khớp chuỗi con trên tên/địa chỉ.
        return Self.fixtures.filter {
            SearchNormalizer.normalize($0.name + " " + ($0.address ?? "")).contains(needle)
        }
    }
}

/// Mặc định của `SessionStore` khi không truyền repository (test cũ): không có địa điểm, mọi thao tác ghi bị từ chối.
struct UnavailableSavedPlaceRepository: SavedPlaceRepository {
    func all() async throws -> [SavedPlace] { [] }
    func create(_ draft: SavedPlaceDraft) async throws -> SavedPlace { throw RepositoryError.unauthorized }
    func update(id: SavedPlace.ID, name: String, kind: PlaceKind, icon: String?, note: String?) async throws -> SavedPlace {
        throw RepositoryError.unauthorized
    }
    func delete(id: SavedPlace.ID) async throws { throw RepositoryError.unauthorized }
}

/// Địa chỉ giả, ổn định theo tọa độ (test/Preview). Gần một kết quả mẫu (≤ 150 m) → địa chỉ của kết quả đó.
struct MockReverseGeocoder: ReverseGeocoder {
    let latency: MockLatency

    func address(at point: GeoPoint) async throws -> String? {
        try await latency.wait()
        if let near = MockPlaceSearchService.fixtures.first(where: { $0.location.distance(to: point) <= 150 }) {
            return near.address
        }
        return String(format: "Gần %.4f, %.4f", point.latitude, point.longitude)
    }
}
