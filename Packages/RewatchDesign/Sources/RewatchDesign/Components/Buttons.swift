import SwiftUI

/// The three brand button variants. Press feedback is darken + scale 0.97 —
/// never opacity fades. Minimum 44pt touch target.
public enum RewatchButtonVariant {
    /// Chocolate/copper fill — the one strong action on a screen.
    case primary
    /// Card surface with a warm border.
    case secondary
    /// Transparent; for tertiary/inline actions.
    case ghost
    /// Destructive tint for irreversible actions.
    case destructive
}

public struct RewatchButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let variant: RewatchButtonVariant
    let fullWidth: Bool

    public init(_ variant: RewatchButtonVariant = .primary, fullWidth: Bool = false) {
        self.variant = variant
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RewatchType.bodySemiBold)
            .padding(.horizontal, Space.xl)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Space.touchTarget)
            .background(background(pressed: configuration.isPressed))
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(borderColor(pressed: configuration.isPressed), lineWidth: variant == .secondary ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .rewatchShadow(.resting)
            .scaleEffect(isEnabled && configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.easeFast, value: configuration.isPressed)
    }

    private func background(pressed: Bool) -> Color {
        guard isEnabled else { return Color.rewatch.secondary }
        return switch variant {
        case .primary: pressed ? Color.rewatch.primaryDeep : Color.rewatch.primary
        case .secondary: pressed ? Color.rewatch.accent : Color.rewatch.card
        case .ghost: pressed ? Color.rewatch.accent : .clear
        case .destructive: pressed ? Color.rewatch.destructive.opacity(0.85) : Color.rewatch.destructive
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Color.rewatch.mutedForeground }
        return switch variant {
        case .primary: Color.rewatch.primaryForeground
        case .secondary, .ghost: Color.rewatch.foreground
        case .destructive: Color(white: 1)
        }
    }

    private func borderColor(pressed: Bool) -> Color {
        guard isEnabled else { return Color.rewatch.border }
        return pressed ? Color.rewatch.primary.opacity(0.4) : Color.rewatch.borderBright
    }
}

public extension ButtonStyle where Self == RewatchButtonStyle {
    static var rewatchPrimary: RewatchButtonStyle { RewatchButtonStyle(.primary) }
    static var rewatchSecondary: RewatchButtonStyle { RewatchButtonStyle(.secondary) }
    static var rewatchGhost: RewatchButtonStyle { RewatchButtonStyle(.ghost) }
    static var rewatchDestructive: RewatchButtonStyle { RewatchButtonStyle(.destructive) }
    static func rewatch(_ variant: RewatchButtonVariant, fullWidth: Bool = false) -> RewatchButtonStyle {
        RewatchButtonStyle(variant, fullWidth: fullWidth)
    }
}

/// Bare press-scale for custom tappable surfaces (cards, rows).
public struct PressableStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        // NOTE: a blanket 44pt hit floor was tried here and DELIBERATELY REMOVED.
        //
        // It was a clear background with `frame(minWidth:minHeight:)` and a
        // `contentShape`, which is layout-free — but it silently widens the hit
        // region of all 60+ call sites by up to 22pt in every direction, and a
        // background is neither clipped nor bounded by the button's own frame.
        // `SearchField`'s 15pt clear button sits `Space.s` from the text field
        // with no clip between them, so the grown region reached back over the
        // field's trailing edge: a tap meant to place the cursor at the end of a
        // query would have wiped the query instead.
        //
        // The change is either that regression or completely inert, depending on
        // whether SwiftUI dispatches to an overflowing background — and that
        // needs a device to settle, not a reading. Targets on this style are a
        // real finding; the fix belongs at the call sites that are actually
        // short, using `a11yExpandTarget` where the neighbors have been looked
        // at, not as a blanket rule nobody has run.
        configuration.label
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.easeFast, value: configuration.isPressed)
    }
}

#Preview("Buttons", traits: .sizeThatFitsLayout) {
    VStack(spacing: Space.l) {
        Button("Buy Now") {}.buttonStyle(.rewatch(.primary, fullWidth: true))
        Button("Make Offer") {}.buttonStyle(.rewatch(.secondary, fullWidth: true))
        Button("Save for Later") {}.buttonStyle(.rewatchGhost)
        Button("Remove Listing") {}.buttonStyle(.rewatchDestructive)
    }
    .padding()
    .background(Color.rewatch.background)
}
