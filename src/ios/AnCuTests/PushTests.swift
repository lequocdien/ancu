import Foundation
import Testing
@testable import AnCu

@MainActor
struct PushFlowTests {
    private func make() -> (SessionStore, NoopPushRegistrar) {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let push = NoopPushRegistrar()
        return (SessionStore(container: container, push: push), push)
    }

    /// Quyền thông báo chỉ hỏi khi người dùng bật thông báo cho một dự án — không hỏi lúc mở app hay lúc lưu.
    @Test func permissionAskedOnlyWhenEnablingNotifications() async throws {
        let (session, push) = make()
        await session.load()
        let id = UUID()
        _ = try await session.toggleSave(id)
        try await session.signIn(with: .apple)
        #expect(push.permissionRequests == 0)

        #expect(try await session.setNotify(true, for: id))
        #expect(push.permissionRequests == 1)
        #expect(try await session.setNotify(false, for: id))
        #expect(push.permissionRequests == 1)
    }

    @Test func deniedPermissionStillKeepsNotifyChoice() async throws {
        let (session, push) = make()
        push.grants = false
        try await session.signIn(with: .apple)
        let id = UUID()
        #expect(try await session.setNotify(true, for: id))
        #expect(session.isNotifying(id))   // vẫn nhận trong hộp thư trong app
    }

    @Test func signOutAndDeleteUnregisterTokenFirst() async throws {
        let (session, push) = make()
        try await session.signIn(with: .apple)
        try await session.signOut()
        #expect(push.unregisterCalls == 1)
        try await session.signIn(with: .apple)
        try await session.deleteAccount()
        #expect(push.unregisterCalls == 2)
    }

    @Test func routerConsumesOnce() {
        let router = DeepLinkRouter()
        let id = UUID()
        router.open(projectID: id)
        #expect(router.consume() == id)
        #expect(router.consume() == nil)
    }

    @Test func mapOpensProjectFromNotification() async throws {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let viewModel = MapViewModel(container: container)
        let project = try #require(try await container.projects.projects(in: .mvpArea, filter: .all).last)
        await viewModel.open(projectID: project.id)
        #expect(viewModel.selectedProject?.id == project.id)
        #expect(viewModel.cameraRequest?.region.center == project.location)

        await viewModel.open(projectID: UUID())   // id không còn tồn tại → giữ nguyên, không crash
        #expect(viewModel.selectedProject?.id == project.id)
    }

    @Test func supabasePushTokenRPC() async throws {
        let rpc = FakeRPCClient()
        rpc.respond("register_push_token", json: "")
        try await SupabasePushTokenRepository(rpc: rpc).register(token: "ab", environment: .sandbox)
        #expect(rpc.lastParams("register_push_token")?["environment"] as? String == "sandbox")
        #expect(PushEnvironment.current == .sandbox)   // test chạy bản Debug
    }
}

struct NotificationPreferencesTests {
    @Test func jsonRoundTripKeepsOnlyDisabledKnownTypes() {
        var prefs = NotificationPreferences()
        prefs.set(.priceChanged, enabled: false)
        prefs.set(.unknown, enabled: false)
        #expect(prefs.json == ["doi_gia": false])
        let parsed = NotificationPreferences(json: ["doi_gia": false, "mo_nhan_ho_so": true, "loai_moi": false])
        #expect(parsed.disabled == [.priceChanged])
        #expect(parsed.isEnabled(.applicationsOpened))
    }
}

@MainActor
struct NotificationSettingsViewModelTests {
    private actor FlakyRepository: NotificationRepository {
        var stored = NotificationPreferences()
        var failsSave = false
        func setFailsSave(_ value: Bool) { failsSave = value }
        func inbox() async throws -> [AppNotification] { [] }
        func markAsRead(id: AppNotification.ID) async throws {}
        func preferences() async throws -> NotificationPreferences { stored }
        func setPreferences(_ preferences: NotificationPreferences) async throws {
            if failsSave { throw RepositoryError.network }
            stored = preferences
        }
    }

    @Test func optimisticSaveRevertsOnFailure() async {
        let repository = FlakyRepository()
        let viewModel = NotificationSettingsViewModel(repository: repository)
        await viewModel.load()
        #expect(viewModel.loadState == .loaded)

        await viewModel.set(.priceChanged, enabled: false)
        #expect(await repository.stored.disabled == [.priceChanged])

        await repository.setFailsSave(true)
        await viewModel.set(.statusChanged, enabled: false)
        #expect(viewModel.saveFailed)
        #expect(viewModel.preferences.isEnabled(.statusChanged))   // trả lại như cũ
    }
}
