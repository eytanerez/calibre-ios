import Foundation

// FIXTURE-PENDING: shapes from `CheckoutPaymentIntentView` / `CheckoutIntentView`
// in app/api/views/orders.py and Backend/docs/mobile-api.md §2.

/// Server-priced money breakdown shared by every checkout flavor. Web card
/// checkout sends `tax_calculated_upfront: false`; the native PaymentIntent
/// and wire paths compute tax up front so the charged amount is final.
public struct CheckoutBreakdown: Decodable, Sendable {
    public let subtotal: APIDecimal
    /// Buyer-side fees (currently just the card convenience fee).
    public let fees: APIDecimal
    public let cardConvenienceFee: APIDecimal?
    public let cardConvenienceFeePercent: APIDecimal?
    /// "card" or "wire".
    public let paymentMethod: String?
    public let sellerFeePercentApplied: APIDecimal?
    public let sellerFeeAmount: APIDecimal?
    public let shipping: APIDecimal
    public let tax: APIDecimal?
    public let taxCalculatedUpfront: Bool?
    public let grandTotal: APIDecimal
    public let currency: String
    public let shippingProvider: String?
    public let offerId: String?
}

/// A Stripe PaymentIntent as the backend hands it to PaymentSheet.
public struct PaymentIntentHandle: Decodable, Sendable {
    public let id: String
    public let clientSecret: String
}

/// `POST /checkout/payment-intent` — the native card checkout. Confirm
/// `paymentIntent.clientSecret` with PaymentSheet, then materialize the order
/// via `POST /orders/from-payment-intent`.
public struct NativeCheckoutIntent: Decodable, Sendable {
    public let paymentIntent: PaymentIntentHandle
    public let publishableKey: String
    public let customerId: String
    /// CustomerSession secret with the `mobile_payment_element` component;
    /// nil when Stripe hiccuped — PaymentSheet still works without it.
    public let customerSessionClientSecret: String?
    public let breakdown: CheckoutBreakdown
}

/// `POST /checkout/create-intent` with `payment_method: "wire"` — the wire
/// transfer path. The intent carries Stripe bank-transfer instructions; the
/// 24 h reservation is claimed via `POST /checkout/wire-reservation`.
public struct WireCheckout: Decodable, Sendable {
    public let session: SessionStub?
    public let wire: WireIntent
    public let breakdown: CheckoutBreakdown

    /// The web-shape session envelope; only `expiresAt` (unix seconds, the
    /// 24 h pay-by moment) matters to the native client.
    public struct SessionStub: Decodable, Sendable {
        public let id: String?
        public let expiresAt: Int?

        /// `expires_at` as a Date, when present.
        public var expiresAtDate: Date? {
            expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    }
}

/// The wire PaymentIntent plus its displayable bank-transfer instructions.
public struct WireIntent: Decodable, Sendable {
    public let paymentIntentId: String
    /// Stripe intent status string, e.g. "requires_action".
    public let status: String
    public let instructions: WireInstructions?
}

/// Stripe `display_bank_transfer_instructions`, trimmed by the backend.
public struct WireInstructions: Decodable, Sendable {
    /// e.g. "us_bank_transfer".
    public let type: String?
    /// The transfer memo the buyer MUST include or the wire can't be matched.
    public let reference: String?
    public let amountRemaining: APIDecimal?
    public let currency: String?
    public let hostedInstructionsUrl: String?
    public let financialAddresses: [WireFinancialAddress]

    enum CodingKeys: String, CodingKey {
        case type, reference, amountRemaining, currency, hostedInstructionsUrl
        case financialAddresses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        amountRemaining = try container.decodeIfPresent(APIDecimal.self, forKey: .amountRemaining)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        hostedInstructionsUrl = try container.decodeIfPresent(String.self, forKey: .hostedInstructionsUrl)
        financialAddresses = (try? container.decodeIfPresent([WireFinancialAddress].self, forKey: .financialAddresses)) ?? []
    }
}

/// One Stripe financial address. US test-mode transfers send an `aba` entry;
/// `swift` appears for international rails. Unknown shapes decode to nils
/// rather than failing the checkout.
public struct WireFinancialAddress: Decodable, Sendable {
    /// "aba" or "swift".
    public let type: String?
    public let supportedNetworks: [String]?
    public let aba: Details?
    public let swift: Details?

    public struct Details: Decodable, Sendable {
        public let bankName: String?
        public let routingNumber: String?
        public let accountNumber: String?
        public let swiftCode: String?
        public let accountHolderName: String?
        public let accountType: String?
    }

    /// The bank detail block regardless of rail.
    public var details: Details? { aba ?? swift }
}
