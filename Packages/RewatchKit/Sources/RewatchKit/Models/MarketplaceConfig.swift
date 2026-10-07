import Foundation

/// `GET /config/marketplace` (public) — the marketplace's own statement of
/// its rates, minimums and windows.
///
/// This exists so a screen can disclose a figure *before* the object that
/// would carry it exists: the offer hold before an offer, the return fee
/// before a return, the card cost before a checkout. It is never a
/// substitute for a real payload figure when one is available — a live
/// breakdown or quote always wins.
public struct MarketplaceConfig: Codable, Sendable {
    public let sellerFeePercentMember: APIDecimal?
    public let sellerFeePercentDealer: APIDecimal?
    /// The flat commission floor, stated only where a payout figure is shown
    /// or in policy documentation — never in a fee headline.
    public let sellerFeeMinimum: APIDecimal?
    public let cardFee: CardFee?
    /// The refundable hold an offer authorizes.
    public let offerHoldAmount: APIDecimal?
    public let offerTtlHours: Int?
    /// How long a buyer has to resolve a failed payment after acceptance.
    public let offerPaymentGraceHours: Int?
    /// How long a buyer has to pay once an offer is accepted.
    public let offerPaymentDeadlineHours: Int?
    public let returnFee: ReturnFeeTerms?
    /// The windows a seller may choose from, e.g. [24, 48, 72].
    public let returnWindows: [Int]
    /// How long a wire reservation holds the watch. One or two values —
    /// a range reads as "24–48 hours".
    public let wireReservationHours: [Int]
    /// States where surcharges are prohibited and the discount presentation
    /// applies, e.g. ["CT", "MA"].
    public let discountPresentationStates: [String]

    public struct CardFee: Codable, Sendable {
        public let percent: APIDecimal?
        public let fixed: APIDecimal?
    }

    enum CodingKeys: String, CodingKey {
        case sellerFeePercentMember, sellerFeePercentDealer, sellerFeeMinimum
        case cardFee, offerHoldAmount, offerTtlHours, offerPaymentGraceHours
        case offerPaymentDeadlineHours
        case returnFee, returnWindows, wireReservationHours
        case discountPresentationStates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sellerFeePercentMember = try? container.decodeIfPresent(APIDecimal.self, forKey: .sellerFeePercentMember)
        sellerFeePercentDealer = try? container.decodeIfPresent(APIDecimal.self, forKey: .sellerFeePercentDealer)
        sellerFeeMinimum = try? container.decodeIfPresent(APIDecimal.self, forKey: .sellerFeeMinimum)
        cardFee = try? container.decodeIfPresent(CardFee.self, forKey: .cardFee)
        offerHoldAmount = try? container.decodeIfPresent(APIDecimal.self, forKey: .offerHoldAmount)
        offerTtlHours = try? container.decodeIfPresent(Int.self, forKey: .offerTtlHours)
        offerPaymentGraceHours = try? container.decodeIfPresent(Int.self, forKey: .offerPaymentGraceHours)
        offerPaymentDeadlineHours = try? container.decodeIfPresent(Int.self, forKey: .offerPaymentDeadlineHours)
        returnFee = try? container.decodeIfPresent(ReturnFeeTerms.self, forKey: .returnFee)
        returnWindows = (try? container.decodeIfPresent([Int].self, forKey: .returnWindows)) ?? []
        // A single number and a range are both plausible wire shapes.
        if let hours = try? container.decodeIfPresent([Int].self, forKey: .wireReservationHours) {
            wireReservationHours = hours
        } else if let hours = try? container.decodeIfPresent(Int.self, forKey: .wireReservationHours) {
            wireReservationHours = [hours]
        } else {
            wireReservationHours = []
        }
        discountPresentationStates =
            (try? container.decodeIfPresent([String].self, forKey: .discountPresentationStates)) ?? []
    }

    /// "24–48 hours" / "24 hours" — nil when the server hasn't said.
    public var wireReservationText: String? {
        switch wireReservationHours.count {
        case 0: nil
        case 1: "\(wireReservationHours[0]) hours"
        default: "\(wireReservationHours.min() ?? 0)–\(wireReservationHours.max() ?? 0) hours"
        }
    }

    /// "CT and MA" / "CT, MA and NY" — nil when the server hasn't said.
    public var discountStatesText: String? {
        switch discountPresentationStates.count {
        case 0: nil
        case 1: discountPresentationStates[0]
        case 2: discountPresentationStates.joined(separator: " and ")
        default:
            discountPresentationStates.dropLast().joined(separator: ", ")
                + " and " + (discountPresentationStates.last ?? "")
        }
    }
}
