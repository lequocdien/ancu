import SwiftUI

struct AccountScreen: View {
    enum Destination: Hashable {
        case eligibility
        case notificationSettings
        case document(LegalDocument)
    }

    @Environment(SessionStore.self) private var session
    @Environment(\.container) private var container
    @AppStorage(BatchingAnalytics.enabledKey) private var sharesUsageData = true
    @State private var path: [Destination] = DebugLaunchOptions.startsEligibilityWizard ? [.eligibility] : []
    @State private var viewModel: AccountViewModel?
    @State private var signInReason: SignInReason?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                MeshBackground()
                List {
                    Section { profileHeader }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                    Section { eligibilityCard }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                    Section {
                        NavigationLink(value: Destination.notificationSettings) {
                            Label("Cài đặt thông báo", systemImage: "bell.badge")
                        }
                        Toggle(isOn: $sharesUsageData) {
                            Label("Chia sẻ dữ liệu sử dụng ẩn danh", systemImage: "chart.bar")
                        }
                    } header: {
                        Text("Cài đặt")
                    } footer: {
                        Text("Giúp cải thiện app: chỉ gồm thao tác chung (mở app, xem, lưu dự án) và thống kê lỗi, gắn với mã cài đặt ngẫu nhiên — không gồm tên, email, vị trí hay câu trả lời kiểm tra điều kiện.")
                    }

                    Section("Thông tin") {
                        ForEach(LegalDocument.allCases) { document in
                            NavigationLink(value: Destination.document(document)) {
                                Label(document.title, systemImage: document.systemImage)
                            }
                        }
                        // App Store yêu cầu thông tin liên hệ nhà phát triển với app có nội dung người dùng tạo.
                        Link(destination: URL(string: "mailto:hotro@ancu.vn")!) {
                            Label("Liên hệ: hotro@ancu.vn", systemImage: "envelope")
                        }
                    }

                    if session.isSignedIn, let viewModel {
                        Section {
                            Button {
                                Task { await viewModel.signOut() }
                            } label: {
                                Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .disabled(viewModel.isSigningOut)

                            Button(role: .destructive) {
                                viewModel.requestDelete()
                            } label: {
                                Label("Xóa tài khoản", systemImage: "trash")
                                    .foregroundStyle(.red)
                            }
                        } footer: {
                            Text("Xóa tài khoản sẽ xóa vĩnh viễn danh sách đã lưu và cài đặt thông báo.")
                        }
                    }

                    Section {
                        EmptyView()
                    } footer: {
                        Text(verbatim: "An Cư · Phiên bản 0.1 (prototype, dữ liệu mẫu)")
                            .frame(maxWidth: .infinity)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tài khoản")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .eligibility:
                    EligibilityWizard(viewModel: EligibilityViewModel(container: container))
                case .notificationSettings:
                    NotificationSettingsView(isSignedIn: session.isSignedIn, repository: container.notifications)
                case .document(let document):
                    LegalDocumentView(document: document)
                }
            }
        }
        .signInPrompt($signInReason)
        .task { if viewModel == nil { viewModel = AccountViewModel(session: session) } }
        .modifier(DeleteAccountFlow(viewModel: viewModel))
    }

    private var profileHeader: some View {
        GlassCard {
            AdaptiveStack {
                Image(systemName: session.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityHidden(true)

                if let user = session.user {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: user.displayName).font(.headline)
                        // Chỉ icon mang màu: chữ xanh/vàng trên nền sáng không đủ tương phản.
                        if user.isPhoneVerified {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.statusOpen)
                                Text("Đã xác thực SĐT \(user.maskedPhone ?? "")")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            // TODO(backend): OTP qua Supabase Auth (bắt buộc trước khi bình luận — NĐ 147).
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(Color.statusSoon)
                                Text("Chưa xác thực số điện thoại")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Bạn đang dùng chế độ khách").font(.headline)
                        Button("Đăng nhập") { signInReason = .tracking }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var eligibilityCard: some View {
        Button {
            path.append(.eligibility)
        } label: {
            GlassCard(style: .tinted(.brandPrimary)) {
                AdaptiveStack {
                    Image(systemName: "checklist")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Kiểm tra điều kiện mua NOXH").font(.headline)
                        Text("4 câu hỏi · khoảng 1 phút · không lưu câu trả lời").font(.caption)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Xóa tài khoản: confirmationDialog (giải thích) → alert (xác nhận cuối, không hoàn tác).
private struct DeleteAccountFlow: ViewModifier {
    let viewModel: AccountViewModel?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Xóa tài khoản?",
                isPresented: binding(for: .explaining),
                titleVisibility: .visible
            ) {
                Button("Tiếp tục", role: .destructive) { viewModel?.continueDelete() }
                Button("Hủy", role: .cancel) { viewModel?.cancelDelete() }
            } message: {
                Text("Danh sách dự án đã lưu, cài đặt thông báo và thông tin đăng nhập sẽ bị xóa khỏi máy chủ.")
            }
            .alert("Xóa vĩnh viễn?", isPresented: binding(for: .finalConfirm)) {
                Button("Xóa vĩnh viễn", role: .destructive) { Task { await viewModel?.confirmDelete() } }
                Button("Hủy", role: .cancel) { viewModel?.cancelDelete() }
            } message: {
                Text("Thao tác này không thể hoàn tác.")
            }
            .alert("Đã xóa tài khoản", isPresented: binding(for: .deleted)) {
                Button("Đóng", role: .cancel) { viewModel?.cancelDelete() }
            }
            .overlay {
                if viewModel?.deleteStep == .deleting {
                    ProgressView("Đang xóa…")
                        .padding(Spacing.xl)
                        .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
            .alert(
                "Không thực hiện được",
                isPresented: Binding(get: { viewModel?.error != nil }, set: { if !$0 { viewModel?.error = nil } })
            ) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text("Kiểm tra kết nối và thử lại.")
            }
    }

    private func binding(for step: AccountViewModel.DeleteStep) -> Binding<Bool> {
        Binding(
            get: { viewModel?.deleteStep == step },
            set: { isPresented in
                // Đóng dialog bằng cách vuốt/bấm ngoài = hủy, trừ khi đã chuyển sang bước kế.
                if !isPresented, viewModel?.deleteStep == step { viewModel?.cancelDelete() }
            }
        )
    }
}

#Preview {
    AccountScreen()
        .environment(SessionStore(container: .preview))
}
