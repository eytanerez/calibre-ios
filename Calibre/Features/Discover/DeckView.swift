import CalibreDesign
import CalibreKit
import SwiftUI

/// What a committed swipe means. Right is save, left is pass.
enum SwipeDirection: Equatable {
    case save, pass
}

/// The interactive stack: the top three cards, a finger-following drag with
/// clamped rotation, SAVE/PASS affordances past 40% of the commit threshold,
/// and an ease-out fly-off (crossfade under Reduce Motion). Pure gesture
/// physics — what a swipe *means* lives in DiscoverScreen.
struct DeckView: View {
    let cards: [Listing]
    /// Set by the control-row buttons to trigger a programmatic swipe;
    /// cleared here once the flight starts.
    @Binding var command: SwipeDirection?
    let namespace: Namespace.ID
    /// Fired the moment a swipe commits (flight start) — semantics happen now.
    let onCommit: (Listing, SwipeDirection) -> Void
    /// Fired when the flight lands — pop the top card here.
    let onAdvance: () -> Void
    let onTap: (Listing) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var translation: CGSize = .zero
    /// The armed haptic fires exactly once per drag.
    @State private var armed = false
    @State private var flying: SwipeDirection?
    /// Reduce Motion commits crossfade instead of flying.
    @State private var topOpacity: Double = 1
    /// 0→1 as the drag nears commit; under-cards scale/lift in sync.
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let commitDistance = size.width * 0.35
            // The bottom 20pt of the geometry is reserved for the under-card
            // peek bands, so the stack reads as a stack.
            let cardSize = CGSize(width: size.width, height: max(size.height - 20, 0))

            ZStack(alignment: .top) {
                ForEach(Array(visible.enumerated()).reversed(), id: \.element.id) { depth, listing in
                    if depth == 0 {
                        topCard(listing, cardSize: cardSize, commitDistance: commitDistance)
                    } else {
                        underCard(listing, depth: depth, cardSize: cardSize)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .onChange(of: command) { _, direction in
                guard let direction else { return }
                command = nil
                guard flying == nil else { return }
                fly(direction, from: .zero, size: size)
            }
        }
    }

    private var visible: [Listing] {
        Array(cards.prefix(3))
    }

    // MARK: - Cards

    private func topCard(_ listing: Listing, cardSize: CGSize, commitDistance: CGFloat) -> some View {
        DeckCard(listing: listing)
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(alignment: .top) { affordances(commitDistance: commitDistance) }
            .matchedTransitionSource(id: listing.id, in: namespace)
            .calibreShadow(translation == .zero ? .resting : .lifted)
            .rotationEffect(.degrees(rotationDegrees), anchor: .bottom)
            .offset(translation)
            .opacity(topOpacity)
            .onTapGesture {
                guard flying == nil, translation == .zero else { return }
                onTap(listing)
            }
            .gesture(dragGesture(size: cardSize, commitDistance: commitDistance))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(for: listing))
            .accessibilityHint("Opens the listing. Use the pass and save buttons below to swipe.")
            .accessibilityAddTraits(.isButton)
    }

    private func underCard(_ listing: Listing, depth: Int, cardSize: CGSize) -> some View {
        let depthProgress = CGFloat(depth) - min(progress, 1)
        return DeckCard(listing: listing)
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(
                // A whisper of warm-ink dimming that lifts as the card rises.
                RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                    .fill(Color.calibre.shadowTint.opacity(0.06 * depthProgress))
            )
            // Anchored at the bottom so the 10/20pt offsets read as visible
            // peek bands under the top card.
            .scaleEffect(1 - 0.03 * depthProgress, anchor: .bottom)
            .offset(y: 10 * depthProgress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Physics

    /// Rotation follows the drag: width/20, clamped to ±8°.
    private var rotationDegrees: Double {
        Double(max(-8, min(8, translation.width / 20)))
    }

    private func dragGesture(size: CGSize, commitDistance: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard flying == nil else { return }
                translation = value.translation
                progress = min(abs(value.translation.width) / commitDistance, 1)
                if !armed, abs(value.translation.width) > commitDistance {
                    armed = true
                    Haptics.shared.play(.armed)
                }
            }
            .onEnded { value in
                guard flying == nil else { return }
                let width = value.translation.width
                let overDistance = abs(width) > commitDistance
                let overVelocity = abs(value.velocity.width) > 800
                armed = false

                if overDistance || overVelocity {
                    let direction: SwipeDirection = overDistance
                        ? (width > 0 ? .save : .pass)
                        : (value.velocity.width > 0 ? .save : .pass)
                    fly(direction, from: value.translation, size: size)
                } else if reduceMotion {
                    translation = .zero
                    progress = 0
                } else {
                    withAnimation(Motion.easeMedium) {
                        translation = .zero
                        progress = 0
                    }
                }
            }
    }

    /// Commit: haptic + semantics fire now; the card flies off along the drag
    /// vector over 420ms of ease-out (a crossfade under Reduce Motion), the
    /// next card scaling up in sync.
    private func fly(_ direction: SwipeDirection, from current: CGSize, size: CGSize) {
        guard let top = cards.first else { return }
        flying = direction
        Haptics.shared.play(direction == .save ? .save : .pass)
        onCommit(top, direction)

        if reduceMotion {
            withAnimation(Motion.easeMedium) {
                topOpacity = 0
                progress = 1
            } completion: {
                land()
            }
            return
        }

        let sign: CGFloat = direction == .save ? 1 : -1
        let targetX = sign * size.width * 1.35
        // Continue along the drag's own slope; straight out from a button.
        let slope = current.width == 0 ? 0 : current.height / abs(current.width)
        let targetY = slope * abs(targetX)
        withAnimation(Motion.easeSlow) {
            translation = CGSize(width: targetX, height: targetY)
            progress = 1
        } completion: {
            land()
        }
    }

    /// Flight over: pop the card and reset — instantly, so the under-card's
    /// promotion to top produces no second animation.
    private func land() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            onAdvance()
            translation = .zero
            progress = 0
            topOpacity = 1
            flying = nil
        }
    }

    // MARK: - Affordances

    /// SAVE (top-left, success-tinted) and PASS (top-right, muted) fade in
    /// past 40% of the commit threshold, full strength at commit.
    private func affordances(commitDistance: CGFloat) -> some View {
        let signedProgress = commitDistance == 0 ? 0 : translation.width / commitDistance
        return HStack {
            affordanceTag("Save", isSave: true)
                .opacity(affordanceOpacity(for: signedProgress))
            Spacer()
            affordanceTag("Pass", isSave: false)
                .opacity(affordanceOpacity(for: -signedProgress))
        }
        .padding(Space.l)
        .accessibilityHidden(true)
    }

    private func affordanceOpacity(for signedProgress: CGFloat) -> Double {
        Double(max(0, min(1, (signedProgress - 0.4) / 0.6)))
    }

    private func affordanceTag(_ text: String, isSave: Bool) -> some View {
        Eyebrow(text, color: isSave ? Color.calibre.success : Color.calibre.mutedForeground)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .background(Color.calibre.background.opacity(0.92), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSave ? Color.calibre.success.opacity(0.5) : Color.calibre.borderBright,
                    lineWidth: 1
                )
            )
    }

    private func accessibilitySummary(for listing: Listing) -> String {
        var parts: [String] = []
        if let brand = listing.brand { parts.append(brand) }
        parts.append(listing.title)
        parts.append(PriceFormatter.format(listing.price.value, currency: listing.currency))
        if let condition = listing.condition?.overall { parts.append(condition) }
        return parts.joined(separator: ", ")
    }
}
