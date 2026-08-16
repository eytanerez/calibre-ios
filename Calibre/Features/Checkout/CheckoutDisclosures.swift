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

/// A checkout failure the buyer needs a truthful sentence about, plus what
/// they can honestly do next.
struct CheckoutProblem: Equatable {
    let message: String
    /// Whether trying the same request again is real advice, or just noise.
    let retryable: Bool
    /// Someone else is in checkout for this watch. Retrying now is a lie.
    let listingReserved: Bool

    init(message: String, retryable: Bool = true, listingReserved: Bool = false) {
        self.message = message
        self.retryable = retryable
        self.listingReserved = listingReserved
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

    static let wireArrivalSentence =
        "The order advances automatically when the bank transfer lands. If funds do not arrive in time the hold releases automatically."

    // MARK: - Returns

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

    // MARK: - Errors

    /// The backend's own message wins wherever it has one; these codes get
    /// the sentence the buyer actually needs, and honest advice about whether
    /// trying again will help.
    static func problem(for error: Error) -> CheckoutProblem {
        guard let apiError = error as? APIError else {
            return CheckoutProblem(message: "Something went wrong. Please try again.")
        }

        if case .server(let message, let code, let status, _) = apiError {
            let served = message.trimmingCharacters(in: .whitespacesAndNewlines)

            if code == "listing_reserved" || status == 409 {
                return CheckoutProblem(
                    message: served.isEmpty
                        ? "Someone else is checking out with this watch right now. If they don't finish, it comes back on its own."
                        : served,
                    retryable: false,
                    listingReserved: true
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
