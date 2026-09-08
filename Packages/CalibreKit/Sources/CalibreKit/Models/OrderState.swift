import Foundation

/// What an order is doing, said once for both of the buyer's screens.
///
/// Two questions a buyer arrives with, and until now neither screen answered
/// either of them plainly. `nextStep` answers "whose move is it, and what
/// happens next"; `timeline` answers "where is my watch" as steps with a real
/// state under each, rather than as a rail whose filled length was the only
/// thing that moved.
///
/// Both read the authentication RECORD wherever the record knows better than
/// the order status. `to_auth` is one status covering the seller still holding
/// the watch, the carrier holding it and the bench holding it; `auth_pass` is a
/// status a payload can carry while `verdict` says the watch did not pass. The
/// status is the shape of the journey and the record is what actually
/// happened, so where they disagree the record wins — and where the record
/// says nothing, nothing is claimed.
///
/// Lives in the package rather than in a view for the reason `OrderMarks` does:
/// so the readings can be tested without a screen, and so the list and the
/// order page cannot drift into wording the same order two different ways.
/// This is the pair the web calls `orderNextStep` / `orderTimeline`
/// (`components/orders/orderState.ts`), which is the authority for the
/// decisions here.

/// The verdict the bench records for a watch that passed, spelled exactly as it
/// is stored (`VERDICT_AUTHENTICATED` in `app/services/auth_records.py`).
private let authenticatedVerdict = "authenticated"

/// The `OrderReturnState` values where the return shipment has arrived and the
/// parcel is at the bench rather than still on the road.
///
/// Read off `state`, which the order payload carries. `isInTransit` cannot
/// stand in for the negative of this: it is true from the carrier's first scan
/// onwards and stays true after the parcel lands, so the two are asked in
/// order — the bench first.
private let returnAtTheBench: Set<String> = ["received", "verifying"]

// MARK: - Who it is waiting on

/// Who the order is waiting on.
public enum OrderActor: String, Sendable, Equatable, CaseIterable {
    case you
    case seller
    case calibre

    /// How each actor is named on screen.
    ///
    /// One table, read by the list and by the order page, so the two cannot
    /// word it differently — which is the whole reason it is a table and not a
    /// string literal at each call site.
    public var label: String {
        switch self {
        case .you: "Waiting on you"
        case .seller: "With the seller"
        case .calibre: "With Calibre"
        }
    }
}

/// The one thing that is true about an order right now.
public struct OrderNextStep: Sendable, Equatable {
    /// Nil when the order is finished and nobody owes anybody anything.
    public let actor: OrderActor?
    /// The state of this order in one line. Never a policy, never a mechanism.
    public let headline: String
    /// The rare paragraph: a hold and a failed authentication are the two
    /// moments where a person wants more than a line, and both are about their
    /// watch rather than about a rule. Nil everywhere else.
    public let body: String?
    /// What happens next, and when. **Nil when nothing honest can be said** —
    /// a date the server did not send is a promise nobody made.
    public let next: String?

    public init(actor: OrderActor?, headline: String, body: String? = nil, next: String?) {
        self.actor = actor
        self.headline = headline
        self.body = body
        self.next = next
    }

    /// The state and what follows it as one run of prose, for a list row.
    ///
    /// The headlines come from two places — written here, and authored as the
    /// arrival sentences — and only some of them end in a full stop, because on
    /// the order page each is a display line with the sentence after it set
    /// apart. Run together in a row they need the stop the display did not.
    public var sentence: String {
        let stopped = headline.hasSuffix(".") || headline.hasSuffix("!") || headline.hasSuffix("?")
        let lead = stopped ? headline : headline + "."
        guard let next else { return lead }
        return "\(lead) \(next)"
    }
}

// MARK: - Where the watch is

/// Where the watch physically is on its way to the bench.
///
/// `to_auth` is a single order status covering three genuinely different
/// situations, and before the record existed all three read as "on its way to
/// our authentication centre" — including the days after it had already
/// arrived. Only the record can tell the last of them apart: the carrier's
/// delivered scan says a parcel reached a building, and `arrivedAt` says a
/// watch reached a person who opened the box and photographed it.
public enum ArrivalPhase: Sendable, Equatable {
    /// The seller has a label; nothing has been scanned.
    case labelBought
    /// The carrier has it.
    case inTransit
    /// The carrier says delivered; the bench has not confirmed.
    case deliveredUnconfirmed
    /// The bench confirmed, with the two liability photographs.
    case onTheBench
}

public extension Order {
    var arrivalPhase: ArrivalPhase {
        if authentication?.arrivedAt != nil { return .onTheBench }
        if toAuthShipment?.deliveredAt != nil { return .deliveredUnconfirmed }
        if toAuthShipment?.shippedAt != nil { return .inTransit }
        return .labelBought
    }

    /// The buyer's sentence for `to_auth`, or nil for every other status —
    /// the caller keeps its own copy for those.
    var arrivalSummary: String? {
        guard status == .toAuth else { return nil }
        switch arrivalPhase {
        case .labelBought:
            return "The seller has their label. Your watch is with them until they hand it to the carrier."
        case .inTransit:
            return "With the carrier, on its way to our authentication centre."
        case .deliveredUnconfirmed:
            return "It has reached our authentication centre and is waiting to be checked in by hand."
        case .onTheBench:
            return "On the bench at our authentication centre."
        }
    }

    /// The same fact for the seller, whose question is "did it get there".
    var sellerArrivalSummary: String? {
        guard status == .toAuth else { return nil }
        switch arrivalPhase {
        case .labelBought:
            return "Your label is ready. Nothing has been scanned yet — the clock starts when the carrier takes it."
        case .inTransit:
            return "The carrier has your watch and it is on its way to authentication."
        case .deliveredUnconfirmed:
            return "Your watch has reached the authentication centre and is waiting to be checked in by hand."
        case .onTheBench:
            return "Your watch is on the bench at the authentication centre."
        }
    }

    /// A person at Calibre is looking at this watch more closely.
    ///
    /// A state of the RECORD, not of the order: the order sits at `to_auth`
    /// throughout, which is why nothing keyed to the status can see one.
    var isHeld: Bool { authentication?.isHeld == true }
}

// MARK: - Saying a date

/// The formatting the two readings share.
///
/// `Date` here is always an instant the server sent. The one calendar day in
/// the payload — the bench's `expected_out_on` — is turned into a day at the
/// reader's own midnight when it is decoded, so that by the time it reaches
/// this file it prints as the day the bench wrote down.
enum OrderDay {
    /// "September 12".
    static func dayMonth(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.dateTime.month(.wide).day())
    }

    /// "September 12 at 3:00 PM" — used where a deadline is the point.
    static func dayAndTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.dateTime.month(.wide).day().hour().minute())
    }
}

private extension Order {
    /// When Calibre expects to be finished with the watch.
    ///
    /// The server's own forecast first, the bench's expected-out date second.
    /// Nil when neither is known, which is the case a sentence must not paper
    /// over.
    var verdictExpectedBy: String? {
        OrderDay.dayMonth(expected?.authenticationVerdictBy)
            ?? OrderDay.dayMonth(authentication?.expectedOutOn)
    }
}

public extension Order {
    /// The date the watch is expected at the buyer's door, from the server
    /// alone. Nil when the server sent none.
    var expectedDeliveryLabel: String? {
        if let delivered = latestShipment?.deliveredAt {
            return OrderDay.dayMonth(delivered)
        }
        return OrderDay.dayMonth(status == .toAuth ? expected?.shippedToYouBy : expected?.deliveredBy)
    }
}

// MARK: - The next step

public extension Order {
    /// Whose move it is, and what happens next.
    ///
    /// Read in order. The clauses above the status switch are all states the
    /// status cannot see: a live return, a proposal waiting on an answer, a
    /// wire still owed, and a hold are each recorded somewhere other than
    /// `status`, and each of them outranks whatever the status happens to say.
    func nextStep(now: Date = .now) -> OrderNextStep {
        // A return that was called off is not a live one. The web reads
        // `order.return`'s presence alone; this app has carried a cancelled
        // return on the payload since returns shipped, and `isCancelled` is
        // the predicate the return panel on this screen already gates on.
        if let activeReturn = returnSummary, !activeReturn.isCancelled, !activeReturn.isRefunded {
            // The parcel has landed. Before this, a return the bench already
            // had still read "on its way to us" — the carrier's scan is set
            // for good, so the in-transit clause below never stopped matching.
            if let state = activeReturn.state, returnAtTheBench.contains(state) {
                return OrderNextStep(
                    actor: .calibre,
                    headline: "Your return is with our authentication centre",
                    next: "We authenticate it again, then your refund is issued."
                )
            }
            if activeReturn.isInTransit {
                return OrderNextStep(
                    actor: .calibre,
                    headline: "Your return is on its way to us",
                    next: "We authenticate it again when it lands, then your refund is issued."
                )
            }
            let by = OrderDay.dayAndTime(activeReturn.shipDeadlineAt)
            return OrderNextStep(
                actor: .you,
                headline: "Send the watch back",
                next: by.map { "Hand it to the carrier by \($0)." }
                    ?? "Print your return label below and hand it to the carrier."
            )
        }

        if authentication?.authCase?.awaitingYou == true {
            return OrderNextStep(
                actor: .you,
                headline: "A proposal is waiting for your answer",
                next: "Nothing about this order changes until you answer."
            )
        }

        if status == .awaitingWire {
            return wireStep
        }

        if let record = authentication, record.isHeld {
            return OrderNextStep(
                actor: .calibre,
                headline: record.holdTitle,
                body: record.holdBody,
                next: "Nothing is expected of you right now."
            )
        }

        switch status {
        case .awaitingWire:
            // Reached only from the clause above, which outranks the hold
            // below it. Named here because the switch names every status —
            // a `default` would swallow the next one somebody adds.
            return wireStep

        case .purchased:
            return OrderNextStep(
                actor: .seller,
                headline: "The seller is preparing your watch",
                next: "We will tell you when it is on its way to authentication."
            )

        case .toAuth:
            // The authored sentence, which is the only thing that tells the
            // three holders of a `to_auth` watch apart.
            let headline = arrivalSummary ?? "Your watch is on its way to our authentication centre."
            switch arrivalPhase {
            case .labelBought:
                return OrderNextStep(
                    actor: .seller,
                    headline: headline,
                    next: "The clock starts when the carrier takes it."
                )
            case .inTransit:
                return OrderNextStep(
                    actor: .calibre,
                    headline: headline,
                    next: "We check every watch in by hand when it arrives."
                )
            case .deliveredUnconfirmed, .onTheBench:
                return OrderNextStep(
                    actor: .calibre,
                    headline: headline,
                    next: verdictExpectedBy.map { "We expect to finish authenticating it by \($0)." }
                        ?? "We will write to you as soon as it is authenticated."
                )
            }

        case .authPass:
            return OrderNextStep(
                actor: .calibre,
                // A pass is claimed only where the record says so. A payload
                // can carry this status beside a verdict that turned the watch
                // down, and the neutral sentence is true either way.
                headline: authentication?.verdict == authenticatedVerdict
                    ? "Authenticated by Calibre"
                    : "Authentication complete",
                next: expectedDeliveryLabel.map { "We are preparing your shipment, due \($0)." }
                    ?? "We are preparing your shipment."
            )

        case .toBuyer:
            return OrderNextStep(
                actor: .calibre,
                headline: "On its way to you",
                next: expectedDeliveryLabel.map { "Expected \($0)." }
                    ?? "Your tracking number is below."
            )

        case .delivered:
            // The one thing left to decide on a delivered order, and only
            // while it is genuinely still open. A closing date in the past is
            // not an offer.
            let stillOpen = returns?.accepted == true && returns?.isOpen(now: now) == true
            let closes = stillOpen ? OrderDay.dayAndTime(returns?.windowEndsAt) : nil
            return OrderNextStep(
                actor: nil,
                headline: "Delivered",
                next: closes.map { "You can send it back until \($0)." }
            )

        case .authFail:
            return OrderNextStep(
                actor: .calibre,
                headline: "This watch did not pass",
                body: "Our authentication centre could not authenticate it, so the sale is off. You are being "
                    + "refunded in full, including the card processing fee, and you owe nothing.",
                next: "Your Calibre contact will write to you with what we found."
            )

        case .cancelled:
            return OrderNextStep(actor: nil, headline: "This order was cancelled", next: nil)

        case .refunded:
            return OrderNextStep(actor: nil, headline: "This order was refunded", next: nil)

        case .unknown:
            return OrderNextStep(actor: nil, headline: "Your order is in progress", next: nil)
        }
    }
}

// MARK: - The timeline

/// `stopped` is a step that was reached and did not complete. Nothing after a
/// stopped step is ever `now`: a watch that did not pass is not on its way.
public enum OrderTimelineState: String, Sendable, Equatable {
    case done
    case now
    case later
    case stopped
}

public struct OrderTimelineStep: Sendable, Equatable, Identifiable {
    public let name: String
    /// What is known about this step — a date, or the bench's own state.
    public let line: String?
    public let state: OrderTimelineState

    public var id: String { name }
}

public extension Order {
    /// The wire the buyer still owes, and how long the watch waits for it.
    private var wireStep: OrderNextStep {
        let due = OrderDay.dayAndTime(paymentDueAt)
        return OrderNextStep(
            actor: .you,
            headline: "Send your wire transfer",
            next: due.map { "The watch is reserved for you until \($0)." }
                ?? "The watch is reserved for you while the wire is pending."
        )
    }

    /// The names of the steps, in the order a watch moves through them.
    static let timelineStepNames = [
        "Order placed",
        "Shipped to authentication",
        "At the authentication centre",
        "Authentication",
        "Shipped to you",
        "Delivered",
    ]

    /// The bench turned this watch down — read off the record where the record
    /// speaks, and off the status where it is the only thing that does.
    ///
    /// The two are asked separately on purpose: `auth_fail` is a refusal a
    /// payload can carry with no record at all, and a negative `verdict` is a
    /// refusal a payload can carry while the status still says `auth_pass`. A
    /// missing record is not a negative one, so nil `verdict` is not a failure.
    var authenticationFailed: Bool {
        if status == .authFail { return true }
        guard let verdict = authentication?.verdict else { return false }
        return verdict != authenticatedVerdict
    }

    /// The last step this order has reached, as an index into
    /// `timelineStepNames`.
    ///
    /// One scale. The rail this replaces kept the checkpoint index and the
    /// status label on separate tables, and they disagreed: `to_auth` lit
    /// "Shipped to authentication" for a seller who had only bought a label,
    /// and `auth_pass` lit "Authenticated" for a watch the bench had turned
    /// down. There is nothing here for a second table to disagree with.
    private var timelineReachedIndex: Int {
        switch status {
        case .awaitingWire:
            return -1
        case .purchased:
            return 0
        case .toAuth:
            // The record, not the status. All three of these are `to_auth`: a
            // seller holding a label they have not used, a carrier holding the
            // parcel, and the bench holding the watch.
            switch arrivalPhase {
            case .labelBought: return 0
            case .inTransit: return 1
            case .deliveredUnconfirmed, .onTheBench: return 2
            }
        case .authPass:
            return 3
        case .authFail:
            // The bench has it and authentication did not complete, whatever
            // the status is called.
            return 2
        case .toBuyer:
            return 4
        case .delivered:
            return 5
        case .cancelled, .refunded, .unknown:
            return 0
        }
    }

    /// The bench's own state, in the words a customer is told it in. Nil when
    /// the server sent no record, because an absent fact is not a negative one.
    ///
    /// "Under review" is keyed to an open case rather than to a `disputed`
    /// order status: this backend's order statuses do not include one, so a
    /// clause reading for it would never fire. A case is the record saying a
    /// person at Calibre is looking at this watch, which is the fact the word
    /// is for.
    private var authenticationLine: String? {
        guard let record = authentication else { return nil }
        if record.verdict == authenticatedVerdict { return "Passed" }
        if record.verdict != nil { return "Did not pass" }
        if record.isHeld { return "On hold" }
        if record.authCase != nil { return "Under review" }
        return record.stage == .inHand ? "On the bench" : nil
    }

    /// The journey, step by step, with what is known under each one.
    ///
    /// Nil for an order that was cancelled or refunded: a column of steps
    /// nothing will ever reach is not a timeline, and the order says what
    /// happened to it in one line instead.
    func timeline() -> [OrderTimelineStep]? {
        if status == .cancelled || status == .refunded { return nil }

        let reached = timelineReachedIndex
        let failed = authenticationFailed
        let authenticationIndex = 3

        let lines: [String?] = [
            status == .awaitingWire ? "Waiting for your wire transfer" : OrderDay.dayMonth(createdAt),
            OrderDay.dayMonth(toAuthShipment?.shippedAt),
            OrderDay.dayMonth(authentication?.arrivedAt),
            authenticationLine,
            OrderDay.dayMonth(toBuyerShipment?.shippedAt),
            OrderDay.dayMonth(latestShipment?.deliveredAt),
        ]

        return Self.timelineStepNames.enumerated().map { index, name in
            var state: OrderTimelineState = .later
            if index <= reached {
                state = .done
            } else if index == reached + 1 {
                state = .now
            }
            if failed {
                // Authentication is where a refusal lands, and nothing
                // downstream of it is waiting to happen. Without this the
                // steps after it stay `now`/`later` and a turned-down watch
                // reads as still on its way.
                state = index < authenticationIndex
                    ? state
                    : (index == authenticationIndex ? .stopped : .later)
            }
            return OrderTimelineStep(name: name, line: lines[index], state: state)
        }
    }
}
