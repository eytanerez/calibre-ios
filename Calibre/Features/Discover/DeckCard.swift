import CalibreDesign
import CalibreKit
import NukeUI
import SwiftUI

/// One deck card: image-forward — the watch photo fills the top ~70%, and a
/// quiet identity panel sits below.
///
/// The panel follows CALIBRE_FINAL_PUSH_CONTRACTS.md §4's element order, the
/// same one `ListingCard` uses, because §4 fixes that order across the whole
/// product and the deck is the second listing-card shape:
///
///     [ photo ]  ⌐ condition pill top-left   ⌐ watcher count top-right
///     BRAND                                          year
///     Model name
///     Ref. 0000000
///     [ verified-dealer chip, only when true ]
///     $ price
///
/// The deck keeps `sectionTitle` for the model line where the grid card uses
/// `bodyMedium` — §4 fixes the order, not the type size, and this card is the
/// full width of the screen.
struct DeckCard: View {
    let listing: Listing

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                photo(width: geo.size.width, height: geo.size.height * 0.7)
                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    // MARK: - Photo

    private func photo(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Color.calibre.secondary.opacity(0.5)
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

            // §4: the condition pill rides top-left over the photograph and
            // the watcher count top-right. Both used to sit in the panel
            // below, where the condition badge shared the price's row.
            if let condition = listing.condition?.overall {
                ConditionPill(condition)
                    .padding(Space.m)
            }
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
            .foregroundStyle(Color.calibre.placeholder)
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
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.75)

            if let reference = listing.referenceNumber {
                Text("Ref. \(reference)")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
            }

            if listing.seller?.isVerifiedDealer == true {
                DealerBadge(compact: true)
                    .padding(.top, 2)
            }

            Spacer(minLength: Space.s)

            Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                .font(CalibreType.price)
                .foregroundStyle(Color.calibre.foreground)
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
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
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
            .fill(Color.calibre.card)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
}
