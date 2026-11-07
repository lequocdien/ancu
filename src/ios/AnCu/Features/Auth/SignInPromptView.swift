import SwiftUI

/// Màn mời đăng nhập: 3 lợi ích + Apple / Google / Facebook (theo cấu hình bản build) + mã qua email.
/// Dùng trong sheet (`.signInPrompt($reason)`) và nhúng trực tiếp ở tab Theo dõi khi là khách.
struct SignInPromptView: View {
    let reason: SignInReason
    var onSignedIn: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @State private var workingProvider: AuthProvider?
    @State private var error: RepositoryError?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Spacing.m) {
                benefit("bookmark.fill", "Giữ danh sách dự án đã lưu khi đổi máy")
                benefit("bell.badge.fill", "Báo ngay khi dự án mở nhận hồ sơ, đổi giá hoặc đổi trạng thái")
                benefit("rectangle.split.3x1.fill", "So sánh 2–3 dự án cạnh nhau")
            }

            if !session.socialProviders.isEmpty {
                VStack(spacing: Spacing.s) {
                    ForEach(session.socialProviders, id: \.self) { provider in
                        switch provider {
                        case .apple:
                            // Nút tự vẽ theo HIG (nền đen/trắng theo giao diện, logo Apple); luồng thật ở `AppleIDCredentialRequest`.
                            providerButton(.apple, title: "Tiếp tục với Apple", systemImage: "applelogo")
                                .buttonStyle(.borderedProminent)
                                .tint(Color(.label))
                                .foregroundStyle(Color(.systemBackground))
                        case .google:
                            providerButton(.google, title: "Tiếp tục với Google", systemImage: "g.circle.fill")
                                .buttonStyle(.bordered)
                        case .facebook:
                            providerButton(.facebook, title: "Tiếp tục với Facebook", systemImage: "f.circle.fill")
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .controlSize(.large)
                .disabled(workingProvider != nil)
            }

            EmailSignInView(session: session, hasOtherOptions: !session.socialProviders.isEmpty, onSignedIn: onSignedIn)

            Text("Bằng việc tiếp tục, bạn đồng ý với Điều khoản sử dụng và Chính sách quyền riêng tư.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert("Không đăng nhập được", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Vui lòng thử lại.")
        }
    }

    private var title: LocalizedStringKey {
        switch reason {
        case .savedLocally: "Đã lưu tạm trên máy này"
        case .notifications: "Đăng nhập để bật thông báo"
        case .savedLayer: "Đăng nhập để xem dự án đã lưu"
        case .tracking: "Theo dõi dự án NOXH"
        case .report: "Đăng nhập để báo thông tin sai"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch reason {
        case .savedLocally: "Đăng nhập để giữ danh sách khi đổi máy và nhận thông báo khi dự án mở nhận hồ sơ."
        case .notifications: "Chúng tôi chỉ gửi thông báo về dự án bạn theo dõi, tối đa 1 lần/ngày mỗi dự án. Không quảng cáo."
        case .savedLayer, .tracking: "Lưu dự án quan tâm, theo dõi hạn nộp hồ sơ và nhận thông báo khi có thay đổi."
        case .report: "Đăng nhập giúp đội dữ liệu liên hệ xác minh khi cần."
        }
    }

    private func benefit(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.brandPrimary)
        }
        .font(.subheadline)
    }

    private func providerButton(_ provider: AuthProvider, title: LocalizedStringKey, systemImage: String) -> some View {
        Button {
            Task { await signIn(provider) }
        } label: {
            HStack(spacing: Spacing.s) {
                if workingProvider == provider {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func signIn(_ provider: AuthProvider) async {
        workingProvider = provider
        defer { workingProvider = nil }
        do {
            if try await session.signIn(with: provider) { onSignedIn() }
        } catch {
            self.error = error
        }
    }
}

extension View {
    /// Trình bày prompt đăng nhập từ chính màn hình gọi (không từ root — xem `SessionStore`).
    func signInPrompt(_ reason: Binding<SignInReason?>) -> some View {
        sheet(item: reason) { current in
            ScrollView {
                SignInPromptView(reason: current) { reason.wrappedValue = nil }
                    .padding(Spacing.xl)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
