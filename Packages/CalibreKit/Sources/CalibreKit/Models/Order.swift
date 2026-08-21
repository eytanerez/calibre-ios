import Foundation

/// Order state machine:
/// awaiting_wire → purchased → to_auth → auth_pass|auth_fail → to_buyer →
/// delivered, with cancelled/refunded terminals.
public enum OrderStatus: String, Codable, Sendable {
    case awaitingWire = "awaiting_wire"
    case purchased
    case toAuth = "to_auth"
    case authPass = "auth_pass"
    case authFail = "auth_fail"
    case toBuyer = "to_buyer"
    case delivered
    case cancelled
    case refunded
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

public enum CheckoutPaymentMethod: String, Codable, Sendable {
    case card
    case wire
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

// FIXTURE-PENDING: authenticated captures blocked by the backend
// mid-migration; shape from `_serialize_order` in app/api/views/orders.py.
/// An order as `/orders/{id}`, `/buyer/orders` and `/account/sales` send it:
/// full money breakdown, shipments by leg, authentication result and the
/// shipping-address snapshot.
public struct Order: Codable, Sendable, Identifiable {
    public let id: String
    /// The number a person says out loud, rendered `#1041`. The uuid above
    /// stays the API identifier; this is display and support vocabulary, and
    /// is nil only on payloads recorded before order numbers existed.
    public let orderNumber: Int?
    public let buyerId: String
    public let listingId: String
    public let listing: ListingSummary?
    public let status: OrderStatus

    // Money breakdown (all Decimal-safe).
    public let subtotal: APIDecimal
    public let feesTotal: APIDecimal
    /// Historical seller fee snapshot captured at purchase time.
    public let sellerFeePercentApplied: APIDecimal?
    public let sellerFeeAmount: APIDecimal?
    public let taxTotal: APIDecimal?
    public let shippingBaseTotal: APIDecimal?
    public let shippingUpchargePercent: APIDecimal?
    public let shippingUpchargeTotal: APIDecimal?
    public let shippingTotal: APIDecimal?
    public let grandTotal: APIDecimal
    public let currency: String
    public let shippingQuoteProvider: String?

    // Payment & payout.
    public let checkoutPaymentMethod: CheckoutPaymentMethod?
    /// Wire orders: pay-by deadline for the 24 h reservation.
    public let paymentDueAt: Date?
    /// The $250 standing behind a wire, so the buyer can be told about the
    /// authorization they can see on their statement. Null on every card
    /// order, and on a wire paying off an offer whose deposit already covers
    /// it.
    public let wireHold: OrderWireHold?
    /// pending / pending_connect / released / reversed / refunded / …
    public let payoutStatus: String?
    public let payoutReleasedAt: Date?
    /// The seller-facing payout block: which trigger applies, the two dates,
    /// the first-payout hold, and the backend's own status/failure wording.
    public let payout: OrderPayout?

    // Returns.
    /// The return terms locked onto this order at purchase, plus the live
    /// window. Nil on payloads recorded before returns shipped.
    public let returns: OrderReturnTerms?
    /// The live return case, present only once a return exists. Read it
    /// through `returnSummary` — `return` is a keyword at the call site.
    public let `return`: OrderReturnSummary?
    /// Dates the backend expects to hit, plus the seller's payout forecast.
    public let expected: OrderExpected?

    /// The open (or finished) return on this order, if there is one.
    public var returnSummary: OrderReturnSummary? { self.return }

    /// The payout block to render: the order's own, falling back to the
    /// forecast under `expected` when only that is present.
    public var payoutBlock: OrderPayout? { payout ?? expected?.payout }

    // Seller fulfillment.
    /// "awaiting_wire_transfer" or "sold_awaiting_label_creation" when the
    /// seller owes an action.
    public let sellerActionState: String?
    public let fulfillmentDeadlineAt: Date?
    public let sellerLabelPaidAt: Date?
    public let sellerLabelCreatedAt: Date?
    /// What Calibre actually paid the carrier for the to-auth label. Deducted
    /// from the payout; `seller_label_paid_at` now means "Calibre paid".
    public let sellerLabelPriceTotal: APIDecimal?
    /// The box the seller measured, in the `box_*_in` names the order has
    /// always stored. Empty until the shipping form is submitted.
    public let sellerLabelPackage: SellerLabelPackage?
    /// Carrier ceilings the shipping form validates against before asking the
    /// server. Nil on payloads that predate the key — the form falls back to
    /// the same defaults the backend uses.
    public let shippingPackageLimits: ShippingPackageLimits?

    // Shipments & authentication.
    public let toAuthShipment: Shipment?
    public let toBuyerShipment: Shipment?
    public let latestShipment: Shipment?
    public let authResult: OrderAuthResult?

    // Addresses.
    public let shippingAddress: OrderShippingAddress?
    public let authCenterAddress: ShippingParty?

    public let createdAt: Date?
    public let updatedAt: Date?

    // MARK: Multi-item checkout

    /// The purchase this order came out of, when it came out of one. Nil on
    /// every order placed before groups existed.
    public let checkoutGroupId: String?
    /// The sibling orders bought in the same purchase. The server sends this
    /// only when there are two or more — a purchase of one watch has nothing
    /// for a "part of a purchase" affordance to point at.
    public let group: OrderGroup?

    /// `#1041` — the order's identity everywhere a person reads it, falling
    /// back to a short form of the uuid only when the server sent no number.
    public var displayNumber: String {
        if let orderNumber { return "#\(orderNumber)" }
        return "#" + String(id.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }

    /// How many watches were bought in this purchase, this one included.
    /// Always at least 1, so a caller never has to special-case an ungrouped
    /// order.
    public var purchaseItemCount: Int { group?.count ?? 1 }
}

/// `order.group` — every order id in the purchase, and how many there are.
public struct OrderGroup: Codable, Sendable, Hashable {
    public let orderIds: [String]
    public let count: Int

    /// The other watches in the purchase, from this order's point of view.
    public func siblingIDs(of orderID: String) -> [String] {
        orderIds.filter { $0 != orderID }
    }
}

/// `POST /orders/from-payment-intent` and `POST /checkout/wire-reservation`.
///
/// The payload is today's single-order shape with an `orders` array beside
/// it, so one response covers both kinds of checkout: `first` is what a
/// single-watch flow always read, and `orders` is what a set polls against
/// until its count matches what was checked out.
public struct OrderMaterialization: Decodable, Sendable {
    /// The order at the top level of the payload.
    public let first: Order
    /// Every order the purchase materialized, `first` included. A server that
    /// predates the array yields the single order, so `count` is never zero.
    public let orders: [Order]

    public var count: Int { orders.count }

    enum CodingKeys: String, CodingKey {
        case orders
    }

    public init(from decoder: Decoder) throws {
        first = try Order(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([Order].self, forKey: .orders) ?? []
        orders = decoded.isEmpty ? [first] : decoded
    }
}

public enum ShipmentType: String, Codable, Sendable {
    case toAuth = "to_auth"
    case toBuyer = "to_buyer"
    case returnToSeller = "return_to_seller"
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// One shipping leg (`_serialize_shipment`).
public struct Shipment: Codable, Sendable, Identifiable {
    public let id: String
    public let shipmentType: ShipmentType
    public let carrier: String?
    public let provider: String?
    public let providerShipmentId: String?
    public let trackingNumber: String?
    public let labelUrl: MediaURL?
    public let reference: String?
    public let referenceShowOnLabel: Bool?
    public let shippedAt: Date?
    public let deliveredAt: Date?
    public let createdAt: Date?
}

/// Carrier tracking history entry for a shipment.
public struct ShippingEvent: Codable, Sendable {
    public let status: String
    public let description: String?
    public let occurredAt: Date?
}

/// Authentication verdict attached to an order (`_serialize_auth_result`).
public struct OrderAuthResult: Codable, Sendable, Identifiable {
    public let id: String
    public let intakeId: String?
    public let outcome: String?
    public let notes: String?
    public let aftermarketFlag: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?
}

/// Immutable snapshot of where the order ships (`_serialize_order_shipping`).
public struct OrderShippingAddress: Codable, Sendable {
    public let fullName: String?
    public let phone: String?
    public let line1: String?
    public let line2: String?
    public let city: String?
    public let region: String?
    public let postalCode: String?
    public let country: String?
    public let sourceAddressId: String?
}

/// A shipping party address (e.g. the authentication center).
public struct ShippingParty: Codable, Sendable {
    public let fullName: String?
    public let companyName: String?
    public let line1: String?
    public let line2: String?
    public let city: String?
    public let region: String?
    public let postalCode: String?
    public let country: String?
    public let phone: String?
    public let email: String?
}

/// One `/orders/{id}/timeline` entry (buyer view is server-filtered).
public struct OrderEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let status: String
    public let actorType: String?
    public let notes: String?
    public let createdAt: Date?
}

// FIXTURE-PENDING: shape from `serialize_seller_review` in
// app/api/views/reviews.py.
/// Verified-purchase seller review — one per delivered order.
public struct SellerReview: Codable, Sendable, Identifiable {
    public let id: String
    public let sellerId: String?
    public let buyerId: String?
    public let orderId: String?
    public let rating: Int
    public let comment: String?
    public let createdAt: Date?
    public let updatedAt: Date?
}


/// The $250 authorization behind a wire order, as the order payload reports
/// it. There is no client-side release control anywhere: the hold is released
/// when the transfer arrives and captured when the deadline passes.
public struct OrderWireHold: Codable, Sendable {
    public let amount: APIDecimal?
    /// Stripe's own vocabulary — `requires_capture` is "authorized, waiting".
    public let status: String?
    public let authorizedAt: Date?
    public let releasedAt: Date?
    public let capturedAt: Date?

    enum CodingKeys: String, CodingKey {
        case amount, status, authorizedAt, releasedAt, capturedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try? container.decodeIfPresent(APIDecimal.self, forKey: .amount)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        authorizedAt = try? container.decodeIfPresent(Date.self, forKey: .authorizedAt)
        releasedAt = try? container.decodeIfPresent(Date.self, forKey: .releasedAt)
        capturedAt = try? container.decodeIfPresent(Date.self, forKey: .capturedAt)
    }

    /// The authorization is live on the card right now.
    public var isLive: Bool {
        releasedAt == nil && capturedAt == nil && authorizedAt != nil
    }
}

/// Carrier ceilings the shipping form checks before it asks the server.
public struct ShippingPackageLimits: Codable, Sendable {
    public let maxLengthIn: Double?
    public let maxGirthPlusLengthIn: Double?
}
