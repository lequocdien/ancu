import SwiftUI

/// Form email → mã 6 số, nhúng trong `SignInPromptView`. Nền đặc (nội dung nhập liệu, không dùng kính).
struct EmailSignInView: View {
    @State private var viewModel: EmailSignInViewModel
    /// Có nút Apple/Google/Facebook phía trên → tiêu đề "Hoặc …".
    var hasOtherOptions = true
    var onSignedIn: () -> Void
    @FocusState private var focused: Field?

    private enum Field { case email, code }

    init(session: SessionStore, hasOtherOptions: Bool = true, onSignedIn: @escaping () -> Void) {
        _viewModel = State(initialValue: EmailSignInViewModel(session: session))
        self.hasOtherOptions = hasOtherOptions
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            switch viewModel.step {
            case .enterEmail: emailStep
            case .enterCode: codeStep
            }
            if let failure = viewModel.failure {
                Label(message(for: failure), systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.brandAccent)
            }
        }
        .padding(Spacing.l)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .animation(.default, value: viewModel.step)
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(hasOtherOptions ? "Hoặc nhận mã đăng nhập qua email" : "Nhận mã đăng nhập qua email")
                .font(.subheadline.weight(.semibold))
            TextField("email@vidu.vn", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($focused, equals: .email)
                .onSubmit { Task { await viewModel.sendCode() } }
                .padding(Spacing.m)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Button {
                Task { await viewModel.sendCode() }
            } label: {
                workingLabel("Gửi mã", systemImage: "envelope")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.canSendCode)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Nhập mã 6 số đã gửi tới \(viewModel.email)").font(.subheadline.weight(.semibold))
            TextField("123456", text: $viewModel.code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.title2.weight(.semibold).monospacedDigit())
                .focused($focused, equals: .code)
                .padding(Spacing.m)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .onAppear { focused = .code }
                .onChange(of: viewModel.code) { _, code in
                    if code.count == 6 { Task { await verify() } }
                }
            Button {
                Task { await verify() }
            } label: {
                workingLabel("Xác nhận", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandPrimary)
            .controlSize(.large)
            .disabled(!viewModel.canVerify)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let wait = viewModel.resendWait(at: context.date)
                HStack {
                    Button("Đổi email") { viewModel.changeEmail() }
                    Spacer()
                    Button(wait > 0 ? "Gửi lại sau \(wait) giây" : "Gửi lại mã") {
                        Task { await viewModel.sendCode() }
                    }
                    .disabled(wait > 0 || viewModel.isWorking)
                }
                .font(.footnote)
            }
        }
    }

    private func workingLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: Spacing.s) {
            if viewModel.isWorking { ProgressView() } else { Image(systemName: systemImage) }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func verify() async {
        if await viewModel.verify() { onSignedIn() }
    }

    private func message(for failure: EmailSignInViewModel.Failure) -> LocalizedStringKey {
        switch failure {
        case .invalidEmail: "Email chưa đúng định dạng."
        case .wrongCode: "Mã không đúng hoặc đã hết hạn."
        case .tooManyRequests: "Bạn thao tác quá nhiều lần. Vui lòng thử lại sau ít phút."
        case .network: "Không kết nối được. Vui lòng thử lại."
        }
    }
}
