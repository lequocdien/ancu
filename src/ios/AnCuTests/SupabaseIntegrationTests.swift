import Foundation
import Supabase
import Testing
@testable import AnCu

/// Gọi stack Supabase local thật (PostgREST + RPC). Tự bỏ qua khi không có `ANCU_SUPABASE_URL`:
///
///     cd src && supabase start
///     TEST_RUNNER_ANCU_SUPABASE_URL=http://127.0.0.1:54321 xcodebuild test …
///
/// So với dữ liệu mock vì `seed.sql` sinh từ cùng mock JSON.
@Suite(.enabled(if: SupabaseIntegration.config != nil, "Cần ANCU_SUPABASE_URL (stack local)"))
struct SupabaseIntegrationTests {
    private let container: AppContainer
    private let mock = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)

    init() throws {
        guard case let .supabase(url, key)? = SupabaseIntegration.config else { throw RepositoryError.network }
        container = .supabase(
            url: url, publishableKey: key, defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"),
            sessionStorage: InMemoryAuthStorage()
        )
    }

    @Test func projectsMatchMockSeed() async throws {
        let remote = try await container.projects.projects(in: .mvpArea, filter: .all)
        let local = try await mock.projects.projects(in: .mvpArea, filter: .all)
        #expect(Set(remote.map(\.id)) == Set(local.map(\.id)))
        #expect(Set(remote.map(\.name)) == Set(local.map(\.name)))

        let open = try await container.projects.projects(in: .mvpArea, filter: .acceptingApplications)
        #expect(!open.isEmpty && open.allSatisfy { $0.status == .acceptingApplications })

        let some = Set(local.prefix(3).map(\.id))
        #expect(Set(try await container.projects.projects(ids: some).map(\.id)) == some)
    }

    @Test func detailHasServerComputedNearestInfra() async throws {
        let id = try #require(try await mock.projects.projects(in: .mvpArea, filter: .all).first?.id)
        let detail = try await container.projects.project(id: id)
        #expect(detail.project.id == id)
        #expect(!detail.nearestInfra.isEmpty)
        #expect(detail.nearestInfra.map(\.distanceMeters) == detail.nearestInfra.map(\.distanceMeters).sorted())
    }

    @Test func unknownProjectIsNotFound() async {
        await #expect(throws: RepositoryError.notFound) {
            try await container.projects.project(id: UUID())
        }
    }

    @Test func searchWithoutDiacriticsFindsOldName() async throws {
        let results = try await container.projects.search("thu duc")
        #expect(results.contains { if case .place = $0 { true } else { false } })
    }

    /// Migration 16: routes() và node JSON trả geometry_accuracy (mock seed = minh họa).
    @Test func routesCarryGeometryAccuracy() async throws {
        let routes = try await container.infrastructure.routes(types: [.metro])
        #expect(!routes.isEmpty && routes.allSatisfy { $0.geometryAccuracy == .illustrative })
        let nodes = try await container.infrastructure.nodes(routeID: try #require(routes.first).id)
        #expect(nodes.allSatisfy { $0.geometryAccuracy == .illustrative })
    }

    @Test func routesAndNodes() async throws {
        let routes = try await container.infrastructure.routes(types: [])
        #expect(routes.count == (try await mock.infrastructure.routes(types: [])).count)
        let metro = try #require(routes.first { $0.type == .metro && $0.status == .operational })
        #expect(!(try await container.infrastructure.nodes(routeID: metro.id)).isEmpty)
        #expect(try await container.infrastructure.routes(types: [.expressway]).allSatisfy { $0.type == .expressway })

        // Giản lược: không bao giờ nhiều điểm hơn bản đầy đủ, mỗi đoạn vẫn ≥ 2 điểm.
        let coarse = try await container.infrastructure.routes(types: [], detail: .coarse)
        let points = { (routes: [InfraRoute]) in routes.flatMap(\.segments).map(\.count).reduce(0, +) }
        #expect(points(coarse) <= points(routes))
        #expect(coarse.allSatisfy { $0.segments.allSatisfy { $0.count >= 2 } })
    }

    @Test func lookupAndRulesMatchMock() async throws {
        let catalog = try await container.lookup.catalog()
        let mockCatalog = try await mock.lookup.catalog()
        for category in LookupCategory.allCases {
            #expect(catalog.items(in: category).map(\.code) == mockCatalog.items(in: category).map(\.code), "\(category)")
        }
        #expect((try await container.lookup.administrativeUnits()).count == (try await mock.lookup.administrativeUnits()).count)
        let remoteBoundary = try #require(try await container.lookup.boundary(of: .hcm))
        let mockBoundary = try #require(try await mock.lookup.boundary(of: .hcm))
        // Giản lược (0,0005°) chỉ được bỏ đỉnh, không làm lệch đỉnh còn lại (vd đỉnh thẳng hàng 10,55/106,75 bị bỏ).
        let original = Set(mockBoundary.polygons.flatMap { $0 })
        #expect(remoteBoundary.polygons.allSatisfy { $0.count >= 3 && $0.allSatisfy(original.contains) })

        let rules = try await container.eligibility.currentRules()
        #expect(Set(rules.map(\.key)) == Set(try await mock.eligibility.currentRules().map(\.key)))
    }

    /// Luồng người dùng thật: mã OTP lấy từ Mailpit của stack local → đăng nhập → bookmark → báo sai → inbox → xóa tài khoản.
    @Test func emailOTPAccountLifecycle() async throws {
        let email = "it-\(UUID().uuidString.prefix(8).lowercased())@ancu.test"
        let auth = container.auth
        let projectID = try #require(try await mock.projects.projects(in: .mvpArea, filter: .all).first?.id)

        // Khách lưu tạm trước khi đăng nhập.
        #expect(try await container.bookmarks.toggle(projectID: projectID))

        try await auth.sendEmailCode(to: email)
        let code = try await Mailpit.latestCode(for: email)
        await #expect(throws: RepositoryError.unauthorized) { _ = try await auth.verifyEmailCode("000000", email: email) }
        let user = try await auth.verifyEmailCode(code, email: email)
        #expect(user.displayName == String(email.split(separator: "@")[0]))
        #expect(await auth.currentUser?.id == user.id)

        try await container.bookmarks.mergeGuestBookmarks()
        try await container.bookmarks.setNotify(true, projectID: projectID)
        let bookmarks = try await container.bookmarks.all()
        #expect(bookmarks.map(\.projectID) == [projectID])
        #expect(bookmarks.first?.notifyEnabled == true && bookmarks.first?.isLocalOnly == false)

        try await container.dataReports.reportIncorrectData(projectID: projectID, note: "Giá đã đổi (integration test)")
        #expect(try await container.notifications.inbox().isEmpty)
        var prefs = try await container.notifications.preferences()
        #expect(prefs.disabled.isEmpty)
        prefs.set(.priceChanged, enabled: false)
        try await container.notifications.setPreferences(prefs)
        #expect(try await container.notifications.preferences().disabled == [.priceChanged])

        try await auth.deleteAccount()
        #expect(await auth.currentUser == nil)
    }

    /// Địa điểm riêng + ghi chú + đề xuất (migration 13) với server thật: vùng MVP, quyền, xóa tài khoản xóa theo.
    @Test func savedPlacesAndNotesLifecycle() async throws {
        let email = "it-places-\(UUID().uuidString.prefix(8).lowercased())@ancu.test"
        let auth = container.auth
        let draft = SavedPlaceDraft(
            name: "Masteri Thảo Điền", address: "Thảo Điền", location: GeoPoint(latitude: 10.8027, longitude: 106.74),
            kind: .commercial, note: " giá 70 tr/m² ", externalRef: "it-ref"
        )
        await #expect(throws: RepositoryError.unauthorized) { _ = try await container.savedPlaces.create(draft) }

        try await auth.sendEmailCode(to: email)
        _ = try await auth.verifyEmailCode(try await Mailpit.latestCode(for: email), email: email)

        let created = try await container.savedPlaces.create(draft)
        #expect(created.serviceArea == .hcm && created.note == "giá 70 tr/m²" && created.kind == .commercial)
        await #expect(throws: RepositoryError.outsideServiceArea) {
            var hanoi = draft
            hanoi.location = GeoPoint(latitude: 21.004, longitude: 105.747)
            _ = try await container.savedPlaces.create(hanoi)
        }

        let updated = try await container.savedPlaces.update(id: created.id, name: "Masteri (đã xem)", kind: .commercial, icon: "cho_lam", note: nil)
        #expect(updated.name == "Masteri (đã xem)" && updated.note == nil && updated.updatedAt >= created.updatedAt)
        #expect(updated.icon == "cho_lam" && created.icon == nil)
        #expect(try await container.savedPlaces.all().map(\.id) == [created.id])

        let projectID = try #require(try await mock.projects.projects(in: .mvpArea, filter: .all).first?.id)
        try await container.bookmarks.setNote("gần chỗ làm", projectID: projectID)
        #expect(try await container.bookmarks.all().first { $0.projectID == projectID }?.note == "gần chỗ làm")
        try await container.bookmarks.setNote(nil, projectID: projectID)
        #expect(try await container.bookmarks.all().first { $0.projectID == projectID }?.note == nil)

        try await container.dataReports.suggestProject(name: "NOXH mới (integration test)", address: nil,
                                                      location: GeoPoint(latitude: 10.85, longitude: 106.77))

        try await container.savedPlaces.delete(id: created.id)
        #expect(try await container.savedPlaces.all().isEmpty)
        _ = try await container.savedPlaces.create(draft)
        try await auth.deleteAccount()
        await #expect(throws: RepositoryError.unauthorized) { _ = try await container.savedPlaces.all() }
    }

    @Test func analyticsBatchAcceptedByServer() async throws {
        guard case let .supabase(url, key)? = SupabaseIntegration.config else { return }
        let rpc = SupabaseRPCClient(client: SupabaseClient(supabaseURL: url, supabaseKey: key))
        try await SupabaseAnalyticsSink(rpc: rpc).send(
            [AnalyticsEvent(name: "app_open"), AnalyticsEvent(name: "project_viewed", props: ["status": "nhan_ho_so"])],
            installID: UUID()
        )
        // Tên sai luật → server bỏ cả lô → sink báo `.decoding` (BatchingAnalytics bỏ lô, không gửi lại).
        await #expect(throws: RepositoryError.decoding) {
            try await SupabaseAnalyticsSink(rpc: rpc).send([AnalyticsEvent(name: "Sai Ten")], installID: UUID())
        }
    }

    /// Ghi bảng trực tiếp bằng key publishable (anon) phải bị RLS chặn — kiểm tra qua PostgREST thật, không chỉ pgTAP.
    @Test func anonCannotInsertBookmark() async throws {
        guard case let .supabase(url, key)? = SupabaseIntegration.config else { return }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        struct Row: Encodable { let user_id: UUID; let project_id: UUID }
        await #expect(throws: (any Error).self) {
            try await client.from("bookmarks").insert(Row(user_id: UUID(), project_id: UUID())).execute()
        }
    }
}

enum SupabaseIntegration {
    static let config: BackendConfig? = BackendConfig.fromEnvironment(ProcessInfo.processInfo.environment)
}

/// Phiên đăng nhập trong bộ nhớ cho test (không đụng Keychain của app chủ).
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}


/// API của Mailpit (hộp thư giả của `supabase start`, cổng 54324) để lấy mã OTP trong test.
enum Mailpit {
    static let baseURL = URL(string: "http://127.0.0.1:54324/api/v1/")!

    private struct Search: Decodable { let messages: [Summary] }
    private struct Summary: Decodable { let ID: String }
    private struct Message: Decodable { let Text: String }

    static func latestCode(for email: String) async throws -> String {
        for _ in 0..<20 {
            var components = URLComponents(url: baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "query", value: "to:\"\(email)\"")]
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            if let id = try JSONDecoder().decode(Search.self, from: data).messages.first?.ID {
                let (body, _) = try await URLSession.shared.data(from: baseURL.appending(path: "message/\(id)"))
                let text = try JSONDecoder().decode(Message.self, from: body).Text
                if let match = text.firstMatch(of: /\b(\d{6})\b/) { return String(match.1) }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw RepositoryError.notFound
    }
}
