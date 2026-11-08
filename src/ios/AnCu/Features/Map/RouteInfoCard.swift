import SwiftUI

/// Thẻ tên tuyến khi chạm vào một tuyến trên bản đồ — các tuyến cùng loại cùng màu nên đây là cách phân biệt.
struct RouteInfoCard: View {
    let route: InfraRoute
    let catalog: LookupCatalog
    let onClose: () -> Void

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Spacing.m) {
                RouteLineSample(color: catalog.color(for: route.type), style: catalog.lineStyle(for: route.status))
                    .padding(.top, Spacing.xs)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: catalog.label(for: route.type))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(catalog.color(for: route.type))
                    Text(verbatim: route.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let caveat = Self.caveat(route.geometryAccuracy) {
                        Label(caveat, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Đóng"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Tuyến chưa xây: hướng tuyến không dùng để xác định ranh giới đất (data-strategy.md mục 2).
    static func caveat(_ accuracy: GeometryAccuracy) -> LocalizedStringKey? {
        switch accuracy {
        case .exact: nil
        case .approximate: "Hướng tuyến gần đúng theo hồ sơ dự án"
        case .illustrative: "Hướng tuyến minh họa theo quy hoạch — không dùng xác định ranh giới đất"
        }
    }

    private var detail: String {
        var parts = [catalog.label(for: route.status)]
        if let year = route.expectedYear {
            // Tuyến đã chạy thì năm là mốc đã qua, không phải "dự kiến".
            parts.append(route.status == .operational
                ? String(localized: "Khai thác từ \(String(year))")
                : String(localized: "Dự kiến \(String(year))"))
        }
        return parts.joined(separator: " · ")
    }
}
