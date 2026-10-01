import RewoundDesign
import RewoundKit
import NukeUI
import SwiftUI

/// One deck card: image-forward — the watch photo fills the top ~70%, and a
/// quiet identity panel sits below.
///
/// The panel follows REWOUND_FINAL_PUSH_CONTRACTS.md §4's element order, the
/// same one `ListingCard` uses, because §4 fixes that order across the whole
/// product and the deck is the second listing-card shape:
///
///     [ photo ]                              ⌐ watcher count top-right
///     BRAND                                          year
///     Model name
///     Ref. 0000000
///     (Like New) (ⓘ Bracelet: Worn)
///     Unpolished · All original · Full set
///     [ verified-dealer chip, only when true ]
///     $ price
///
/// The grade left the photograph for the line under the title on 2026-09-30,
/// and the two condition rows are the grid card's own (Option D, 2026-10-01):
/// the grade pill with a neutral outlined pill beside it when a part was
/// graded lower, then the seller's facts. One reading on every card shape.
/// The deck is a single card with no neighbour to line up with, so it holds
/// neither row when it has nothing to put in it.
///
/// The deck keeps `sectionTitle` for the model line where the grid card uses
/// `bodyMedium` — §4 fixes the order, not the type size, and this card is the
/// full width of the screen.
struct DeckCard: View {
    let listing: Listing

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The panel's natural height, measured off a hidden copy. The photo gives
    /// way to it (down to a floor) so a long note is never cut off.
    @State private var panelHeight: CGFloat = 0

    private var breakdown: ConditionBreakdown { ConditionBreakdown(listing: listing) }

    /// 70% of the card, as drawn before the facts existed, less whatever the
    /// panel needs beyond the 30% that leaves it; never under 40%.
    static func photoHeight(card: CGFloat, panel: CGFloat) -> CGFloat {
        max(card * 0.4, min(card * 0.7, card - panel))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                photo(
                    width: geo.size.width,
                    height: Self.photoHeight(card: geo.size.height, panel: panelHeight)
                )
                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(alignment: .topLeading) {
                panel
                    .frame(width: geo.size.width, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
            }
        }
        .background(Color.rewound.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
    }

    // MARK: - Photo

    private func photo(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Color.rewound.secondary.opacity(0.5)
                if let url = listing.images.first?.url {
                    LazyImage(request: DeckImage.request(for: url)) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else if state.error != nil {
                            fallbackGlyph
                        } else {
                            Rectangle().shimmer()
                        }
                    }
                } else {
                    fallbackGlyph
                }
            }
            .frame(width: width, height: height)
            .clipped()

            // §4: the watcher count rides top-right over the photograph. The
            // grade rode top-left until 2026-09-30, when it moved under the
            // title to lead the seller's answers.
            if let watchers = listing.metrics?.watchers, watchers > 0 {
                WatcherPill(count: watchers)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: width, height: height)
    }

    private var fallbackGlyph: some View {
        Image(systemName: "clock")
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(Color.rewound.placeholder)
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // Brand left, year right — the same arrangement, and the same
            // no-clipping rules, as `ListingCard`. The year takes its width
            // first and is pinned against compression; the brand shrinks and
            // then wraps rather than ever ending in an ellipsis (§0.6).
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Eyebrow(listing.brand ?? "Watch")
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)
                if let year = listing.productionYear.map(String.init) {
                    Spacer(minLength: Space.xs)
                    Eyebrow(year)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
            }

            Text(listing.model ?? listing.title)
                .font(RewoundType.sectionTitle)
                .foregroundStyle(Color.rewound.foreground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.75)

            if let reference = listing.referenceNumber {
                Text("Ref. \(reference)")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
            }

            let grade = GradeScale.cleaned(listing.condition?.overall)
            let part = breakdown.cardChip
            if grade != nil || part != nil {
                CardConditionRow(grade: grade, part: part, reserves: false)
                    .padding(.top, Space.xs)
            }
            CardFactsLine(
                facts: ListingHistoryWords.cardFacts(for: listing),
                font: RewoundType.label,
                reserves: false
            )

            if listing.seller?.isVerifiedDealer == true {
                DealerBadge(compact: true)
                    .padding(.top, 2)
            }

            Spacer(minLength: Space.s)

            Text(PriceFormatter.listing(listing.price.value, currency: listing.currency))
                .font(RewoundType.price)
                .foregroundStyle(Color.rewound.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
    }
}

/// Card-shaped shimmer used while the first page loads (and when a refill is
/// catching up) — the deck keeps its silhouette instead of showing a spinner.
struct DeckCardSkeleton: View {
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Rectangle()
                    .frame(height: geo.size.height * 0.7)
                    .shimmer()
                VStack(alignment: .leading, spacing: Space.m) {
                    Rectangle().frame(width: 90, height: 10).shimmer()
                    Rectangle().frame(width: 210, height: 20).shimmer()
                    Spacer(minLength: 0)
                    Rectangle().frame(width: 110, height: 18).shimmer()
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.rewound.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
    }
}

/// The loading silhouette of the whole deck — a top skeleton over two
/// under-plates at the stack's resting scales and offsets.
struct DeckSkeleton: View {
    var body: some View {
        ZStack {
            underPlate.scaleEffect(0.94, anchor: .bottom).offset(y: 20)
            underPlate.scaleEffect(0.97, anchor: .bottom).offset(y: 10)
            DeckCardSkeleton()
        }
        .padding(.bottom, 20)
        // A ZStack of shimmer plates is not an accessibility element, so the
        // label below had nothing to attach to and the deck came up silent —
        // VoiceOver found no cards and no explanation for why.
        .accessibilityElement()
        .accessibilityLabel("Loading the deck")
    }

    private var underPlate: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.rewound.card)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
    }
}
