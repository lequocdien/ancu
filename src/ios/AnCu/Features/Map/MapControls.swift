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
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
    let isSearching: Bool
    let failed: Bool
    let catalog: LookupCatalog
    let isAvailable: (AdministrativeUnit) -> Bool
    let onSelect: (SearchResult) -> Void

    var body: some View {
        GlassCard(padding: Spacing.s) {
            if isSearching && results.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(Spacing.m)
            } else if failed {
                message("Không tìm được lúc này. Kiểm tra kết nối và thử lại.", systemImage: "wifi.exclamationmark")
            } else if results.isEmpty && comingSoonAreas.isEmpty {
                message("Không tìm thấy kết quả", systemImage: "magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { result in
                            row(for: result)
                        }
                        ForEach(comingSoonAreas, id: \.code) { area in
                            comingSoonRow(title: area.label, subtitle: nil)
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
