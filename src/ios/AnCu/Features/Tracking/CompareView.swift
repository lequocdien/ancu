import SwiftUI

/// So sánh 2–3 dự án. Giá trị tốt nhất: chữ đậm + icon ✓ (không chỉ dựa vào màu).
struct CompareView: View {
    let viewModel: TrackingViewModel

    var body: some View {
        ZStack {
            MeshBackground()
            ScrollView {
                switch viewModel.comparisonState {
                case .idle, .loading:
                    ProgressView().padding(Spacing.xxl)
                case .failed:
                    ContentUnavailableView {
                        Label("Không tải được dữ liệu so sánh", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Thử lại") { Task { await viewModel.loadComparison() } }
                    }
                case .loaded:
                    table.padding(Spacing.l)
                }
            }
        }
        .navigationTitle("So sánh")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadComparison() }
    }

    private var table: some View {
        let details = viewModel.comparisonDetails
        return GlassCard(padding: Spacing.m) {
            Grid(alignment: .topLeading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.m) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(details, id: \.project.id) { detail in
                        Text(verbatim: detail.project.name)
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                ForEach(viewModel.comparisonRows) { row in
                    GridRow {
                        Text(verbatim: row.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                            cell(value, isBest: row.bestIndex == index)
                        }
                    }
                }
                Divider()
                Text("Khoảng cách đường chim bay. Giá trị tốt nhất có dấu ✓.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .gridCellColumns(details.count + 1)
            }
        }
    }

    private func cell(_ value: String, isBest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            if isBest {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandPrimary)
                    .imageScale(.small)
            }
            Text(verbatim: value)
                .font(.subheadline.weight(isBest ? .bold : .regular).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isBest ? "\(value), tốt nhất" : value))
    }
}
