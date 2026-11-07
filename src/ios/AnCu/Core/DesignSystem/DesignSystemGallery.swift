#if DEBUG
import MapKit
import SwiftUI

/// Bảng xem toàn bộ token + component. Mở bằng #Preview, hoặc chạy app với launch argument
/// `-DesignSystemGallery` để chụp màn hình trên Simulator.
struct DesignSystemGallery: View {
    enum Backdrop: Hashable { case mesh, map }

    @State private var backdrop: Backdrop = .mesh
    @State private var enabledLayers: Set<RouteType> = [.metro, .ringRoad]
    @Namespace private var glassNamespace

    private let catalog = LookupCatalog.galleryPreview

    var body: some View {
        ZStack {
            switch backdrop {
            case .mesh: MeshBackground()
            case .map:
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 10.88, longitude: 106.80),
                    span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
                )))
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Picker("Nền", selection: $backdrop) {
                        Text("Mesh").tag(Backdrop.mesh)
                        Text("Map").tag(Backdrop.map)
                    }
                    .pickerStyle(.segmented)

                    section("Màu") { swatches }
                    section("Trạng thái dự án") { badges }
                    section("Chip lớp (kính, morph)") { chips }
                    section("Nút") { buttons }
                    section("Card kính") { cards }
                    section("Trong sheet (nền đặc)") { tiles }
                    section("Kiểu nét tuyến") { routeLines }
                }
                .padding(Spacing.l)
            }
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).font(.sectionTitle)
            content()
        }
    }

    private var swatches: some View {
        let tokens: [(String, Color)] = [
            ("brandPrimary", .brandPrimary), ("brandAccent", .brandAccent),
            ("statusOpen", .statusOpen), ("statusSoon", .statusSoon),
            ("statusClosed", .statusClosed), ("statusBuilding", .statusBuilding),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: Spacing.s) {
            ForEach(tokens, id: \.0) { name, color in
                VStack(spacing: Spacing.xs) {
                    RoundedRectangle(cornerRadius: Radius.control).fill(color).frame(height: 40)
                    Text(verbatim: name).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var badges: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: Spacing.s) {
            ForEach([ProjectStatus.acceptingApplications, .upcoming, .underConstruction, .closed], id: \.self) {
                StatusBadge($0, catalog: catalog)
            }
        }
    }

    private var chips: some View {
        AdaptiveGlassContainer(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ForEach([RouteType.metro, .ringRoad, .expressway, .nationalHighway], id: \.self) { type in
                    let isOn = enabledLayers.contains(type)
                    Button {
                        withAnimation(Motion.snappy) {
                            if isOn { enabledLayers.remove(type) } else { enabledLayers.insert(type) }
                        }
                    } label: {
                        Text(verbatim: catalog.label(for: type))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                    }
                    .buttonStyle(.plain)
                    .adaptiveGlass(isOn ? .tinted(Color.brandPrimary.opacity(0.6)).interactive() : .interactive)
                    .adaptiveGlassID(type, in: glassNamespace)
                }
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: Spacing.m) {
            PrimaryButton(title: "Bật thông báo", systemImage: "bell.fill") {}
            PrimaryButton(title: "Đang gửi", isLoading: true) {}
            HStack {
                Button {} label: { Label("Lưu", systemImage: "bookmark") }
                    .adaptiveGlassButton()
                Button {} label: { Image(systemName: "location.fill") }
                    .adaptiveGlassButton()
            }
        }
    }

    private var cards: some View {
        VStack(spacing: Spacing.m) {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    StatusBadge(.acceptingApplications, catalog: catalog)
                    Text(verbatim: "NOXH Mẫu An Phú").font(.headline)
                    Text(verbatim: "Còn 12 ngày nhận hồ sơ").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            GlassCard(style: .tinted(.brandPrimary)) {
                Label("Kiểm tra điều kiện mua NOXH", systemImage: "checklist").font(.headline)
            }
        }
    }

    private var tiles: some View {
        Grid(horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
            GridRow {
                MetricTile(title: "Giá tham khảo", value: "18,5 tr/m²", systemImage: "tag")
                MetricTile(title: "Số căn", value: "1.200", systemImage: "building.2")
            }
            GridRow {
                MetricTile(title: "Pháp lý", value: "Đủ điều kiện bán", systemImage: "checkmark.seal")
                MetricTile(title: "Nhận hồ sơ", value: "Còn 12 ngày", systemImage: "calendar", caption: "01/12 – 15/12")
            }
        }
    }

    private var routeLines: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach([RouteStatus.operational, .underConstruction, .planned], id: \.self) { status in
                let style = catalog.lineStyle(for: status)
                HStack {
                    Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: 120, y: 0)) }
                        .stroke(Color.routeRing.opacity(style.opacity), style: style.strokeStyle)
                        .frame(width: 120, height: style.lineWidth)
                    Text(verbatim: catalog.label(for: status)).font(.caption)
                }
            }
        }
    }
}

extension LookupCatalog {
    /// Catalog đồng bộ cho preview — không chờ `LookupRepository`.
    static let galleryPreview = LookupCatalog(items: [
        .projectStatus: [
            LookupItem(code: "nhan_ho_so", label: "Đang nhận hồ sơ", sortOrder: 1, colorHex: "#10B981", symbolName: "envelope.open.fill"),
            LookupItem(code: "sap_mo", label: "Sắp mở", sortOrder: 2, colorHex: "#F59E0B", symbolName: "clock.fill"),
            LookupItem(code: "dang_xay", label: "Đang xây dựng", sortOrder: 3, colorHex: "#6366F1", symbolName: "hammer.fill"),
            LookupItem(code: "da_dong", label: "Đã đóng", sortOrder: 4, colorHex: "#94A3B8", symbolName: "lock.fill"),
        ],
        .routeType: [
            LookupItem(code: "metro", label: "Metro", sortOrder: 1),
            LookupItem(code: "vanh_dai", label: "Vành đai", sortOrder: 2),
            LookupItem(code: "cao_toc", label: "Cao tốc", sortOrder: 3),
            LookupItem(code: "quoc_lo", label: "Quốc lộ", sortOrder: 4),
        ],
        .routeStatus: [
            LookupItem(code: "da_khai_thac", label: "Đã khai thác", sortOrder: 1, attributes: ["line_style": "solid"]),
            LookupItem(code: "dang_thi_cong", label: "Đang thi công", sortOrder: 2, attributes: ["line_style": "thin"]),
            LookupItem(code: "quy_hoach", label: "Quy hoạch", sortOrder: 3, attributes: ["line_style": "dashed"]),
        ],
    ])
}

#Preview("Light") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}
#endif
