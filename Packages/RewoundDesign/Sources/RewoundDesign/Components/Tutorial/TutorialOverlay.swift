import SwiftUI

// MARK: - Anchoring

/// Collects the frames of controls tagged with `.tutorialAnchor(_:)` so the
/// overlay can spotlight the *real* on-screen element wherever it lands.
struct TutorialAnchorPreference: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension View {
    /// Tags this control so a tutorial step can spotlight it by `id`.
    func tutorialAnchor(_ id: String) -> some View {
        anchorPreference(key: TutorialAnchorPreference.self, value: .bounds) { [id: $0] }
    }

    /// Hosts a hands-on tutorial layer above this view. Apply at the screen
    /// root, below the tagged controls, so their anchors are visible.
    func tutorialOverlay(_ controller: TutorialController) -> some View {
        modifier(TutorialOverlayModifier(controller: controller))
    }
}

// MARK: - Overlay host

struct TutorialOverlayModifier: ViewModifier {
    let controller: TutorialController

    func body(content: Content) -> some View {
        content
            // The scrim stacks pixels over the screen; it does not take the
            // screen out of the accessibility tree, so VoiceOver still walks a
            // lesson's worth of blocked controls behind it. Only a
            // `.tapToContinue` beat blocks everything — a `.perform` step needs
            // the real control underneath to stay reachable.
            .a11yCoveredBy(controller.currentStep?.advance == .tapToContinue)
            .overlayPreferenceValue(TutorialAnchorPreference.self) { anchors in
                GeometryReader { proxy in
                    if let step = controller.currentStep {
                        TutorialScrim(
                            step: step,
                            position: controller.position,
                            targetRect: step.anchor
                                .flatMap { anchors[$0] }
                                .map { proxy[$0] },
                            containerSize: proxy.size,
                            safeAreaInsets: proxy.safeAreaInsets,
                            controller: controller
                        )
                        .ignoresSafeArea()
                    }
                }
                .ignoresSafeArea()
            }
            .animation(Motion.easeMedium, value: controller.activeIndex)
    }
}

// MARK: - Scrim

/// The dimmed layer with a hole cut around the spotlit control, the looping
/// hint, and the coaching card. Touches pass through the hole to the real
/// control; touches elsewhere are blocked (or advance concept steps).
struct TutorialScrim: View {
    let step: TutorialStep
    let position: (step: Int, total: Int)?
    let targetRect: CGRect?
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let controller: TutorialController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardHeight: CGFloat = 0

    /// Padded (and, for circles, squared) target rect in overlay coordinates.
    private var spotRect: CGRect? {
        guard let target = targetRect else { return nil }
        let padded = target.insetBy(dx: -step.cutoutPadding, dy: -step.cutoutPadding)
        guard case .circle = step.cutout else { return padded }
        let side = max(padded.width, padded.height)
        return CGRect(x: padded.midX - side / 2, y: padded.midY - side / 2, width: side, height: side)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimLayer
            interactionLayer
            if let rect = spotRect {
                TutorialSpotlightRing(rect: rect, cutout: step.cutout)
                if step.hint != .none {
                    TutorialHintView(hint: step.hint, rect: rect)
                        .id(step.id)
                }
            }
            coachLayer
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        // Modal only where nothing beneath needs reaching. A `.perform` step
        // waits on the real control under the hole, so sealing the layer would
        // make the lesson impossible to finish.
        .accessibilityAddTraits(step.advance == .tapToContinue ? .isModal : [])
        // A lesson arrives over a screen the reader is already standing in, so
        // without this the card is drawn and never spoken.
        .onAppear { A11y.screenChanged(step.title) }
        .onChange(of: step.id) { _, _ in A11y.screenChanged(step.title) }
    }

    // MARK: Dim

    private var dimLayer: some View {
        // Bleed the outer rect well past the edges so the dim covers the
        // safe-area strips; the hole is cut with the even-odd rule.
        let outer = CGRect(
            x: -200, y: -200,
            width: containerSize.width + 400, height: containerSize.height + 400
        )
        return Path { path in
            path.addRect(outer)
            if let rect = spotRect { addCutout(&path, rect) }
        }
        .fill(Color.calibre.shadowTint.opacity(0.62), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func addCutout(_ path: inout Path, _ rect: CGRect) {
        switch step.cutout {
        case .circle:
            path.addEllipse(in: rect)
        case .capsule:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))
        case .roundedRect(let radius):
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        case .rect:
            path.addRect(rect)
        }
    }

    // MARK: Interaction

    @ViewBuilder private var interactionLayer: some View {
        switch step.advance {
        case .tapToContinue:
            // A tap anywhere on the dimmed area moves the concept beat along.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { controller.advance() }
        case .perform:
            // Block strays around the control; leave the hole open so the
            // real gesture/tap lands on the real control beneath.
            if let rect = spotRect {
                TutorialBlockerPanes(hole: rect, container: containerSize)
            }
        }
    }

    // MARK: Coach card

    private var coachLayer: some View {
        let width = min(380, containerSize.width - 2 * Space.margin)
        let measured = card
            .frame(maxWidth: width)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TutorialCardHeightKey.self, value: proxy.size.height)
                }
            )

        // Once the words are large enough, a step's card outgrows the room
        // between the safe area and the tab bar — and a card centred on a
        // screen it doesn't fit runs off BOTH ends, so the title and the
        // button that ends the lesson are equally unreachable. Above that
        // threshold, cap it and let it scroll. The height preference stays on
        // the card *inside* the scroll view, so it keeps reporting its own
        // intrinsic height and the branch can't flip-flop. Below the
        // threshold — every default-size lesson — this is the layer as shipped.
        return Group {
            if cardHeight > availableCardHeight {
                ScrollView { measured }
                    .frame(width: width, height: availableCardHeight)
            } else {
                measured
            }
        }
        .position(x: containerSize.width / 2, y: cardCenterY)
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        .onPreferenceChange(TutorialCardHeightKey.self) { cardHeight = $0 }
    }

    /// The vertical room a card may occupy — the same top and bottom
    /// clearances `cardCenterY` keeps, and exactly the height at which its
    /// `minCenter <= maxCenter` guard gives up.
    private var availableCardHeight: CGFloat {
        max(0, containerSize.height - safeAreaInsets.top - Space.l - safeAreaInsets.bottom - 72)
    }

    private var card: some View {
        TutorialCoachCard(step: step, position: position, controller: controller)
            .id(step.id)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
    }

    /// Where to centre the coach card. Prefer the gap opposite the target;
    /// if neither gap fits the measured card, centre it over the spotlight so
    /// it is always fully on-screen. A generous bottom clearance keeps it
    /// clear of a floating tab bar (which iOS doesn't report as a safe inset).
    private var cardCenterY: CGFloat {
        // A card taller than the room available is drawn capped and scrolling,
        // so centre the height it actually occupies. Identical below that
        // threshold, where the card is shorter than the room it has.
        let half = min(cardHeight, availableCardHeight) / 2
        let minCenter = safeAreaInsets.top + Space.l + half
        let bottomClearance = safeAreaInsets.bottom + 72
        let maxCenter = containerSize.height - bottomClearance - half
        let screenCenter = (minCenter + maxCenter) / 2

        guard minCenter <= maxCenter else { return containerSize.height / 2 }
        guard cardHeight > 0, let rect = spotRect else { return screenCenter }

        let gap = Space.l
        let below = rect.maxY + gap + half
        let above = rect.minY - gap - half
        let targetInTopHalf = rect.midY < containerSize.height * 0.5

        // Preferred side first, then the other, then centre-over.
        let preferred = targetInTopHalf ? below : above
        let fallback = targetInTopHalf ? above : below
        if fitsBelow(preferred, min: minCenter, max: maxCenter) { return clamp(preferred, minCenter, maxCenter) }
        if fitsBelow(fallback, min: minCenter, max: maxCenter) { return clamp(fallback, minCenter, maxCenter) }
        return screenCenter
    }

    private func fitsBelow(_ center: CGFloat, min: CGFloat, max: CGFloat) -> Bool {
        center >= min && center <= max
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }
}

private struct TutorialCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = Swift.max(value, nextValue())
    }
}

// MARK: - Passthrough blockers

/// Four clear panes surrounding the hole. They capture stray taps (so the
/// user can't wander off mid-lesson) while leaving the hole itself open for
/// the real control to receive the actual gesture.
struct TutorialBlockerPanes: View {
    let hole: CGRect
    let container: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            pane(CGRect(x: 0, y: 0, width: container.width, height: max(0, hole.minY)))
            pane(CGRect(x: 0, y: hole.maxY, width: container.width, height: max(0, container.height - hole.maxY)))
            pane(CGRect(x: 0, y: hole.minY, width: max(0, hole.minX), height: hole.height))
            pane(CGRect(x: hole.maxX, y: hole.minY, width: max(0, container.width - hole.maxX), height: hole.height))
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
    }

    private func pane(_ rect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture { Haptics.shared.play(.selection) }
            // Four tappable rectangles that only say "no". Left reachable they
            // are four unnamed buttons between the reader and the coach card.
            .accessibilityHidden(true)
    }
}

// MARK: - Coach card

struct TutorialCoachCard: View {
    let step: TutorialStep
    let position: (step: Int, total: Int)?
    let controller: TutorialController

    private var isLast: Bool { position.map { $0.step == $0.total } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                if let position {
                    Eyebrow("Tip \(position.step) of \(position.total)")
                }
                Spacer()
                Button("Skip") { controller.skip() }
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Ends this walkthrough and won't show it again")
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(step.title)
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.message)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionRow
        }
        .frame(maxWidth: 380, alignment: .leading)
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .calibreShadow(.modal)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actionRow: some View {
        switch step.advance {
        case .tapToContinue:
            Button {
                controller.advance()
            } label: {
                Text(isLast ? "Got it" : "Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
        case .perform(let event):
            if let prompt = step.actionPrompt {
                HStack(spacing: Space.s) {
                    Image(systemName: promptSymbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(prompt)
                        .font(CalibreType.bodySemiBold)
                }
                .foregroundStyle(Color.calibre.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isSummaryElement)
            }
            // A `.perform` step only ends when the real swipe, drag or
            // long-press happens — which Switch Control cannot produce and
            // VoiceOver cannot aim, so the lesson dead-ends and the screen
            // stays blocked. This is the way out, and only someone already
            // navigating by focus is ever shown it.
            if A11y.isNavigatingByFocus {
                Button {
                    controller.fire(event)
                } label: {
                    Text(isLast ? "Got it" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .accessibilityHint("Moves on without performing the gesture")
            }
        }
    }

    private var promptSymbol: String {
        switch step.hint {
        case .swipe, .drag: "hand.draw"
        case .longPress: "hand.tap.fill"
        case .type: "keyboard"
        default: "hand.tap"
        }
    }
}
