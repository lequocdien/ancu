import SwiftUI

/// Kiểm tra `min_supported_version` lúc mở app và mỗi lần quay lại foreground (Phase 1 bước 4.8).
/// Lỗi mạng KHÔNG chặn app (fail-open): giữ nguyên trạng thái trước đó.
@MainActor
@Observable
final class UpdateGateViewModel {
    private(set) var blockingConfig: ClientConfig?
    private let repository: any ConfigRepository
    private let current: AppVersion

    init(repository: any ConfigRepository, current: AppVersion = .current) {
        self.repository = repository
        self.current = current
    }

    var requiresUpdate: Bool { blockingConfig != nil }

    func check() async {
        guard let config = try? await repository.clientConfig() else { return }
        blockingConfig = config.requiresUpdate(current: current) ? config : nil
    }
}

struct UpdateGate<Content: View>: View {
    @State private var viewModel: UpdateGateViewModel
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder let content: Content

    init(repository: any ConfigRepository, @ViewBuilder content: () -> Content) {
        _viewModel = State(initialValue: UpdateGateViewModel(repository: repository))
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
            if let config = viewModel.blockingConfig {
                ForceUpdateView(config: config)
                    .transition(.opacity)
            }
        }
        .task { await viewModel.check() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.check() } }
        }
    }
}

/// Màn chặn toàn màn hình, không có nút đóng. Nền đặc (không kính) để chắc chắn che nội dung phía sau.
struct ForceUpdateView: View {
    let config: ClientConfig
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: Spacing.l) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityHidden(true)
                Text("Cần cập nhật An Cư")
                    .font(.title2.weight(.bold))
                Text("Phiên bản này không còn được hỗ trợ. Vui lòng cập nhật lên phiên bản \(config.minSupportedVersion.description) trở lên để tiếp tục xem dữ liệu dự án mới nhất.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let url = config.appStoreURL {
                    PrimaryButton(title: "Cập nhật trên App Store", systemImage: "arrow.up.forward.app") {
                        openURL(url)
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 480)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    ForceUpdateView(config: ClientConfig(minSupportedVersion: AppVersion(1, 2, 0), appStoreURL: URL(string: "https://apps.apple.com")))
}
