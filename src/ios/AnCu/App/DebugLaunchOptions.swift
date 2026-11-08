import Foundation

/// Hook chỉ dùng khi chụp màn hình trên Simulator (simctl không bấm được). Release luôn trả giá trị mặc định.
///
///     xcrun simctl launch <device> vn.ancu.app -SignedIn -Tab tracking
enum DebugLaunchOptions {
    static var showsDesignSystemGallery: Bool { flag("-DesignSystemGallery") }
    static var selectsFirstProject: Bool { flag("-SelectFirstProject") }
    static var signsInOnLaunch: Bool { flag("-SignedIn") }
    static var startsEligibilityWizard: Bool { flag("-EligibilityWizard") }
    static var opensDetailLarge: Bool { flag("-DetailLarge") }
    static var seedsBookmarks: Bool { flag("-SeedBookmarks") }
    /// Như bấm "Gần tôi" — dùng với `xcrun simctl location <device> set <lat>,<lng>`.
    static var locatesOnLaunch: Bool { flag("-LocateOnLaunch") }
    /// Server "yêu cầu" phiên bản 99.0.0 → màn chặn cập nhật (chỉ Mock).
    static var forcesUpdate: Bool { flag("-ForceUpdate") }
    /// Bỏ lựa chọn chip bản đồ đã lưu → chụp màn hình/test UI luôn từ trạng thái mặc định.
    static var resetsMapPreferences: Bool { flag("-ResetMapPreferences") }
    /// Tạo sẵn 3 địa điểm riêng (cần đăng nhập, vd `-SignedIn`) — chụp tab Theo dõi / lớp "Đã lưu".
    static var seedsPlaces: Bool { flag("-SeedPlaces") }
    /// Mở sẵn sheet sửa địa điểm riêng đầu tiên (dùng kèm `-SignedIn -SeedPlaces`).
    static var editsFirstPlace: Bool { flag("-EditFirstPlace") }
    /// Bật sẵn lớp "Đã lưu" trên bản đồ.
    static var showsSavedLayer: Bool { flag("-ShowSavedLayer") }

    /// `-PickAt 10.80,106.74` — như nhấn giữ tại điểm đó (chế độ chọn vị trí trước khi lưu).
    static var pickAt: GeoPoint? {
        guard let parts = value(after: "-PickAt")?.split(separator: ",").compactMap({ Double($0) }), parts.count == 2 else { return nil }
        return GeoPoint(latitude: parts[0], longitude: parts[1])
    }

    /// `-SelectRouteAt 10.7766,106.7031` — như chạm vào tuyến tại điểm đó (thẻ tên tuyến).
    static var selectRouteAt: GeoPoint? {
        guard let parts = value(after: "-SelectRouteAt")?.split(separator: ",").compactMap({ Double($0) }), parts.count == 2 else { return nil }
        return GeoPoint(latitude: parts[0], longitude: parts[1])
    }

    /// `-SearchQuery vinhomes` — điền sẵn ô tìm kiếm.
    static var searchQuery: String? { value(after: "-SearchQuery") }

    /// `-Tab map|tracking|account`
    static var initialTab: String? { value(after: "-Tab") }

    /// `-FocusArea hcm_cu` — như bấm chip vùng (highlight ranh giới).
    static var focusArea: String? { value(after: "-FocusArea") }

    private static func value(after flag: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
        #else
        return nil
        #endif
    }

    private static func flag(_ name: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(name)
        #else
        false
        #endif
    }
}
