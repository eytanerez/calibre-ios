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

    // MARK: Tax availability

    /// Where the `tax` figure came from: "provider", "debug_stub" or
    /// "unavailable". The quote endpoints used to answer 503 when the tax
    /// provider was down; they now price everything else and say so here.
    ///
    /// Optional, like the two warnings below, because a server that predates
    /// that change sends none of the three keys — and a quote that decodes
    /// with an unknown tax source is worth far more than one that throws.
    public let taxSource: String?
    /// The server's own sentence for a tax outage. Print it verbatim where it
    /// is present: it is the wording the site shows, and two platforms
    /// explaining the same outage differently is its own kind of wrong.
    public let taxUnavailableWarning: String?
    /// The banner that accompanies a stubbed tax figure outside production.
    public let taxStubWarning: String?

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

    /// True when the tax provider could not be reached and `tax` is a
    /// placeholder zero rather than a figure anyone stands behind. Every total
    /// on this breakdown is then a before-tax total, and a screen that renders
    /// one without saying so is telling the buyer a price they will not pay.
    ///
    /// False for an older payload that sends no `tax_source` at all — the
    /// absence of the key is not evidence of an outage.
    public var isTaxUnavailable: Bool {
        taxSource == "unavailable"
    }
}

/// `breakdown_group` — how the server prices a checkout that covers a set of
/// watches. Present on every checkout response, one watch or ten.
///
/// The shape says the thing the screen has to say: each watch has its own
/// price, shipping and return terms (`items`), and the purchase has exactly
/// one card fee, one tax line and one total (`combined`). A per-item line
/// therefore carries no `card_fee` and no `totals` — those belong to the
/// purchase, not to any one watch in it.
public struct CheckoutBreakdownGroup: Decodable, Sendable {
    public let items: [Item]
    /// Nil only on the display-only quote, which prices nothing that needs a
    /// destination and so has no combined column to state.
    public let combined: Combined?
    /// The purchase these watches belong to. Nil before a group exists (the
    /// read-only quote) — analytics omits the property rather than inventing
    /// one.
    public let checkoutGroupId: String?

    /// One watch's own share of the purchase. Every key a single-item
    /// `CheckoutBreakdown` carries except `card_fee` and `totals`, plus the
    /// `listing_id` that says which watch it is about.
    public struct Item: Decodable, Sendable, Identifiable {
        public let listingId: String
        public let subtotal: APIDecimal
        /// This item's allocated share of the one card fee. The shares sum to
        /// `combined.card_fee.amount` — the server allocates, never the client.
        public let fees: APIDecimal?
        public let cardConvenienceFee: APIDecimal?
        public let cardConvenienceFeePercent: APIDecimal?
        public let paymentMethod: String?
        public let sellerFeePercentApplied: APIDecimal?
        public let sellerFeeAmount: APIDecimal?
        public let shipping: APIDecimal
        public let tax: APIDecimal?
        public let taxCalculatedUpfront: Bool?
        /// This order's grand total — its own share of the purchase, and the
        /// exact figure `purchase_completed.value` reports for it.
        public let grandTotal: APIDecimal
        public let currency: String
        public let shippingProvider: String?
        public let offerId: String?
        public let pricingMode: CheckoutBreakdown.PricingMode?
        public let acceptedCardFunding: [String]?
        public let display: CheckoutBreakdown.DisplayPrices?
        public let paymentDisclosures: CheckoutBreakdown.PaymentDisclosures?
        /// This watch's own return terms — they are the seller's, so two
        /// watches in one purchase can differ.
        public let returns: ListingReturnTerms?
        public let returnFee: ReturnFeeTerms?

        public var id: String { listingId }
    }

    /// The purchase's single column: one card fee, one tax line, one total.
    public struct Combined: Decodable, Sendable {
        public let subtotal: APIDecimal
        public let shipping: APIDecimal
        public let tax: APIDecimal?
        public let cardFee: CheckoutBreakdown.CardFee?
        public let totals: CheckoutBreakdown.MethodTotals?
        public let grandTotal: APIDecimal
        public let pricingMode: CheckoutBreakdown.PricingMode?
        public let acceptedCardFunding: [String]?
        public let display: CheckoutBreakdown.DisplayPrices?
        public let currency: String
        public let itemCount: Int
        public let paymentMethod: String?
        /// The purchase has one tax line, so it has one tax source. Read from
        /// `combined` rather than from any item for the same reason `tax` is.
        public let taxSource: String?
        public let taxUnavailableWarning: String?
        public let taxStubWarning: String?
    }

    /// The combined column expressed as a `CheckoutBreakdown`, so every piece
    /// of copy already written against one payment breakdown renders a
    /// multi-watch purchase without being told there is more than one watch.
    ///
    /// Nothing here is computed: each figure is the server's own `combined`
    /// value, moved across. The keys `combined` does not carry — the card-fee
    /// disclosure, and the return terms of a purchase of exactly one watch —
    /// come from the items, which do carry them; return terms are deliberately
    /// dropped for a set of two or more, because two watches can have
    /// different terms and one merged sentence would be true of neither.
    public var combinedBreakdown: CheckoutBreakdown? {
        guard let combined else { return nil }
        let single = items.count == 1 ? items.first : nil
        return CheckoutBreakdown(
            subtotal: combined.subtotal,
            fees: APIDecimal(combined.cardFee?.amount.value ?? 0),
            cardConvenienceFee: combined.cardFee?.amount,
            cardConvenienceFeePercent: combined.cardFee?.percent,
            paymentMethod: combined.paymentMethod,
            sellerFeePercentApplied: single?.sellerFeePercentApplied,
            sellerFeeAmount: single?.sellerFeeAmount,
            shipping: combined.shipping,
            tax: combined.tax,
            taxCalculatedUpfront: items.first?.taxCalculatedUpfront,
            grandTotal: combined.grandTotal,
            currency: combined.currency,
            shippingProvider: single?.shippingProvider,
            offerId: single?.offerId,
            pricingMode: combined.pricingMode,
            cardFee: combined.cardFee,
            totals: combined.totals,
            acceptedCardFunding: combined.acceptedCardFunding,
            display: combined.display,
            // Marketplace policy, identical on every line, so the first line
            // states it for the purchase.
            paymentDisclosures: items.first?.paymentDisclosures,
            returns: single?.returns,
            returnFee: single?.returnFee,
            // One tax line for the purchase, so the outage travels with it.
            // Nil where the server said nothing, which reads as "not an
            // outage" — the same answer a pre-change server gets.
            taxSource: combined.taxSource,
            taxUnavailableWarning: combined.taxUnavailableWarning,
            taxStubWarning: combined.taxStubWarning
        )
    }
}

/// `GET /checkout/quote` — the set priced, reserving nothing and charging
/// nothing. Same money shape as a checkout intent, minus the PaymentIntent.
public struct CheckoutQuote: Decodable, Sendable {
    public let breakdown: CheckoutBreakdown?
    public let breakdownGroup: CheckoutBreakdownGroup?

    public var payableBreakdown: CheckoutBreakdown? {
        breakdown ?? breakdownGroup?.combinedBreakdown
    }
}

/// `GET /listings/{id}/quote` — the one-watch quote wrapper.
///
/// The endpoint answers `data.breakdown`, matching the checkout quote's
/// single-watch branch. Keeping the wrapper explicit prevents the transport
/// from trying to decode the outer object itself as money.
public struct ListingQuote: Decodable, Sendable {
    public let breakdown: CheckoutBreakdown
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
    /// The legacy single-watch breakdown. Present for a checkout of exactly
    /// one watch; absent for a set, whose money lives in `breakdownGroup`.
    public let breakdown: CheckoutBreakdown?
    public let breakdownGroup: CheckoutBreakdownGroup?

    /// The money to render, whichever kind of checkout this is: the single
    /// breakdown when the server sent one, the group's combined column
    /// otherwise. Never a client-side sum.
    public var payableBreakdown: CheckoutBreakdown? {
        breakdown ?? breakdownGroup?.combinedBreakdown
    }
}

/// `POST /checkout/create-intent` with `payment_method: "wire"` — the wire
/// transfer path. The intent carries Stripe bank-transfer instructions; the
/// 24 h reservation is claimed via `POST /checkout/wire-reservation`.
public struct WireCheckout: Decodable, Sendable {
    public let session: SessionStub?
    public let wire: WireIntent
    /// The refundable $250 placed on the buyer's credit card *before* the
    /// bank details are shown. Null when an accepted offer's own deposit is
    /// already standing behind this wire — Calibre never stacks two.
    public let wireHold: WireHold?
    /// As on the card path: the single-watch breakdown when the checkout
    /// covers one watch, and nothing when it covers a set.
    public let breakdown: CheckoutBreakdown?
    public let breakdownGroup: CheckoutBreakdownGroup?

    /// The amount to wire and the lines behind it — one breakdown either way.
    public var payableBreakdown: CheckoutBreakdown? {
        breakdown ?? breakdownGroup?.combinedBreakdown
    }

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

/// The refundable authorization behind a wire, as the checkout response
/// states it.
///
/// A `clientSecret` means the issuer wants a challenge: confirm *that same*
/// intent and then re-request the wire checkout. Never open a fresh checkout
/// while a live hold exists — a new attempt mints a new hold and leaves the
/// stale authorization sitting on the buyer's card until it expires
/// (admin-contracts §11.6, binding).
public struct WireHold: Decodable, Sendable {
    /// The key every client files the disclosure copy under.
    public static let disclosureKey = "wire_hold_disclosure"

    public let amount: APIDecimal?
    public let currency: String?
    /// Stripe's own status word. `requires_capture` means authorized.
    public let status: String?
    public let paymentIntentId: String?
    public let disclosureKey: String?
    public let clientSecret: String?
    /// Sent beside `clientSecret` on a challenge, because a native SDK has to
    /// be keyed before it can confirm anything and the wire path may never
    /// have priced a card (admin-contracts §11.9). Web ignores it.
    public let publishableKey: String?

    enum CodingKeys: String, CodingKey {
        case amount, currency, status, paymentIntentId, disclosureKey
        case clientSecret, publishableKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try? container.decodeIfPresent(APIDecimal.self, forKey: .amount)
        currency = try? container.decodeIfPresent(String.self, forKey: .currency)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        paymentIntentId = try? container.decodeIfPresent(String.self, forKey: .paymentIntentId)
        disclosureKey = try? container.decodeIfPresent(String.self, forKey: .disclosureKey)
        clientSecret = try? container.decodeIfPresent(String.self, forKey: .clientSecret)
        publishableKey = try? container.decodeIfPresent(String.self, forKey: .publishableKey)
    }

    /// The issuer wants a challenge before the authorization stands.
    public var requiresAction: Bool {
        status == "requires_action" || status == "requires_confirmation"
    }

    /// The authorization is in place and the bank details may be shown.
    public var isAuthorized: Bool { status == "requires_capture" }
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
