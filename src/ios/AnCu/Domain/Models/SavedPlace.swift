import Foundation

/// Loại địa điểm riêng (danh mục `place_kinds`, PRD 4.6).
enum PlaceKind: String, LookupCode {
    case socialHousing = "noxh"
    case commercial = "thuong_mai"
    case other = "khac"
    case unknown
    static let category = LookupCategory.placeKind
}

/// Dự án/địa điểm NGOÀI hệ thống người dùng tự lưu (bảng `saved_places`) — riêng tư, chỉ chủ tài khoản thấy.
/// Dự án có trong An Cư dùng `Bookmark` (để giữ thông báo).
struct SavedPlace: Identifiable, Hashable, Sendable {
    /// Khớp CHECK ở migration 13.
    static let maxNameLength = 200
    static let maxAddressLength = 500
    static let maxNoteLength = 2000
    static let maxCount = 200

    let id: UUID
    var name: String
    let address: String?
    /// Vị trí người dùng tự chọn (kết quả tìm kiếm / ghim tay) — không phải GPS của máy (compliance.md 2.1).
    let location: GeoPoint
    var kind: PlaceKind
    /// Mã icon tự chọn (danh mục `place_icons`); `nil` = icon theo loại.
    var icon: String?
    /// Server tính từ vị trí (vùng MVP gần nhất).
    let serviceArea: ServiceArea
    var note: String?
    /// Định danh Apple Maps (nếu lưu từ kết quả tìm kiếm).
    let externalRef: String?
    let createdAt: Date
    var updatedAt: Date
}

/// Dữ liệu để tạo `SavedPlace`.
struct SavedPlaceDraft: Hashable, Sendable {
    var name: String
    var address: String?
    var location: GeoPoint
    var kind: PlaceKind
    var note: String?
    var externalRef: String?
    var icon: String? = nil
}

/// Một kết quả tìm kiếm địa điểm ngoài hệ thống (Apple Maps).
struct PlaceCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let address: String?
    let location: GeoPoint
    let externalRef: String?
}

/// Kiểm tra trước khi gửi — khớp CHECK ở server, để UI báo lỗi sớm và Mock hành xử như thật.
enum SavedPlaceValidation {
    static func validate(name: String, kind: PlaceKind, note: String?) throws -> (name: String, note: String?) {
        guard let cleanedName = UserText.cleaned(name), cleanedName.count <= SavedPlace.maxNameLength,
              kind != .unknown
        else { throw RepositoryError.decoding }
        let cleanedNote = UserText.cleaned(note)
        guard (cleanedNote?.count ?? 0) <= SavedPlace.maxNoteLength else { throw RepositoryError.decoding }
        return (cleanedName, cleanedNote)
    }
}

/// Chuẩn hóa văn bản người dùng nhập: bỏ khoảng trắng đầu/cuối; rỗng → `nil`.
enum UserText {
    static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
