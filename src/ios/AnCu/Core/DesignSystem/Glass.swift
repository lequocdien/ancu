import SwiftUI

// MARK: - Điểm DUY NHẤT trong codebase biết về Liquid Glass (iOS 26) và vật liệu fallback
//
// Feature code chỉ dùng: `.adaptiveGlass(_:in:)`, `AdaptiveGlassContainer`, `.adaptiveGlassID(_:in:)`,
// `.adaptiveGlassButton(_:)`, `.adaptiveTabBarMinimizeOnScroll()`.
// `DesignSystemTests.glassAPIsOnlyInGlassFile` fail nếu file khác gọi trực tiếp API kính/material.
//
// - iOS 26+: Liquid Glass.
// - iOS 17–25: `.ultraThinMaterial`.
// - Reduce Transparency hoặc Increase Contrast: nền đặc `secondarySystemBackground`.

/// Mô phỏng API `Glass` của iOS 26 để feature code không phải `#available`.
struct GlassStyle: Equatable {
    var tint: Color?
    var isInteractive = false

    static let regular = GlassStyle()
    static let interactive = GlassStyle(isInteractive: true)

    static func tinted(_ color: Color) -> GlassStyle {
        GlassStyle(tint: color)
    }

    func interactive() -> GlassStyle {
        GlassStyle(tint: tint, isInteractive: true)
    }
}

struct AdaptiveGlass<S: Shape>: ViewModifier {
    let style: GlassStyle
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background {
                    shape.fill(Color(.secondarySystemBackground))
                    if let tint = style.tint { shape.fill(tint.opacity(0.18)) }
                }
                .overlay { shape.stroke(Color(.separator), lineWidth: 1) }
        } else if #available(iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
                // Material làm nhạt tint nhiều hơn kính iOS 26 → cần độ phủ cao hơn để trạng thái "đang bật" còn nhận ra được.
                if let tint = style.tint { shape.fill(tint.opacity(0.45)) }
            }
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint = style.tint { glass = glass.tint(tint) }
        if style.isInteractive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func adaptiveGlass<S: Shape>(_ style: GlassStyle = .regular, in shape: S = Capsule()) -> some View {
        modifier(AdaptiveGlass(style: style, shape: shape))
    }

    /// Cho phép kính morph giữa các trạng thái (chip bật/tắt). iOS < 26: không làm gì.
    @ViewBuilder
    func adaptiveGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Áp lên `TabView`. iOS < 26: không làm gì.
    @ViewBuilder
    func adaptiveTabBarMinimizeOnScroll() -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

/// Nhóm control kính đặt cạnh nhau để kính hòa vào nhau và morph (iOS 26).
/// iOS < 26: chỉ render nội dung — layout (HStack/VStack) do caller tự đặt bên trong.
struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Nút

enum GlassButtonKind {
    /// Nút kính trung tính, không tint.
    case regular
    /// Nút chính, tint `brandPrimary`. Mỗi màn chỉ một nút loại này.
    case prominent
    /// Nút tròn chỉ có icon (Gần tôi, Chú giải…).
    case icon
}

extension View {
    @ViewBuilder
    func adaptiveGlassButton(_ kind: GlassButtonKind = .regular) -> some View {
        if #available(iOS 26, *) {
            switch kind {
            case .regular: buttonStyle(.glass)
            case .prominent: buttonStyle(.glassProminent).tint(.brandPrimary).foregroundStyle(Color.onBrandPrimary)
            case .icon: buttonStyle(.glass).buttonBorderShape(.circle)
            }
        } else {
            switch kind {
            case .regular: buttonStyle(FallbackGlassButtonStyle())
            case .prominent: buttonStyle(.borderedProminent).tint(.brandPrimary).foregroundStyle(Color.onBrandPrimary)
            case .icon: buttonStyle(FallbackGlassIconButtonStyle())
            }
        }
    }
}

/// `.bordered` mặc định gần như vô hình trên nền map → dùng capsule material cho đồng bộ với các control kính khác.
private struct FallbackGlassButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(controlSize == .large ? .body.weight(.semibold) : .subheadline.weight(.semibold))
            .padding(.horizontal, controlSize == .large ? Spacing.l : Spacing.m)
            .padding(.vertical, controlSize == .large ? Spacing.m : Spacing.s)
            .adaptiveGlass(.regular, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Nút icon tròn cố định 48pt (đủ vùng chạm 44pt theo HIG).
private struct FallbackGlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(width: 48, height: 48)
            .adaptiveGlass(.regular, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
    }
}
