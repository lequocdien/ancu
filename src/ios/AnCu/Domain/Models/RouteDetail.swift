import Foundation

/// Mức chi tiết hình học tuyến theo zoom (Phase 1 bước 3.2). Phân bậc thay vì tolerance liên tục
/// để cache được và không gọi lại server mỗi lần zoom một chút.
enum RouteDetail: Int, CaseIterable, Comparable, Sendable {
    case coarse
    case medium
    case full

    /// Tham số `tolerance_degrees` của RPC `routes` (ST_SimplifyPreserveTopology). 0,002° ≈ 220 m —
    /// nhỏ hơn 1–2 điểm ảnh khi đang nhìn cả vùng (~0,6° trên ~400 pt).
    var toleranceDegrees: Double {
        switch self {
        case .coarse: 0.002
        case .medium: 0.0005
        case .full: 0
        }
    }

    /// Theo bề ngang khung nhìn (độ kinh). Ngưỡng có biên trễ nhỏ do dùng `<`.
    static func forLongitudeDelta(_ delta: Double) -> RouteDetail {
        switch delta {
        case ..<0.15: .full
        case ..<0.6: .medium
        default: .coarse
        }
    }

    static func < (lhs: RouteDetail, rhs: RouteDetail) -> Bool { lhs.rawValue < rhs.rawValue }
}
