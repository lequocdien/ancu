import AuthenticationServices
import CryptoKit
import UIKit

/// Lấy identity token Sign in with Apple để đổi lấy phiên Supabase (`signInWithIdToken`).
/// Cần capability "Sign in with Apple" (Apple Developer account) — thiếu thì Apple trả lỗi 1000 → `.unauthorized`.
struct AppleIDCredential: Sendable {
    let idToken: String
    /// Nonce gốc; Apple chỉ nhận SHA-256 của nó, Supabase cần bản gốc để đối chiếu.
    let rawNonce: String
    /// Apple chỉ gửi tên ở LẦN ĐẦU người dùng cấp quyền.
    let fullName: String?
}

@MainActor
final class AppleIDCredentialRequest: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleIDCredential, any Error>?
    private var rawNonce = ""

    func perform() async throws -> AppleIDCredential {
        rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8)
        else {
            finish(.failure(RepositoryError.decoding))
            return
        }
        let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
        finish(.success(AppleIDCredential(idToken: token, rawNonce: rawNonce, fullName: name?.isEmpty == false ? name : nil)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let code = (error as? ASAuthorizationError)?.code
        finish(.failure(code == .canceled ? CancellationError() : RepositoryError.unauthorized))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<AppleIDCredential, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
