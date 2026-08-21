import CalibreDesign
import CalibreKit
import StripePaymentSheet
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
        // Canonical vocabulary: the good-faith hold was forfeited to the
        // seller. It was never a penalty deposit, and it was never a charge
        // the buyer chose to make.
        return viewerIsSeller
            ? .init(text: "Hold forfeited to you", tone: .neutral)
            : .init(text: "Hold forfeited", tone: .danger)
    case .unknown:
        return .init(text: "Updated", tone: .neutral)
    }
}

// MARK: - The hold figure

/// The hold riding on an offer, formatted from the payload. Once an offer
/// exists this is the only sanctioned source of the figure — no screen may
/// state it from memory. Nil when the payload carries no hold, in which case
/// the sentence is written without a number rather than with a guess.
func offerHoldText(_ offer: Offer?) -> String? {
    guard let offer, let hold = offer.hold else { return nil }
    return PriceFormatter.format(hold.amount.value, currency: hold.currency ?? offer.currency)
}

/// The hold figure for a screen that may not have an offer yet: the offer's
/// own hold first, the marketplace config second, and no number at all third.
/// A live payload figure always wins over the config.
@MainActor
func offerHoldText(_ offer: Offer?, config: ConfigStore) -> String? {
    offerHoldText(offer) ?? config.offerHoldText
}

/// "$250 hold" when the figure is known, plain "hold" when it isn't, so the
/// surrounding sentence reads properly either way.
func offerHoldNoun(_ holdText: String?) -> String {
    guard let holdText else { return "hold" }
    return "\(holdText) hold"
}

/// The currency the hold is denominated in, for figures the server derives
/// from it.
func offerHoldCurrency(_ offer: Offer) -> String {
    offer.hold?.currency ?? offer.currency
}

/// A forfeit the server has actually settled. An empty object on the wire is
/// not one, and must not be read as an outcome.
func offerSettledForfeit(_ offer: Offer) -> OfferForfeit? {
    guard let forfeit = offer.forfeit,
          forfeit.forfeitedAt != nil || forfeit.sellerAmount != nil
    else { return nil }
    return forfeit
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

// MARK: - The deposit, and renewing it

/// How close to expiring a live offer's authorization has to be before the
/// buyer is asked to replace it. Card authorizations do not last forever and
/// a negotiation can easily outlive one; an offer must never sit accepted
/// with no live deposit behind it.
let offerHoldRenewalWindowHours = 48

/// The three states where the deposit is the thing holding everything
/// together: a negotiation still moving, and an acceptance still waiting to be
/// paid. Mirrors `offers.LIVE_HOLD_OFFER_STATUSES`.
let offerLiveHoldStatuses: Set<OfferStatus> = [.pendingSeller, .countered, .acceptedPendingPayment]

/// Whether this offer's deposit runs out soon enough to ask for a new one.
///
/// The date is `hold.captureBefore` — the last moment the authorization can
/// be captured, which is what actually expires. An offer that is no longer
/// live, a hold already released or captured, and a payload with no date at
/// all all answer false: none of them has anything left to renew.
func offerHoldNeedsRenewal(
    _ offer: Offer?,
    withinHours: Int = offerHoldRenewalWindowHours,
    now: Date = .now
) -> Bool {
    guard let offer, let hold = offer.hold, let captureBefore = hold.captureBefore else { return false }
    guard offerLiveHoldStatuses.contains(offer.status) else { return false }
    guard hold.releasedAt == nil, hold.capturedAt == nil else { return false }
    return captureBefore <= now.addingTimeInterval(TimeInterval(max(1, withinHours)) * 3600)
}

/// A 409 refusing an offer action because the deposit behind it has aged out.
/// Not a refusal of the price — a refusal to let an offer sit accepted with
/// nothing behind it. The same renewal the banner offers is what clears it.
func offerHoldRenewalRequired(_ error: Error) -> Bool {
    (error as? APIError)?.serverCode == "offer_hold_renewal_required"
}

/// Runs one deposit renewal: cancel-and-replace the authorization, then
/// confirm the new intent with the card sheet the offer flow already uses.
///
/// Owned by the screen rather than the store because the sheet has to outlive
/// the call — Stripe holds it weakly.
@MainActor
@Observable
final class OfferHoldRenewer {
    @ObservationIgnored private let commerce: CommerceStore

    private(set) var renewing = false
    var error: String?
    @ObservationIgnored private var paymentSheet: PaymentSheet?

    init(commerce: CommerceStore) {
        self.commerce = commerce
    }

    /// Replaces the deposit. Answers the refreshed offer on success so the
    /// caller can redraw from the server's own account of it.
    func renew(offerID: String) async -> Offer? {
        guard !renewing else { return nil }
        renewing = true
        error = nil
        defer { renewing = false }

        let renewed: Offer
        do {
            renewed = try await commerce.renewOfferHold(offerID: offerID)
        } catch {
            self.error = (error as? APIError)?.errorDescription
                ?? "We couldn\u{2019}t renew the hold just now. Please try again shortly."
            return nil
        }

        // No secret means Stripe took the new authorization without asking
        // the buyer anything — there is nothing left to confirm.
        guard let clientSecret = renewed.hold?.clientSecret else {
            Haptics.shared.play(.success)
            return renewed
        }
        if let key = renewed.publishableKey {
            STPAPIClient.shared.publishableKey = key
        }
        let sheet = PaymentSheet(
            paymentIntentClientSecret: clientSecret,
            configuration: CalibreStripe.configuration(
                customerID: nil,
                customerSessionClientSecret: nil
            )
        )
        paymentSheet = sheet

        let outcome: PaymentSheetResult = await withCheckedContinuation { continuation in
            CalibreStripe.present(sheet) { result in
                continuation.resume(returning: result)
            }
        }
        switch outcome {
        case .completed:
            Haptics.shared.play(.success)
            return (try? await commerce.confirmHold(offerID: offerID)) ?? renewed
        case .canceled:
            error = "The new authorization wasn\u{2019}t completed, so this offer still needs one."
            return nil
        case .failed(let failure):
            error = CalibreStripe.failureMessage(for: failure)
            return nil
        }
    }
}

// MARK: - What a seller would take home

/// What a seller would take home on an offer, worked out from published
/// figures: the amount, less the commission at their own effective rate
/// (floored at the marketplace minimum), less the estimated label to
/// authentication.
///
/// Nothing here invents a rate — an unknown rate produces no answer at all,
/// because a made-up number next to "you'd take home" is worse than no
/// number. It is an estimate and must be labelled as one wherever it is
/// shown: the shipping figure is priced from a standard box nobody has
/// measured, and the real label is bought after the sale.
struct SellerNetProceeds {
    let offerAmount: Decimal
    /// The greater of the percentage and the marketplace minimum.
    let commission: Decimal
    /// True when the marketplace minimum charged instead of the percentage.
    let minimumApplied: Bool
    let shipping: Decimal
    /// Amount less commission less shipping. Never below zero.
    let takeHome: Decimal

    init?(offerAmount: Decimal, feePercent: Decimal?, feeMinimum: Decimal?, shippingEstimate: Decimal?) {
        guard offerAmount > 0, let feePercent else { return nil }
        let percentageFee = offerAmount * feePercent / 100
        let minimum = feeMinimum ?? 0
        let commission = max(percentageFee, minimum)
        let shipping = shippingEstimate ?? 0
        self.offerAmount = offerAmount
        self.commission = commission
        // A floor that beat the percentage is the only honest explanation for
        // a commission line that does not divide, so it is reported rather
        // than left for the seller to wonder about.
        self.minimumApplied = minimum > percentageFee
        self.shipping = shipping
        self.takeHome = max(0, offerAmount - commission - shipping)
    }
}

// MARK: - Forfeiture disclosure (canonical §Offers, placements §17.5)

/// Canonical §Offers: payment is due within 24 hours of acceptance.
///
/// The figure itself comes from `offer_payment_deadline_hours` on the
/// marketplace config; this constant is only what the sentence falls back to
/// while the config hasn't landed, so the disclosure is never silent about a
/// deadline the buyer is being held to.
private let canonicalPaymentDueHours = 24

func offerPaymentDuePhrase(_ deadlineHours: Int?) -> String {
    "\(deadlineHours ?? canonicalPaymentDueHours) hours"
}

/// Canonical §Offers: offers expire after 24 hours. Same rule as above — the
/// config's `offer_ttl_hours` wins, and this is only the unloaded fallback.
private let canonicalOfferTtlHours = 24

func offerExpiryPhrase(_ ttlHours: Int?) -> String {
    "\(ttlHours ?? canonicalOfferTtlHours) hours"
}

/// Canonical §Offers: a failed payment leaves 12 hours to resolve it. The
/// config's `offer_payment_grace_hours` wins; this is the unloaded fallback.
private let canonicalGraceHours = 12

/// The window a buyer has to fix a failed payment, in words.
private func offerGracePhrase(_ graceHours: Int?) -> String {
    "\(graceHours ?? canonicalGraceHours) hours"
}

/// The disclosure §17.5 requires **at placement**, spoken to the buyer about
/// to authorize the hold. Every figure arrives from the caller — payload
/// first, marketplace config second — and a figure the server hasn't stated
/// drops out of the sentence instead of being invented.
func offerPlacementDisclosure(
    holdText: String?,
    expiryHours: Int?,
    graceHours: Int?,
    paymentDueHours: Int?
) -> String {
    let holdPhrase = holdText.map { "a refundable \($0) hold" } ?? "a refundable hold"
    let expiry = "Your offer expires after \(offerExpiryPhrase(expiryHours)) if the seller does not respond."

    return """
    Placing an offer authorizes \(holdPhrase) on your credit card. It is a hold, not a charge, and it is \
    released once you pay. \(expiry)

    An accepted offer is a sale, with the same fees and the same return terms as any purchase, and payment \
    is due within \(offerPaymentDuePhrase(paymentDueHours)) of acceptance. If your payment fails you have \
    \(offerGracePhrase(graceHours)) to resolve it. If you do not, your \(offerHoldNoun(holdText)) is \
    forfeited to the seller, less the cost of processing it.
    """
}

/// The disclosure §17.5 requires **at acceptance**, adapted to whose money is
/// at risk. `amountText` is the agreed price; every other figure is optional
/// and drops out of the sentence when the server hasn't stated it.
func offerAcceptanceDisclosure(
    amountText: String,
    holdText: String?,
    graceHours: Int?,
    paymentDueHours: Int?,
    viewerIsSeller: Bool,
    buyerName: String
) -> String {
    let holdNoun = offerHoldNoun(holdText)
    let grace = offerGracePhrase(graceHours)
    let due = offerPaymentDuePhrase(paymentDueHours)

    if viewerIsSeller {
        return """
        Accepting makes this a sale at \(amountText), with the same fees and the same return terms as any \
        purchase. The listing is reserved while \(buyerName) pays, and payment is due within \(due).

        If their payment fails they have \(grace) to resolve it. If they do not, their \(holdNoun) is \
        forfeited to you, less the cost of processing it.
        """
    }

    return """
    You are agreeing to buy this watch for \(amountText). An accepted offer is a sale, with the same fees \
    and the same return terms as any purchase, and payment is due within \(due).

    If your payment fails you have \(grace) to resolve it. If you do not, your \(holdNoun) is forfeited to \
    the seller, less the cost of processing it.
    """
}

// MARK: - The payment-failure warning and its settled outcome

/// What a screen shows once a payment has failed after acceptance: the clock,
/// the exact amount at stake, and what happens if the clock runs out — or,
/// once it has run out, the outcome the server settled on.
struct OfferResolutionNotice {
    enum Emphasis {
        /// The clock is still running and money is still at risk.
        case urgent
        /// Settled. A record, not a warning.
        case settled
    }

    let emphasis: Emphasis
    let icon: String
    let title: String
    /// The live deadline, while it is still in the future.
    let deadline: Date?
    /// The exact figure, straight from the payload — never computed here.
    let amountText: String?
    let amountCaption: String
    let message: String
}

/// Builds the notice for an offer, or nil when there is nothing to warn about.
/// Once `forfeit` is present the outcome replaces the warning; the net figure
/// the seller received is only ever the server's own `sellerAmount`, and is
/// omitted entirely when the server hasn't sent it.
@MainActor
func offerResolutionNotice(
    for offer: Offer,
    viewerIsSeller: Bool,
    config: ConfigStore
) -> OfferResolutionNotice? {
    let holdText = offerHoldText(offer, config: config)
    let holdNoun = offerHoldNoun(holdText)

    if let forfeit = offerSettledForfeit(offer) {
        var message: String
        if viewerIsSeller {
            message = "The payment was not resolved in time, so the buyer's \(holdNoun) was forfeited to "
                + "you, less the cost of processing it."
            if let sellerAmount = forfeit.sellerAmount {
                let net = PriceFormatter.format(sellerAmount.value, currency: offerHoldCurrency(offer))
                message += " You received \(net)."
            }
        } else {
            message = "The payment was not resolved in time, so your \(holdNoun) was forfeited to the "
                + "seller, less the cost of processing it."
        }
        return OfferResolutionNotice(
            emphasis: .settled,
            icon: "lock.shield",
            title: viewerIsSeller ? "The hold was forfeited to you" : "Your hold was forfeited",
            deadline: nil,
            amountText: holdText,
            amountCaption: "Forfeited",
            message: message
        )
    }

    guard offer.paymentFailedAt != nil || offer.resolveBy != nil else { return nil }

    let deadline = offer.resolveBy.flatMap { $0 > .now ? $0 : nil }
    let grace = offerGracePhrase(config.paymentGraceHours)
    let stillRunning = deadline != nil

    let message: String
    if viewerIsSeller {
        message = stillRunning
            ? "The buyer has \(grace) from the failed payment to resolve it. If they do not, their "
                + "\(holdNoun) is forfeited to you, less the cost of processing it."
            : "The buyer had \(grace) to resolve it. If it stays unresolved, their \(holdNoun) is "
                + "forfeited to you, less the cost of processing it."
    } else {
        message = stillRunning
            ? "You have \(grace) from the failed payment to resolve it. If you do not, your \(holdNoun) "
                + "is forfeited to the seller, less the cost of processing it."
            : "You had \(grace) to resolve it. If it stays unresolved, your \(holdNoun) is forfeited to "
                + "the seller, less the cost of processing it."
    }

    return OfferResolutionNotice(
        emphasis: .urgent,
        icon: "exclamationmark.triangle",
        title: viewerIsSeller ? "The buyer's payment didn't go through" : "Your payment didn't go through",
        deadline: deadline,
        amountText: holdText,
        amountCaption: "At stake",
        message: message
    )
}

/// Renders an ``OfferResolutionNotice``. Urgent carries the destructive tint
/// at low weight — prominent without shouting, because money at risk deserves
/// precision rather than alarm. Settled borrows ``CalloutBand``'s quiet
/// chrome, because nothing is at risk any more.
struct OfferResolutionBand: View {
    let notice: OfferResolutionNotice

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: notice.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 32, height: 32)
                .background(
                    Color.calibre.card,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: Space.s) {
                Text(notice.title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                if let deadline = notice.deadline {
                    CountdownChip(until: deadline)
                }

                if let amountText = notice.amountText {
                    VStack(alignment: .leading, spacing: 1) {
                        Eyebrow(notice.amountCaption)
                        Text(amountText)
                            .font(CalibreType.price)
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .padding(.top, 2)
                }

                Text(notice.message)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(Space.l)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var iconTint: Color {
        switch notice.emphasis {
        case .urgent: Color.calibre.destructive
        case .settled: Color.calibre.mutedForeground
        }
    }

    private var fill: Color {
        switch notice.emphasis {
        case .urgent: Color.calibre.destructive.opacity(0.07)
        case .settled: Color.calibre.accent.opacity(0.4)
        }
    }

    private var stroke: Color {
        switch notice.emphasis {
        case .urgent: Color.calibre.destructive.opacity(0.28)
        case .settled: Color.calibre.border
        }
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
