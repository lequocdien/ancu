import Foundation
import Observation

/// Đăng nhập bằng mã 6 số gửi qua email (Phase 1 bước 4.1): nhập email → nhận mã → nhập mã.
@MainActor
@Observable
final class EmailSignInViewModel {
    enum Step: Equatable {
        case enterEmail
        case enterCode
    }

    enum Failure: Equatable {
        case invalidEmail
        case wrongCode
        case tooManyRequests
        case network
    }

    /// Gửi lại mã sớm nhất sau khoảng này (server cũng giới hạn).
    static let resendInterval: TimeInterval = 30

    var email = "" {
        didSet { if email != oldValue { failure = nil } }
    }
    var code = "" {
        didSet {
            let digits = String(code.filter(\.isNumber).prefix(6))
            if digits != code { code = digits }
            if code != oldValue { failure = nil }
        }
    }
    private(set) var step: Step = .enterEmail
    private(set) var isWorking = false
    private(set) var failure: Failure?
    private(set) var lastSentAt: Date?

    private let session: SessionStore
    private let now: () -> Date

    init(session: SessionStore, now: @escaping () -> Date = { .now }) {
        self.session = session
        self.now = now
    }

    var canSendCode: Bool { !isWorking && EmailAddress.isPlausible(email) }
    var canVerify: Bool { !isWorking && code.count == 6 }

    /// Số giây còn phải chờ để gửi lại mã (0 = gửi được).
    func resendWait(at date: Date) -> Int {
        guard let lastSentAt else { return 0 }
        return max(0, Int((Self.resendInterval - date.timeIntervalSince(lastSentAt)).rounded(.up)))
    }

    func sendCode() async {
        guard EmailAddress.isPlausible(email) else {
            failure = .invalidEmail
            return
        }
        guard !isWorking, resendWait(at: now()) == 0 else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.sendEmailCode(to: email)
            lastSentAt = now()
            code = ""
            step = .enterCode
        } catch {
            failure = Self.failure(for: error, invalid: .invalidEmail)
        }
    }

    /// Trả `true` khi đăng nhập xong.
    func verify() async -> Bool {
        guard canVerify else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.verifyEmailCode(code, email: email)
            return true
        } catch {
            failure = Self.failure(for: error, invalid: .wrongCode)
            return false
        }
    }

    func changeEmail() {
        step = .enterEmail
        code = ""
        failure = nil
    }

    private static func failure(for error: RepositoryError, invalid: Failure) -> Failure {
        switch error {
        case .rateLimited: .tooManyRequests
        case .unauthorized, .decoding, .notFound, .outsideServiceArea, .limitReached: invalid
        case .network: .network
        }
    }
}
