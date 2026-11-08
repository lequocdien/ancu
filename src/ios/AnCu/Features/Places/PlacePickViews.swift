import SwiftUI

/// Ghim đang chọn — gắn vào tọa độ (Annotation, anchor `.bottom`: mũi ghim là điểm chọn). Nhấc lên khi đang kéo.
struct PlacePickPin: View {
    let catalog: LookupCatalog
    var isLifted = false
    @ScaledMetric(relativeTo: .body) private var stem: CGFloat = 12

    var body: some View {
        let color = catalog.color(for: PlaceKind.other, default: .brandPrimary)
        VStack(spacing: 0) {
            SavedPlacePinView(kind: .other, catalog: catalog)
            Rectangle()
                .fill(color)
                .frame(width: 2, height: stem)
            Ellipse()
                .fill(.black.opacity(0.25))
                .frame(width: 10, height: 4)
        }
        .scaleEffect(isLifted ? 1.2 : 1, anchor: .bottom)
        .animation(.snappy(duration: 0.15), value: isLifted)
        // Vùng chạm rộng hơn ghim (≥ 44pt) để dễ bắt khi kéo.
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("Ghim vị trí đã chọn"))
        .accessibilityHint(Text("Kéo để đổi vị trí, hoặc dùng nút Đưa ghim vào giữa"))
    }
}

/// Gợi ý trên cùng khi đang chọn vị trí.
struct PlacePickHint: View {
    var body: some View {
        Label("Kéo ghim để chỉnh vị trí", systemImage: "hand.draw")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .adaptiveGlass(in: Capsule())
    }
}

/// Thẻ dưới đáy: tên, trạng thái vùng, Hủy / Lưu tại đây.
struct PlacePickCard: View {
    let pick: PlacePick
    let catalog: LookupCatalog
    let onCancel: () -> Void
    /// Đưa ghim về giữa màn hình (ghim trôi khỏi màn hình sau khi kéo/zoom; cách chỉnh cho VoiceOver).
    var onRecenter: () -> Void = {}
    let onSave: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top, spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: pick.name ?? String(localized: "Vị trí đã chọn"))
                            .font(.headline)
                            .lineLimit(2)
                        status
                    }
                    Spacer(minLength: 0)
                    Button(action: onRecenter) {
                        Image(systemName: "scope")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityLabel(Text("Đưa ghim vào giữa màn hình"))
                }
                HStack(spacing: Spacing.s) {
                    Button("Hủy", action: onCancel)
                        .controlSize(.large)
                        .adaptiveGlassButton()
                    PrimaryButton(title: "Lưu tại đây", systemImage: "mappin.and.ellipse", action: onSave)
                        .disabled(!pick.canSave)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var status: some View {
        if pick.isCheckingArea {
            HStack(spacing: Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("Đang kiểm tra khu vực…")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let area = pick.area {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label {
                    Text("Trong khu vực \(catalog.label(for: area))")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.statusOpen)
                }
                .font(.subheadline)
                addressLine
            }
        } else {
            Label {
                Text("Ngoài khu vực hỗ trợ — kéo ghim vào một tỉnh có trong hàng chọn vùng.")
            } icon: {
                Image(systemName: "mappin.slash").foregroundStyle(Color.brandAccent)
            }
            .font(.subheadline)
        }
    }

    /// Địa chỉ theo vị trí ghim hiện tại — cập nhật mỗi khi dừng kéo bản đồ.
    @ViewBuilder
    private var addressLine: some View {
        if pick.needsResolvedAddress && pick.isResolvingAddress {
            Text("Đang tìm địa chỉ…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let address = pick.currentAddress {
            Label {
                Text(verbatim: address).lineLimit(2)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Địa chỉ: \(address)"))
        } else {
            Text("Chưa xác định được địa chỉ — vẫn lưu được.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
