import SwiftUI

/// Badge trạng thái. Là content (không dùng kính).
/// Chữ dùng `.primary`, chỉ icon mang màu: chữ màu amber/xám trên nền sáng không đạt tương phản WCAG.
struct StatusBadge: View {
    /// Nhãn lấy từ catalog (server-driven) nên là `String`, không localize ở client.
    let label: String
    let symbolName: String?
    let color: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbolName {
                Image(systemName: symbolName)
                    .foregroundStyle(color)
                    .imageScale(.small)
            }
            Text(verbatim: label)
                .foregroundStyle(.primary)
        }
        .font(.badge)
        // Cỡ chữ accessibility: cho xuống 2 dòng thay vì cắt "Đang nhận hồ…".
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension StatusBadge {
    init(_ status: ProjectStatus, catalog: LookupCatalog) {
        self.init(
            label: catalog.label(for: status),
            symbolName: catalog.item(for: status)?.symbolName,
            color: catalog.color(for: status)
        )
    }
}
