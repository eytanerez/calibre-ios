import CalibreDesign
import CalibreKit
import SwiftUI

/// What a committed swipe means. Right is save, left is pass.
enum SwipeDirection: Equatable {
    case save, pass
}

private enum DeckDragAxis {
    case horizontal, vertical
}

/// A card that has committed and is flying off — purely cosmetic, detached
/// from `cards` so it never blocks the next gesture.
private struct DepartingCard: Identifiable {
    let listing: Listing
    let direction: SwipeDirection
    /// The drag offset at the instant of commit — the flight continues along
    /// this vector rather than snapping to a straight line.
    let startTranslation: CGSize
    var id: String { listing.id }
}

/// The interactive stack: the top three cards, a finger-following drag with
/// clamped rotation, SAVE/PASS affordances past 40% of the commit threshold,
/// and an ease-out fly-off (crossfade under Reduce Motion). A commit advances
/// the stack immediately — the departing card animates away as a detached
/// overlay so the next card is live from the very next touch, in one
/// continuous motion with no dead window. Pure gesture physics — what a
/// swipe *means* lives in DiscoverScreen.
struct DeckView: View {
    let cards: [Listing]
    /// Set by the control-row buttons to trigger a programmatic swipe;
    /// cleared here once the flight starts.
    @Binding var command: SwipeDirection?
    let namespace: Namespace.ID
    /// Fired the moment a swipe commits (flight start) — semantics happen now.
    let onCommit: (Listing, SwipeDirection) -> Void
    /// Fired the moment a swipe commits — pop the top card here, synchronously,
    /// so the next card is interactive immediately.
    let onAdvance: () -> Void
    let onTap: (Listing) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var translation: CGSize = .zero
    /// The armed haptic fires exactly once per drag.
    @State private var armed = false
    /// 0→1 as the drag nears commit; under-cards scale/lift in sync.
    @State private var progress: CGFloat = 0
    /// Lock the gesture to one axis after the first deliberate movement so a
    /// diagonal thumb path cannot make a card jump or accidentally commit.
    @State private var dragAxis: DeckDragAxis?

    /// The card currently flying off, animating independently of the live
    /// stack below it. Never blocks input.
    @State private var departing: DepartingCard?
    @State private var departingOffset: CGSize = .zero
    @State private var departingOpacity: Double = 1

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

                if let departing {
                    DeckCard(listing: departing.listing)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .calibreShadow(.lifted)
                        .rotationEffect(.degrees(rotation(for: departingOffset)), anchor: .bottom)
                        .offset(departingOffset)
                        .opacity(departingOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(10)
                        .id(departing.id)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .onChange(of: command) { _, direction in
                guard let direction else { return }
                command = nil
                commit(direction, dragOffset: .zero, size: size)
            }
            .onChange(of: cards.first?.id) {
                // Defensive reset for external mutations (Undo reinstates a
                // card, a feed refill/reset swaps the stack) — a commit we
                // triggered ourselves already reset this state synchronously.
                resetDrag(animated: false)
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
            .rotationEffect(.degrees(rotation(for: translation)), anchor: .bottom)
            .offset(translation)
            .onTapGesture {
                guard translation == .zero else { return }
                onTap(listing)
            }
            .highPriorityGesture(dragGesture(listing: listing, size: cardSize, commitDistance: commitDistance))
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
    private func rotation(for offset: CGSize) -> Double {
        Double(max(-8, min(8, offset.width / 20)))
    }

    private func dragGesture(listing: Listing, size: CGSize, commitDistance: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if dragAxis == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    // Wait for a more deliberate sample and bias toward
                    // horizontal — swiping is the primary gesture here, and a
                    // natural thumb path drifts vertically enough at the
                    // first ~10pt that an even split too easily mis-locked
                    // to vertical, silently ignoring the rest of a genuine
                    // horizontal swipe.
                    guard max(horizontal, vertical) >= 18 else { return }
                    dragAxis = vertical > horizontal * 1.4 ? .vertical : .horizontal
                }

                guard dragAxis == .horizontal else { return }

                // Horizontal movement stays one-to-one with the finger. A
                // small damped vertical component keeps the card tactile
                // without letting diagonal drags throw it around the screen.
                let dampedY = max(-44, min(44, value.translation.height * 0.22))
                translation = CGSize(width: value.translation.width, height: dampedY)
                progress = min(abs(value.translation.width) / commitDistance, 1)
                if !armed, abs(value.translation.width) >= commitDistance {
                    armed = true
                    Haptics.shared.play(.armed)
                }
            }
            .onEnded { value in
                guard dragAxis == .horizontal else {
                    resetDrag(animated: false)
                    return
                }

                let width = value.translation.width
                let overDistance = abs(width) > commitDistance
                let predictedWidth = value.predictedEndTranslation.width
                // Prediction is useful for a quick flick, but require a real
                // horizontal start so a tiny tap or vertical gesture never
                // dismisses the card.
                let intentionalFlick = abs(width) >= 36
                    && abs(predictedWidth) > commitDistance
                    && abs(predictedWidth) > abs(value.predictedEndTranslation.height)
                armed = false

                if overDistance || intentionalFlick {
                    let decidingWidth = overDistance ? width : predictedWidth
                    let direction: SwipeDirection = decidingWidth > 0 ? .save : .pass
                    let dampedY = max(-44, min(44, value.translation.height * 0.22))
                    commit(direction, dragOffset: CGSize(width: value.translation.width, height: dampedY), size: size)
                } else if reduceMotion {
                    resetDrag(animated: false)
                } else {
                    resetDrag(animated: true)
                }
            }
    }

    private func resetDrag(animated: Bool) {
        let changes = {
            translation = .zero
            progress = 0
            armed = false
            dragAxis = nil
        }
        if animated {
            withAnimation(Motion.easeMedium, changes)
        } else {
            changes()
        }
    }

    /// Commit: haptic + semantics fire now, the stack advances in the very
    /// same call (so the next card is interactive before this function
    /// returns), and the departing card peels off as a detached overlay that
    /// can never block the next gesture.
    private func commit(_ direction: SwipeDirection, dragOffset: CGSize, size: CGSize) {
        guard let top = cards.first else { return }
        Haptics.shared.play(direction == .save ? .save : .pass)

        // Reset the interactive state instantly — the promoted card was
        // never dragged and must render at rest, not mid-animation.
        translation = .zero
        progress = 0
        armed = false
        dragAxis = nil

        // Advance first: `cards` (owned by the parent) drops its head now,
        // so the next card is already promoted and gesture-ready by the time
        // this function returns — one continuous motion, no dead window.
        onCommit(top, direction)
        onAdvance()

        // The departing card is a snapshot, fully decoupled from `cards`.
        departing = DepartingCard(listing: top, direction: direction, startTranslation: dragOffset)
        departingOffset = dragOffset
        departingOpacity = 1

        if reduceMotion {
            withAnimation(Motion.easeMedium) {
                departingOpacity = 0
            } completion: {
                departing = nil
            }
            return
        }

        let sign: CGFloat = direction == .save ? 1 : -1
        let targetX = sign * size.width * 1.35
        // Continue along the drag's own slope; straight out from a button.
        let slope = dragOffset.width == 0 ? 0 : dragOffset.height / abs(dragOffset.width)
        let targetY = slope * abs(targetX)
        withAnimation(Motion.easeSlow) {
            departingOffset = CGSize(width: targetX, height: targetY)
        } completion: {
            departing = nil
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
