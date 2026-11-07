import SwiftUI

/// Nút hành động chính, kính tint `brandPrimary`. Mỗi màn chỉ một nút này (spec mục 6).
/// Nút phụ: `Button { } label: { } .adaptiveGlassButton()`.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if isLoading {
                    ProgressView()
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .adaptiveGlassButton(.prominent)
        .disabled(isLoading)
    }
}
