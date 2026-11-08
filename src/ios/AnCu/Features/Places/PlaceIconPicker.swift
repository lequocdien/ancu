import SwiftUI

/// Lưới chọn icon cho địa điểm (danh mục `place_icons`, PRD 4.6). Ô đầu "Theo loại" = không chọn (`nil`).
/// Icon lấy từ catalog → server thêm icon mới (kèm `sf_symbol`) không cần phát hành app.
struct PlaceIconPicker: View {
    @Binding var selection: String?
    let kind: PlaceKind
    let catalog: LookupCatalog

    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = 44

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cell + 4), spacing: Spacing.s)], spacing: Spacing.s) {
            option(code: nil, symbol: catalog.symbolName(for: kind, default: "mappin"), label: String(localized: "Theo loại"))
            ForEach(catalog.items(in: .placeIcon), id: \.code) { item in
                if let symbol = item.symbolName {
                    option(code: item.code, symbol: symbol, label: item.label)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func option(code: String?, symbol: String, label: String) -> some View {
        let isSelected = selection == code
        let color = catalog.color(for: kind, default: .brandPrimary)
        return Button {
            selection = code
        } label: {
            RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous)
                .fill(isSelected ? color : Color(.tertiarySystemFill))
                .frame(width: cell, height: cell)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: cell * 0.42, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .overlay {
                    if code == nil {
                        // Đánh dấu ô "Theo loại" để không nhầm với một icon thường.
                        Image(systemName: "a.circle.fill")
                            .font(.system(size: cell * 0.26))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .offset(x: cell * 0.34, y: -cell * 0.34)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
