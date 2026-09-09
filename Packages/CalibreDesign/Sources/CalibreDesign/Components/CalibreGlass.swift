import SwiftUI

/// Liquid Glass chrome for the consumer app, ported from the admin app's
/// `adminGlass` so the two houses use one material rather than two that drift.
///
/// **The fallback is the product here, not a courtesy.** The admin app is
/// pinned to iOS 26, so its `#available` branch is documentation. Calibre
/// deploys to iOS 18, which means most people holding a phone will see the
/// second branch and nothing else — so it is designed rather than degraded: a
/// warm ground under the frost so it does not read as grey system chrome, a
/// hairline in the bright border token so the edge is deliberate, and a soft
/// shadow so the surface says it is floating over the conversation rather than
/// sitting in it. Both themes were checked against their own tokens; no raw
/// colour appears below.
///
/// Glass is CHROME. It never goes under content — a price, a spec table or a
/// photograph on glass is unreadable in one theme or the other.
public extension View {

    /// Glass chrome in `shape`. `interactive` gives the material the press
    /// response, which is for a bar of controls and not for a static band.
    /// `enabled` lets a surface whose states differ keep one stable view
    /// identity while the glass comes and goes — the composer is exactly that
    /// case, and a view that is rebuilt instead of restyled drops the
    /// keyboard's focus on the way through.
    @ViewBuilder
    func calibreGlass(in shape: some Shape, interactive: Bool = false, enabled: Bool = true) -> some View {
        if !enabled {
            self
        } else if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            modifier(CalibreFrostedGlass(shape: shape))
        }
    }

    /// The common case: a pill of chrome.
    @ViewBuilder
    func calibreGlassPill(interactive: Bool = true) -> some View {
        calibreGlass(in: Capsule(), interactive: interactive)
    }

    /// A panel of chrome — a composer, a floating tray.
    @ViewBuilder
    func calibreGlassPanel(radius: CGFloat = Radius.panel, interactive: Bool = false) -> some View {
        calibreGlass(
            in: RoundedRectangle(cornerRadius: radius, style: .continuous),
            interactive: interactive
        )
    }
}

/// What glass looks like before iOS 26, which on this app is most of the time.
///
/// Three layers, in the order they are painted: the ultra-thin material, which
/// is what actually blurs; a wash of the card token OVER it, because the
/// material's own light is neutral and a neutral tray on a cream page reads as
/// grey plastic — the wash is what makes it Calibre's glass rather than the
/// system's; and a hairline so the edge does not dissolve into a light
/// background. The shadow is what says "floating"; without it the material
/// alone reads as a flat panel in light mode.
///
/// The wash sits inside the same `.background` as the material rather than in a
/// second one behind it. A `.background` added after another goes FURTHER
/// BACK, so the obvious spelling puts the warmth underneath the frost, where
/// the frost washes it out — which is exactly what the first attempt did, and
/// it took a screenshot to see.
private struct CalibreFrostedGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.calibre.card.opacity(0.45))
                }
            }
            .overlay {
                shape.stroke(Color.calibre.borderBright.opacity(0.75), lineWidth: 0.5)
            }
            .shadow(color: Color.calibre.shadowTint.opacity(0.12), radius: 18, y: 6)
    }
}

/// Wraps a group of glass pieces so they blend into each other rather than
/// stacking as separate sheets. Below iOS 26 it is a plain passthrough, so no
/// caller has to branch.
public struct CalibreGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = Space.s, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

public extension View {
    /// The composer's surface, shared by Support and by buyer↔seller Messages
    /// so the two can never come to look like different apps. Each screen
    /// keeps its own controls; only the material and the shape are shared.
    ///
    /// The glass sits in a `.background`, never on the composer's own stack,
    /// because the field has to stay in one structural slot for the life of
    /// the screen. A composer built as two branches — one for rest, one for
    /// focus — is rebuilt when it morphs, and the keyboard goes down with the
    /// view that owned it.
    ///
    /// **Do not add a keyboard inset to a screen that calls this.** SwiftUI's
    /// automatic avoidance already lifts the composer; a container inset on
    /// top of it counts the keyboard twice and leaves a keyboard-sized hole
    /// under the bar.
    func calibreComposerSurface(radius: CGFloat = Radius.panel) -> some View {
        background {
            Color.clear
                .calibreGlassPanel(radius: radius, interactive: true)
        }
        // The inset is what makes the bar a tray rather than a band. Glass
        // that runs edge to edge under a hairline is just a tinted footer;
        // held off the edges, with the page showing around it, it reads as
        // something laid on top of the conversation.
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.s)
    }
}
