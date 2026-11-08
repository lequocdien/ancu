import SwiftUI

/// Sheet lưu / sửa địa điểm ngoài hệ thống (PRD 4.6). Form hệ thống — nền đặc, không kính.
struct PlaceEditorSheet: View {
    @State private var viewModel: PlaceEditorViewModel
    let catalog: LookupCatalog
    /// Người dùng chọn theo dõi dự án có sẵn trong An Cư thay vì lưu riêng.
    var onOpenProject: (Project) -> Void = { _ in }
    /// Lưu / xóa xong (không gọi khi bấm Hủy).
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics
    @State private var confirmsDelete = false
    @State private var pendingSuggestionAlert = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, note }

    init(
        viewModel: PlaceEditorViewModel, catalog: LookupCatalog,
        onOpenProject: @escaping (Project) -> Void = { _ in }, onSaved: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.catalog = catalog
        self.onOpenProject = onOpenProject
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.isOutsideServiceArea {
                    outsideAreaSection
                } else if let project = viewModel.nearbyProject {
                    duplicateSection(project)
                }

                Section {
                    TextField("Tên dự án hoặc địa điểm", text: $viewModel.name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .note }
                    if let address = viewModel.address {
                        LabeledContent("Địa chỉ") {
                            Text(verbatim: address).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
                    Picker("Loại", selection: $viewModel.kind) {
                        ForEach(catalog.orderedCases(PlaceKind.self), id: \.self) { kind in
                            Text(verbatim: catalog.label(for: kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l, bottom: Spacing.s, trailing: Spacing.l))
                }

                Section("Icon") {
                    PlaceIconPicker(selection: $viewModel.icon, kind: viewModel.kind, catalog: catalog)
                }

                Section {
                    TextField("Ví dụ: giá 45 tr/m², đã xem nhà mẫu, cách chỗ làm 8 km", text: $viewModel.note, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focusedField, equals: .note)
                } header: {
                    Text("Ghi chú")
                } footer: {
                    Text("\(viewModel.noteCount)/\(SavedPlace.maxNoteLength) ký tự · chỉ bạn thấy ghi chú này.")
                        .foregroundStyle(viewModel.isNoteTooLong ? Color.brandAccent : .secondary)
                }

                if viewModel.canSuggest {
                    Section {
                        Toggle("Đề xuất An Cư thêm dự án này", isOn: $viewModel.suggestsToAnCu)
                    } footer: {
                        Text("Gửi tên, địa chỉ và vị trí để đội dữ liệu xác minh. Ghi chú của bạn không được gửi.")
                    }
                }

                if case .failed(let error) = viewModel.saveState {
                    Section {
                        Label(Self.message(for: error), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.brandAccent)
                    }
                }

                if viewModel.isEditing {
                    Section {
                        Button("Xóa địa điểm", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Sửa địa điểm" : "Lưu địa điểm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.saveState == .saving {
                        ProgressView()
                    } else {
                        Button("Lưu") { Task { await save() } }
                            .disabled(!viewModel.canSave)
                    }
                }
            }
            .task { await viewModel.load() }
            .onAppear { if viewModel.name.isEmpty { focusedField = .name } }
            .confirmationDialog("Xóa địa điểm này?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Xóa", role: .destructive) {
                    Task { if await viewModel.delete() { onSaved(); dismiss() } }
                }
            } message: {
                Text("Ghi chú đi kèm cũng bị xóa.")
            }
            .alert("Đã lưu địa điểm", isPresented: $pendingSuggestionAlert) {
                Button("Đóng") { onSaved(); dismiss() }
            } message: {
                Text(suggestionFailureMessage)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Phần

    private var outsideAreaSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Ngoài khu vực hỗ trợ").font(.subheadline.weight(.semibold))
                    Text("Địa điểm này nằm ngoài các tỉnh An Cư đang hỗ trợ nên chưa lưu được.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "mappin.slash").foregroundStyle(Color.brandAccent)
            }
        }
    }

    private func duplicateSection(_ project: Project) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Dự án này đã có trong An Cư?").font(.subheadline.weight(.semibold))
                        Text("\(project.name) ở gần đây. Theo dõi dự án để nhận thông báo khi mở nhận hồ sơ.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill").foregroundStyle(Color.brandPrimary)
                }
                Button("Xem dự án \(project.name)") {
                    dismiss()
                    onOpenProject(project)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, Spacing.xxs)
        } footer: {
            Text("Vẫn muốn lưu riêng? Điền thông tin bên dưới.")
        }
    }

    // MARK: Hành động

    private func save() async {
        guard await viewModel.save() else { return }
        switch viewModel.suggestionOutcome {
        case .sent:
            analytics.track(AnalyticsEvent(name: AnalyticsEvent.projectSuggested))
            onSaved()
            dismiss()
        case .failed:
            pendingSuggestionAlert = true
        case nil:
            onSaved()
            dismiss()
        }
    }

    private var suggestionFailureMessage: LocalizedStringKey {
        if case .failed(.rateLimited) = viewModel.suggestionOutcome {
            return "Chưa gửi được đề xuất: bạn đã gửi tối đa 10 lần trong 24 giờ."
        }
        return "Chưa gửi được đề xuất. Bạn có thể thử lại sau."
    }

    static func message(for error: RepositoryError) -> LocalizedStringKey {
        switch error {
        case .outsideServiceArea: "Ngoài khu vực hỗ trợ — địa điểm phải thuộc một tỉnh An Cư đang hỗ trợ."
        case .limitReached: "Bạn đã lưu tối đa \(SavedPlace.maxCount) địa điểm. Xóa bớt để lưu thêm."
        case .unauthorized: "Phiên đăng nhập đã hết. Hãy đăng nhập lại."
        case .decoding: "Kiểm tra lại tên (tối đa \(SavedPlace.maxNameLength) ký tự) và ghi chú."
        case .notFound: "Địa điểm này không còn tồn tại."
        case .rateLimited, .network: "Không lưu được. Kiểm tra kết nối và thử lại — nội dung bạn nhập vẫn còn."
        }
    }
}
