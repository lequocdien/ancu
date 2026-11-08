import SwiftUI

// MARK: - Ánh xạ danh mục (lookup) → màu, icon, kiểu nét
//
// Code đã biết → token adaptive (đúng Light/Dark/High Contrast).
// Danh mục chưa có token → `color_hex` / `sf_symbol` từ catalog, để server thêm kiểu mới mà không cần phát hành app.
// `.unknown` (code server mới, app cũ chưa biết) → màu trung tính, không bao giờ crash hay trống.

extension LookupCatalog {
    func color(for status: ProjectStatus) -> Color {
        switch status {
        case .acceptingApplications: .statusOpen
        case .upcoming: .statusSoon
        case .underConstruction: .statusBuilding
        case .closed, .unknown: .statusClosed
        }
    }

    func color(for type: NotificationType) -> Color {
        switch type {
        case .applicationsOpened: .statusOpen
        case .priceChanged: .brandAccent
        case .statusChanged: .statusBuilding
        case .unknown: .statusClosed
        }
    }

    /// Danh mục chưa có token riêng: lấy `color_hex` từ catalog.
    func color<C: LookupCode>(for code: C, default fallback: Color) -> Color {
        item(for: code)?.colorHex.flatMap(Color.init(hex:)) ?? fallback
    }

    func symbolName<C: LookupCode>(for code: C, default fallback: String = "circle.fill") -> String {
        item(for: code)?.symbolName ?? fallback
    }

    /// Kiểu nét lấy từ `line_style` của catalog; thiếu thì suy theo trạng thái.
    /// Trạng thái lạ vẽ như "quy hoạch": thà hiển thị thận trọng còn hơn khiến người dùng tưởng tuyến đã chạy.
    func lineStyle(for status: RouteStatus) -> RouteLineStyle {
        switch item(for: status)?.attributes["line_style"] {
        case "solid": .operational
        case "thin": .underConstruction
        case "dashed": .planned
        default:
            switch status {
            case .operational: .operational
            case .underConstruction: .underConstruction
            case .planned, .unknown: .planned
            }
        }
    }
}

/// Mọi tuyến CÙNG độ rộng 4pt (màu = loại tuyến); trạng thái phân biệt bằng KIỂU NÉT (2026-11-07, chốt sau khi thử
/// gạch chấm + bù thị giác 4,5/3,5pt rồi quay lại theo lựa chọn của bạn):
/// đã khai thác = liền · đang thi công = gạch dài 12–4 · quy hoạch = gạch ngắn thưa 4–6, mờ 60%.
struct RouteLineStyle: Equatable, Sendable {
    let lineWidth: CGFloat
    let dash: [CGFloat]
    let opacity: Double

    static let width: CGFloat = 4
    static let operational = RouteLineStyle(lineWidth: width, dash: [], opacity: 1)
    static let underConstruction = RouteLineStyle(lineWidth: width, dash: [12, 4], opacity: 1)
    static let planned = RouteLineStyle(lineWidth: width, dash: [4, 6], opacity: 0.6)

    /// Nét đứt dùng đầu vuông: đầu tròn lấn mỗi bên lineWidth/2 vào khoảng hở → khe 4pt bị lấp kín, nhìn như nét liền.
    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: dash.isEmpty ? .round : .butt, lineJoin: .round, dash: dash)
    }
}

extension LookupCatalog {
    /// Màu tuyến theo LOẠI (mọi tuyến Metro cùng một màu). `color_hex` của danh mục `route_types` → đổi màu từ server
    /// không cần phát hành app. `color_hex` riêng từng tuyến vẫn lưu ở DB nhưng không dùng để vẽ.
    func color(for type: RouteType) -> Color {
        color(for: type, default: InfraRoute.fallbackColor(for: type))
    }
}

extension InfraRoute {
    static func fallbackColor(for type: RouteType) -> Color {
        switch type {
        case .metro: .routeMetro
        case .ringRoad: .routeRing
        case .expressway: .routeExpressway
        case .nationalHighway, .unknown: .routeNational
        }
    }
}
