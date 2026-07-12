import Foundation

/// Full offer lifecycle, including the $250 good-faith hold states and
/// multi-round counter negotiation.
public enum OfferStatus: String, Codable, Sendable {
    /// Stripe card hold being authorized.
    case holdPending = "hold_pending"
    case holdFailed = "hold_failed"
    /// Hold authorized; waiting on the seller.
    case pendingSeller = "pending_seller"
    /// Seller countered; waiting on the buyer.
    case countered
    /// Agreed — buyer must pay by `buyerPaymentDueAt`.
    case acceptedPendingPayment = "accepted_pending_payment"
    case paid
    case declined
    case withdrawn
    case expired
    /// Buyer missed the payment deadline; the hold was captured.
    case penaltyCaptured = "penalty_captured"
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

// FIXTURE-PENDING: authenticated captures blocked by the backend
// mid-migration; shape from `_serialize_offer` in app/api/views/offers.py.
/// An offer as every offers endpoint serializes it. `hold.clientSecret` and
/// `publishableKey` are only present on the create response.
public struct Offer: Codable, Sendable, Identifiable {
    public let id: String
    public let listingId: String
    public let buyerId: String
    public let sellerId: String
    /// Set once the offer is paid and an order exists.
    public let orderId: String?
    public let amount: APIDecimal
    public let currency: String
    public let status: OfferStatus
    public let buyerMessage: String?
    public let sellerResponse: String?
    /// Ordered negotiation rounds, oldest first (max 20).
    public let negotiationHistory: [NegotiationEntry]
    /// "seller" when pending_seller, "buyer" when countered, else nil.
    public let awaiting: String?
    public let expiresAt: Date?
    public let buyerPaymentDueAt: Date?
    public let buyerPenaltyConsentAt: Date?
    public let acceptedAt: Date?
    public let paidAt: Date?
    public let hold: OfferHold?
    public let buyer: OfferParticipant?
    public let listing: OfferListingSummary?
    /// "sent" or "received", relative to the caller.
    public let perspective: String?
    /// Stripe publishable key — create response only.
    public let publishableKey: String?
    /// Stripe customer session secret — create response only.
    public let customerSessionClientSecret: String?
    public let createdAt: Date?
    public let updatedAt: Date?
}

/// One `negotiation_history` round: `{by, amount, message, at}`.
public struct NegotiationEntry: Codable, Sendable {
    /// "buyer" or "seller".
    public let by: String
    public let amount: APIDecimal
    public let message: String?
    public let at: Date?
}

/// The good-faith card hold riding on an offer.
public struct OfferHold: Codable, Sendable {
    public let amount: APIDecimal
    public let currency: String?
    /// Mirrors the Stripe PaymentIntent status string.
    public let status: String?
    public let paymentIntentId: String?
    public let captureBefore: Date?
    public let authorizedAt: Date?
    public let releasedAt: Date?
    public let capturedAt: Date?
    /// PaymentSheet-compatible client secret — create response only.
    public let clientSecret: String?
}

public struct OfferParticipant: Codable, Sendable, Identifiable {
    public let id: String
    public let username: String
}

public struct OfferListingSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let listingNumber: Int?
    public let title: String
    public let status: ListingStatus
    public let price: APIDecimal
    public let currency: String
}
