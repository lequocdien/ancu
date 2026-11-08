import SwiftUI

/// Sheet chi tiết dự án. Dùng sheet mặc định (iOS 26 tự là kính ở detent thấp) — KHÔNG set presentationBackground.
/// Bên trong sheet: khối nền đặc, không kính (tránh glass-on-glass).
struct ProjectDetailSheet: View {
    @State private var viewModel: ProjectDetailViewModel
    let catalog: LookupCatalog

    @Environment(SessionStore.self) private var session
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var signInReason: SignInReason?
    @State private var showsReportForm = false
    @State private var showsNoteEditor = false
    @State private var actionError: RepositoryError?

    init(viewModel: ProjectDetailViewModel, catalog: LookupCatalog) {
        _viewModel = State(initialValue: viewModel)
        self.catalog = catalog
    }

    private var project: Project { viewModel.project }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                actions
                BookmarkNoteRow(note: session.note(for: project.id)) {
                    if session.isSignedIn { showsNoteEditor = true } else { signInReason = .savePlace }
                }
                metrics
                connectivity
                sourceInfo
                scamWarning
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .task { await viewModel.load() }
        .signInPrompt($signInReason)
        .sheet(isPresented: $showsReportForm) {
            ReportDataSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showsNoteEditor) {
            BookmarkNoteSheet(project: project, initialNote: session.note(for: project.id))
        }
        .alert("Không thực hiện được", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Kiểm tra kết nối và thử lại.")
        }
    }

    // MARK: Phần

    private var header: some View {
        AdaptiveStack(verticalAlignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: project.name)
                    .font(.title3.weight(.bold))
                Text(verbatim: project.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            StatusBadge(project.status, catalog: catalog)
        }
    }

    private var actions: some View {
        let isSaved = session.isSaved(project.id)
        let isNotifying = session.isNotifying(project.id)
        let isPending = session.pendingProjectIDs.contains(project.id)
        return AdaptiveStack(spacing: Spacing.s) {
            Button {
                Task { await toggleSave() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .symbolEffect(.bounce, value: isSaved)
                    Text(isSaved ? "Đã lưu" : "Lưu")
                }
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            }
            .controlSize(.large)
            .adaptiveGlassButton()
            .accessibilityAddTraits(isSaved ? .isSelected : [])

            PrimaryButton(
                title: isNotifying ? "Đang theo dõi" : "Bật thông báo",
                systemImage: isNotifying ? "bell.fill" : "bell"
            ) {
                Task { await toggleNotify(currentlyOn: isNotifying) }
            }
            .sensoryFeedback(.success, trigger: isNotifying) { _, new in new }
        }
        .disabled(isPending)
    }

    /// 2×2 ở cỡ chữ thường; 1 cột ở cỡ chữ accessibility.
    @ViewBuilder
    private var metrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Spacing.s) {
                priceTile
                unitsTile
                legalTile
                windowTile
            }
        } else {
            Grid(horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
                GridRow {
                    priceTile
                    unitsTile
                }
                GridRow {
                    legalTile
                    windowTile
                }
            }
        }
    }

    private var priceTile: some View {
        MetricTile(
            title: "Giá tham khảo",
            value: project.price.map(DisplayFormat.price) ?? String(localized: "Chưa công bố"),
            systemImage: "tag",
            caption: project.price?.isEstimated == true ? String(localized: "Giá dự kiến") : nil
        )
    }

    private var unitsTile: some View {
        MetricTile(title: "Số căn", value: project.unitCount.map(DisplayFormat.number) ?? "—", systemImage: "building.2")
    }

    private var legalTile: some View {
        MetricTile(title: "Pháp lý", value: catalog.label(for: project.legalStatus), systemImage: "checkmark.seal")
    }

    private var windowTile: some View {
        MetricTile(
            title: "Nhận hồ sơ",
            value: DisplayFormat.phase(viewModel.phase),
            systemImage: "calendar",
            caption: project.applicationWindow.map(DisplayFormat.dateRange)
        )
    }

    private var connectivity: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Kết nối giao thông").font(.sectionTitle)

            switch viewModel.detailState {
            case .loading:
                ForEach(0..<2, id: \.self) { _ in
                    InfraRow(name: "Ga Metro mẫu", detail: "Tuyến mẫu · 2027", distance: "1,2 km", systemImage: "tram.fill")
                }
                .redacted(reason: .placeholder)
            case .failed:
                Button("Không tải được. Thử lại") {
                    Task { await viewModel.load() }
                }
                .font(.subheadline)
            case .loaded:
                if viewModel.nearestInfra.isEmpty {
                    Text("Chưa có ga hoặc nút giao trong dữ liệu.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.nearestInfra, id: \.node.id) { infra in
                        InfraRow(
                            name: infra.node.name,
                            detail: infraDetail(infra),
                            distance: DisplayFormat.distance(infra.distanceMeters),
                            systemImage: Self.symbol(for: infra.node.type)
                        )
                    }
                }
            }

            Text("Khoảng cách đường chim bay")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var sourceInfo: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if viewModel.isStale {
                Label("Thông tin có thể đã cũ", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.statusSoon)
            }
            HStack(spacing: Spacing.xs) {
                Text("Nguồn:")
                Link(project.sourceURL.host() ?? project.sourceURL.absoluteString, destination: project.sourceURL)
                    .lineLimit(1)
                Text(verbatim: "·")
                Text("Cập nhật: \(DisplayFormat.date(project.verifiedAt))")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                if session.isSignedIn {
                    viewModel.resetReport()
                    showsReportForm = true
                } else {
                    signInReason = .report
                }
            } label: {
                Label("Báo thông tin sai", systemImage: "flag")
                    .font(.footnote.weight(.medium))
            }
        }
    }

    /// Banner cố định: nền đặc brandAccent 12%, KHÔNG kính.
    private var scamWarning: some View {
        Label {
            Text("NOXH không có suất ngoại giao — cẩn trọng lời mời mua suất.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(Color.brandAccent)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    // MARK: Hành động

    private func toggleSave() async {
        do {
            if try await session.toggleSave(project.id) == .savedLocallyNeedsPrompt {
                signInReason = .savedLocally
            }
        } catch {
            actionError = error
        }
    }

    private func toggleNotify(currentlyOn: Bool) async {
        do {
            if try await !session.setNotify(!currentlyOn, for: project.id) {
                signInReason = .notifications
            }
        } catch {
            actionError = error
        }
    }

    private func infraDetail(_ infra: NearestInfra) -> String {
        var parts: [String] = []
        if let routeName = infra.routeName { parts.append(routeName) }
        // Ga chưa có vị trí chính xác → khoảng cách chỉ là ước tính.
        switch infra.node.geometryAccuracy {
        case .exact: break
        case .approximate: parts.append(String(localized: "vị trí ga gần đúng"))
        case .illustrative: parts.append(String(localized: "vị trí ga minh họa"))
        }
        if let status = infra.routeStatus { parts.append(catalog.label(for: status)) }
        if let year = infra.expectedYear {
            // Tuyến đã chạy thì năm là mốc đã qua, không phải "dự kiến".
            parts.append(infra.routeStatus == .operational
                ? String(localized: "Khai thác từ \(String(year))")
                : String(localized: "Dự kiến \(String(year))"))
        }
        return parts.joined(separator: " · ")
    }

    private static func symbol(for type: NodeType) -> String {
        switch type {
        case .metroStation: "tram.fill"
        case .interchange: "road.lanes"
        case .keyLandmark: "airplane"
        case .unknown: "mappin"
        }
    }
}

private struct InfraRow: View {
    let name: String
    let detail: String
    let distance: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: name).font(.subheadline.weight(.medium))
                if !detail.isEmpty {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Spacing.s)
            Text(verbatim: distance)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

/// Form "Báo thông tin sai" (RPC `report_data`).
struct ReportDataSheet: View {
    @Bindable var viewModel: ProjectDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics

    var body: some View {
        form
            .onChange(of: viewModel.reportState) { _, state in
                if state == .sent { analytics.track(AnalyticsEvent(name: AnalyticsEvent.reportSubmitted)) }
            }
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ví dụ: dự án đã đổi khung nhận hồ sơ sang 01/12", text: $viewModel.reportNote, axis: .vertical)
                        .lineLimit(4...8)
                } header: {
                    Text(verbatim: viewModel.project.name)
                } footer: {
                    Text("\(viewModel.reportNote.count)/\(ProjectDetailViewModel.reportNoteLimit) ký tự. Đội dữ liệu xử lý trong 72 giờ.")
                }

                switch viewModel.reportState {
                case .sent:
                    Label("Đã gửi. Cảm ơn bạn!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusOpen)
                case .failed:
                    Label("Gửi không thành công. Thử lại.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.brandAccent)
                case .idle, .sending:
                    EmptyView()
                }
            }
            .navigationTitle("Báo thông tin sai")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.reportState == .sent ? "Xong" : "Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.reportState == .sending {
                        ProgressView()
                    } else if viewModel.reportState != .sent {
                        Button("Gửi") { Task { await viewModel.submitReport() } }
                            .disabled(!viewModel.canSubmitReport)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
