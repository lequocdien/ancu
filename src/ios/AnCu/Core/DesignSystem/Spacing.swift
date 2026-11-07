import SwiftUI

/// Thang khoảng cách 4pt.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    /// Card, MetricTile, khối nền đặc trong sheet.
    static let card: CGFloat = 20
    static let control: CGFloat = 12
}

/// Bố cục ngang ở cỡ chữ thường, chuyển dọc ở cỡ chữ accessibility (AX1–AX5) để chữ không bị bẻ từng từ.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat = Spacing.m
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}
