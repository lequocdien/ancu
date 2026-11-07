import SwiftUI

struct TrackingScreen: View {
    @State private var viewModel: TrackingViewModel
    @State private var detailProject: Project?
    @State private var showsComparison = false
    @State private var compareLimitHit = false

    @Environment(SessionStore.self) private var session
    @Environment(\.container) private var container
    @Environment(\.analytics) private var analytics

    init(viewModel: TrackingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeshBackground()
                if session.isSignedIn {
                    signedInContent
                } else {
                    ScrollView {
                        GlassCard(padding: Spacing.xl) {
                            SignInPromptView(reason: .tracking)
                        }
                        .padding(Spacing.l)
                    }
                }
            }
            .navigationTitle("Theo dõi")
            .onChange(of: viewModel.isComparing) { _, comparing in
                if comparing { analytics.track(AnalyticsEvent(name: AnalyticsEvent.compareOpened)) }
            }
            .toolbar { toolbar }
            .navigationDestination(isPresented: $showsComparison) {
                CompareView(viewModel: viewModel)
            }
        }
        .task(id: session.savedProjectIDs) {
            await viewModel.loadSaved(ids: session.savedProjectIDs)
        }
        .task(id: session.isSignedIn) {
            if session.isSignedIn { await viewModel.loadInbox() } else { viewModel.endComparing() }
        }
        .sheet(item: $detailProject) { project in
            ProjectDetailSheet(viewModel: ProjectDetailViewModel(project: project, container: container), catalog: viewModel.catalog)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.warning, trigger: compareLimitHit) { _, hit in hit }
    }

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Picker("Mục", selection: $viewModel.segment) {
                    Text("Đã lưu").tag(TrackingViewModel.Segment.saved)
                    Text(viewModel.unreadCount > 0 ? "Thông báo (\(viewModel.unreadCount))" : "Thông báo")
                        .tag(TrackingViewModel.Segment.inbox)
                }
                .pickerStyle(.segmented)

                switch viewModel.segment {
                case .saved: savedList
                case .inbox: InboxView(viewModel: viewModel)
                }
            }
            .padding(Spacing.l)
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isComparing && viewModel.segment == .saved {
                PrimaryButton(
                    title: "So sánh \(viewModel.compareSelection.count)/\(TrackingViewModel.maxCompare) dự án",
                    systemImage: "rectangle.split.3x1"
                ) {
                    showsComparison = true
                }
                .disabled(!viewModel.canCompare)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.s)
            }
        }
    }

    @ViewBuilder
    private var savedList: some View {
        switch viewModel.savedState {
        case .idle, .loading:
            if viewModel.savedProjects.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    GlassCard { SavedProjectCard.placeholder }
                }
                .redacted(reason: .placeholder)
            } else {
                savedCards
            }
        case .failed where viewModel.savedProjects.isEmpty:
            ContentUnavailableView {
                Label("Không tải được danh sách", systemImage: "wifi.exclamationmark")
            } actions: {
                Button("Thử lại") { Task { await viewModel.loadSaved(ids: session.savedProjectIDs) } }
            }
        case .failed, .loaded:
            if viewModel.savedProjects.isEmpty {
                ContentUnavailableView(
                    "Chưa lưu dự án nào",
                    systemImage: "bookmark",
                    description: Text("Bấm Lưu ở chi tiết dự án trên bản đồ để theo dõi hạn nộp hồ sơ.")
                )
            } else {
                savedCards
            }
        }
    }

    @ViewBuilder
    private var savedCards: some View {
        if viewModel.isComparing {
            Text("Chọn 2–3 dự án để so sánh")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        LazyVStack(spacing: Spacing.m) {
            ForEach(viewModel.savedProjects) { project in
                savedCard(project)
            }
        }
    }

    private func savedCard(_ project: Project) -> some View {
        let isSelected = viewModel.isSelectedForCompare(project.id)
        return Button {
            if viewModel.isComparing {
                if !viewModel.toggleCompare(project.id) { compareLimitHit.toggle() }
            } else {
                detailProject = project
            }
        } label: {
            GlassCard {
                HStack(alignment: .top, spacing: Spacing.m) {
                    if viewModel.isComparing {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.brandPrimary : .secondary)
                    }
                    SavedProjectCard(
                        project: project,
                        catalog: viewModel.catalog,
                        phase: viewModel.phase(of: project),
                        elapsedFraction: viewModel.elapsedFraction(of: project),
                        isNotifying: session.isNotifying(project.id)
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(role: .destructive) {
                Task { _ = try? await session.toggleSave(project.id) }
            } label: {
                Label("Bỏ lưu", systemImage: "bookmark.slash")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if session.isSignedIn && viewModel.segment == .saved && viewModel.savedProjects.count >= 2 {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.isComparing ? "Xong" : "So sánh") {
                    if viewModel.isComparing { viewModel.endComparing() } else { viewModel.isComparing = true }
                }
            }
        }
    }
}

struct SavedProjectCard: View {
    let project: Project
    let catalog: LookupCatalog
    let phase: ApplicationPhase
    let elapsedFraction: Double?
    let isNotifying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .top) {
                StatusBadge(project.status, catalog: catalog)
                Spacer(minLength: 0)
                if isNotifying {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(Color.brandPrimary)
                        .accessibilityLabel(Text("Đang bật thông báo"))
                }
            }
            Text(verbatim: project.name).font(.headline)
            Text(verbatim: project.address).font(.subheadline).foregroundStyle(.secondary)

            HStack {
                Label {
                    Text(verbatim: DisplayFormat.phase(phase))
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer()
                if let price = project.price {
                    Text(verbatim: DisplayFormat.price(price))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let elapsedFraction {
                ProgressView(value: elapsedFraction)
                    .tint(Color.statusOpen)
                    .accessibilityLabel(Text("Thời gian nhận hồ sơ đã qua"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static var placeholder: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(verbatim: "Đang nhận hồ sơ").font(.caption)
            Text(verbatim: "NOXH Tên dự án mẫu").font(.headline)
            Text(verbatim: "Phường mẫu, TP.HCM").font(.subheadline)
            Text(verbatim: "Còn 12 ngày").font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Khách") {
    TrackingScreen(viewModel: TrackingViewModel(container: .preview))
        .environment(SessionStore(container: .preview))
}
