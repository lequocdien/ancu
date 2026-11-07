import SwiftUI

/// Hộp thông báo: icon/màu theo `notification_types`.
struct InboxView: View {
    let viewModel: TrackingViewModel

    var body: some View {
        switch viewModel.inboxState {
        case .idle:
            ProgressView().frame(maxWidth: .infinity).padding(Spacing.xl)
        case .loading where viewModel.notifications.isEmpty:
            ProgressView().frame(maxWidth: .infinity).padding(Spacing.xl)
        case .failed where viewModel.notifications.isEmpty:
            ContentUnavailableView {
                Label("Không tải được thông báo", systemImage: "wifi.exclamationmark")
            } actions: {
                Button("Thử lại") { Task { await viewModel.loadInbox() } }
            }
        default:
            if viewModel.notifications.isEmpty {
                ContentUnavailableView(
                    "Chưa có thông báo",
                    systemImage: "bell",
                    description: Text("Bật thông báo ở dự án đã lưu để nhận tin khi mở nhận hồ sơ, đổi giá hoặc đổi trạng thái.")
                )
            } else {
                LazyVStack(spacing: Spacing.m) {
                    ForEach(viewModel.notifications) { notification in
                        Button {
                            Task { await viewModel.markAsRead(notification) }
                        } label: {
                            GlassCard(padding: Spacing.m) {
                                row(notification)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ notification: AppNotification) -> some View {
        let color = viewModel.catalog.color(for: notification.type)
        return HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: viewModel.catalog.symbolName(for: notification.type, default: "bell.fill"))
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: notification.title)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                    Spacer(minLength: Spacing.s)
                    Text(verbatim: viewModel.relativeDate(notification.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: notification.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !notification.isRead {
                Circle()
                    .fill(Color.brandPrimary)
                    .frame(width: 8, height: 8)
                    .padding(.top, Spacing.xs)
                    .accessibilityLabel(Text("Chưa đọc"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
