import SwiftUI

/// Ghi chú riêng cho dự án trong An Cư (`bookmarks.note`, RPC `set_bookmark_note`). Chưa lưu dự án → tự lưu khi có ghi chú.
struct BookmarkNoteSheet: View {
    let project: Project

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var isSaving = false
    @State private var error: RepositoryError?
    @FocusState private var isFocused: Bool

    init(project: Project, initialNote: String?) {
        self.project = project
        _note = State(initialValue: initialNote ?? "")
    }

    private var isTooLong: Bool { note.trimmingCharacters(in: .whitespacesAndNewlines).count > SavedPlace.maxNoteLength }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ví dụ: hỏi lại chủ đầu tư về tiến độ, cách chỗ làm 5 km", text: $note, axis: .vertical)
                        .lineLimit(5...12)
                        .focused($isFocused)
                } header: {
                    Text(verbatim: project.name)
                } footer: {
                    Text("\(note.count)/\(SavedPlace.maxNoteLength) ký tự · chỉ bạn thấy ghi chú này.")
                        .foregroundStyle(isTooLong ? Color.brandAccent : .secondary)
                }
                if error != nil {
                    Section {
                        Label("Không lưu được. Kiểm tra kết nối và thử lại — nội dung bạn nhập vẫn còn.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.brandAccent)
                    }
                }
            }
            .navigationTitle("Ghi chú")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Lưu") { Task { await save() } }
                            .disabled(isTooLong)
                    }
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            // Chưa đăng nhập không mở được sheet này (ProjectDetailSheet hiện prompt trước).
            if try await session.setNote(note, for: project.id) { dismiss() }
        } catch {
            self.error = error
        }
    }
}

/// Khối "Ghi chú của bạn" trong sheet chi tiết dự án.
struct BookmarkNoteRow: View {
    let note: String?
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "note.text")
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(note == nil ? "Thêm ghi chú" : "Ghi chú của bạn")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: note ?? String(localized: "Chỉ bạn thấy — giá đã hỏi, ấn tượng khi xem nhà mẫu…"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
