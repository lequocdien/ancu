import Foundation

/// Toàn bộ dữ liệu mock đã map sang Domain.
struct MockDataset: Sendable {
    let catalog: LookupCatalog
    let administrativeUnits: [AdministrativeUnit]
    let projects: [Project]
    let coverImages: [Project.ID: URL]
    let routes: [InfraRoute]
    let nodes: [InfraNode]
    let notifications: [AppNotification]
    let eligibilityRules: [EligibilityRule]
    let boundaries: [AreaBoundary]
}

/// Độ trễ giả lập để UI có loading/skeleton state. Test dùng `.none`.
/// Lưu ý: khi Task bị hủy, `wait()` ném `CancellationError` (không phải `RepositoryError`) — ViewModel bỏ qua lỗi này.
struct MockLatency: Sendable {
    let duration: Duration

    static let none = MockLatency(duration: .zero)
    static let standard = MockLatency(duration: .milliseconds(300))

    func wait() async throws {
        if duration > .zero { try await Task.sleep(for: duration) }
    }
}

/// Đọc JSON trong bundle một lần rồi cache. Mọi lỗi (thiếu file, sai JSON, sai contract) → `RepositoryError.decoding`.
actor MockDataStore {
    /// Ngày soạn mock data. Mọi ngày trong JSON được dời theo khoảng cách tới hôm nay (xem `DateShift`).
    static let anchorDate: Date = Project.vietnamCalendar.date(from: DateComponents(year: 2026, month: 11, day: 6))!

    private let bundle: Bundle
    private let now: @Sendable () -> Date
    private var cached: MockDataset?

    init(bundle: Bundle = .main, now: @escaping @Sendable () -> Date = { .now }) {
        self.bundle = bundle
        self.now = now
    }

    func dataset() throws -> MockDataset {
        if let cached { return cached }
        let loaded = try load()
        cached = loaded
        return loaded
    }

    private func load() throws -> MockDataset {
        let shift = DateShift(anchor: Self.anchorDate, now: now())

        var lookupItems: [LookupCategory: [LookupItem]] = [:]
        for category in LookupCategory.allCases {
            let dtos: [LookupItemDTO] = try decode(category.rawValue)
            lookupItems[category] = try dtos.map(DTOMapper.lookupItem)
        }

        let projectDTOs: [ProjectDTO] = try decode("projects")
        let coverImages = Dictionary(
            projectDTOs.compactMap { dto in dto.coverImageUrl.flatMap(URL.init(string:)).map { (dto.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        return MockDataset(
            catalog: LookupCatalog(items: lookupItems),
            administrativeUnits: try (decode("administrative_units") as [AdministrativeUnitDTO]).map(DTOMapper.administrativeUnit),
            projects: try projectDTOs.map { try DTOMapper.project($0, shift: shift) },
            coverImages: coverImages,
            routes: try (decode("routes") as [RouteDTO]).map { try DTOMapper.route($0, shift: shift) },
            nodes: try (decode("nodes") as [NodeDTO]).map(DTOMapper.node),
            notifications: try (decode("notifications") as [NotificationDTO]).map { try DTOMapper.notification($0, shift: shift) },
            eligibilityRules: try (decode("eligibility_rules") as [EligibilityRuleDTO]).map(DTOMapper.eligibilityRule),
            boundaries: try (decode("service_area_boundaries") as [ServiceAreaBoundaryDTO]).map(DTOMapper.boundary)
        )
    }

    private func decode<T: Decodable>(_ name: String) throws -> T {
        // Synchronized folder copy resource phẳng vào bundle; vẫn thử thư mục con phòng khi đổi sang folder reference.
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Lookup")
        else { throw RepositoryError.decoding }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw RepositoryError.decoding
        }
    }
}
