import SwiftUI

/// The three brand button variants. Press feedback is darken + scale 0.97 —
/// never opacity fades. Minimum 44pt touch target.
public enum CalibreButtonVariant {
    /// Chocolate/copper fill — the one strong action on a screen.
    case primary
    /// Card surface with a warm border.
    case secondary
    /// Transparent; for tertiary/inline actions.
    case ghost
    /// Destructive tint for irreversible actions.
    case destructive
}

public struct CalibreButtonStyle: ButtonStyle {
    let variant: CalibreButtonVariant
    let fullWidth: Bool

    public init(_ variant: CalibreButtonVariant = .primary, fullWidth: Bool = false) {
        self.variant = variant
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CalibreType.bodySemiBold)
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Space.touchTarget)
            .background(background(pressed: configuration.isPressed))
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(borderColor(pressed: configuration.isPressed), lineWidth: variant == .secondary ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .calibreShadow(variant == .primary ? .resting : .resting)
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.easeFast, value: configuration.isPressed)
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary: pressed ? Color.calibre.primaryDeep : Color.calibre.primary
        case .secondary: pressed ? Color.calibre.accent : Color.calibre.card
        case .ghost: pressed ? Color.calibre.accent : .clear
        case .destructive: pressed ? Color.calibre.destructive.opacity(0.85) : Color.calibre.destructive
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: Color.calibre.primaryForeground
        case .secondary, .ghost: Color.calibre.foreground
        case .destructive: Color(white: 1)
        }
    }

    private func borderColor(pressed: Bool) -> Color {
        pressed ? Color.calibre.primary.opacity(0.4) : Color.calibre.borderBright
    }
}

public extension ButtonStyle where Self == CalibreButtonStyle {
    static var calibrePrimary: CalibreButtonStyle { CalibreButtonStyle(.primary) }
    static var calibreSecondary: CalibreButtonStyle { CalibreButtonStyle(.secondary) }
    static var calibreGhost: CalibreButtonStyle { CalibreButtonStyle(.ghost) }
    static var calibreDestructive: CalibreButtonStyle { CalibreButtonStyle(.destructive) }
    static func calibre(_ variant: CalibreButtonVariant, fullWidth: Bool = false) -> CalibreButtonStyle {
        CalibreButtonStyle(variant, fullWidth: fullWidth)
    }
}

/// Bare press-scale for custom tappable surfaces (cards, rows).
public struct PressableStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.easeFast, value: configuration.isPressed)
    }
}

#Preview("Buttons", traits: .sizeThatFitsLayout) {
    VStack(spacing: Space.l) {
        Button("Buy Now") {}.buttonStyle(.calibre(.primary, fullWidth: true))
        Button("Make Offer") {}.buttonStyle(.calibre(.secondary, fullWidth: true))
        Button("Save for Later") {}.buttonStyle(.calibreGhost)
        Button("Remove Listing") {}.buttonStyle(.calibreDestructive)
    }
    .padding()
    .background(Color.calibre.background)
}
