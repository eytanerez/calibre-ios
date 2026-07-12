import CalibreDesign
import CalibreKit
import NukeUI
import Nuke
import SwiftUI

// Shared display pieces for the money track (checkout + offers).

/// Square image well on the quiet secondary fill, downsampled to its
/// container. The watch is the hero; the well never competes.
struct SquareThumb: View {
    let url: URL?
    var side: CGFloat

    var body: some View {
        LazyImage(request: request) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: side * 0.3, weight: .light))
                    .foregroundStyle(Color.calibre.placeholder)
            }
        }
        .frame(width: side, height: side)
        .background(Color.calibre.secondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var request: ImageRequest? {
        guard let url else { return nil }
        let pixels = side * UIScreen.main.scale
        return ImageRequest(
            url: url,
            processors: [.resize(size: CGSize(width: pixels, height: pixels), unit: .pixels, crop: true)]
        )
    }
}

/// Compact listing summary row — image well, eyebrow brand line, title,
/// serif price. Used at the top of review, offer entry and offer detail.
struct ListingMiniCard: View {
    let title: String
    let eyebrow: String
    let priceText: String
    let imageURL: URL?

    init(title: String, eyebrow: String, priceText: String, imageURL: URL?) {
        self.title = title
        self.eyebrow = eyebrow
        self.priceText = priceText
        self.imageURL = imageURL
    }

    init(listing: Listing) {
        self.init(
            title: listing.title,
            eyebrow: [listing.brand, listing.productionYear.map(String.init)]
                .compactMap(\.self)
                .joined(separator: " · "),
            priceText: PriceFormatter.format(listing.price.value, currency: listing.currency),
            imageURL: listing.images.first?.url
        )
    }

    var body: some View {
        HStack(spacing: Space.m) {
            SquareThumb(url: imageURL, side: 64)

            VStack(alignment: .leading, spacing: 3) {
                if !eyebrow.isEmpty {
                    Eyebrow(eyebrow)
                }
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(2)
                Text(priceText)
                    .font(CalibreType.priceSmall)
                    .foregroundStyle(Color.calibre.foreground)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Skeleton stand-in for the mini card while the listing loads.
struct ListingMiniCardSkeleton: View {
    var body: some View {
        HStack(spacing: Space.m) {
            Rectangle().frame(width: 64, height: 64).shimmer()
            VStack(alignment: .leading, spacing: Space.s) {
                Rectangle().frame(width: 90, height: 10).shimmer()
                Rectangle().frame(width: 160, height: 14).shimmer()
                Rectangle().frame(width: 70, height: 16).shimmer()
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}

/// The slim step eyebrow above checkout — "SHIPPING → PAYMENT → REVIEW" with
/// the current step in ink. Quiet by design; the one sanctioned uppercase.
struct EyebrowProgress: View {
    let steps: [String]
    let currentIndex: Int

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(steps.indices, id: \.self) { index in
                Eyebrow(
                    steps[index],
                    color: index == currentIndex
                        ? Color.calibre.foreground
                        : Color.calibre.mutedForeground.opacity(0.55)
                )
                if index < steps.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.calibre.mutedForeground.opacity(0.4))
                }
            }
        }
        .animation(Motion.easeMedium, value: currentIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(steps.count): \(steps[currentIndex])")
    }
}

/// Inline destructive error line with a quiet entrance.
struct InlineErrorLine: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(CalibreType.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.calibre.destructive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .offset(y: -3)))
    }
}

/// Primary button label that swaps in a compact progress while busy.
struct BusyLabel: View {
    let title: String
    let busy: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.calibre.primaryForeground)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}
