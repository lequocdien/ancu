import SwiftUI

/// Ghim địa điểm riêng: ô vuông bo góc viền trắng + icon theo loại — khác ghim tròn của dự án NOXH,
/// để nhận ra ngay "của tôi" so với dữ liệu An Cư trên cùng bản đồ.
struct SavedPlacePinView: View {
    let kind: PlaceKind
    /// Mã icon tự chọn (`place_icons`); `nil` / mã lạ → icon theo loại.
    var icon: String? = nil
    let catalog: LookupCatalog
    /// Ghim tạm lúc nhấn giữ, chưa lưu.
    var isDraft = false

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    var body: some View {
        let color = isDraft ? Color.secondary : catalog.color(for: kind, default: .brandPrimary)
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: isDraft ? "mappin" : symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.white, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .padding(.bottom, 2)
    }

    private var symbol: String {
        catalog.placeIconSymbol(icon) ?? catalog.symbolName(for: kind, default: "mappin")
    }
}
