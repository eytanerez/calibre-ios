import SwiftUI

/// Strict radius ladder — one scale, no ad-hoc corners.
public enum Radius {
    /// Buttons, inputs, icon tiles.
    public static let control: CGFloat = 8
    /// Cards, panels, callouts.
    public static let card: CGFloat = 12
    /// Sheets, modals, gallery frames.
    public static let overlay: CGFloat = 16
}

/// Spacing rhythm (pt).
public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 28
    /// Default horizontal screen margin.
    public static let margin: CGFloat = 20
    /// Minimum touch target for primary controls.
    public static let touchTarget: CGFloat = 44
}

/// Warm ink-tinted elevation. Resting cards are defined by borders;
/// shadows appear only on lift and overlays.
public enum Elevation {
    case resting     // controls at rest
    case lifted      // cards on press/drag
    case menu        // popovers, toasts
    case modal       // sheets, large overlays

    var layers: [(opacity: CGFloat, radius: CGFloat, y: CGFloat)] {
        switch self {
        case .resting: [(0.05, 2, 1)]
        case .lifted: [(0.07, 6, 2), (0.12, 18, 8)]
        case .menu: [(0.08, 10, 4), (0.16, 36, 16)]
        case .modal: [(0.12, 20, 8), (0.22, 60, 28)]
        }
    }
}

public extension View {
    /// Applies the brand elevation style (ink-tinted, never cold black).
    func calibreShadow(_ elevation: Elevation) -> some View {
        modifier(CalibreShadowModifier(elevation: elevation))
    }
}

private struct CalibreShadowModifier: ViewModifier {
    let elevation: Elevation
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        // Dark mode needs slightly stronger opacity for shadows to register at all.
        let boost: CGFloat = scheme == .dark ? 1.6 : 1.0
        return elevation.layers.reduce(AnyView(content)) { view, layer in
            AnyView(view.shadow(
                color: Color.calibre.shadowTint.opacity(layer.opacity * boost),
                radius: layer.radius,
                x: 0,
                y: layer.y
            ))
        }
    }
}
