import SwiftUI

/// The radius ladder — five tiers, assigned by the SIZE of a surface, not by
/// what kind of component it is. A large panel at 12pt reads squarer than a
/// chip at 12pt even though the number is identical, so the bigger the
/// surface, the rounder the corner. CALIBRE_FINAL_PUSH_CONTRACTS.md §1.
///
/// When the tier is not obvious, measure the surface's **short edge** at its
/// most common rendered size:
///
/// - `>= 240pt` → `card`
/// - `120…240pt` → `box`
/// - `< 120pt` → `control`, or `chip` if it is a label rather than a control
///
/// A surface that changes tier between size classes takes the tier it holds
/// at the larger one, so it does not visibly change shape as the window
/// narrows. Every `.cornerRadius(_:)` / `RoundedRectangle` takes a name from
/// here, never a literal.
///
/// The three small rungs moved up once the cards went round (chip 6→8,
/// control 8→12, box 12→14): buttons and text fields were then the squarest
/// thing left on any screen, which is what the round-2 review actually saw.
/// `panel` and `card` are unchanged, so the ladder still climbs by size — it
/// just starts higher. The site's tokens carry the identical numbers.
public enum Radius {
    /// Tags, small bars, square-ish badges, the condition pill's square variant.
    public static let chip: CGFloat = 8
    /// Buttons, inputs, selects, text editors, small icon buttons and tiles.
    public static let control: CGFloat = 12
    /// Callouts, banners, info boxes, list rows, small tiles, toasts.
    public static let box: CGFloat = 14
    /// Modals, drawers, sheets, popovers, menus, large section panels.
    public static let panel: CGFloat = 16
    /// Listing cards, metric tiles, hero frames, the gallery frame.
    public static let card: CGFloat = 20

    /// The focus ring rides 3pt outside the control it surrounds, so it has to
    /// move whenever `control` does. It was written out longhand at three call
    /// sites; naming it is what keeps the fourth one from being wrong.
    public static let focusRing: CGFloat = control + 3

    /// Was the top of a three-tier ladder (control/card/overlay) and is the
    /// same 16pt the `panel` tier now carries. Kept so the app's existing
    /// sheet and cover call sites keep building while they are renamed; new
    /// code says `panel`.
    @available(*, deprecated, renamed: "panel", message: "The 16pt tier is now Radius.panel — see CALIBRE_FINAL_PUSH_CONTRACTS.md §1.")
    public static let overlay: CGFloat = panel
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
