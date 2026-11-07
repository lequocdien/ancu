import Foundation

/// Dời mọi ngày trong mock theo khoảng cách từ `anchor` (ngày soạn dữ liệu) tới hôm nay,
/// để dữ liệu luôn có dự án đang mở / sắp mở / đã đóng dù chạy prototype vào ngày nào.
/// Chỉ dùng cho mock — backend thật trả ngày thật.
struct DateShift: Sendable {
    let days: Int

    static let none = DateShift(days: 0)

    init(days: Int) { self.days = days }

    init(anchor: Date, now: Date, calendar: Calendar = Project.vietnamCalendar) {
        days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: now)
        ).day ?? 0
    }

    func apply(_ date: Date, calendar: Calendar = Project.vietnamCalendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

/// Parse ngày theo giờ Việt Nam. Hàm thuần, ném `RepositoryError.decoding` khi sai định dạng.
enum DTODateParser {
    static func day(_ string: String) throws -> Date {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Project.vietnamCalendar.date(
                  from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
              )
        else { throw RepositoryError.decoding }
        return date
    }

    static func timestamp(_ string: String) throws -> Date {
        guard let date = try? Date(string, strategy: .iso8601) else { throw RepositoryError.decoding }
        return date
    }
}

/// DTO → Domain, dùng chung cho Mock và Supabase. Mọi vi phạm contract → `RepositoryError.decoding`.
enum DTOMapper {
    static func point(_ dto: PointDTO) throws -> GeoPoint {
        guard (-90...90).contains(dto.lat), (-180...180).contains(dto.lng) else { throw RepositoryError.decoding }
        return GeoPoint(latitude: dto.lat, longitude: dto.lng)
    }

    static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http" else {
            throw RepositoryError.decoding
        }
        return url
    }

    static func lookupItem(_ dto: LookupItemDTO) throws -> LookupItem {
        LookupItem(
            code: dto.code,
            label: dto.labelVi,
            sortOrder: dto.sortOrder,
            colorHex: dto.colorHex,
            symbolName: dto.sfSymbol,
            attributes: dto.attributes ?? [:],
            center: try dto.center.map(point)
        )
    }

    static func administrativeUnit(_ dto: AdministrativeUnitDTO) throws -> AdministrativeUnit {
        AdministrativeUnit(
            code: dto.code,
            name: dto.name,
            province: dto.province,
            serviceArea: ServiceArea(code: dto.serviceArea),
            oldNames: dto.oldNames,
            center: try point(dto.center)
        )
    }

    static func project(_ dto: ProjectDTO, shift: DateShift) throws -> Project {
        let window: DateInterval?
        switch (dto.applicationStart, dto.applicationEnd) {
        case let (start?, end?):
            let s = shift.apply(try DTODateParser.day(start))
            let e = shift.apply(try DTODateParser.day(end))
            guard s <= e else { throw RepositoryError.decoding }
            window = DateInterval(start: s, end: e)
        case (nil, nil):
            window = nil
        default:
            throw RepositoryError.decoding   // chỉ có một đầu khung thời gian
        }

        let price: PriceRange?
        switch (dto.priceMin, dto.priceMax) {
        case let (min?, max?):
            guard min > 0, min <= max else { throw RepositoryError.decoding }
            price = PriceRange(min: decimal(min), max: decimal(max), isEstimated: dto.priceIsEstimated ?? true)
        case (nil, nil):
            price = nil
        default:
            throw RepositoryError.decoding
        }

        return Project(
            id: dto.id,
            name: dto.name,
            address: dto.address,
            wardCode: dto.wardCode,
            serviceArea: ServiceArea(code: dto.serviceArea),
            location: try point(dto.location),
            status: ProjectStatus(code: dto.status),
            legalStatus: LegalStatus(code: dto.legalStatus),
            applicationWindow: window,
            price: price,
            unitCount: dto.unitCount,
            developer: dto.developer,
            sourceURL: try url(dto.sourceUrl),
            verifiedAt: shift.apply(try DTODateParser.day(dto.verifiedAt))
        )
    }

    static func route(_ dto: RouteDTO, shift: DateShift) throws -> InfraRoute {
        let segments = try dto.segments.map { try $0.map(point) }
        guard !segments.isEmpty, segments.allSatisfy({ $0.count >= 2 }) else { throw RepositoryError.decoding }
        return InfraRoute(
            id: dto.id,
            name: dto.name,
            type: RouteType(code: dto.type),
            status: RouteStatus(code: dto.status),
            expectedYear: dto.expectedYear,
            colorHex: dto.colorHex,
            segments: segments,
            sourceURL: try url(dto.sourceUrl),
            verifiedAt: shift.apply(try DTODateParser.day(dto.verifiedAt))
        )
    }

    static func node(_ dto: NodeDTO) throws -> InfraNode {
        InfraNode(
            id: dto.id,
            routeID: dto.routeId,
            name: dto.name,
            type: NodeType(code: dto.type),
            location: try point(dto.location)
        )
    }

    static func nearestInfra(_ dto: NearestInfraDTO) throws -> NearestInfra {
        guard dto.distanceMeters >= 0 else { throw RepositoryError.decoding }
        return NearestInfra(
            node: try node(dto.node),
            routeName: dto.routeName,
            routeType: dto.routeType.map(RouteType.init(code:)),
            routeStatus: dto.routeStatus.map(RouteStatus.init(code:)),
            expectedYear: dto.expectedYear,
            distanceMeters: dto.distanceMeters
        )
    }

    static func projectDetail(_ dto: ProjectDetailDTO) throws -> ProjectDetail {
        ProjectDetail(
            project: try project(dto.project, shift: .none),
            nearestInfra: try dto.nearestInfra.map(nearestInfra),
            coverImageURL: dto.coverImageUrl.flatMap(URL.init(string:))
        )
    }

    static func clientConfig(_ dto: ClientConfigDTO) throws -> ClientConfig {
        guard let version = AppVersion(dto.minSupportedVersion) else { throw RepositoryError.decoding }
        return ClientConfig(minSupportedVersion: version, appStoreURL: try dto.appStoreUrl.map(url))
    }

    static func bookmark(_ dto: BookmarkDTO) throws -> Bookmark {
        Bookmark(
            projectID: dto.projectId,
            notifyEnabled: dto.notifyEnabled,
            createdAt: try DTODateParser.timestamp(dto.createdAt),
            isLocalOnly: false
        )
    }

    /// Tên trống (đăng nhập email) → phần trước @ của email, cuối cùng là tên chung.
    static func user(_ dto: ProfileDTO, email: String?) -> AppUser {
        let name = dto.displayName.trimmingCharacters(in: .whitespaces)
        let fallback = email.flatMap { $0.split(separator: "@").first.map(String.init) } ?? String(localized: "Người dùng An Cư")
        return AppUser(
            id: dto.id,
            displayName: name.isEmpty ? fallback : name,
            isPhoneVerified: dto.isPhoneVerified,
            maskedPhone: dto.maskedPhone
        )
    }

    static func boundary(_ dto: ServiceAreaBoundaryDTO) throws -> AreaBoundary {
        let polygons = try dto.polygons.map { try $0.map(point) }
        guard !polygons.isEmpty, polygons.allSatisfy({ $0.count >= 3 }) else { throw RepositoryError.decoding }
        return AreaBoundary(area: ServiceArea(code: dto.code), polygons: polygons, isMock: dto.isMock)
    }

    static func notification(_ dto: NotificationDTO, shift: DateShift) throws -> AppNotification {
        AppNotification(
            id: dto.id,
            type: NotificationType(code: dto.type),
            projectID: dto.projectId,
            title: dto.title,
            body: dto.body,
            createdAt: shift.apply(try DTODateParser.timestamp(dto.createdAt)),
            isRead: dto.isRead
        )
    }

    static func eligibilityRule(_ dto: EligibilityRuleDTO) throws -> EligibilityRule {
        let value: EligibilityRule.Value
        switch dto.valueType {
        case "number":
            guard let number = dto.valueNumber else { throw RepositoryError.decoding }
            value = .number(decimal(number))
        case "text":
            guard let text = dto.valueText else { throw RepositoryError.decoding }
            value = .text(text)
        case "codes":
            guard let codes = dto.valueCodes else { throw RepositoryError.decoding }
            value = .codes(codes)
        default:
            throw RepositoryError.decoding
        }
        return EligibilityRule(
            key: dto.ruleKey,
            value: value,
            legalReference: dto.legalReference,
            effectiveFrom: try DTODateParser.day(dto.effectiveFrom),
            isMock: dto.isMock
        )
    }

    /// Đi qua chuỗi để tránh sai số nhị phân (22.5 → 22.5, không phải 22.499999…).
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }
}
