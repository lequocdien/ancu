import Foundation

/// Khoảng giá tham khảo, đơn vị triệu VND/m².
struct PriceRange: Hashable, Sendable {
    let min: Decimal
    let max: Decimal
    /// `true` khi chưa có quyết định phê duyệt giá → UI ghi "Giá dự kiến" (data-strategy.md).
    let isEstimated: Bool
}

struct Project: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let wardCode: String?
    let serviceArea: ServiceArea
    let location: GeoPoint
    let status: ProjectStatus
    let legalStatus: LegalStatus
    let applicationWindow: DateInterval?
    let price: PriceRange?
    let unitCount: Int?
    let developer: String?
    let sourceURL: URL
    let verifiedAt: Date
}

/// Giai đoạn nhận hồ sơ tính theo ngày hiện tại — dùng cho badge "Còn N ngày", sắp xếp tab Theo dõi.
enum ApplicationPhase: Hashable, Sendable {
    case notAnnounced
    case upcoming(daysUntilStart: Int)
    case open(daysLeft: Int)
    case ended
}

extension Project {
    /// Lịch tính ngày theo giờ Việt Nam, để hạn nộp không lệch ngày khi máy để múi giờ khác.
    static let vietnamCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        return calendar
    }()

    func applicationPhase(at now: Date, calendar: Calendar = Project.vietnamCalendar) -> ApplicationPhase {
        guard let window = applicationWindow else { return .notAnnounced }
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: window.start)
        let end = calendar.startOfDay(for: window.end)

        if today < start {
            let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
            return .upcoming(daysUntilStart: days)
        }
        if today <= end {
            let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
            return .open(daysLeft: days)
        }
        return .ended
    }

    /// Quá 30 ngày chưa đối chiếu → UI hiện "Thông tin có thể đã cũ" (data-strategy.md mục 2).
    func isStale(at now: Date, maxAgeDays: Int = 30, calendar: Calendar = Project.vietnamCalendar) -> Bool {
        guard let limit = calendar.date(byAdding: .day, value: -maxAgeDays, to: now) else { return false }
        return verifiedAt < limit
    }
}

/// Ga / nút giao / điểm hạ tầng lớn gần nhất của một dự án. MVP: khoảng cách đường chim bay.
struct NearestInfra: Hashable, Sendable {
    let node: InfraNode
    /// `nil` khi node không thuộc tuyến nào (vd Sân bay Long Thành).
    let routeName: String?
    let routeType: RouteType?
    let routeStatus: RouteStatus?
    let expectedYear: Int?
    let distanceMeters: Double
}

struct ProjectDetail: Hashable, Sendable {
    let project: Project
    let nearestInfra: [NearestInfra]
    let coverImageURL: URL?
}

struct ProjectFilter: Hashable, Sendable {
    /// Rỗng = mọi trạng thái.
    var statuses: Set<ProjectStatus> = []
    /// Rỗng = mọi vùng phục vụ.
    var serviceAreas: Set<ServiceArea> = []

    static let all = ProjectFilter()
    static let acceptingApplications = ProjectFilter(statuses: [.acceptingApplications])

    func matches(_ project: Project) -> Bool {
        (statuses.isEmpty || statuses.contains(project.status))
            && (serviceAreas.isEmpty || serviceAreas.contains(project.serviceArea))
    }
}
