import Foundation

/// Cấu hình server gửi xuống app (RPC `client_config`). Phase 1 bước 4.8.
struct ClientConfig: Equatable, Sendable {
    let minSupportedVersion: AppVersion
    /// Trang App Store của app; `nil` khi chưa phát hành → màn chặn không có nút cập nhật.
    let appStoreURL: URL?

    /// Mặc định khi không tải được: không chặn ai (fail-open).
    static let permissive = ClientConfig(minSupportedVersion: AppVersion(0, 0, 0), appStoreURL: nil)

    func requiresUpdate(current: AppVersion) -> Bool {
        current < minSupportedVersion
    }
}

/// Phiên bản dạng `major.minor.patch` (thiếu phần → 0). So sánh theo số, không theo chuỗi ("0.10.0" > "0.9.0").
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        numbers += Array(repeating: 0, count: 3 - numbers.count)
        self.init(numbers[0], numbers[1], numbers[2])
    }

    /// `CFBundleShortVersionString` của bản đang chạy.
    static var current: AppVersion {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) ?? AppVersion(0, 0, 0)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}
