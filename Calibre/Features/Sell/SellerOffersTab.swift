import CalibreDesign
import CalibreKit
import SwiftUI

/// Offers buyers have made, the ones needing an answer first.
///
/// Rows only — answering happens on the offer itself, which owns accept,
/// counter and decline along with the hold that rides on them. Rebuilding any
/// of that here would be a second implementation of the same negotiation.
struct SellerOffersTab: View {
    let offers: [Offer]
    /// The seller's own listings, for the photograph on a row. Offers arrive
    /// with a listing summary that carries no image.
    let listings: [Listing]
    let actions: SellerShopActions

    var body: some View {
        Group {
            if offers.isEmpty {
                emptyState.sellRow()
            } else {
                ForEach(sortedOffers) { offer in
                    offerRow(offer)
                        .sellRow(bottom: Space.m)
                }
            }
        }
    }

    /// Waiting on the seller first, then by whichever clock is running,
    /// soonest first; everything settled falls to the bottom, newest first.
    /// The payload arrives newest-first, which buries an offer about to
    /// expire under three that already have their answer.
    private var sortedOffers: [Offer] {
        offers.sorted { first, second in
            let firstWaiting = first.status == .pendingSeller
            let secondWaiting = second.status == .pendingSeller
            if firstWaiting != secondWaiting { return firstWaiting }
            switch (offerLiveDeadline(for: first), offerLiveDeadline(for: second)) {
            case let (.some(left), .some(right)) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            return (first.createdAt ?? .distantPast) > (second.createdAt ?? .distantPast)
        }
    }

    private func offerRow(_ offer: Offer) -> some View {
        let presentation = offerStatusPresentation(for: offer, viewerIsSeller: true)
        let listing = listings.first { $0.id == offer.listingId }
        return Button {
            actions.openOffer(offer.id)
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                SellThumb(url: listing?.images.first?.url)

                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.listing?.title ?? listing?.title ?? "Your listing")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)

                    // The amount on the table right now, which after a
                    // counter is not the amount the offer opened at.
                    Text(PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency))
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)

                    if let asking = offer.listing?.price.value ?? listing?.price.value {
                        Text("Asking \(PriceFormatter.format(asking, currency: offer.currency))")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    HStack(spacing: Space.s) {
                        StatusBadge(presentation.text, tone: presentation.tone)
                        if let deadline = offerLiveDeadline(for: offer) {
                            CountdownChip(until: deadline)
                        }
                    }
                    .padding(.top, 2)

                    if let buyer = offer.buyer?.username {
                        Text("From @\(buyer)")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    if let message = offerLatestMessage(offer) {
                        Text(message)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .padding(.top, Space.xs)
            }
            .padding(Space.m)
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the offer, where you can accept, counter or decline")
    }

    private var emptyState: some View {
        EmptyState(
            icon: "arrow.left.arrow.right",
            title: "No one has made an offer yet",
            message: "When a buyer offers on one of your watches it lands here, with their deposit already held and the clock running.",
            aside: "The first number is rarely the last one."
        )
    }
}
