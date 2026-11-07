import AuthenticationServices
import Foundation
import Supabase

/// Supabase Auth (Phase 1 bước 4.1, architecture.md 5.6): email OTP + Apple (id token) + Google/Facebook (OAuth web).
/// Phiên lưu trong Keychain (mặc định của SDK) và tự làm mới token.
actor SupabaseAuthService: AuthService {
    /// OAuth Google/Facebook quay về app qua scheme này (`additional_redirect_urls` trong config.toml).
    static let redirectURL = URL(string: "ancu://login-callback")!

    nonisolated let socialProviders: [AuthProvider]
    private let client: SupabaseClient
    private let rpc: any RPCClient
    /// Hồ sơ của phiên hiện tại — tránh gọi `current_profile` mỗi lần repository hỏi "đã đăng nhập chưa".
    private var cachedUser: AppUser?

    init(client: SupabaseClient, rpc: any RPCClient, socialProviders: [AuthProvider]) {
        self.client = client
        self.rpc = rpc
        self.socialProviders = socialProviders
    }

    var currentUser: AppUser? {
        get async {
            guard let session = client.auth.currentSession else {
                cachedUser = nil
                return nil
            }
            if let cachedUser, cachedUser.id == session.user.id { return cachedUser }
            // Mất mạng lúc mở app vẫn coi là đã đăng nhập (phiên còn trong Keychain); tên tạm lấy từ email.
            let user = (try? await loadProfile()) ?? Self.fallbackUser(session.user)
            cachedUser = user
            return user
        }
    }

    func signIn(with provider: AuthProvider) async throws -> AppUser {
        guard socialProviders.contains(provider) else { throw RepositoryError.unauthorized }
        do {
            switch provider {
            case .apple:
                let request = await AppleIDCredentialRequest()
                let credential = try await request.perform()
                try await client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: credential.idToken, nonce: credential.rawNonce)
                )
                // TODO(backend): lưu `credential.fullName` vào profiles.display_name (Apple chỉ gửi tên lần đầu).
            case .google:
                try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.redirectURL)
            case .facebook:
                try await client.auth.signInWithOAuth(provider: .facebook, redirectTo: Self.redirectURL)
            }
        } catch {
            throw Self.map(error)
        }
        return try await refreshUser()
    }

    func sendEmailCode(to email: String) async throws {
        guard EmailAddress.isPlausible(email) else { throw RepositoryError.decoding }
        do {
            try await client.auth.signInWithOTP(email: Self.normalized(email), shouldCreateUser: true)
        } catch {
            throw Self.map(error)
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AppUser {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { throw RepositoryError.unauthorized }
        do {
            try await client.auth.verifyOTP(email: Self.normalized(email), token: digits, type: .email)
        } catch {
            throw Self.map(error)
        }
        return try await refreshUser()
    }

    func signOut() async throws {
        cachedUser = nil
        // `.local`: chỉ thoát máy này, không đá các máy khác của cùng tài khoản.
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            throw Self.map(error)
        }
    }

    func deleteAccount() async throws {
        let _: Data = try await rpc.call("delete_my_account", params: NoRPCParams())
        cachedUser = nil
        // User đã bị xóa phía server → signOut có thể báo lỗi; điều cần là xóa phiên trên máy.
        try? await client.auth.signOut(scope: .local)
    }

    private func refreshUser() async throws -> AppUser {
        cachedUser = nil
        guard let user = await currentUser else { throw RepositoryError.unauthorized }
        return user
    }

    private func loadProfile() async throws -> AppUser {
        let dto: ProfileDTO = try await rpc.call("current_profile")
        return DTOMapper.user(dto, email: client.auth.currentUser?.email)
    }

    private static func fallbackUser(_ user: User) -> AppUser {
        let profile = ProfileDTO(id: user.id, displayName: "", isPhoneVerified: false, maskedPhone: nil)
        return DTOMapper.user(profile, email: user.email)
    }

    private static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Lỗi Auth → `RepositoryError`; người dùng tự hủy → `CancellationError`.
    static func map(_ error: any Error) -> any Error {
        switch error {
        case let error as AuthError:
            guard case let .api(_, code, _, response) = error else { return RepositoryError.unauthorized }
            if response.statusCode == 429 || code == .overRequestRateLimit || code == .overEmailSendRateLimit {
                return RepositoryError.rateLimited
            }
            return (400..<500).contains(response.statusCode) ? RepositoryError.unauthorized : RepositoryError.network
        case let error as ASWebAuthenticationSessionError where error.code == .canceledLogin:
            return CancellationError()
        default:
            return SupabaseErrorMapper.map(error)
        }
    }
}
