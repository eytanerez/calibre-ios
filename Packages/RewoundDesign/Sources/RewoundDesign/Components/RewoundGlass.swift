import SwiftUI

/// Liquid Glass chrome for the consumer app, ported from the admin app's
/// `adminGlass` so the two houses use one material rather than two that drift.
///
/// **The fallback is the product here, not a courtesy.** The admin app is
/// pinned to iOS 26, so its `#available` branch is documentation. Rewound
/// deploys to iOS 18, which means most people holding a phone will see the
/// second branch and nothing else — so it is designed rather than degraded: a
/// warm ground under the frost so it does not read as gray system chrome, a
/// hairline in the bright border token so the edge is deliberate, and a soft
/// shadow so the surface says it is floating over the conversation rather than
/// sitting in it. Both themes were checked against their own tokens; no raw
/// color appears below.
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
    func rewoundGlass(in shape: some Shape, interactive: Bool = false, enabled: Bool = true) -> some View {
        if !enabled {
            self
        } else if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            modifier(RewoundFrostedGlass(shape: shape))
        }
    }

    /// The common case: a pill of chrome.
    @ViewBuilder
    func rewoundGlassPill(interactive: Bool = true) -> some View {
        rewoundGlass(in: Capsule(), interactive: interactive)
    }

    /// A panel of chrome — a composer, a floating tray.
    @ViewBuilder
    func rewoundGlassPanel(radius: CGFloat = Radius.panel, interactive: Bool = false) -> some View {
        rewoundGlass(
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
/// gray plastic — the wash is what makes it Rewound's glass rather than the
/// system's; and a hairline so the edge does not dissolve into a light
/// background. The shadow is what says "floating"; without it the material
/// alone reads as a flat panel in light mode.
///
/// The wash sits inside the same `.background` as the material rather than in a
/// second one behind it. A `.background` added after another goes FURTHER
/// BACK, so the obvious spelling puts the warmth underneath the frost, where
/// the frost washes it out — which is exactly what the first attempt did, and
/// it took a screenshot to see.
private struct RewoundFrostedGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.rewound.card.opacity(0.45))
                }
            }
            .overlay {
                shape.stroke(Color.rewound.borderBright.opacity(0.75), lineWidth: 0.5)
            }
            .shadow(color: Color.rewound.shadowTint.opacity(0.12), radius: 18, y: 6)
    }
}

/// Wraps a group of glass pieces so they blend into each other rather than
/// stacking as separate sheets. Below iOS 26 it is a plain passthrough, so no
/// caller has to branch.
public struct RewoundGlassGroup<Content: View>: View {
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
    func rewoundComposerSurface(radius: CGFloat = Radius.panel) -> some View {
        background {
            Color.clear
                .rewoundGlassPanel(radius: radius, interactive: true)
        }
        // The inset is what makes the bar a tray rather than a band. Glass
        // that runs edge to edge under a hairline is just a tinted footer;
        // held off the edges, with the page showing around it, it reads as
        // something laid on top of the conversation.
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.s)
    }
}

public extension View {
    /// The empty, loading and error states of a conversation screen, which
    /// sit between its header and the composer tray.
    ///
    /// Scrollable so they give way to the keyboard. As a plain view framed to
    /// `maxHeight: .infinity` a state like "How can we help?" still had a
    /// minimum height, and once the keyboard took its share the header, that
    /// state and the tray no longer fitted: SwiftUI spilled the stack out of
    /// both ends, the header under the navigation bar and the bottom of the
    /// tray under the keyboard (Eytan, 2026-09-23). In a scroll view the state
    /// can shrink to nothing, and it is still centred whenever it fits.
    func conversationPlaceholder() -> some View {
        ScrollView {
            frame(maxWidth: .infinity)
                .padding(.vertical, Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// A transparent multiline input for the shared glass conversation tray.
/// The tray supplies the surface; an opaque form-field card would cover it.
public struct RewoundMessageField: View {
    @Binding private var text: String
    public init(text: Binding<String>) { _text = text }
    public var body: some View {
        TextField("Write a message", text: $text, axis: .vertical)
            .lineLimit(1...5)
            .font(RewoundType.body)
            .foregroundStyle(Color.rewound.foreground)
            .tint(Color.rewound.primary)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, Space.s)
            .frame(minHeight: Space.touchTarget)
            .accessibilityLabel("Write a message")
    }
}

// MARK: - A toolbar button that draws its own glass

/// A trailing toolbar item whose label draws its own glass disc, with the
/// bar's shared glass switched off behind it.
///
/// On iOS 26 every toolbar item gets the bar's glass. A label that also draws
/// a circle (an `ellipsis.circle` glyph, or a filled disc) shows as a button
/// inside a button (Eytan, 2026-09-23). The bar's glass alone is no answer for
/// a ⋯: it hugs three dots as a wide capsule beside a round back control. So
/// the label draws the one disc (`rewoundToolbarDisc()`) and the bar stands
/// down, which is the construction the admin app settled on for its ⋯.
public struct RewoundOwnGlassToolbarItem<Label: View>: ToolbarContent {
    private let placement: ToolbarItemPlacement
    private let label: Label

    public init(placement: ToolbarItemPlacement = .topBarTrailing, @ViewBuilder label: () -> Label) {
        self.placement = placement
        self.label = label()
    }

    public var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) { label }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { label }
        }
    }
}

public extension View {
    /// The disc a `RewoundOwnGlassToolbarItem` label draws: the back
    /// control's 44pt, in the design system's glass.
    func rewoundToolbarDisc() -> some View {
        frame(width: Space.touchTarget, height: Space.touchTarget)
            .rewoundGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
    }
}
