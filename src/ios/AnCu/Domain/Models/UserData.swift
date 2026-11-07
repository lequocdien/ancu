import Foundation

struct AppUser: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let isPhoneVerified: Bool
    /// Chỉ giữ dạng đã che ("••• 482"); số đầy đủ không đi vào Domain.
    let maskedPhone: String?
}

enum AuthProvider: String, CaseIterable, Sendable {
    case apple, google, facebook

    /// "apple,google" (Info.plist ← xcconfig) → thứ tự hiển thị chuẩn; bỏ giá trị lạ.
    /// Có Google/Facebook mà thiếu Apple → tự thêm Apple (App Store Review 4.8).
    static func parseList(_ raw: String?) -> [AuthProvider] {
        let names = Set((raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        var providers = Set(allCases.filter { names.contains($0.rawValue) })
        if !providers.isEmpty { providers.insert(.apple) }
        return allCases.filter(providers.contains)
    }
}

/// Loại thông báo đã tắt. Không có trong danh sách = đang bật (thêm loại mới không làm ai mất thông báo).
struct NotificationPreferences: Equatable, Sendable {
    var disabled: Set<NotificationType> = []

    func isEnabled(_ type: NotificationType) -> Bool { !disabled.contains(type) }

    mutating func set(_ type: NotificationType, enabled: Bool) {
        if enabled { disabled.remove(type) } else { disabled.insert(type) }
    }

    /// Shape server: {"doi_gia": false, ...}
    var json: [String: Bool] {
        Dictionary(uniqueKeysWithValues: disabled.filter { $0 != .unknown }.map { ($0.rawValue, false) })
    }

    init(disabled: Set<NotificationType> = []) { self.disabled = disabled }

    init(json: [String: Bool]) {
        disabled = Set(json.filter { !$0.value }.compactMap { NotificationType(rawValue: $0.key) })
    }
}

enum EmailAddress {
    /// Kiểm tra hình thức tối thiểu ở client; server mới là nơi quyết định.
    static func isPlausible(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 254, !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}

struct Bookmark: Identifiable, Hashable, Sendable {
    var id: Project.ID { projectID }
    let projectID: Project.ID
    var notifyEnabled: Bool
    let createdAt: Date
    /// `true` khi khách lưu tạm trên máy, chưa gộp vào tài khoản (prd.md mục 4.1).
    var isLocalOnly: Bool
}

struct AppNotification: Identifiable, Hashable, Sendable {
    let id: UUID
    let type: NotificationType
    let projectID: Project.ID
    let title: String
    let body: String
    let createdAt: Date
    var isRead: Bool
}

/// Một luật trong bảng `eligibility_rules`. Ngưỡng nằm ở dữ liệu, không hardcode trong app.
struct EligibilityRule: Hashable, Sendable {
    enum Value: Hashable, Sendable {
        case number(Decimal)
        case text(String)
        case codes([String])
    }

    let key: String
    let value: Value
    let legalReference: String
    let effectiveFrom: Date
    /// `true` cho dữ liệu prototype — UI phải gắn nhãn MOCK.
    let isMock: Bool
}
