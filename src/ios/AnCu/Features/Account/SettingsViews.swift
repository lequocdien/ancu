import SwiftUI

/// Tùy chọn loại thông báo theo tài khoản (RPC `set_notification_prefs`) — áp cho mọi máy, fan-out phía server tôn trọng.
@MainActor
@Observable
final class NotificationSettingsViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    private(set) var preferences = NotificationPreferences()
    private(set) var loadState: LoadState = .idle
    private(set) var saveFailed = false
    private let repository: any NotificationRepository

    init(repository: any NotificationRepository) {
        self.repository = repository
    }

    func load() async {
        loadState = .loading
        do {
            preferences = try await repository.preferences()
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    /// Lạc quan: đổi ngay trên UI, lỗi thì trả lại như cũ.
    func set(_ type: NotificationType, enabled: Bool) async {
        let previous = preferences
        preferences.set(type, enabled: enabled)
        saveFailed = false
        do {
            try await repository.setPreferences(preferences)
        } catch {
            preferences = previous
            saveFailed = true
        }
    }
}

struct NotificationSettingsView: View {
    let isSignedIn: Bool
    @State private var viewModel: NotificationSettingsViewModel

    init(isSignedIn: Bool, repository: any NotificationRepository) {
        self.isSignedIn = isSignedIn
        _viewModel = State(initialValue: NotificationSettingsViewModel(repository: repository))
    }

    var body: some View {
        Form {
            Section {
                toggle("Dự án mở nhận hồ sơ", .applicationsOpened)
                toggle("Thay đổi giá", .priceChanged)
                toggle("Thay đổi trạng thái pháp lý", .statusChanged)
            } footer: {
                Text("Chỉ áp dụng cho dự án bạn đã bật thông báo, trên mọi thiết bị đăng nhập. Tối đa 1 thông báo/ngày cho mỗi dự án, không gửi quảng cáo.")
            }
            .disabled(!isSignedIn || viewModel.loadState != .loaded)

            if !isSignedIn {
                Section {
                    Label("Đăng nhập để nhận thông báo.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.loadState == .failed || viewModel.saveFailed {
                Section {
                    Label(viewModel.saveFailed ? "Chưa lưu được thay đổi. Vui lòng thử lại." : "Không tải được cài đặt.",
                          systemImage: "wifi.exclamationmark")
                        .foregroundStyle(Color.brandAccent)
                    if viewModel.loadState == .failed {
                        Button("Thử lại") { Task { await viewModel.load() } }
                    }
                }
            }
        }
        .navigationTitle("Cài đặt thông báo")
        .navigationBarTitleDisplayMode(.inline)
        .task { if isSignedIn { await viewModel.load() } }
    }

    private func toggle(_ title: LocalizedStringKey, _ type: NotificationType) -> some View {
        Toggle(title, isOn: Binding(
            get: { viewModel.preferences.isEnabled(type) },
            set: { enabled in Task { await viewModel.set(type, enabled: enabled) } }
        ))
    }
}

enum LegalDocument: String, CaseIterable, Identifiable, Hashable {
    case communityRules
    case privacyPolicy
    case termsOfUse

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .communityRules: "Quy tắc cộng đồng"
        case .privacyPolicy: "Chính sách quyền riêng tư"
        case .termsOfUse: "Điều khoản sử dụng"
        }
    }

    var systemImage: String {
        switch self {
        case .communityRules: "person.3"
        case .privacyPolicy: "hand.raised"
        case .termsOfUse: "doc.text"
        }
    }

    /// Bản tóm tắt cho prototype. Văn bản chính thức cần luật sư duyệt (compliance.md).
    var summary: [LocalizedStringKey] {
        switch self {
        case .communityRules:
            [
                "Chia sẻ trải nghiệm thật về dự án. Phân biệt rõ trải nghiệm của bạn với cáo buộc chưa kiểm chứng.",
                "Không đăng số điện thoại, Zalo, đường link hay lời mời mua \"suất ngoại giao\", \"tiền chênh\".",
                "Nội dung vi phạm bị ẩn; tài khoản vi phạm nhiều lần bị khóa.",
                "Dùng nút Báo cáo và Chặn khi gặp nội dung lừa đảo.",
            ]
        case .privacyPolicy:
            [
                "Câu trả lời kiểm tra điều kiện mua không được gửi lên máy chủ.",
                "Ảnh được xóa vị trí GPS trước khi tải lên.",
                "Chỉ dùng vị trí khi bạn bấm \"Gần tôi\", không theo dõi nền.",
                "Bạn có thể xóa tài khoản và toàn bộ dữ liệu trong mục Tài khoản.",
            ]
        case .termsOfUse:
            [
                "Thông tin dự án được tổng hợp từ nguồn công khai, có ghi nguồn và ngày cập nhật.",
                "Hướng tuyến hạ tầng mang tính minh họa, không dùng để xác định ranh giới đất.",
                "Kết quả kiểm tra điều kiện chỉ để tham khảo; cơ quan có thẩm quyền xét duyệt mới là căn cứ cuối cùng.",
                "An Cư không nhận quảng cáo từ môi giới; nội dung trả phí (nếu có) được gắn nhãn.",
            ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        List {
            Section {
                ForEach(Array(document.summary.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            } footer: {
                Text("Bản tóm tắt dùng cho bản thử nghiệm, chưa phải văn bản pháp lý chính thức.")
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
