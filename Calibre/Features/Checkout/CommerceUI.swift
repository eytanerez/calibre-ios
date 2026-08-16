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
        ZStack {
            Color.calibre.secondary.opacity(0.5)
            if let request {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
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
        .frame(width: side, height: side)
        .clipped()
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

    private var fallbackGlyph: some View {
        Image(systemName: "clock")
            .font(.system(size: side * 0.3, weight: .light))
            .foregroundStyle(Color.calibre.placeholder)
            .accessibilityHidden(true)
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

/// The watches in a purchase, one row each: thumbnail, title, its own price
/// and shipping, and its own return terms.
///
/// A purchase covering several watches has one card fee, one tax line and one
/// total — but each watch keeps its own price, its own shipping and its own
/// return terms, because those are the seller's and two watches in one
/// purchase can differ. This card is where that per-watch truth is stated; the
/// combined column underneath is where the purchase's single figures are.
struct CheckoutItemsCard: View {
    let items: [CheckoutItem]
    /// Suppressed on screens that state return terms in their own section.
    var showsReturnTerms: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(CheckoutCopy.watchCount(items.count) + " in this purchase")

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 {
                        Rectangle()
                            .fill(Color.calibre.border)
                            .frame(height: 1)
                            .padding(.leading, 56 + Space.m + Space.l)
                    }
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

    private func row(_ item: CheckoutItem) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            SquareThumb(url: item.imageURL, side: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let line = priceLine(item) {
                    Text(line)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                if showsReturnTerms, let line = item.line.flatMap(CheckoutCopy.itemReturnLine) {
                    Text(line)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "$4,400 · Shipping $72" — both the server's own figures for this
    /// watch. Shipping drops out until the set has been priced to an address.
    private func priceLine(_ item: CheckoutItem) -> String? {
        guard let price = item.priceText else { return nil }
        guard let shipping = item.shippingText else { return price }
        return "\(price) · Shipping \(shipping)"
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

/// The clear and conspicuous notice a discount-presentation state (Connecticut
/// and Massachusetts today) owes the buyer: the price here depends on how they
/// pay, and by how much.
///
/// It belongs on every step where a payment method is being chosen or a price
/// is being shown, which is why it lives here rather than inside one screen —
/// a buyer who takes the wire route never reaches the review step, so a notice
/// that only appeared there would never be seen by the people it is for.
struct DiscountPresentationNotice: View {
    let breakdown: CheckoutBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            CalloutBand(
                icon: "info.circle",
                title: "The price here depends on how you pay",
                message: "The listed price is the card price. Paying by wire receives a discount off it. The final total is the same in every state — only how it is presented differs."
            )
            if !priceRows.isEmpty {
                SpecList(priceRows)
            }
        }
    }

    /// Both totals, from whichever key the payload carries them under. A
    /// figure the server hasn't sent is left out rather than derived.
    private var priceRows: [(String, String)] {
        let currency = breakdown.currency
        let card = breakdown.totals?.card?.value ?? breakdown.display?.price.value
        let wire = breakdown.totals?.wire?.value ?? breakdown.display?.wirePrice?.value
        guard let card, let wire else { return [] }
        return [
            ("Card price", PriceFormatter.format(card, currency: currency)),
            ("Wire price", PriceFormatter.format(wire, currency: currency)),
        ]
    }
}

/// A checkout failure, with the only honest next step under it.
///
/// The interesting case is a watch someone else got to first. In a purchase
/// of several that is not a dead end and must not read like one: the watch is
/// named, and the buyer is offered the rest of their set, re-priced. Only when
/// nothing would be left does this fall back to "back to the watch".
struct CheckoutProblemBlock: View {
    let model: CheckoutModel
    let problem: CheckoutProblem
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            InlineErrorLine(message: message)

            if let reserved = model.reservedWatch, model.canContinueWithoutReservedWatch {
                Button {
                    Haptics.shared.play(.press)
                    Task { await model.continueWithoutReservedWatch() }
                } label: {
                    BusyLabel(
                        title: "Continue without \(reserved.title)",
                        busy: model.preparingCardIntent || model.preparingWire
                    )
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.preparingCardIntent || model.preparingWire)

                Text("Nothing has been charged. We'll price your purchase again without it.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else if problem.listingReserved {
                Button("Back to the watch") {
                    Haptics.shared.play(.press)
                    model.path.removeAll()
                }
                .buttonStyle(.calibreGhost)
            } else if problem.retryable {
                Button("Try again", action: retry)
                    .buttonStyle(.calibreGhost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The server's own sentence, unless we can name the watch — in which
    /// case the buyer is told which one, and what is still on the table.
    private var message: String {
        guard problem.listingReserved, let reserved = model.reservedWatch else {
            return problem.message
        }
        let remaining = model.canContinueWithoutReservedWatch ? model.itemCount - 1 : 0
        return CheckoutCopy.reservedWatchMessage(reserved.title, remaining: remaining)
    }
}

/// The quiet note that a watch was left behind, said once rather than letting
/// the set silently shrink.
struct DroppedWatchNote: View {
    let title: String
    let remaining: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
            Text("We left \(title) out — someone else was checking out with it. You're buying \(CheckoutCopy.watchCount(remaining)).")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
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
