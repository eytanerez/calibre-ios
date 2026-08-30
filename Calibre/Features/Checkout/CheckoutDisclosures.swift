import CalibreKit
import Foundation

// Everything checkout has to *say* about money, in one place, built only from
// what the payload actually carries. Not one figure below is computed or
// remembered — when the server is silent the sentence loses its number rather
// than gaining a guess.

/// The funding gate's verdict, carried from the model to the view so the copy
/// can be written where the marketplace config lives.
///
/// `code` is the backend's machine reason; `serverMessage` is its own
/// plain-English line, used when the code is one we don't recognise.
struct CardRefusal: Equatable {
    let code: String?
    let serverMessage: String?
}

/// Why wire was refused before a deposit could be placed. Both are 402s, and
/// both are things the buyer can act on without leaving checkout.
enum WireCardRefusal: Equatable {
    /// No credit card on file. The buyer adds one and wire is tried again.
    case needsCard(String?)
    /// A card is on file but it is debit or prepaid, which is exactly what a
    /// deposit cannot be.
    case mustBeCredit(String?)

    /// Built from the backend's machine code. Any other code is not this
    /// refusal and is left to the ordinary failure path.
    init?(code: String?, serverMessage: String?) {
        let message = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch code {
        case "wire_card_required": self = .needsCard(message?.isEmpty == false ? message : nil)
        case "wire_card_must_be_credit": self = .mustBeCredit(message?.isEmpty == false ? message : nil)
        default: return nil
        }
    }

    /// Whether adding a card is the way through this one.
    var offersAddCard: Bool {
        if case .needsCard = self { return true }
        return false
    }
}

/// A checkout failure the buyer needs a truthful sentence about, plus what
/// they can honestly do next.
struct CheckoutProblem: Equatable {
    let message: String
    /// Whether trying the same request again is real advice, or just noise.
    let retryable: Bool
    /// Someone else is in checkout for this watch. Retrying now is a lie.
    let listingReserved: Bool
    /// Which watch, when the server named one. A checkout covering several
    /// watches fails on exactly one of them, and the buyer is owed its name
    /// before being asked what to do about it.
    let reservedListingID: String?

    init(
        message: String,
        retryable: Bool = true,
        listingReserved: Bool = false,
        reservedListingID: String? = nil
    ) {
        self.message = message
        self.retryable = retryable
        self.listingReserved = listingReserved
        self.reservedListingID = reservedListingID
    }
}

enum CheckoutCopy {

    // MARK: - Numbers

    /// Renders a percent the server sent, trimming a trailing `.00`/`.0` for
    /// reading without ever changing the value: "2.90" reads "2.9%".
    static func percentText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        let text = formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        return "\(text)%"
    }

    /// "2.9% + $0.30" — the two parts of the card cost as the server states
    /// them. Nil when the breakdown predates `card_fee`, in which case the
    /// dollar figure stands on its own.
    static func cardFeeRateText(_ breakdown: CheckoutBreakdown) -> String? {
        guard let fee = breakdown.cardFee else { return nil }
        var parts: [String] = []
        if let percent = fee.percent {
            parts.append(percentText(percent.value))
        }
        if let fixed = fee.fixed {
            parts.append(PriceFormatter.format(fixed.value, currency: breakdown.currency))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " + ")
    }

    /// The exact card cost in dollars, from `card_fee` when the breakdown has
    /// it and the legacy key when it doesn't.
    static func cardFeeAmount(_ breakdown: CheckoutBreakdown) -> Decimal? {
        if let fee = breakdown.cardFee { return fee.amount.value }
        return breakdown.cardConvenienceFee?.value
    }

    static func cardFeeAmountText(_ breakdown: CheckoutBreakdown) -> String? {
        guard let amount = cardFeeAmount(breakdown) else { return nil }
        return PriceFormatter.format(amount, currency: breakdown.currency)
    }

    /// The sentence under the receipt line. The rate is quoted only when the
    /// payload carries it; the promise behind it is always true.
    static func cardFeeNote(_ breakdown: CheckoutBreakdown) -> String {
        if let rate = cardFeeRateText(breakdown) {
            return "The card fee is \(rate) — exactly our cost of accepting the card, never more."
        }
        return "The card fee is exactly our cost of accepting the card, never more."
    }

    // MARK: - Which cards work here

    /// Stated at card entry, while wire is still one tap away — never after
    /// submission. The accepted list comes from the order's own breakdown;
    /// the states, when we name them, come from the marketplace config.
    static func acceptedCardsNote(_ breakdown: CheckoutBreakdown, statesText: String?) -> String {
        var sentences: [String] = []

        if let funding = breakdown.acceptedCardFunding, !funding.isEmpty {
            sentences.append("This order accepts \(list(funding)) cards.")
        }

        sentences.append("Prepaid cards are not accepted anywhere on Calibre.")

        if !breakdown.acceptsDebit {
            if let statesText {
                sentences.append(
                    "Debit is accepted only where the discount presentation applies — today that is \(statesText) — and this order is not one of those."
                )
            } else {
                sentences.append(
                    "Debit is accepted only where the discount presentation applies, and this order is not one of those."
                )
            }
        }

        return sentences.joined(separator: " ")
    }

    // MARK: - Refusals

    /// A refused card, said warmly and plainly. Never a dead end: the view
    /// puts "use a different card" and "pay by wire" directly beneath this.
    static func refusalMessage(_ refusal: CardRefusal, statesText: String?) -> String {
        switch refusal.code {
        case "prepaid_not_accepted":
            return "Prepaid cards are not accepted anywhere on Calibre."
        case "debit_not_accepted_in_state":
            if let statesText {
                return "Debit cards are accepted only where the discount presentation applies — today that is \(statesText) — and this order is not one of those."
            }
            return "Debit cards are accepted only where the discount presentation applies, and this order is not one of those."
        case "card_funding_not_accepted", "card_funding_unknown":
            return "We could not confirm what kind of card this is, so we cannot accept it here."
        default:
            let message = refusal.serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty { return message }
            return "This card can't be used for this order."
        }
    }

    /// The way out, always available at any price.
    static let wireAlwaysAvailable =
        "Wire transfer is available at any price and has no processing cost."

    // MARK: - Wire

    /// "24–48 hours" from the config when it has landed, the canonical
    /// phrasing in prose when it hasn't.
    static func wireReservationPhrase(_ configText: String?) -> String {
        configText ?? "24 to 48 hours"
    }

    static func wireReservationSentence(_ configText: String?) -> String {
        "Choosing wire holds the watch for \(wireReservationPhrase(configText)) while the transfer arrives."
    }

    /// Unused today, and kept correct rather than kept as it was: with the
    /// $250 authorization in the picture, "the hold releases" would read as
    /// the deposit coming off, which is the opposite of what a missed
    /// deadline does to it.
    static let wireArrivalSentence =
        "The order advances automatically when the bank transfer lands. If the transfer isn\u{2019}t sent by the deadline the watch goes back on the market."

    // MARK: - The wire deposit

    /// The disclosure filed under `wire_hold.disclosure_key`
    /// (`WireHold.disclosureKey`), shown at the moment wire is chosen and
    /// before anything is committed. This wording is fixed and identical on
    /// web, iOS and Android \u{2014} it is what decides a dispute.
    static let wireHoldDisclosure =
        "Choosing wire places a refundable $250 authorization on your card. It\u{2019}s released as soon as your transfer arrives. If the transfer isn\u{2019}t sent by the deadline, the $250 is charged and goes to the seller."

    /// Said again on the instructions screen, where the buyer is looking at
    /// the authorization on their statement.
    static let wireHoldPlaced =
        "$250 authorization placed \u{2014} released when your transfer arrives."

    /// Why wire cannot start, and what to do about it. The backend's own
    /// sentence wins when it wrote one.
    static func wireCardRefusalMessage(_ refusal: WireCardRefusal) -> String {
        switch refusal {
        case .needsCard(let message):
            return message ?? "Paying by wire needs a credit card on file for the refundable $250 authorization."
        case .mustBeCredit(let message):
            return message ?? "Paying by wire needs a credit card. Debit and prepaid cards can\u{2019}t be used \u{2014} a deposit has to be a promise a bank is standing behind, and a debit or prepaid balance can be spent elsewhere."
        }
    }

    // MARK: - Returns

    /// The one line that decides the question, with the window in it where
    /// there is one. Cancellation is named here because there is no longer
    /// any such thing on the buyer's side: once a sale is final, it is final.
    static func returnTermsHeadline(_ breakdown: CheckoutBreakdown) -> String {
        guard let terms = breakdown.returns, terms.accepted else {
            return "This is a final sale \u{2014} it cannot be returned or cancelled"
        }
        if let hours = terms.windowHours {
            return "This seller accepts returns: \(hours)-hour window"
        }
        return "This seller accepts returns"
    }

    /// The listing's return terms with the real numbers, before purchase.
    /// Any figure the payload doesn't carry simply drops out of the sentence.
    static func returnTermLines(_ breakdown: CheckoutBreakdown) -> [String] {
        guard let terms = breakdown.returns else { return [] }
        guard terms.accepted else {
            return ["This watch is sold without returns."]
        }

        var lines: [String] = []
        if let hours = terms.windowHours {
            lines.append("You can start a return within \(hours) hours of signing for the watch.")
        } else {
            lines.append("Returns are accepted on this watch.")
        }

        if let fee = breakdown.returnFee {
            switch (fee.percent, fee.minimum) {
            case (let percent?, let minimum?):
                lines.append(
                    "A return costs \(percentText(percent.value)) of the watch price, with a minimum of \(PriceFormatter.format(minimum.value, currency: breakdown.currency))."
                )
            case (let percent?, nil):
                lines.append("A return costs \(percentText(percent.value)) of the watch price.")
            case (nil, let minimum?):
                lines.append(
                    "A return costs at least \(PriceFormatter.format(minimum.value, currency: breakdown.currency))."
                )
            case (nil, nil):
                break
            }
        }

        lines.append("Calibre's return label is deducted from your refund.")
        if breakdown.paymentDisclosures?.cardFeeNonrefundable == true {
            lines.append("The card fee is not refunded.")
        }
        return lines
    }

    /// One watch's return terms in a single line, for the itemised list of a
    /// purchase covering several. Return terms are the seller's, so two
    /// watches in one purchase can answer differently and each says its own.
    /// A line with nothing to state is no line at all.
    static func itemReturnLine(_ item: CheckoutBreakdownGroup.Item) -> String? {
        guard let terms = item.returns else { return nil }
        guard terms.accepted else { return "Sold without returns" }

        var line = terms.windowHours.map { "Returns within \($0) hours of delivery" }
            ?? "Returns accepted"
        if let fee = item.returnFee {
            switch (fee.percent, fee.minimum) {
            case (let percent?, let minimum?):
                line += " · \(percentText(percent.value)) return fee, minimum \(PriceFormatter.format(minimum.value, currency: item.currency))"
            case (let percent?, nil):
                line += " · \(percentText(percent.value)) return fee"
            case (nil, let minimum?):
                line += " · return fee from \(PriceFormatter.format(minimum.value, currency: item.currency))"
            case (nil, nil):
                break
            }
        }
        return line
    }

    // MARK: - A set of watches

    /// "3 watches" — the one place the count is turned into words, so every
    /// screen says it the same way.
    static func watchCount(_ count: Int) -> String {
        count == 1 ? "1 watch" : "\(count) watches"
    }

    /// The watch someone else got to first, and what happens to the rest.
    static func reservedWatchMessage(_ title: String, remaining: Int) -> String {
        if remaining > 0 {
            return "Someone else is checking out with \(title) right now. You can go on with the other \(watchCount(remaining)) — we'll re-price your purchase without it."
        }
        return "Someone else is checking out with \(title) right now. If they don't finish, it comes back on its own."
    }

    // MARK: - Errors

    /// The backend's own message wins wherever it has one; these codes get
    /// the sentence the buyer actually needs, and honest advice about whether
    /// trying again will help.
    static func problem(for error: Error) -> CheckoutProblem {
        guard let apiError = error as? APIError else {
            // Not every failure in checkout comes back from our API, and the
            // ones that don't are the ones a buyer most needs words for: a
            // 3-D Secure decline carries Stripe's own sentence ("Your card has
            // insufficient funds."), a cancelled challenge carries "You
            // cancelled the check with your bank, so nothing was charged", an
            // unreadable card carries a line about checking the details. Every
            // one of them travels as `CheckoutMessageError`, which is not an
            // `APIError` — so all of them used to be thrown away here and
            // replaced with "Something went wrong. Please try again." That is
            // not just vaguer, it is wrong advice: a declined card declines
            // again, every time, and the buyer is left retrying instead of
            // reaching for another card or the wire route.
            let written = (error as? LocalizedError)?.errorDescription?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let written, !written.isEmpty {
                return CheckoutProblem(message: written)
            }
            return CheckoutProblem(message: "Something went wrong. Please try again.")
        }

        if case .server(let message, let code, let status, let details) = apiError {
            let served = message.trimmingCharacters(in: .whitespacesAndNewlines)

            if code == "listing_reserved" || details?["code"] == "listing_reserved" || status == 409 {
                return CheckoutProblem(
                    message: served.isEmpty
                        ? "Someone else is checking out with this watch right now. If they don't finish, it comes back on its own."
                        : served,
                    retryable: false,
                    listingReserved: true,
                    reservedListingID: reservedListingID(in: details)
                )
            }

            if code == "tax_unavailable" || status == 503 {
                return CheckoutProblem(
                    message: served.isEmpty
                        ? "We couldn't calculate sales tax right now, and we won't guess at it. Please try again shortly."
                        : served
                )
            }
        }

        return CheckoutProblem(
            message: apiError.errorDescription ?? "Something went wrong. Please try again."
        )
    }

    // MARK: - Helpers

    /// Which watch the server refused, from its error details. The client's
    /// decoder converts wire keys to camelCase, so both spellings are read —
    /// and a blank id is no id at all.
    private static func reservedListingID(in details: [String: String]?) -> String? {
        guard let details else { return nil }
        let raw = details["listing_id"] ?? details["listingId"]
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    /// "credit", "credit and debit", "credit, debit and X".
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return items.joined(separator: " and ")
        default:
            return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}
