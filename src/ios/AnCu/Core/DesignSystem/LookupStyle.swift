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

/// Quy hoạch = nét đứt opacity 0.5 · Đang thi công = nét liền 3pt · Đã khai thác = nét liền 5pt.
struct RouteLineStyle: Equatable, Sendable {
    let lineWidth: CGFloat
    let dash: [CGFloat]
    let opacity: Double

    static let operational = RouteLineStyle(lineWidth: 5, dash: [], opacity: 1)
    static let underConstruction = RouteLineStyle(lineWidth: 3, dash: [], opacity: 1)
    static let planned = RouteLineStyle(lineWidth: 3, dash: [8, 6], opacity: 0.5)

    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dash)
    }
}

extension InfraRoute {
    /// Màu từ dữ liệu tuyến; hex sai thì dùng màu mặc định theo loại tuyến.
    var displayColor: Color {
        Color(hex: colorHex) ?? Self.fallbackColor(for: type)
    }

    static func fallbackColor(for type: RouteType) -> Color {
        switch type {
        case .metro: .routeMetro1
        case .ringRoad: .routeRing
        case .expressway: .routeExpressway
        case .nationalHighway, .unknown: .routeNational
        }
    }
}
