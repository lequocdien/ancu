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
