import CalibreDesign
import CalibreKit
import NukeUI
import SwiftUI

/// One deck card: image-forward — the watch photo fills the top ~70%, and a
/// quiet identity panel (eyebrow brand line, serif title, serif price,
/// condition pill) sits below.
struct DeckCard: View {
    let listing: Listing

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                photo(width: geo.size.width, height: geo.size.height * 0.7)
                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    // MARK: - Photo

    private func photo(width: CGFloat, height: CGFloat) -> some View {
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
    }

    private var fallbackGlyph: some View {
        Image(systemName: "clock")
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(Color.calibre.placeholder)
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if !eyebrowText.isEmpty {
                Eyebrow(eyebrowText)
            }
            Text(listing.title)
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Spacer(minLength: Space.s)

            HStack(alignment: .center, spacing: Space.m) {
                Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                    .font(CalibreType.price)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let condition = listing.condition?.overall {
                    StatusBadge(condition)
                }
            }
        }
        .padding(Space.l)
    }

    private var eyebrowText: String {
        [listing.brand, listing.productionYear.map(String.init)]
            .compactMap(\.self)
            .joined(separator: " · ")
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
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
        .accessibilityLabel("Loading the deck")
    }

    private var underPlate: some View {
        RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
            .fill(Color.calibre.card)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
}
