import CalibreDesign
import CalibreKit
import Foundation
import Observation
import SwiftUI

/// Every offer status in plain human words, tinted for the right urgency.
/// Copy adapts to whose turn it is — the same `pending_seller` reads
/// "Waiting on the seller" to the buyer and "Waiting on you" to the seller.
struct OfferStatusPresentation {
    let text: String
    let tone: StatusBadge.Tone
}

func offerStatusPresentation(for offer: Offer, viewerIsSeller: Bool) -> OfferStatusPresentation {
    switch offer.status {
    case .holdPending:
        return .init(text: "Hold not completed", tone: .warning)
    case .holdFailed:
        return .init(text: "Hold not completed", tone: .danger)
    case .pendingSeller:
        return viewerIsSeller
            ? .init(text: "Waiting on you", tone: .warning)
            : .init(text: "Waiting on the seller", tone: .info)
    case .countered:
        return viewerIsSeller
            ? .init(text: "You countered", tone: .info)
            : .init(text: "The seller countered", tone: .warning)
    case .acceptedPendingPayment:
        return .init(text: "Accepted — payment due", tone: .success)
    case .paid:
        return .init(text: "Paid", tone: .success)
    case .declined:
        return .init(text: "Declined", tone: .danger)
    case .withdrawn:
        return .init(text: "Withdrawn", tone: .neutral)
    case .expired:
        return .init(text: "Expired", tone: .neutral)
    case .penaltyCaptured:
        return .init(text: "Deposit charged", tone: .danger)
    case .unknown:
        return .init(text: "Updated", tone: .neutral)
    }
}

/// The live deadline a countdown should track, when one exists.
func offerLiveDeadline(for offer: Offer) -> Date? {
    let deadline: Date? = switch offer.status {
    case .pendingSeller, .countered: offer.expiresAt
    case .acceptedPendingPayment: offer.buyerPaymentDueAt
    default: nil
    }
    guard let deadline, deadline > .now else { return nil }
    return deadline
}

/// Whether the viewer is the seller side of this offer.
func offerViewerIsSeller(_ offer: Offer, userID: String?) -> Bool {
    if let perspective = offer.perspective {
        return perspective == "received"
    }
    return offer.sellerId == userID
}

/// The latest amount on the table (the last negotiation round, falling back
/// to the offer amount).
func offerCurrentAmount(_ offer: Offer) -> Decimal {
    offer.negotiationHistory.last?.amount.value ?? offer.amount.value
}

/// The most recent message in the negotiation, for row previews.
func offerLatestMessage(_ offer: Offer) -> String? {
    if let message = offer.negotiationHistory.last(where: { $0.message?.isEmpty == false })?.message {
        return message
    }
    if let response = offer.sellerResponse, !response.isEmpty { return response }
    if let message = offer.buyerMessage, !message.isEmpty { return message }
    return nil
}

/// An offer can still be walked away from by the buyer while it's open.
func offerIsOpen(_ offer: Offer) -> Bool {
    switch offer.status {
    case .holdPending, .pendingSeller, .countered, .acceptedPendingPayment:
        true
    default:
        false
    }
}

/// Fetches and caches listing thumbnails for offer rows — the offer payload
/// carries no image, so rows resolve their listing lazily, once each.
@MainActor
@Observable
final class ListingThumbCache {
    @ObservationIgnored private let catalog: CatalogStore
    private var thumbs: [String: URL] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []

    init(catalog: CatalogStore) {
        self.catalog = catalog
    }

    func url(for listingID: String) -> URL? {
        thumbs[listingID]
    }

    func warm(listingID: String) {
        guard thumbs[listingID] == nil, !inFlight.contains(listingID) else { return }
        inFlight.insert(listingID)
        Task { [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(listingID) }
            guard let listing = try? await self.catalog.listing(id: listingID),
                  let url = listing.images.first?.url else { return }
            self.thumbs[listingID] = url
        }
    }
}

/// Mini-card built from the offer's own listing summary (no image on the
/// wire — the thumb comes from the cache when it lands).
struct OfferListingMiniCard: View {
    let offer: Offer
    let thumbURL: URL?

    var body: some View {
        ListingMiniCard(
            title: offer.listing?.title ?? "Listing",
            eyebrow: offer.listing?.listingNumber.map { "Listing #\($0)" } ?? "",
            priceText: PriceFormatter.format(
                offer.listing?.price.value ?? offer.amount.value,
                currency: offer.listing?.currency ?? offer.currency
            ),
            imageURL: thumbURL
        )
    }
}
