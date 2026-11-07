import Foundation
import Testing
@testable import AnCu

struct BackendConfigTests {
    private static let cloudURL = URL(string: "https://abc.supabase.co")!
    private static var plist: [String: Any] { [
        BackendConfig.urlInfoKey: "https://abc.supabase.co",
        BackendConfig.keyInfoKey: "sb_publishable_plist",
    ] }

    /// JWT giả (chữ ký không kiểm tra) với role cho trước.
    private static func jwt(role: String) -> String {
        let payload = Data(#"{"iss":"supabase-demo","role":"\#(role)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(payload).signature"
    }

    @Test func defaultsToMockWhenNothingConfigured() {
        #expect(BackendConfig.resolve(environment: [:], arguments: [], infoDictionary: [:]) == .mock)
    }

    /// xcconfig để trống → Info.plist có chuỗi rỗng.
    @Test func emptyXcconfigValuesMeanMock() {
        let info: [String: Any] = [BackendConfig.urlInfoKey: "", BackendConfig.keyInfoKey: ""]
        #expect(BackendConfig.resolve(environment: [:], arguments: [], infoDictionary: info) == .mock)
    }

    @Test func infoPlistSelectsSupabase() {
        #expect(BackendConfig.resolve(environment: [:], arguments: [], infoDictionary: Self.plist)
                == .supabase(url: Self.cloudURL, publishableKey: "sb_publishable_plist"))
    }

    @Test func debugFlagOverridesInfoPlist() {
        #expect(BackendConfig.resolve(environment: [:], arguments: ["-Backend", "local"], infoDictionary: Self.plist) == .local)
        #expect(BackendConfig.resolve(environment: [:], arguments: ["-Backend", "mock"], infoDictionary: Self.plist) == .mock)
        #expect(BackendConfig.resolve(environment: [:], arguments: ["-Backend", "la"], infoDictionary: Self.plist) != .mock)
    }

    @Test func environmentOverridesEverything() {
        let config = BackendConfig.resolve(
            environment: ["ANCU_SUPABASE_URL": "https://env.supabase.co", "ANCU_SUPABASE_KEY": "sb_publishable_env"],
            arguments: ["-Backend", "local"],
            infoDictionary: Self.plist
        )
        #expect(config == .supabase(url: URL(string: "https://env.supabase.co")!, publishableKey: "sb_publishable_env"))
    }

    @Test func remoteURLWithoutKeyIsRejected() {
        #expect(BackendConfig.fromEnvironment(["ANCU_SUPABASE_URL": "https://abc.supabase.co"]) == nil)
        #expect(BackendConfig.fromEnvironment(["ANCU_SUPABASE_URL": "http://127.0.0.1:54321"]) == .local)
        #expect(BackendConfig.fromEnvironment(["ANCU_SUPABASE_URL": "khong la url"]) == nil)
        // Quên mẹo "$()" trong xcconfig → giá trị bị cắt thành "https:".
        #expect(BackendConfig.fromInfoDictionary([BackendConfig.urlInfoKey: "https:", BackendConfig.keyInfoKey: "sb_publishable_x"]) == nil)
    }

    @Test func publishableKeyCheck() {
        #expect(BackendConfig.isPublishableKey("sb_publishable_abc"))
        #expect(BackendConfig.isPublishableKey(Self.jwt(role: "anon")))
        #expect(!BackendConfig.isPublishableKey("sb_secret_abc"))
        #expect(!BackendConfig.isPublishableKey(Self.jwt(role: "service_role")))
        #expect(!BackendConfig.isPublishableKey("khong-phai-key"))
    }

    /// Lỡ cấu hình key quyền cao: không bao giờ dùng, về Mock.
    @Test func secretKeyFallsBackToMock() {
        let info: [String: Any] = [BackendConfig.urlInfoKey: "https://abc.supabase.co", BackendConfig.keyInfoKey: "sb_secret_abc"]
        #expect(BackendConfig.resolve(environment: [:], arguments: [], infoDictionary: info) == .mock)
        #expect(BackendConfig.fromEnvironment(["ANCU_SUPABASE_URL": "https://abc.supabase.co", "ANCU_SUPABASE_KEY": Self.jwt(role: "service_role")]) == nil)
    }

    /// Bản build hiện tại: Info.plist có đủ key (rỗng khi chưa có Secrets-*.xcconfig) — chứng minh plist được gộp.
    @Test func builtInfoPlistContainsBackendKeys() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info[BackendConfig.urlInfoKey] is String)
        #expect(info[BackendConfig.keyInfoKey] is String)
        #expect(info["CFBundleDisplayName"] as? String == "An Cư")
    }
}
