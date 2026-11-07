import SwiftUI

/// Nền cho màn không có map (Theo dõi, Tài khoản).
/// iOS 18+: MeshGradient 3×3 trôi chậm (chu kỳ ~20s). iOS 17: LinearGradient tĩnh. Reduce Motion: đứng yên.
struct MeshBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = MeshPalette.colors(for: colorScheme)
        Group {
            if #available(iOS 18, *) {
                AnimatedMesh(palette: colors)
            } else {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

@available(iOS 18, *)
private struct AnimatedMesh: View {
    let palette: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 20

    var body: some View {
        // 30 fps là đủ cho chuyển động chậm, đỡ tốn pin hơn tốc độ màn hình.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let phase = reduceMotion
                ? 0
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
                    / Self.period * 2 * .pi
            MeshGradient(width: 3, height: 3, points: Self.points(phase: phase), colors: colors)
        }
    }

    /// Tông brand ở góc trên trái, trung tính ở giữa, tông ấm ở góc dưới phải.
    private var colors: [Color] {
        let (brand, neutral, warm) = (palette[0], palette[1], palette[2])
        return [
            brand, brand, neutral,
            brand, neutral, warm,
            neutral, warm, warm,
        ]
    }

    /// Góc cố định, điểm giữa cạnh và tâm dao động nhỏ (≤ 0.1) để lưới không bị gấp.
    private static func points(phase: Double) -> [SIMD2<Float>] {
        func wobble(_ offset: Double, _ amplitude: Double = 0.08) -> Float {
            Float(sin(phase + offset) * amplitude)
        }
        return [
            [0, 0], [0.5 + wobble(0), 0], [1, 0],
            [0, 0.5 + wobble(1.3)], [0.5 + wobble(2.1, 0.1), 0.5 + wobble(0.7, 0.1)], [1, 0.5 + wobble(3.4)],
            [0, 1], [0.5 + wobble(4.2), 1], [1, 1],
        ]
    }
}
