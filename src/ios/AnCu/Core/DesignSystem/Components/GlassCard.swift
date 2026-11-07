import SwiftUI

/// Card kính đặt trực tiếp trên nền mesh/map (vd card dự án ở tab Theo dõi).
/// KHÔNG đặt trong sheet hay trong card kính khác — ở đó dùng nền đặc (`MetricTile`).
struct GlassCard<Content: View>: View {
    var style: GlassStyle = .regular
    var padding: CGFloat = Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveGlass(style, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
