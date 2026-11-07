import SwiftUI

/// Ô số liệu (Giá tham khảo, Số căn, Pháp lý, Khung nhận hồ sơ…).
/// Nằm trong sheet → nền đặc, không kính (tránh glass-on-glass).
struct MetricTile: View {
    let title: LocalizedStringKey
    /// Giá trị đã format sẵn bởi ViewModel (dữ liệu, không localize).
    let value: String
    var systemImage: String?
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.metricLabel)
            .foregroundStyle(.secondary)

            Text(verbatim: value)
                .font(.metricValue)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let caption {
                Text(verbatim: caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
