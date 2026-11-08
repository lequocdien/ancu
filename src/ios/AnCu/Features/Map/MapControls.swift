import SwiftUI

// Lớp kính nổi trên map (spec mục 6, "Áp dụng theo màn hình"). Mọi hiệu ứng kính đi qua DesignSystem.

/// Thanh tìm kiếm nổi: capsule kính.
struct MapSearchBar: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Tìm dự án, phường/xã, tên cũ…", text: $query)
                .focused(isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    // Vùng chạm 44×44 (HIG) — chỉ có icon ~17pt thì gần như bấm không trúng.
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Bù lại để thanh tìm kiếm không cao/rộng thêm vì vùng chạm lớn.
                .padding(.vertical, -Spacing.m)
                .padding(.trailing, -Spacing.m)
                .accessibilityLabel(Text("Xóa từ khóa"))
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .adaptiveGlass(.regular, in: Capsule())
    }
}

/// Chip bật/tắt (lớp tuyến, vùng, bộ lọc). Đang bật = kính tint brand.
struct MapChip: View {
    let title: Text
    var systemImage: String?
    let isOn: Bool
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isOn && differentiateWithoutColor {
                    Image(systemName: "checkmark").imageScale(.small)
                } else if let systemImage {
                    Image(systemName: systemImage).imageScale(.small)
                }
                title
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .adaptiveGlass(isOn ? .tinted(Color.brandPrimary.opacity(0.6)).interactive() : .interactive, in: Capsule())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Kết quả tìm kiếm. Một card kính duy nhất, các dòng bên trong không dùng kính.
struct MapSearchResults: View {
    let results: [SearchResult]
    let comingSoonAreas: [LookupItem]
    /// Nhóm "Địa điểm khác" (Apple Maps, PRD 4.6). Rỗng → không hiện nhóm.
    var places: [PlaceResult] = []
    let isSearching: Bool
    let failed: Bool
    let catalog: LookupCatalog
    let isAvailable: (AdministrativeUnit) -> Bool
    let onSelect: (SearchResult) -> Void
    var onSelectPlace: (PlaceCandidate) -> Void = { _ in }

    var body: some View {
        GlassCard(padding: Spacing.s) {
            if isSearching && results.isEmpty && places.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(Spacing.m)
            } else if failed && places.isEmpty {
                message("Không tìm được lúc này. Kiểm tra kết nối và thử lại.", systemImage: "wifi.exclamationmark")
            } else if results.isEmpty && comingSoonAreas.isEmpty && places.isEmpty {
                VStack(spacing: Spacing.xs) {
                    message("Không tìm thấy kết quả", systemImage: "magnifyingglass")
                    pinHint
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Dự án trong An Cư luôn đứng trên: lưu chúng mới nhận được thông báo.
                        if !places.isEmpty && !(results.isEmpty && comingSoonAreas.isEmpty) {
                            sectionHeader("Trong An Cư")
                        }
                        ForEach(results) { result in
                            row(for: result)
                        }
                        ForEach(comingSoonAreas, id: \.code) { area in
                            comingSoonRow(title: area.label, subtitle: nil)
                        }
                        if !places.isEmpty {
                            sectionHeader("Địa điểm khác · lưu riêng cho bạn")
                            ForEach(places) { place in
                                placeRow(place)
                            }
                            pinHint
                        }
                    }
                }
                .frame(maxHeight: 320)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    @ViewBuilder
    private func row(for result: SearchResult) -> some View {
        switch result {
        case .project(let project):
            Button {
                onSelect(result)
            } label: {
                HStack(spacing: Spacing.m) {
                    Image(systemName: catalog.symbolName(for: project.status, default: "house.fill"))
                        .foregroundStyle(catalog.color(for: project.status))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: project.name).font(.body.weight(.medium))
                        Text(verbatim: project.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .place(let unit):
            if isAvailable(unit) {
                Button {
                    onSelect(result)
                } label: {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary).frame(width: 24)
                        placeText(unit)
                        Spacer(minLength: 0)
                    }
                    .padding(Spacing.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                comingSoonRow(title: unit.name, subtitle: unit.oldNames.first.map { "Trước đây: \($0)" })
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, Spacing.s)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    /// Ngoài vùng MVP: hiện mờ + nhãn, không bấm được (PRD 4.6) — người dùng hiểu vì sao, không tưởng lỗi.
    @ViewBuilder
    private func placeRow(_ place: PlaceResult) -> some View {
        let candidate = place.candidate
        let content = HStack(spacing: Spacing.m) {
            Image(systemName: place.isAvailable ? "plus.circle" : "nosign")
                .foregroundStyle(place.isAvailable ? Color.brandPrimary : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: candidate.name).font(.body.weight(.medium))
                    .foregroundStyle(place.isAvailable ? .primary : .secondary)
                if place.isAvailable {
                    if let address = candidate.address {
                        Text(verbatim: address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text("Ngoài khu vực hỗ trợ").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .contentShape(Rectangle())

        if place.isAvailable {
            Button { onSelectPlace(candidate) } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Lưu địa điểm này kèm ghi chú"))
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("Địa điểm nằm ngoài các tỉnh An Cư hỗ trợ, chưa lưu được"))
        }
    }

    private var pinHint: some View {
        Label("Không thấy? Nhấn giữ trên bản đồ để tự ghim", systemImage: "hand.tap")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(Spacing.s)
    }

    private func placeText(_ unit: AdministrativeUnit) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: unit.name).font(.body.weight(.medium))
            // Hiện tên cũ để người dùng nhận ra địa danh quen thuộc sau sáp nhập.
            let old = unit.oldNames.isEmpty ? "" : " · trước đây \(unit.oldNames.joined(separator: ", "))"
            Text(verbatim: unit.province + old).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func comingSoonRow(title: String, subtitle: String?) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "clock").foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: title).font(.body.weight(.medium)).foregroundStyle(.secondary)
                if let subtitle { Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Text("Sắp có")
                .font(.badge)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xxs)
                .background(Color.statusClosed.opacity(0.2), in: Capsule())
        }
        .padding(Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: LocalizedStringKey, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(Spacing.m)
    }
}
