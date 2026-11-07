import Foundation

/// Lựa chọn chip trên bản đồ được ghi nhớ giữa các lần mở app (architecture.md 5.6).
/// Lưu **mã** (khớp DB) thay vì enum để app cũ/mới đọc được của nhau; mã lạ bị bỏ qua khi khôi phục.
/// Không nhớ "Đã lưu" (khách mở app sẽ thấy bản đồ trống) và "Tất cả NOXH".
struct MapPreferences: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    /// Lớp tuyến người dùng **tắt**. Lưu phần tắt (không phải phần bật) để loại tuyến mới thêm sau mặc định bật.
    var disabledRouteTypes: [String] = []
    /// Chip "Đang nhận hồ sơ".
    var acceptingApplicationsOnly = false
    /// Mã `service_areas` đang chọn; `nil` = toàn vùng MVP.
    var focusedArea: String?

    init(disabledRouteTypes: [String] = [], acceptingApplicationsOnly: Bool = false, focusedArea: String? = nil) {
        self.disabledRouteTypes = disabledRouteTypes
        self.acceptingApplicationsOnly = acceptingApplicationsOnly
        self.focusedArea = focusedArea
    }

    /// Thiếu khóa (bản cũ hơn / bản sau bỏ bớt) → giá trị mặc định thay vì bỏ cả bản ghi.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        disabledRouteTypes = try container.decodeIfPresent([String].self, forKey: .disabledRouteTypes) ?? []
        acceptingApplicationsOnly = try container.decodeIfPresent(Bool.self, forKey: .acceptingApplicationsOnly) ?? false
        focusedArea = try container.decodeIfPresent(String.self, forKey: .focusedArea)
    }
}

/// Nơi lưu `MapPreferences`. Đồng bộ (không async): phải đọc được trong `init` của ViewModel,
/// trước lần vẽ đầu — tránh bản đồ hiện mặc định rồi mới nhảy sang lựa chọn cũ.
protocol MapPreferencesStore: Sendable {
    func load() -> MapPreferences?
    func save(_ preferences: MapPreferences)
    func clear()
}
