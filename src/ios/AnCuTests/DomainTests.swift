import Foundation
import Testing
@testable import AnCu

struct ProjectPhaseTests {
    private let calendar = Project.vietnamCalendar

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func project(window: DateInterval?, verifiedAt: Date = .now) -> Project {
        Project(
            id: UUID(), name: "Test", address: "", wardCode: nil, serviceArea: .hcm,
            location: GeoPoint(latitude: 10.8, longitude: 106.7), status: .acceptingApplications,
            legalStatus: .eligibleForSale, applicationWindow: window, price: nil, unitCount: nil,
            developer: nil, sourceURL: URL(string: "https://example.com")!, verifiedAt: verifiedAt
        )
    }

    @Test func noWindowIsNotAnnounced() {
        #expect(project(window: nil).applicationPhase(at: date(2026, 11, 6)) == .notAnnounced)
    }

    @Test func beforeStartIsUpcoming() {
        let p = project(window: DateInterval(start: date(2026, 11, 25), end: date(2026, 12, 10)))
        #expect(p.applicationPhase(at: date(2026, 11, 6)) == .upcoming(daysUntilStart: 19))
    }

    @Test func insideWindowCountsDaysLeft() {
        let p = project(window: DateInterval(start: date(2026, 11, 1), end: date(2026, 11, 18)))
        #expect(p.applicationPhase(at: date(2026, 11, 6)) == .open(daysLeft: 12))
    }

    @Test func lastDayIsStillOpen() {
        let p = project(window: DateInterval(start: date(2026, 11, 1), end: date(2026, 11, 18, hour: 0)))
        #expect(p.applicationPhase(at: date(2026, 11, 18, hour: 23)) == .open(daysLeft: 0))
    }

    @Test func afterEndIsEnded() {
        let p = project(window: DateInterval(start: date(2026, 10, 1), end: date(2026, 10, 15)))
        #expect(p.applicationPhase(at: date(2026, 11, 6)) == .ended)
    }

    @Test func staleAfter30Days() {
        let now = date(2026, 11, 6)
        #expect(project(window: nil, verifiedAt: date(2026, 10, 1)).isStale(at: now))
        #expect(!project(window: nil, verifiedAt: date(2026, 10, 20)).isStale(at: now))
    }
}

struct GeoTests {
    @Test func regionContainsPoint() {
        let region = MapRegion.mvpArea
        #expect(region.contains(GeoPoint(latitude: 10.85, longitude: 106.77)))   // Thủ Đức
        #expect(!region.contains(GeoPoint(latitude: 21.03, longitude: 105.85)))  // Hà Nội
    }

    @Test func straightLineDistance() {
        let benThanh = GeoPoint(latitude: 10.7721, longitude: 106.6983)
        let suoiTien = GeoPoint(latitude: 10.8794, longitude: 106.8139)
        let km = benThanh.distance(to: suoiTien) / 1000
        #expect((15...18).contains(km))
    }
}

struct LookupTests {
    private let catalog = LookupCatalog(items: [
        .projectStatus: [
            LookupItem(code: "da_dong", label: "Đã đóng", sortOrder: 3),
            LookupItem(code: "nhan_ho_so", label: "Đang nhận hồ sơ", sortOrder: 1, colorHex: "#10B981"),
            LookupItem(code: "sap_mo", label: "Sắp mở", sortOrder: 2),
            LookupItem(code: "trang_thai_moi", label: "Trạng thái mới", sortOrder: 4),
        ],
        .serviceArea: [
            LookupItem(code: "tp_hcm", label: "TP.HCM", sortOrder: 1, attributes: ["in_mvp": "true"]),
            LookupItem(code: "ha_noi", label: "Hà Nội", sortOrder: 6, attributes: ["in_mvp": "false"]),
        ],
    ])

    @Test func unknownCodeMapsToUnknown() {
        #expect(ProjectStatus(code: "trang_thai_moi") == .unknown)
        #expect(ProjectStatus(code: "nhan_ho_so") == .acceptingApplications)
    }

    @Test func labelFallsBackToCode() {
        #expect(catalog.label(for: ProjectStatus.acceptingApplications) == "Đang nhận hồ sơ")
        #expect(catalog.label(for: ProjectStatus.underConstruction) == "dang_xay")
    }

    @Test func orderedCasesFollowSortOrderAndSkipUnknown() {
        #expect(catalog.orderedCases(ProjectStatus.self) == [.acceptingApplications, .upcoming, .closed])
    }

    @Test func mvpFlag() {
        #expect(catalog.isInMVP(.hcm))
        #expect(!catalog.isInMVP(.haNoi))
        #expect(!catalog.isInMVP(.dongNai))  // thiếu trong catalog → coi như ngoài MVP
    }

    @Test func filterMatches() {
        let filter = ProjectFilter(statuses: [.acceptingApplications], serviceAreas: [.dongNai])
        let base = Project(
            id: UUID(), name: "", address: "", wardCode: nil, serviceArea: .dongNai,
            location: GeoPoint(latitude: 10.9, longitude: 106.9), status: .acceptingApplications,
            legalStatus: .unknown, applicationWindow: nil, price: nil, unitCount: nil, developer: nil,
            sourceURL: URL(string: "https://example.com")!, verifiedAt: .now
        )
        #expect(filter.matches(base))
        #expect(ProjectFilter.all.matches(base))
        #expect(!ProjectFilter(serviceAreas: [.hcm]).matches(base))
    }
}

/// Phase 1 bước 0.4: camera không bao giờ đưa được Hoàng Sa / Trường Sa vào giữa màn hình.
struct MapBoundsTests {
    @Test func allowedAreaCoversMVPAndAllMockProjects() async throws {
        let area = MapRegion.allowedArea
        let mvp = MapRegion.mvpArea
        for corner in [GeoPoint(latitude: mvp.minLatitude, longitude: mvp.minLongitude),
                       GeoPoint(latitude: mvp.maxLatitude, longitude: mvp.maxLongitude)] {
            #expect(area.contains(corner))
        }
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let all = MapRegion(center: GeoPoint(latitude: 16, longitude: 106), latitudeDelta: 20, longitudeDelta: 20)
        let projects = try await container.projects.projects(in: all, filter: .all)
        #expect(!projects.isEmpty)
        #expect(projects.allSatisfy { area.contains($0.location) })
    }

    @Test(arguments: [
        GeoPoint(latitude: 16.5, longitude: 112.0),   // Hoàng Sa
        GeoPoint(latitude: 10.0, longitude: 114.0),   // Trường Sa
        GeoPoint(latitude: 8.6, longitude: 111.9),    // Trường Sa (đảo Trường Sa)
    ])
    func archipelagosAreFarOutsideReach(_ point: GeoPoint) {
        let area = MapRegion.allowedArea
        #expect(!area.contains(point))
        // Ở khoảng cách tối đa, nửa đường chéo khung nhìn < khoảng cách từ mép khung tâm tới quần đảo.
        let nearestCenter = GeoPoint(
            latitude: min(max(point.latitude, area.minLatitude), area.maxLatitude),
            longitude: min(max(point.longitude, area.minLongitude), area.maxLongitude)
        )
        #expect(nearestCenter.distance(to: point) > MapRegion.maxCameraDistance * MapRegion.visibleHalfDiagonalRatio)
    }
}
