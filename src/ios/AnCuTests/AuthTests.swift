import Foundation
import Testing
@testable import AnCu

struct AuthHelpersTests {
    @Test(arguments: [
        ("", [AuthProvider]()),
        ("email", []),
        ("apple", [.apple]),
        ("google, FACEBOOK", [.apple, .google, .facebook]),   // có bên thứ ba → luôn có Apple
        ("facebook,apple,la", [.apple, .facebook]),
    ])
    func parsesProviderList(_ raw: String, _ expected: [AuthProvider]) {
        #expect(AuthProvider.parseList(raw) == expected)
    }

    @Test(arguments: ["an@ancu.vn", " an.nguyen+noxh@mail.co ", "a@b.c"])
    func plausibleEmails(_ email: String) {
        #expect(EmailAddress.isPlausible(email))
    }

    @Test(arguments: ["", "an", "an@", "@ancu.vn", "an@ancu", "an @ancu.vn", "an@.vn", "an@ancu.vn."])
    func implausibleEmails(_ email: String) {
        #expect(!EmailAddress.isPlausible(email))
    }

    @Test func profileFallsBackToEmailName() {
        let id = UUID()
        let user = DTOMapper.user(ProfileDTO(id: id, displayName: " ", isPhoneVerified: false, maskedPhone: nil), email: "minh.an@ancu.vn")
        #expect(user.displayName == "minh.an")
        let named = DTOMapper.user(ProfileDTO(id: id, displayName: "An", isPhoneVerified: true, maskedPhone: "••• 482"), email: nil)
        #expect(named.displayName == "An" && named.isPhoneVerified)
    }
}

@MainActor
struct EmailSignInViewModelTests {
    private func make(now: @escaping () -> Date = { .now }) -> (EmailSignInViewModel, SessionStore) {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let session = SessionStore(container: container)
        return (EmailSignInViewModel(session: session, now: now), session)
    }

    @Test func fullFlowSignsInAndMergesGuestBookmarks() async throws {
        let (viewModel, session) = make()
        let projectID = UUID()
        _ = try await session.toggleSave(projectID)
        #expect(session.bookmarks.first?.isLocalOnly == true)

        viewModel.email = "an@ancu.vn"
        #expect(viewModel.canSendCode)
        await viewModel.sendCode()
        #expect(viewModel.step == .enterCode)

        viewModel.code = "12a34-56789"   // chỉ giữ 6 chữ số
        #expect(viewModel.code == "123456")
        #expect(await viewModel.verify())
        #expect(session.isSignedIn)
        #expect(session.bookmarks.allSatisfy { !$0.isLocalOnly })
    }

    @Test func wrongCodeShowsFailureAndStaysSignedOut() async {
        let (viewModel, session) = make()
        viewModel.email = "an@ancu.vn"
        await viewModel.sendCode()
        viewModel.code = "000000"
        #expect(await !viewModel.verify())
        #expect(viewModel.failure == .wrongCode)
        #expect(!session.isSignedIn)
        viewModel.code = "00000"
        #expect(viewModel.failure == nil)   // sửa mã thì xóa lỗi
    }

    @Test func invalidEmailNeverCallsServer() async {
        let (viewModel, _) = make()
        viewModel.email = "an@"
        #expect(!viewModel.canSendCode)
        await viewModel.sendCode()
        #expect(viewModel.failure == .invalidEmail && viewModel.step == .enterEmail)
    }

    @Test func resendIsThrottled() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let (viewModel, _) = make(now: { clock })
        viewModel.email = "an@ancu.vn"
        await viewModel.sendCode()
        #expect(viewModel.resendWait(at: clock) == 30)
        clock.addTimeInterval(29.2)
        #expect(viewModel.resendWait(at: clock) == 1)
        clock.addTimeInterval(1)
        #expect(viewModel.resendWait(at: clock) == 0)
    }
}

/// Hủy màn Apple/Google không phải lỗi.
@MainActor
struct SignInCancellationTests {
    private struct CancellingAuth: AuthService {
        var currentUser: AppUser? { get async { nil } }
        let socialProviders: [AuthProvider] = [.apple]
        func signIn(with provider: AuthProvider) async throws -> AppUser { throw CancellationError() }
        func sendEmailCode(to email: String) async throws {}
        func verifyEmailCode(_ code: String, email: String) async throws -> AppUser { throw RepositoryError.unauthorized }
        func signOut() async throws {}
        func deleteAccount() async throws {}
    }

    @Test func cancelReturnsFalseWithoutError() async throws {
        let container = AppContainer.mock(defaultsSuite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"), latency: .none)
        let session = SessionStore(auth: CancellingAuth(), bookmarks: container.bookmarks)
        #expect(try await session.signIn(with: .apple) == false)
        #expect(!session.isSignedIn)
    }
}

/// Bookmark Supabase với fake RPC: khách lưu trên máy, đăng nhập thì gộp rồi dùng server.
struct SupabaseBookmarkRepositoryTests {
    private actor SwitchableAuth: AuthService {
        var user: AppUser?
        nonisolated let socialProviders: [AuthProvider] = []
        var currentUser: AppUser? { user }
        func setUser(_ user: AppUser?) { self.user = user }
        func signIn(with provider: AuthProvider) async throws -> AppUser { throw RepositoryError.unauthorized }
        func sendEmailCode(to email: String) async throws {}
        func verifyEmailCode(_ code: String, email: String) async throws -> AppUser { throw RepositoryError.unauthorized }
        func signOut() async throws { user = nil }
        func deleteAccount() async throws { user = nil }
    }

    @Test func guestSavesLocallyThenMergesOnSignIn() async throws {
        let rpc = FakeRPCClient()
        let auth = SwitchableAuth()
        let repository = SupabaseBookmarkRepository(rpc: rpc, auth: auth, suite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"))
        let projectID = RPCFixtures.projectID

        #expect(try await repository.toggle(projectID: projectID))
        #expect(try await repository.all().map(\.isLocalOnly) == [true])
        await #expect(throws: RepositoryError.unauthorized) { try await repository.setNotify(true, projectID: projectID) }
        #expect(rpc.calls.isEmpty)

        await auth.setUser(MockAuthService.demoUser)
        rpc.respond("merge_guest_bookmarks", json: "1")
        try await repository.mergeGuestBookmarks()
        #expect(rpc.lastParams("merge_guest_bookmarks")?["project_ids"] as? [String] == [projectID.uuidString])

        rpc.respond("my_bookmarks", json: #"[{"project_id": "\#(projectID.uuidString)", "notify_enabled": true, "created_at": "2026-11-07T04:39:49.936656+00:00"}]"#)
        let all = try await repository.all()
        #expect(all.count == 1 && all[0].notifyEnabled && !all[0].isLocalOnly)

        // Đã gộp → máy không còn bản tạm, gộp lại không gọi server.
        try await repository.mergeGuestBookmarks()
        #expect(rpc.callCount("merge_guest_bookmarks") == 1)
    }

    @Test func signedInToggleUsesServer() async throws {
        let rpc = FakeRPCClient()
        let auth = SwitchableAuth()
        await auth.setUser(MockAuthService.demoUser)
        let repository = SupabaseBookmarkRepository(rpc: rpc, auth: auth, suite: MockDefaultsSuite(name: "test.\(UUID().uuidString)"))
        rpc.respond("toggle_bookmark", json: "true")
        #expect(try await repository.toggle(projectID: RPCFixtures.projectID))
        #expect(rpc.lastParams("toggle_bookmark")?["project_id"] as? String == RPCFixtures.projectID.uuidString)
    }

    @Test func reportRateLimitMapsFromRPCCode() {
        #expect(SupabaseErrorMapper.map(postgrestCode: "AC429") == .rateLimited)
        #expect(SupabaseErrorMapper.map(postgrestCode: "28000") == .unauthorized)
    }
}
