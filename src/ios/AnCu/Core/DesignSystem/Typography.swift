import SwiftUI

// SF Pro theo text style hệ thống để ăn Dynamic Type. Số liệu dùng `.monospacedDigit()` để cột số không nhảy.

extension Font {
    /// Giá, số căn, khoảng cách, countdown.
    static let metricValue = Font.title3.weight(.semibold).monospacedDigit()
    static let metricValueLarge = Font.title2.weight(.semibold).monospacedDigit()
    static let metricLabel = Font.caption.weight(.medium)
    static let sectionTitle = Font.headline
    static let badge = Font.caption.weight(.semibold)
}

// MARK: - Motion

enum Motion {
    static let sheet = Animation.spring(duration: 0.4, bounce: 0.2)
    static let snappy = Animation.snappy(duration: 0.25)

    /// Trả `nil` khi Reduce Motion để caller viết `withAnimation(Motion.resolve(.snappy, reduceMotion: ...))`.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

extension View {
    /// Hiệu ứng nhịp thở cho nội dung cần gây chú ý (vd ghim "Đang nhận hồ sơ"). Tắt khi Reduce Motion.
    func pulsing(_ isActive: Bool = true) -> some View {
        modifier(PulseModifier(isActive: isActive))
    }
}

private struct PulseModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && !reduceMotion && expanded ? 1.12 : 1)
            .onAppear { restart() }
            .onChange(of: isActive) { restart() }
            .onChange(of: reduceMotion) { restart() }
    }

    private func restart() {
        guard isActive, !reduceMotion else {
            expanded = false
            return
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            expanded = true
        }
    }
}
