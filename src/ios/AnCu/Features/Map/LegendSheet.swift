import SwiftUI

/// Giải thích màu ghim, kiểu nét tuyến và năm dự kiến khai thác. Kèm hai câu miễn trừ bắt buộc.
struct LegendSheet: View {
    let catalog: LookupCatalog
    let routes: [InfraRoute]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Trạng thái dự án") {
                    ForEach(catalog.orderedCases(ProjectStatus.self), id: \.self) { status in
                        Label {
                            Text(verbatim: catalog.label(for: status))
                        } icon: {
                            Image(systemName: catalog.symbolName(for: status, default: "house.fill"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(catalog.color(for: status), in: Circle())
                        }
                    }
                }

                Section("Kiểu nét theo trạng thái tuyến") {
                    ForEach(catalog.orderedCases(RouteStatus.self), id: \.self) { status in
                        HStack(spacing: Spacing.m) {
                            RouteLineSample(color: .secondary, style: catalog.lineStyle(for: status))
                            Text(verbatim: catalog.label(for: status))
                        }
                    }
                }

                Section("Tuyến và năm dự kiến khai thác") {
                    ForEach(routes.sorted(by: Self.byYear)) { route in
                        HStack(spacing: Spacing.m) {
                            RouteLineSample(color: route.displayColor, style: catalog.lineStyle(for: route.status))
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(verbatim: route.name)
                                Text(verbatim: catalog.label(for: route.status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if let year = route.expectedYear {
                                Text(verbatim: String(year))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    Label("Hướng tuyến mang tính minh họa theo quy hoạch được công bố, không dùng để xác định ranh giới đất.", systemImage: "info.circle")
                    Label("Khoảng cách tới ga/nút giao tính theo đường chim bay.", systemImage: "ruler")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Chú giải")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    /// Tuyến có năm khai thác sớm hơn lên trước; chưa có năm xuống cuối.
    private static func byYear(_ lhs: InfraRoute, _ rhs: InfraRoute) -> Bool {
        switch (lhs.expectedYear, rhs.expectedYear) {
        case let (l?, r?) where l != r: l < r
        case (nil, _?): false
        case (_?, nil): true
        default: lhs.name < rhs.name
        }
    }
}

struct RouteLineSample: View {
    let color: Color
    let style: RouteLineStyle

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 7))
            path.addLine(to: CGPoint(x: 36, y: 7))
        }
        .stroke(color.opacity(style.opacity), style: style.strokeStyle)
        .frame(width: 36, height: 14)
        .accessibilityHidden(true)
    }
}
