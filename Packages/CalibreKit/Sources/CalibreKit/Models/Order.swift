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
    /// pending / pending_connect / released / reversed / refunded / …
    public let payoutStatus: String?
    public let payoutReleasedAt: Date?

    // Seller fulfillment.
    /// "awaiting_wire_transfer" or "sold_awaiting_label_creation" when the
    /// seller owes an action.
    public let sellerActionState: String?
    public let fulfillmentDeadlineAt: Date?
    public let sellerLabelPaidAt: Date?
    public let sellerLabelCreatedAt: Date?
    public let sellerLabelPriceTotal: APIDecimal?

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
