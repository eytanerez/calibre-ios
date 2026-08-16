import Foundation

// FIXTURE-PENDING: shapes from `CheckoutPaymentIntentView` / `CheckoutIntentView`
// in app/api/views/orders.py and Backend/docs/mobile-api.md §2.

/// Server-priced money breakdown shared by every checkout flavor. Web card
/// checkout sends `tax_calculated_upfront: false`; the native PaymentIntent
/// and wire paths compute tax up front so the charged amount is final.
public struct CheckoutBreakdown: Decodable, Sendable {
    public let subtotal: APIDecimal
    /// Buyer-side fees (currently just the card processing cost).
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

    // MARK: Breakdown v2

    /// How this order's price is presented. In `discount` states the listed
    /// price is the card price and wire earns a discount off it; the final
    /// total is identical either way.
    public let pricingMode: PricingMode?
    /// The exact processing cost, with the percent and fixed parts the
    /// receipt line quotes. Never reconstructed client-side.
    public let cardFee: CardFee?
    /// Both totals, so a buyer can see the wire number before switching.
    public let totals: MethodTotals?
    /// Which card fundings this order accepts, e.g. ["credit"] or
    /// ["credit","debit"]. Prepaid is never in this list.
    public let acceptedCardFunding: [String]?
    /// The prices to display for this order under its pricing mode.
    public let display: DisplayPrices?
    public let paymentDisclosures: PaymentDisclosures?
    /// The listing's return terms, so checkout can state them with real
    /// numbers before the buyer pays.
    public let returns: ListingReturnTerms?
    /// What a return would cost, for the same disclosure.
    public let returnFee: ReturnFeeTerms?

    public enum PricingMode: String, Decodable, Sendable {
        case surcharge
        case discount
        case unknown

        public init(from decoder: Decoder) throws {
            self = try decodeWireStatus(from: decoder, fallback: .unknown)
        }
    }

    public struct CardFee: Decodable, Sendable {
        /// e.g. "2.90" — the percent the receipt line quotes.
        public let percent: APIDecimal?
        /// e.g. "0.30".
        public let fixed: APIDecimal?
        public let amount: APIDecimal
    }

    public struct MethodTotals: Decodable, Sendable {
        public let card: APIDecimal?
        public let wire: APIDecimal?
    }

    public struct DisplayPrices: Decodable, Sendable {
        /// In discount mode this is the card-inclusive price.
        public let price: APIDecimal
        /// In discount mode, the lower wire price. Nil elsewhere.
        public let wirePrice: APIDecimal?
    }

    public struct PaymentDisclosures: Decodable, Sendable {
        public let cardFeeNonrefundable: Bool?
    }

    /// True where surcharges are prohibited and the discount presentation
    /// applies (Connecticut and Massachusetts today). Those screens owe a
    /// clear and conspicuous notice of the payment-method price difference.
    public var isDiscountPresentation: Bool {
        pricingMode == .discount
    }

    /// Whether a debit card is accepted on this order.
    public var acceptsDebit: Bool {
        acceptedCardFunding?.contains("debit") ?? false
    }
}

/// `POST /checkout/validate-payment-method` — run the moment a PaymentMethod
/// exists, while wire is still one tap away.
///
/// `reason` is one of prepaid_not_accepted, debit_not_accepted_in_state,
/// card_funding_not_accepted, card_funding_unknown.
public struct PaymentMethodValidation: Decodable, Sendable {
    public let accepted: Bool
    /// "credit", "debit", "prepaid" or "unknown" as the network reports it.
    public let funding: String?
    public let pricingMode: CheckoutBreakdown.PricingMode?
    public let acceptedCardFunding: [String]?
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case accepted, funding, pricingMode, acceptedCardFunding, reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
        funding = try container.decodeIfPresent(String.self, forKey: .funding)
        pricingMode = try? container.decodeIfPresent(CheckoutBreakdown.PricingMode.self, forKey: .pricingMode)
        acceptedCardFunding = try container.decodeIfPresent([String].self, forKey: .acceptedCardFunding)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// `POST /checkout/confirm` — the server confirms the PaymentIntent. When
/// `requiresAction` is true, hand `clientSecret` to the SDK's next-action
/// handling and then materialize the order as usual.
public struct CheckoutConfirmation: Decodable, Sendable {
    public let status: String
    public let clientSecret: String?
    public let requiresAction: Bool
    public let funding: String?

    enum CodingKeys: String, CodingKey {
        case status, clientSecret, requiresAction, funding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        clientSecret = try container.decodeIfPresent(String.self, forKey: .clientSecret)
        requiresAction = try container.decodeIfPresent(Bool.self, forKey: .requiresAction) ?? false
        funding = try container.decodeIfPresent(String.self, forKey: .funding)
    }
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
