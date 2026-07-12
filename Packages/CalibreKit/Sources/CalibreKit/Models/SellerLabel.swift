import Foundation

// MARK: - Package

/// Box dimensions + weight the seller ships the watch in. Values ride the
/// wire as decimal strings (the backend echoes them back as strings).
public struct SellerLabelPackagePayload: Encodable, Sendable {
    public let boxLengthIn: String
    public let boxWidthIn: String
    public let boxHeightIn: String
    public let weightLb: String
    public let notes: String?

    public init(
        boxLengthIn: Decimal,
        boxWidthIn: Decimal,
        boxHeightIn: Decimal,
        weightLb: Decimal,
        notes: String? = nil
    ) {
        self.boxLengthIn = "\(boxLengthIn)"
        self.boxWidthIn = "\(boxWidthIn)"
        self.boxHeightIn = "\(boxHeightIn)"
        self.weightLb = "\(weightLb)"
        self.notes = notes
    }
}

/// The package as the backend echoes it (`_package_payload` — all strings).
public struct SellerLabelPackage: Codable, Sendable {
    public let boxLengthIn: APIDecimal?
    public let boxWidthIn: APIDecimal?
    public let boxHeightIn: APIDecimal?
    public let weightLb: APIDecimal?
    public let notes: String?
}

// MARK: - Quote & payment intent

/// One shipping-cost quote for the seller's to-auth label.
public struct SellerLabelQuote: Codable, Sendable {
    public let amount: APIDecimal
    public let currency: String
    public let provider: String?
    public let fallbackReason: String?
}

// FIXTURE-PENDING: shape from `SellerLabelQuoteView` /
// `SellerLabelPaymentIntentView` in app/api/views/orders.py.
/// `POST /orders/{id}/seller-label/quote` and `/seller-label/payment-intent`
/// share this shape. When a label already exists both short-circuit with
/// `alreadyCreated == true` plus the existing shipment; the payment-intent
/// variant otherwise carries the PaymentSheet fields.
public struct SellerLabelIntent: Codable, Sendable {
    public struct PaymentIntent: Codable, Sendable {
        public let id: String
        public let clientSecret: String
    }

    public let alreadyCreated: Bool?
    public let shipment: Shipment?
    public let paymentIntent: PaymentIntent?
    public let publishableKey: String?
    public let customerId: String?
    public let customerSessionClientSecret: String?
    public let quote: SellerLabelQuote?
    public let package: SellerLabelPackage?
}

// FIXTURE-PENDING: shape from `SellerLabelFinalizeView` in
// app/api/views/orders.py.
/// `POST /orders/{id}/seller-label/finalize` — the purchased label's
/// shipment and the advanced order.
public struct SellerLabelFinalizeResult: Codable, Sendable {
    public let alreadyCreated: Bool
    public let shipment: Shipment?
    public let order: Order?
}
