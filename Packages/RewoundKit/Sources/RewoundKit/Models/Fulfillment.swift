import Foundation

// The seller's part of fulfillment, start to finish. The seller no longer
// buys their own label: they say how big the box is, Calibre buys the label,
// and what it actually cost comes off their payout. The four label-checkout
// endpoints this replaced are gone from the API.

// MARK: - The box

/// Box dimensions and weight as the shipping form asks for them — inches and
/// pounds, the words a person filling in a form knows. Values ride the wire as
/// decimal strings so nothing is lost to binary floating point.
public struct FulfillmentPackagePayload: Encodable, Sendable, Equatable {
    public let length: String
    public let width: String
    public let height: String
    public let weight: String
    public let notes: String?

    public init(length: Decimal, width: Decimal, height: Decimal, weight: Decimal, notes: String? = nil) {
        self.length = "\(length)"
        self.width = "\(width)"
        self.height = "\(height)"
        self.weight = "\(weight)"
        self.notes = notes
    }
}

/// The package as the order stores and echoes it — the `box_*_in`/`weight_lb`
/// names everything downstream has always used.
public struct SellerLabelPackage: Codable, Sendable {
    public let boxLengthIn: APIDecimal?
    public let boxWidthIn: APIDecimal?
    public let boxHeightIn: APIDecimal?
    public let weightLb: APIDecimal?
    public let notes: String?

    /// Whether anything was ever recorded — the server sends `{}` until the
    /// seller submits the form.
    public var isEmpty: Bool {
        boxLengthIn == nil && boxWidthIn == nil && boxHeightIn == nil && weightLb == nil
    }
}

// MARK: - Quote

/// `POST /orders/{id}/fulfillment/shipping-quote` — what this box would cost.
/// Nothing is bought and nothing is charged; this is the figure the form
/// shows next to the payout while the seller is still choosing a box.
///
/// An order that already has a to-auth label answers `alreadyCreated: true`
/// with that shipment instead of a price.
public struct FulfillmentShippingQuote: Decodable, Sendable {
    public let alreadyCreated: Bool?
    public let shipment: Shipment?
    public let amount: APIDecimal?
    public let currency: String?
    public let provider: String?
    public let fallbackReason: String?
    public let package: SellerLabelPackage?
    /// What this box does to the money — the server's own ledger, never a
    /// subtraction done here.
    public let payoutPreview: PayoutBreakdown?
}

// MARK: - Submit

/// `POST /orders/{id}/fulfillment/shipping-details` — the form, submitted.
/// Calibre buys the label immediately and the order starts moving to
/// authentication. Idempotent: an order that already has a to-auth label
/// answers with that label and `alreadyCreated: true`, and Calibre never buys
/// a second one.
public struct FulfillmentShippingDetails: Decodable, Sendable {
    public struct Label: Decodable, Sendable {
        public let url: MediaURL?
        public let trackingNumber: String?
        public let carrier: String?
    }

    public let alreadyCreated: Bool
    public let shipment: Shipment?
    public let label: Label?
    public let payoutPreview: PayoutBreakdown?
    /// The advanced order, so the caller never has to re-fetch it.
    public let order: Order?
}
