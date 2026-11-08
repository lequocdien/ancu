import Foundation
import Testing
@testable import AnCu

/// Chạy trên JSON thật trong app bundle (test được host bởi app) — bắt lỗi dữ liệu mock, không chỉ lỗi code.
struct MockRepositoryTests {
    /// Cố định "hôm nay" = ngày anchor để kết quả không đổi theo ngày chạy test.
    private static let fixedNow: @Sendable () -> Date = { MockDataStore.anchorDate.addingTimeInterval(12 * 3600) }

    private func makeContainer() -> AppContainer {
        .mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none, now: Self.fixedNow)
    }

    @Test func datasetLoadsAndIsConsistent() async throws {
        let data = try await MockDataStore(now: Self.fixedNow).dataset()

        #expect(data.projects.count == 15)
        #expect(Set(data.projects.map(\.id)).count == 15)
        // Mọi dự án nằm trong vùng MVP, thuộc vùng phục vụ có in_mvp = true.
        for project in data.projects {
            #expect(MapRegion.mvpArea.contains(project.location), "\(project.name) ngoài vùng MVP")
            #expect(data.catalog.isInMVP(project.serviceArea), "\(project.name) thuộc vùng ngoài MVP")
            #expect(project.status != .unknown && project.legalStatus != .unknown)
        }
        // Đủ 4 trạng thái để UI có gì hiển thị.
        #expect(Set(data.projects.map(\.status)) == [.acceptingApplications, .upcoming, .underConstruction, .closed])

        // Node trỏ tới route có thật.
        let routeIDs = Set(data.routes.map(\.id))
        for node in data.nodes { if let id = node.routeID { #expect(routeIDs.contains(id), "\(node.name)") } }
        #expect(data.routes.allSatisfy { $0.type != .unknown && $0.status != .unknown })

        // Thông báo trỏ tới dự án có thật.
        let projectIDs = Set(data.projects.map(\.id))
        #expect(data.notifications.allSatisfy { projectIDs.contains($0.projectID) })

        // Ward code của dự án có trong danh mục phường/xã.
        let wardCodes = Set(data.administrativeUnits.map(\.code))
        #expect(data.projects.allSatisfy { $0.wardCode.map(wardCodes.contains) ?? true })

        // Mọi danh mục lookup đều có dữ liệu.
        for category in LookupCategory.allCases { #expect(!data.catalog.items(in: category).isEmpty, "\(category)") }
    }

    @Test func ruleValuesAreMarkedMock() async throws {
        let rules = try await makeContainer().eligibility.currentRules()
        let incomeRules = rules.filter { $0.key.hasPrefix("income_") }
        #expect(incomeRules.count == 4)
        #expect(incomeRules.allSatisfy { $0.isMock })
    }

    @Test func projectsFilteredByRegionAndStatus() async throws {
        let repo = makeContainer().projects
        let all = try await repo.projects(in: .mvpArea, filter: .all)
        #expect(all.count == 15)

        let open = try await repo.projects(in: .mvpArea, filter: .acceptingApplications)
        #expect(open.count == 5)
        #expect(open.allSatisfy { $0.status == .acceptingApplications })

        let dongNai = try await repo.projects(in: .mvpArea, filter: ProjectFilter(serviceAreas: [.dongNai]))
        #expect(dongNai.count == 5)

        let hanoi = MapRegion(center: GeoPoint(latitude: 21.03, longitude: 105.85), latitudeDelta: 0.3, longitudeDelta: 0.3)
        #expect(try await repo.projects(in: hanoi, filter: .all).isEmpty)
    }

    @Test func detailHasNearestInfraAndAirportForDongNai() async throws {
        let repo = makeContainer().projects
        let all = try await repo.projects(in: .mvpArea, filter: .all)

        let thuDuc = try #require(all.first { $0.name == "NOXH Hòa Bình Xanh" })
        let thuDucDetail = try await repo.project(id: thuDuc.id)
        let metro = try #require(thuDucDetail.nearestInfra.first { $0.node.type == .metroStation })
        #expect(metro.node.name == "Ga Thủ Đức")
        #expect(metro.distanceMeters < 1_000)
        #expect(metro.routeStatus == .operational)
        #expect(!thuDucDetail.nearestInfra.contains { $0.node.type == .keyLandmark })

        let longThanh = try #require(all.first { $0.name == "Khu nhà ở Long Thành Sky" })
        let longThanhDetail = try await repo.project(id: longThanh.id)
        let airport = try #require(longThanhDetail.nearestInfra.first { $0.node.type == .keyLandmark })
        #expect(airport.routeName == nil)
        #expect(airport.distanceMeters < NearestInfraCalculator.landmarkRadiusMeters)

        await #expect(throws: RepositoryError.notFound) { try await repo.project(id: UUID()) }
    }

    @Test func applicationPhasesAtAnchorDate() async throws {
        let all = try await makeContainer().projects.projects(in: .mvpArea, filter: .all)
        let hoaBinh = try #require(all.first { $0.name == "NOXH Hòa Bình Xanh" })
        #expect(hoaBinh.applicationPhase(at: Self.fixedNow()) == .open(daysLeft: 12))
        let nhaBe = try #require(all.first { $0.name == "Nhà ở xã hội Nhà Bè Riverside" })
        #expect(nhaBe.isStale(at: Self.fixedNow()))
    }

    @Test func searchIgnoresDiacriticsAndOldNames() async throws {
        let repo = makeContainer().projects

        let thuDuc = try await repo.search("thu duc")
        #expect(thuDuc.contains { if case .place(let unit) = $0 { unit.code == "hcm_thu_duc" } else { false } })
        #expect(thuDuc.contains { if case .project(let p) = $0 { p.name == "NOXH Hòa Bình Xanh" } else { false } })

        // Tên cũ "Biên Hòa" → các phường mới ở Đồng Nai.
        let bienHoa = try await repo.search("Biên Hòa")
        #expect(bienHoa.contains { if case .place(let unit) = $0 { unit.code == "dn_tran_bien" } else { false } })

        // "Long Bình" có ở cả TP.HCM và Đồng Nai — phải trả cả hai.
        let longBinh = try await repo.search("long binh")
        let places = longBinh.compactMap { if case .place(let unit) = $0 { unit.serviceArea } else { nil } }
        #expect(Set(places) == [.hcm, .dongNai])

        #expect(try await repo.search("a").isEmpty)
    }

    @Test func routesFilterByType() async throws {
        let repo = makeContainer().infrastructure
        let metro = try await repo.routes(types: [.metro])
        #expect(metro.count == 4)
        #expect(try await repo.routes(types: []).count == 11)
        let metro1 = try #require(metro.first { $0.name.hasPrefix("Metro số 1") })
        #expect(try await repo.nodes(routeID: metro1.id).count == 14)
    }

    @Test func guestBookmarksThenMergeAfterSignIn() async throws {
        let container = makeContainer()
        let projectID = UUID()

        #expect(try await container.bookmarks.toggle(projectID: projectID))
        #expect(try await container.bookmarks.all().first?.isLocalOnly == true)
        await #expect(throws: RepositoryError.unauthorized) {
            try await container.bookmarks.setNotify(true, projectID: projectID)
        }
        await #expect(throws: RepositoryError.unauthorized) { try await container.notifications.inbox() }

        _ = try await container.auth.signIn(with: .apple)
        try await container.bookmarks.mergeGuestBookmarks()
        try await container.bookmarks.setNotify(true, projectID: projectID)
        let merged = try #require(try await container.bookmarks.all().first)
        #expect(!merged.isLocalOnly && merged.notifyEnabled)

        #expect(try await container.bookmarks.toggle(projectID: projectID) == false)
        #expect(try await container.bookmarks.all().isEmpty)
    }

    @Test func bookmarksPersistAcrossContainers() async throws {
        let suite = MockDefaultsSuite(name: "test.\(UUID().uuidString)")
        let id = UUID()
        _ = try await AppContainer.mock(defaultsSuite: suite, latency: .none).bookmarks.toggle(projectID: id)
        let reloaded = try await AppContainer.mock(defaultsSuite: suite, latency: .none).bookmarks.all()
        #expect(reloaded.map(\.projectID) == [id])
    }

    @Test func signOutKeepsOnlyGuestBookmarks() async throws {
        let container = makeContainer()
        let guestID = UUID(), accountID = UUID()
        try await container.bookmarks.toggle(projectID: guestID)
        _ = try await container.auth.signIn(with: .google)
        try await container.bookmarks.toggle(projectID: accountID)

        try await container.auth.signOut()
        #expect(try await container.bookmarks.all().map(\.projectID) == [guestID])
    }

    @Test func deleteAccountClearsEverything() async throws {
        let container = makeContainer()
        _ = try await container.auth.signIn(with: .apple)
        try await container.bookmarks.toggle(projectID: UUID())
        try await container.auth.deleteAccount()
        #expect(await container.auth.currentUser == nil)
        #expect(try await container.bookmarks.all().isEmpty)
    }

    @Test func dataReportValidation() async throws {
        let container = makeContainer()
        await #expect(throws: RepositoryError.unauthorized) {
            try await container.dataReports.reportIncorrectData(projectID: UUID(), note: "Sai giá")
        }
        _ = try await container.auth.signIn(with: .apple)
        await #expect(throws: RepositoryError.decoding) {
            try await container.dataReports.reportIncorrectData(projectID: UUID(), note: "   ")
        }
        try await container.dataReports.reportIncorrectData(projectID: UUID(), note: "Sai giá")
    }

    @Test func notificationsMarkAsRead() async throws {
        let container = makeContainer()
        _ = try await container.auth.signIn(with: .apple)
        let inbox = try await container.notifications.inbox()
        #expect(inbox.count == 8)
        #expect(inbox == inbox.sorted { $0.createdAt > $1.createdAt })
        let unread = try #require(inbox.first { !$0.isRead })
        try await container.notifications.markAsRead(id: unread.id)
        #expect(try await container.notifications.inbox().first { $0.id == unread.id }?.isRead == true)
    }
}
