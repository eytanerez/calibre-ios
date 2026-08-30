import Foundation

/// The return terms a seller chose at listing time. Locked onto the order at
/// purchase, so an order's terms never move underneath the buyer.
public struct ListingReturnTerms: Codable, Sendable, Hashable {
    public let accepted: Bool
    /// 24, 48 or 72 — nil when returns aren't accepted.
    public let windowHours: Int?

    enum CodingKeys: String, CodingKey {
        case accepted, windowHours
    }

    public init(accepted: Bool, windowHours: Int?) {
        self.accepted = accepted
        self.windowHours = windowHours
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
        windowHours = try container.decodeIfPresent(Int.self, forKey: .windowHours)
    }

    /// The window as a noun phrase — "72-hour returns".
    ///
    /// Item 1.22: everywhere the product used to say a seller "accepts
    /// returns", it says for how long instead. "Accepts returns" is the answer
    /// to a question nobody asked; the buyer is deciding whether they have
    /// time to get the watch on their wrist and change their mind, and that is
    /// a number. The database has held the all-or-nothing rule as a CHECK
    /// constraint since migration 20260830_0080, so an accepting listing
    /// always carries 24, 48 or 72 — the nil arm only covers rows recorded
    /// before that and says the honest thing rather than inventing a duration.
    public var summary: String? {
        guard accepted else { return nil }
        guard let windowHours else { return "Returns accepted" }
        return "\(windowHours)-hour returns"
    }

    /// The same fact as a sentence, for a paragraph rather than a chip.
    public var sentence: String? {
        guard accepted else { return nil }
        guard let windowHours else {
            return "This seller accepts returns after delivery."
        }
        return "This seller accepts returns for \(windowHours) hours after delivery."
    }
}

/// The return window a buyer can filter the market by (item 1.21). The values
/// are the server's: `all` plus the three windows a seller may commit to
/// (`RETURN_WINDOW_HOURS_CHOICES` in Backend/app/api/serializers.py). `any`
/// carries no parameter at all — it is the absence of the filter, not the
/// server's `all`, which means "accepts returns, whatever the window".
public enum ReturnWindowFilter: String, CaseIterable, Sendable, Hashable {
    case any
    case all
    case hours24 = "24"
    case hours48 = "48"
    case hours72 = "72"

    /// What `GET /listings?return_window_hours=` receives, or nil for `any`.
    public var wireValue: String? {
        self == .any ? nil : rawValue
    }

    public var label: String {
        switch self {
        case .any: "Any"
        case .all: "All"
        case .hours24: "24h"
        case .hours48: "48h"
        case .hours72: "72h"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .any: "Any return terms"
        case .all: "Accepts returns, any window"
        case .hours24: "24-hour returns"
        case .hours48: "48-hour returns"
        case .hours72: "72-hour returns"
        }
    }
}

/// The return fee's shape, as both the checkout breakdown and the public
/// marketplace config state it: a percentage with a flat minimum, charged on
/// the watch price alone.
public struct ReturnFeeTerms: Codable, Sendable {
    public let percent: APIDecimal?
    public let minimum: APIDecimal?
}

/// The live return window on an order: when it opened, when it closes, and
/// whether it is still open right now (the server decides — the clock stops
/// when a return starts, so a client can't infer this from dates alone).
public struct ReturnWindow: Codable, Sendable {
    public let startedAt: Date?
    public let endsAt: Date?
    public let open: Bool

    enum CodingKeys: String, CodingKey {
        case startedAt, endsAt, open
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        open = try container.decodeIfPresent(Bool.self, forKey: .open) ?? false
    }
}


/// Why the buyer is sending the watch back. Exactly these seven, exactly
/// these words: the first three say something about the seller, the two
/// change-of-heart reasons say nothing about anybody, and `arrivedDamaged`
/// says something about the journey. Collapsing them is what made returns
/// unreadable before.
public enum OrderReturnReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case conditionNotAsDescribed = "condition_not_as_described"
    case wrongReference = "wrong_reference"
    case missingBoxPapers = "missing_box_papers"
    case doesNotFit = "does_not_fit"
    case changedMind = "changed_mind"
    case arrivedDamaged = "arrived_damaged"
    case other

    public var id: String { rawValue }

    /// The buyer's own words for it. Pinned verbatim across web, iOS and
    /// Android (admin-contracts §11.9): the first two share a "Not as
    /// described" stem because they are one family of complaint about the
    /// seller, and a buyer picking between them should see that.
    public var label: String {
        switch self {
        case .conditionNotAsDescribed: "Not as described \u{2014} condition worse than listed"
        case .wrongReference: "Not as described \u{2014} wrong reference, model, or year"
        case .missingBoxPapers: "Missing box, papers, or accessories"
        case .doesNotFit: "Doesn\u{2019}t fit / doesn\u{2019}t suit me"
        case .changedMind: "Changed my mind"
        case .arrivedDamaged: "Arrived damaged"
        case .other: "Other"
        }
    }

    /// The one reason a note is not optional: "other" without one says
    /// nothing at all, and the server refuses it.
    public var requiresNote: Bool { self == .other }
}

/// One return photograph, staged against the order or claimed by a return.
public struct OrderReturnImage: Codable, Sendable, Identifiable {
    public let id: String
    /// One of the six listing photo categories.
    public let category: String?
    public let url: MediaURL?

    /// The slot this photo fills, when the category is one we know.
    public var slot: ListingImageCategory? {
        category.flatMap(ListingImageCategory.init(rawValue:))
    }
}

/// `GET /orders/{id}/return-quote` — the exact refund, itemized, before the
/// buyer commits to anything. Never computed client-side.
public struct ReturnQuote: Decodable, Sendable {
    public let watchPrice: APIDecimal
    public let taxRefund: APIDecimal?
    public let returnFee: Fee
    /// The original outbound label, deducted from the refund.
    public let outboundLabelDeduction: APIDecimal?
    /// Calibre's return label — signature required, insured for the full sale
    /// price — whose cost is deducted from the refund. Nil on payloads that
    /// predate the field, in which case the row is simply not drawn.
    public let returnLabelDeduction: APIDecimal?
    /// The card fee that is never refunded, or its equivalent for a wire
    /// buyer who never paid one — `processingWithholdingBasis` says which.
    public let processingWithholding: APIDecimal?
    /// "card_fee_never_refunded" or "card_fee_equivalent".
    public let processingWithholdingBasis: String?
    public let refundTotal: APIDecimal
    public let currency: String
    public let window: ReturnWindow?
    /// Set when a return is already open on this order.
    public let existingReturn: OrderReturn?
    /// What the buyer has photographed so far — one unclaimed row per angle,
    /// so the six slots come back filled in after a relaunch.
    public let stagedImages: [OrderReturnImage]

    public struct Fee: Decodable, Sendable {
        public let percent: APIDecimal
        public let minimum: APIDecimal
        public let amount: APIDecimal
    }

    enum CodingKeys: String, CodingKey {
        case watchPrice, taxRefund, returnFee, outboundLabelDeduction
        case returnLabelDeduction
        case processingWithholding, processingWithholdingBasis
        case refundTotal, currency, window, existingReturn, stagedImages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        watchPrice = try container.decode(APIDecimal.self, forKey: .watchPrice)
        taxRefund = try container.decodeIfPresent(APIDecimal.self, forKey: .taxRefund)
        returnFee = try container.decode(Fee.self, forKey: .returnFee)
        outboundLabelDeduction = try container.decodeIfPresent(APIDecimal.self, forKey: .outboundLabelDeduction)
        returnLabelDeduction = try container.decodeIfPresent(APIDecimal.self, forKey: .returnLabelDeduction)
        processingWithholding = try container.decodeIfPresent(APIDecimal.self, forKey: .processingWithholding)
        processingWithholdingBasis = try container.decodeIfPresent(String.self, forKey: .processingWithholdingBasis)
        refundTotal = try container.decode(APIDecimal.self, forKey: .refundTotal)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        window = try? container.decodeIfPresent(ReturnWindow.self, forKey: .window)
        existingReturn = try? container.decodeIfPresent(OrderReturn.self, forKey: .existingReturn)
        stagedImages = (try? container.decodeIfPresent([OrderReturnImage].self, forKey: .stagedImages)) ?? []
    }
}

/// One open or completed return. Every field is optional on purpose: the
/// contract pins down the label and the ship deadline, and leaves the rest of
/// the return record to the backend's own serializer — a field we haven't
/// seen must never cost the buyer their return screen.
public struct OrderReturn: Decodable, Sendable {
    public let id: String?
    public let orderId: String?
    /// e.g. requested / in_transit / received / refunded / cancelled.
    public let status: String?
    /// Why the buyer opened it. Required from the buyer, so it is only ever
    /// nil on a payload written before reasons existed.
    public let reason: OrderReturnReason?
    public let reasonNote: String?
    /// The six angles the return was opened with.
    public let images: [OrderReturnImage]
    public let requestedAt: Date?
    public let shippedDeclaredAt: Date?
    public let receivedAt: Date?
    public let refundedAt: Date?
    public let cancelledAt: Date?
    /// The buyer has 48 business hours from here to hand the watch over.
    public let shipDeadlineAt: Date?
    public let refundTotal: APIDecimal?
    /// The return label's cost, frozen onto the return when it was created.
    public let returnLabelDeduction: APIDecimal?
    public let currency: String?
    public let label: ReturnLabel?
    public let window: ReturnWindow?
    /// Seller's post-refund choice, when they've made one.
    public let relistDecision: String?

    enum CodingKeys: String, CodingKey {
        case id, orderId, status, reason, reasonNote, images
        case requestedAt, shippedDeclaredAt, receivedAt
        case refundedAt, cancelledAt, shipDeadlineAt, refundTotal
        case returnLabelDeduction, currency
        case label, window, relistDecision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        orderId = try? container.decodeIfPresent(String.self, forKey: .orderId)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        reason = try? container.decodeIfPresent(OrderReturnReason.self, forKey: .reason)
        reasonNote = try? container.decodeIfPresent(String.self, forKey: .reasonNote)
        images = (try? container.decodeIfPresent([OrderReturnImage].self, forKey: .images)) ?? []
        requestedAt = try? container.decodeIfPresent(Date.self, forKey: .requestedAt)
        shippedDeclaredAt = try? container.decodeIfPresent(Date.self, forKey: .shippedDeclaredAt)
        receivedAt = try? container.decodeIfPresent(Date.self, forKey: .receivedAt)
        refundedAt = try? container.decodeIfPresent(Date.self, forKey: .refundedAt)
        cancelledAt = try? container.decodeIfPresent(Date.self, forKey: .cancelledAt)
        shipDeadlineAt = try? container.decodeIfPresent(Date.self, forKey: .shipDeadlineAt)
        refundTotal = try? container.decodeIfPresent(APIDecimal.self, forKey: .refundTotal)
        returnLabelDeduction = try? container.decodeIfPresent(APIDecimal.self, forKey: .returnLabelDeduction)
        currency = try? container.decodeIfPresent(String.self, forKey: .currency)
        label = try? container.decodeIfPresent(ReturnLabel.self, forKey: .label)
        window = try? container.decodeIfPresent(ReturnWindow.self, forKey: .window)
        relistDecision = try? container.decodeIfPresent(String.self, forKey: .relistDecision)
    }

    /// True once the watch is on its way back — cancelling is no longer the
    /// buyer's to make (the server 409s `return_in_transit`).
    public var isInTransit: Bool {
        shippedDeclaredAt != nil || status == "in_transit"
    }

    public var isFinished: Bool {
        refundedAt != nil || cancelledAt != nil || status == "refunded" || status == "cancelled"
    }
}

/// Calibre's return label: signature required, insured for the full sale
/// price, and its cost deducted from the refund.
public struct ReturnLabel: Decodable, Sendable {
    public let shipmentId: String?
    public let carrier: String?
    public let trackingNumber: String?
    public let labelUrl: MediaURL?
}

/// `POST /orders/{id}/return` — the created return, its label and the ship
/// deadline, which the backend sends alongside (not inside) the return.
public struct ReturnStartResult: Decodable, Sendable {
    public let `return`: OrderReturn
    public let label: ReturnLabel?
    public let shipDeadlineAt: Date?

    private enum CodingKeys: String, CodingKey {
        case label, shipDeadlineAt
    }

    public init(from decoder: Decoder) throws {
        // The return payload is sent flat, with `label`/`ship_deadline_at`
        // as siblings — decode the record from the same container.
        `return` = try OrderReturn(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? container.decodeIfPresent(ReturnLabel.self, forKey: .label)) ?? `return`.label
        shipDeadlineAt = (try? container.decodeIfPresent(Date.self, forKey: .shipDeadlineAt))
            ?? `return`.shipDeadlineAt
    }
}

/// `POST /orders/{id}/return/relist-decision` — the seller's call once a
/// return has been refunded.
public struct RelistDecision: Decodable, Sendable {
    public let relistDecision: String?
    public let listingId: String?
    public let listingStatus: ListingStatus?
}

/// `POST /orders/{id}/fulfillment/shipped` — the seller declaring their
/// outbound handover, which buys a grace period for the first carrier scan.
public struct FulfillmentShipped: Decodable, Sendable {
    public let orderId: String?
    public let sellerShippedDeclaredAt: Date?
    public let autoCancelGraceUntil: Date?
    /// Echoed back so the seller sees the line that went with the parcel.
    /// Only the first declaration writes one; a repeat leaves it as it was.
    public let packingNote: String?

    /// What fits on the card in the box.
    public static let packingNoteLimit = 280
}

/// The payout block on an order and on `/account/payouts` rows.
///
/// Seller-facing copy built from this must never use the words Stripe,
/// balance, or connected account — this is money going to their bank.
public struct OrderPayout: Codable, Sendable {
    /// "auth_pass" (no returns accepted) or "return_window_close".
    public let trigger: String?
    /// What the seller actually receives — the server's own "You receive"
    /// figure, net of the commission it also reports. No client may derive
    /// this from a subtotal and a fee; when it is absent the row is omitted.
    public let amount: APIDecimal?
    public let releasedAt: Date?
    /// When it should land in the seller's bank — about two business days
    /// after release, and longer for a first payout.
    public let expectedArrivalAt: Date?
    /// A new seller's first payout may take 7–14 days regardless of timing.
    public let firstPayoutHold: Bool?
    /// The backend's own plain-English status line.
    public let statusLabel: String?
    /// Set when a payout failed — the actual reason, to show as-is.
    public let failureReason: String?
    /// The four lines the transfer is built from — sale price, commission,
    /// the label Calibre bought, payout. No client assembles these itself.
    public let breakdown: PayoutBreakdown?

    enum CodingKeys: String, CodingKey {
        case trigger, amount, releasedAt, expectedArrivalAt, firstPayoutHold
        case statusLabel, failureReason, breakdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try? container.decodeIfPresent(String.self, forKey: .trigger)
        amount = try? container.decodeIfPresent(APIDecimal.self, forKey: .amount)
        releasedAt = try? container.decodeIfPresent(Date.self, forKey: .releasedAt)
        expectedArrivalAt = try? container.decodeIfPresent(Date.self, forKey: .expectedArrivalAt)
        firstPayoutHold = try? container.decodeIfPresent(Bool.self, forKey: .firstPayoutHold)
        statusLabel = try? container.decodeIfPresent(String.self, forKey: .statusLabel)
        failureReason = try? container.decodeIfPresent(String.self, forKey: .failureReason)
        breakdown = try? container.decodeIfPresent(PayoutBreakdown.self, forKey: .breakdown)
    }
}

/// The payout ledger, exactly as `services.payouts.payout_breakdown` states
/// it: sale price, then the commission (with its rate, and whether the
/// marketplace minimum applied instead), then what the label cost, then what
/// is left. Every figure is the server's — nothing here is subtracted on the
/// device, and a figure the payload omits is simply not a row.
public struct PayoutBreakdown: Codable, Sendable {
    public let salePrice: APIDecimal?
    public let commission: Commission?
    /// The actual cost of the to-auth label Calibre bought.
    public let shippingLabel: APIDecimal?
    /// What the seller receives.
    public let amount: APIDecimal?

    public struct Commission: Codable, Sendable {
        public let percent: APIDecimal?
        public let amount: APIDecimal?
        /// True when the marketplace minimum charged instead of the rate.
        public let minimumApplied: Bool?

        enum CodingKeys: String, CodingKey {
            case percent, amount, minimumApplied
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            percent = try? container.decodeIfPresent(APIDecimal.self, forKey: .percent)
            amount = try? container.decodeIfPresent(APIDecimal.self, forKey: .amount)
            minimumApplied = try? container.decodeIfPresent(Bool.self, forKey: .minimumApplied)
        }
    }

    enum CodingKeys: String, CodingKey {
        case salePrice, commission, shippingLabel, amount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        salePrice = try? container.decodeIfPresent(APIDecimal.self, forKey: .salePrice)
        commission = try? container.decodeIfPresent(Commission.self, forKey: .commission)
        shippingLabel = try? container.decodeIfPresent(APIDecimal.self, forKey: .shippingLabel)
        amount = try? container.decodeIfPresent(APIDecimal.self, forKey: .amount)
    }
}

/// The `return` summary an order carries once a return exists. Distinct from
/// `OrderReturnTerms`, which describes the policy; this describes the case.
public struct OrderReturnSummary: Codable, Sendable {
    /// e.g. requested / in_transit / received / refunded / cancelled.
    public let state: String?
    /// Why the buyer opened it, in the marketplace's own vocabulary.
    public let reason: OrderReturnReason?
    public let reasonNote: String?
    public let initiatedAt: Date?
    public let shipDeadlineAt: Date?
    /// Set once the carrier scans the parcel, which ends the grace period.
    public let carrierFirstScanAt: Date?
    public let refundTotal: APIDecimal?
    /// The return label's cost, frozen onto the return and deducted from the
    /// refund. Nil on payloads that predate the field.
    public let returnLabelDeduction: APIDecimal?
    /// Null until the seller decides.
    public let relistDecision: String?
    public let label: Label?

    public struct Label: Codable, Sendable {
        public let trackingNumber: String?
        public let labelUrl: MediaURL?
    }

    enum CodingKeys: String, CodingKey {
        case state, reason, reasonNote, initiatedAt, shipDeadlineAt, carrierFirstScanAt
        case refundTotal, returnLabelDeduction, relistDecision, label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try? container.decodeIfPresent(String.self, forKey: .state)
        reason = try? container.decodeIfPresent(OrderReturnReason.self, forKey: .reason)
        reasonNote = try? container.decodeIfPresent(String.self, forKey: .reasonNote)
        initiatedAt = try? container.decodeIfPresent(Date.self, forKey: .initiatedAt)
        shipDeadlineAt = try? container.decodeIfPresent(Date.self, forKey: .shipDeadlineAt)
        carrierFirstScanAt = try? container.decodeIfPresent(Date.self, forKey: .carrierFirstScanAt)
        refundTotal = try? container.decodeIfPresent(APIDecimal.self, forKey: .refundTotal)
        returnLabelDeduction = try? container.decodeIfPresent(APIDecimal.self, forKey: .returnLabelDeduction)
        relistDecision = try? container.decodeIfPresent(String.self, forKey: .relistDecision)
        label = try? container.decodeIfPresent(Label.self, forKey: .label)
    }

    /// The watch is on its way back; cancelling is no longer available.
    public var isInTransit: Bool {
        state == "in_transit" || carrierFirstScanAt != nil
    }

    public var isRefunded: Bool { state == "refunded" }
    public var isCancelled: Bool { state == "cancelled" }

    /// True while the buyer still owes the handover.
    public var awaitingShipment: Bool {
        state == "requested" && carrierFirstScanAt == nil
    }
}

/// Dates the backend expects to hit, sent on order payloads under `expected`.
/// Nullable throughout — an estimate we don't have is left unsaid.
public struct OrderExpected: Codable, Sendable {
    public let authenticationVerdictBy: Date?
    public let shippedToYouBy: Date?
    public let deliveredBy: Date?
    public let returnWindowEndsAt: Date?
    /// Seller-only forecast of the payout. Merge with the order's own
    /// `payout` block, which additionally carries the status and failure
    /// wording.
    public let payout: OrderPayout?

    enum CodingKeys: String, CodingKey {
        case authenticationVerdictBy, shippedToYouBy, deliveredBy
        case returnWindowEndsAt, payout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authenticationVerdictBy = try? container.decodeIfPresent(Date.self, forKey: .authenticationVerdictBy)
        shippedToYouBy = try? container.decodeIfPresent(Date.self, forKey: .shippedToYouBy)
        deliveredBy = try? container.decodeIfPresent(Date.self, forKey: .deliveredBy)
        returnWindowEndsAt = try? container.decodeIfPresent(Date.self, forKey: .returnWindowEndsAt)
        payout = try? container.decodeIfPresent(OrderPayout.self, forKey: .payout)
    }
}

/// The order's own copy of the return terms, plus the live window.
public struct OrderReturnTerms: Codable, Sendable {
    public let accepted: Bool
    public let windowHours: Int?
    public let windowStartedAt: Date?
    public let windowEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case accepted, windowHours, windowStartedAt, windowEndsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
        windowHours = try container.decodeIfPresent(Int.self, forKey: .windowHours)
        windowStartedAt = try container.decodeIfPresent(Date.self, forKey: .windowStartedAt)
        windowEndsAt = try container.decodeIfPresent(Date.self, forKey: .windowEndsAt)
    }

    /// Whether the buyer can still start a return right now.
    public func isOpen(now: Date = .now) -> Bool {
        guard accepted, let ends = windowEndsAt else { return false }
        return ends > now
    }
}
