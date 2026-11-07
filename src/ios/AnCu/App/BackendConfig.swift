import Foundation

/// Backend dùng cho phiên chạy (architecture.md 5.5, Phase 1 bước 1.3).
enum BackendConfig: Equatable, Sendable {
    case mock
    case supabase(url: URL, publishableKey: String)

    /// Stack `supabase start` (src/supabase). Key publishable mặc định của CLI — công khai, chỉ dùng local.
    static let local = BackendConfig.supabase(
        url: URL(string: "http://127.0.0.1:54321")!,
        publishableKey: "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    )

    static let urlInfoKey = "AnCuSupabaseURL"
    static let keyInfoKey = "AnCuSupabaseKey"

    /// Thứ tự ưu tiên (cao → thấp):
    /// 1. Biến môi trường `ANCU_SUPABASE_URL` + `ANCU_SUPABASE_KEY` (test, CI)
    /// 2. DEBUG `-Backend local` | `-Backend mock` (ghi đè tạm khi chạy tay)
    /// 3. Info.plist ← `Config/*.xcconfig` ← `Secrets-*.xcconfig` (bản build thật)
    /// 4. Mock
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> BackendConfig {
        if let config = fromEnvironment(environment) { return config }
        #if DEBUG
        if let index = arguments.firstIndex(of: "-Backend"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "local": return .local
            case "mock": return .mock
            default: break
            }
        }
        #endif
        if let config = fromInfoDictionary(infoDictionary) { return config }
        return .mock
    }

    static func fromEnvironment(_ environment: [String: String]) -> BackendConfig? {
        guard let url = remoteURL(environment["ANCU_SUPABASE_URL"]) else { return nil }
        if let key = nonEmpty(environment["ANCU_SUPABASE_KEY"]) {
            return isPublishableKey(key) ? .supabase(url: url, publishableKey: key) : nil
        }
        // Chỉ URL mà không key: chấp nhận cho stack local (dùng key mặc định của CLI), từ chối remote.
        guard url.host == "127.0.0.1" || url.host == "localhost" else { return nil }
        return .local
    }

    /// xcconfig để trống → plist chứa chuỗi rỗng → `nil` (về Mock).
    static func fromInfoDictionary(_ info: [String: Any]) -> BackendConfig? {
        guard let url = remoteURL(info[urlInfoKey] as? String),
              let key = nonEmpty(info[keyInfoKey] as? String), isPublishableKey(key)
        else { return nil }
        return .supabase(url: url, publishableKey: key)
    }

    /// Chặn nhúng nhầm key quyền cao vào app (bỏ qua RLS → lộ toàn bộ DB). Bản build chứa key là công khai.
    static func isPublishableKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return false }
        if key.hasPrefix("sb_publishable_") { return true }
        // Key cũ dạng JWT: chỉ nhận role `anon`.
        return jwtRole(key) == "anon"
    }

    private static func jwtRole(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return payload["role"] as? String
    }

    private static func remoteURL(_ raw: String?) -> URL? {
        guard let raw = nonEmpty(raw), let url = URL(string: raw),
              url.scheme == "http" || url.scheme == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}
