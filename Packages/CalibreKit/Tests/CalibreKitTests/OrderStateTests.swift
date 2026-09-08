import Foundation
import XCTest
@testable import CalibreKit

/// `Order.nextStep()` and `Order.timeline()` — the two readings both buyer
/// screens now take their words from.
///
/// The cases here are the ones where the order STATUS and the authentication
/// RECORD disagree, because those are the readings the rail this replaced got
/// wrong, and every one of them was wrong in the same direction: it told the
/// buyer their watch was further along than it was.
final class OrderStateTests: XCTestCase {

    // MARK: - Building an order

    /// An order payload with only what a case needs, decoded through the
    /// client's own decoder — so a test can never pass on a shape the app
    /// would refuse.
    private func order(
        status: String,
        authentication: String = "null",
        toAuthShipment: String = "null",
        toBuyerShipment: String = "null",
        latestShipment: String = "null",
        extra: String = ""
    ) throws -> Order {
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "\(status)",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD",
          "created_at": "2026-08-01T12:00:00Z",
          "authentication": \(authentication),
          "to_auth_shipment": \(toAuthShipment),
          "to_buyer_shipment": \(toBuyerShipment),
          "latest_shipment": \(latestShipment)\(extra)
        }
        """
        return try apiDecoder().decode(Order.self, from: Data(json.utf8))
    }

    private func record(
        stage: String = "in_hand",
        step: String = "started",
        verdict: String = "null",
        arrivedAt: String = "null",
        expectedOutOn: String = "null"
    ) -> String {
        """
        {"record_id": "r1", "number": "1041", "kind": "authentication",
         "stage": "\(stage)", "step": "\(step)", "verdict": \(verdict),
         "arrived_at": \(arrivedAt), "expected_out_on": \(expectedOutOn)}
        """
    }

    private func shipment(shippedAt: String = "null", deliveredAt: String = "null") -> String {
        """
        {"id": "sh1", "shipment_type": "to_auth", "carrier": "FedEx",
         "shipped_at": \(shippedAt), "delivered_at": \(deliveredAt)}
        """
    }

    private func step(_ order: Order, _ name: String) throws -> OrderTimelineStep {
        let steps = try XCTUnwrap(order.timeline())
        return try XCTUnwrap(steps.first { $0.name == name })
    }

    // MARK: - Wrong reading one: a label is not a shipment

    /// A `to_auth` order where the seller only holds a label has not shipped.
    ///
    /// All three of these are `to_auth`: a seller holding a label they have not
    /// used, a carrier holding the parcel, and the bench holding the watch. The
    /// rail this replaced marked "Shipped to authentication" complete for the
    /// first of them — the one where nothing has shipped, and where the person
    /// who has to act is the seller.
    func testALabelWithNoScanIsNotShippedToAuthentication() throws {
        let labelOnly = try order(status: "to_auth", toAuthShipment: shipment())

        XCTAssertEqual(labelOnly.arrivalPhase, .labelBought)
        XCTAssertNotEqual(try step(labelOnly, "Shipped to authentication").state, .done)
        XCTAssertEqual(try step(labelOnly, "Shipped to authentication").state, .now)
        XCTAssertEqual(try step(labelOnly, "Order placed").state, .done)

        // And the actor: it is the seller's move, not Calibre's.
        XCTAssertEqual(labelOnly.nextStep().actor, .seller)
        XCTAssertEqual(labelOnly.nextStep().actor?.label, "With the seller")

        // The same status, once the carrier has actually taken it.
        let inTransit = try order(
            status: "to_auth",
            toAuthShipment: shipment(shippedAt: "\"2026-08-04T18:00:00Z\"")
        )
        XCTAssertEqual(inTransit.arrivalPhase, .inTransit)
        XCTAssertEqual(try step(inTransit, "Shipped to authentication").state, .done)
        XCTAssertEqual(inTransit.nextStep().actor, .calibre)
    }

    // MARK: - Wrong reading two: a pass the record did not give

    /// An `auth_pass` order carrying a negative verdict has not passed.
    ///
    /// The status is the shape of the journey and the record is what happened,
    /// so where they disagree the record wins. A rail keyed to the status alone
    /// lit "Authentication" complete for a watch the bench turned down.
    func testAuthPassWithANegativeVerdictIsNotAPass() throws {
        let turnedDown = try order(
            status: "auth_pass",
            authentication: record(verdict: "\"not_authentic\"")
        )

        XCTAssertTrue(turnedDown.authenticationFailed)
        XCTAssertEqual(try step(turnedDown, "Authentication").state, .stopped)
        XCTAssertEqual(try step(turnedDown, "Authentication").line, "Did not pass")
        // Nothing downstream of a refusal is on its way.
        XCTAssertEqual(try step(turnedDown, "Shipped to you").state, .later)
        XCTAssertEqual(try step(turnedDown, "Delivered").state, .later)
        // And the headline claims nothing the record did not say.
        XCTAssertEqual(turnedDown.nextStep().headline, "Authentication complete")

        let passed = try order(
            status: "auth_pass",
            authentication: record(verdict: "\"authenticated\"")
        )
        XCTAssertFalse(passed.authenticationFailed)
        XCTAssertEqual(try step(passed, "Authentication").state, .done)
        XCTAssertEqual(try step(passed, "Authentication").line, "Passed")
        XCTAssertEqual(passed.nextStep().headline, "Authenticated by Calibre")

        // A missing record is not a negative one. Every order served by a
        // deployment predating the record has none, and none of them failed.
        let noRecord = try order(status: "auth_pass")
        XCTAssertFalse(noRecord.authenticationFailed)
        XCTAssertEqual(try step(noRecord, "Authentication").state, .done)
        XCTAssertNil(try step(noRecord, "Authentication").line)
    }

    // MARK: - Wrong reading three: a stopped journey is drawn, not hidden

    /// `auth_fail` stops at Authentication, with nothing after it reading as
    /// still on its way — and the journey is still drawn.
    ///
    /// The screen used to hide the rail entirely on `auth_fail`. A buyer whose
    /// watch had been turned down got no answer at all to "where is my watch",
    /// on the one status where the question is hardest to ask a person.
    func testAuthFailIsDrawnStoppedRatherThanHidden() throws {
        let failed = try order(status: "auth_fail", authentication: record(step: "completed"))

        let steps = try XCTUnwrap(failed.timeline(), "auth_fail still has a journey to draw")
        XCTAssertEqual(steps.count, Order.timelineStepNames.count)
        XCTAssertEqual(try step(failed, "Authentication").state, .stopped)

        // Nothing after the refusal is `now` — no step is waiting to happen.
        let after = steps.drop { $0.name != "Authentication" }.dropFirst()
        XCTAssertFalse(after.isEmpty)
        XCTAssertTrue(after.allSatisfy { $0.state == .later }, "nothing after a refusal is on its way")
        XCTAssertFalse(steps.contains { $0.state == .now })

        // Cancelled and refunded are the two that genuinely have no journey.
        XCTAssertNil(try order(status: "cancelled").timeline())
        XCTAssertNil(try order(status: "refunded").timeline())
        XCTAssertEqual(try order(status: "cancelled").nextStep().headline, "This order was cancelled")
    }

    // MARK: - A date nobody promised

    /// `next` is nil wherever the server gave no date.
    ///
    /// The rule this protects is the whole reason `next` is optional: a client
    /// that fills the gap with a sentence of its own has made a promise on
    /// Calibre's behalf that nobody at Calibre made.
    func testNextIsNilWhereNothingHonestCanBeSaid() throws {
        // Delivered, with no return window open: there is nothing left to say.
        let delivered = try order(status: "delivered")
        XCTAssertEqual(delivered.nextStep().headline, "Delivered")
        XCTAssertNil(delivered.nextStep().next)
        XCTAssertNil(delivered.nextStep().actor)

        // A closing date in the past is not an offer.
        let closed = try order(
            status: "delivered",
            extra: """
            ,
              "returns": {"accepted": true, "window_hours": 48,
                          "window_started_at": "2026-08-01T00:00:00Z",
                          "window_ends_at": "2026-08-03T00:00:00Z"}
            """
        )
        XCTAssertNil(closed.nextStep(now: Date(timeIntervalSince1970: 1_790_000_000)).next)

        // Cancelled and refunded say what happened and stop.
        XCTAssertNil(try order(status: "cancelled").nextStep().next)
        XCTAssertNil(try order(status: "refunded").nextStep().next)

        // On the bench with no expected-out date, the sentence does not name
        // one — it says what will happen, not when.
        let noDate = try order(
            status: "to_auth",
            authentication: record(arrivedAt: "\"2026-08-04T18:00:00Z\"")
        )
        let without = try XCTUnwrap(noDate.nextStep().next)
        XCTAssertEqual(without, "We will write to you as soon as it is authenticated.")
        XCTAssertFalse(without.contains("by "), "no date is named when the server sent none")
    }

    // MARK: - The one calendar day in the payload

    /// `expected_out_on` is a date-only string, and it must survive decoding.
    ///
    /// Before this it did not survive at all. `ISO8601DateFormatter` returns
    /// nil for a string with no time, so the decoder every payload goes through
    /// threw on it — and the synthesized initializer let the throw travel, so a
    /// single bench date took the whole `Order` with it. This asserts the
    /// order decodes, that the day is the day the bench wrote down rather than
    /// the one before it, and that the date reaches the sentence.
    func testTheBenchDateIsReadAsACalendarDay() throws {
        let withDate = try order(
            status: "to_auth",
            authentication: record(
                arrivedAt: "\"2026-08-04T18:00:00Z\"",
                expectedOutOn: "\"2026-09-12\""
            )
        )

        let expected = try XCTUnwrap(
            withDate.authentication?.expectedOutOn,
            "a date-only expected_out_on must decode, not take the order down with it"
        )

        // The day that comes out is the day that went in, in the reader's own
        // calendar — which is the whole point of not reading it as an instant.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: expected)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 12)

        // And it reaches the sentence rather than stopping at the model.
        let next = try XCTUnwrap(withDate.nextStep().next)
        XCTAssertTrue(next.contains("September 12"), "expected the bench's day in: \(next)")
    }

    /// The whole order survives a bench date, which is what actually broke.
    ///
    /// Asserted separately from the formatting above because the failure was
    /// never about the day being wrong — it was about the order, the screen,
    /// and every row of a list the order appeared in failing to decode.
    func testABenchDateDoesNotCostTheOrderOrTheListItIsIn() throws {
        let page = """
        {"results": [
          {"id": "o1", "buyer_id": "b1", "listing_id": "l1", "status": "to_auth",
           "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00", "currency": "USD",
           "authentication": {"record_id": "r1", "number": "1041", "kind": "authentication",
                              "stage": "in_hand", "step": "started", "expected_out_on": "2026-09-12"}},
          {"id": "o2", "buyer_id": "b1", "listing_id": "l2", "status": "purchased",
           "subtotal": "2.00", "fees_total": "0.00", "grand_total": "2.00", "currency": "USD"}
         ],
         "pagination": {"page": 1, "page_size": 20, "total": 2, "total_pages": 1}}
        """
        let decoded = try apiDecoder().decode(PageResponse<Order>.self, from: Data(page.utf8))
        XCTAssertEqual(decoded.results.count, 2, "one bench date must not empty the page")
        XCTAssertNotNil(decoded.results.first?.authentication?.expectedOutOn)
    }

    /// A value in neither shape costs its own line and nothing else.
    func testAnUnreadableBenchDateCostsOnlyItself() throws {
        let odd = try order(
            status: "to_auth",
            authentication: record(expectedOutOn: "\"not a date\"")
        )
        XCTAssertNotNil(odd.authentication, "the record still decodes")
        XCTAssertNil(odd.authentication?.expectedOutOn)

        // An instant is still read as an instant, for a deployment sending one.
        let instant = try order(
            status: "to_auth",
            authentication: record(expectedOutOn: "\"2026-09-12T00:00:00Z\"")
        )
        XCTAssertNotNil(instant.authentication?.expectedOutOn)
    }

    // MARK: - One table of names

    /// The list and the order page read the actor from the same table, so they
    /// cannot word it differently.
    func testTheActorIsNamedByOneTable() {
        XCTAssertEqual(OrderActor.you.label, "Waiting on you")
        XCTAssertEqual(OrderActor.seller.label, "With the seller")
        XCTAssertEqual(OrderActor.calibre.label, "With Calibre")
    }

    /// The clauses above the status switch outrank whatever the status says.
    func testTheRecordOutranksTheStatusWord() throws {
        // A hold is a state of the record; the order sits at `to_auth`.
        let held = try order(
            status: "to_auth",
            authentication: record(step: "on_hold", arrivedAt: "\"2026-08-04T18:00:00Z\"")
        )
        XCTAssertTrue(held.isHeld)
        XCTAssertEqual(held.nextStep().actor, .calibre)
        XCTAssertNotNil(held.nextStep().body, "a hold is one of the two moments that earns a paragraph")
        XCTAssertEqual(try step(held, "Authentication").line, "On hold")

        // A proposal waiting on the buyer outranks the hold above it.
        let awaiting = try order(
            status: "to_auth",
            authentication: """
            {"record_id": "r1", "number": "1041", "kind": "authentication",
             "stage": "in_hand", "step": "on_hold",
             "case": {"id": "c1", "status": "open", "awaiting_you": true, "has_proposal": true}}
            """
        )
        XCTAssertEqual(awaiting.nextStep().actor, .you)
        XCTAssertEqual(awaiting.nextStep().headline, "A proposal is waiting for your answer")
    }

    // MARK: - A return that has landed

    /// A return the bench already has is not still on the road.
    ///
    /// `isInTransit` is true from the carrier's first scan onwards and stays
    /// true after the parcel arrives, so a return in `received` or `verifying`
    /// read "on its way to us" for as long as it sat on the bench. The state
    /// is asked first, which is the reading Android and the web share.
    func testAReturnAtTheBenchIsNotStillOnItsWay() throws {
        func withReturn(_ state: String, scanned: Bool) throws -> Order {
            try order(
                status: "delivered",
                extra: """
                ,
                  "return": {"state": "\(state)",
                             "ship_deadline_at": "2026-08-10T17:00:00Z",
                             "carrier_first_scan_at": \(scanned ? "\"2026-08-06T09:00:00Z\"" : "null")}
                """
            )
        }

        for state in ["received", "verifying"] {
            for scanned in [true, false] {
                let arrived = try withReturn(state, scanned: scanned)
                let reading = arrived.nextStep()
                XCTAssertEqual(reading.actor, .calibre, state)
                XCTAssertEqual(reading.headline, "Your return is with our authentication centre", state)
                XCTAssertEqual(reading.next, "We authenticate it again, then your refund is issued.", state)
            }
        }

        // Still on the road, and still worded that way.
        let onTheRoad = try withReturn("in_transit", scanned: true)
        XCTAssertEqual(onTheRoad.nextStep().headline, "Your return is on its way to us")

        // Not handed over yet: the buyer still owes the carrier a parcel.
        let owed = try withReturn("requested", scanned: false)
        XCTAssertEqual(owed.nextStep().actor, .you)
        XCTAssertEqual(owed.nextStep().headline, "Send the watch back")

        // A settled return leaves the order to be described by its own status.
        let cancelled = try withReturn("cancelled", scanned: false)
        XCTAssertEqual(cancelled.nextStep().headline, "Delivered")
    }

    // MARK: - Under review

    /// An open case is what "Under review" is keyed to.
    ///
    /// Not a `disputed` order status: there is no such status on this backend,
    /// so a clause reading for one could never fire and the word would never
    /// appear. A case is the record saying a person at Calibre is looking at
    /// this watch, which is the fact the word is for.
    func testUnderReviewComesFromAnOpenCaseAndNotFromAStatus() throws {
        let reviewed = try order(
            status: "to_auth",
            authentication: """
            {"record_id": "r1", "number": "1041", "kind": "authentication",
             "stage": "intake", "step": "started",
             "case": {"id": "c1", "status": "open", "awaiting_you": false, "has_proposal": false}}
            """
        )
        XCTAssertEqual(try step(reviewed, "Authentication").line, "Under review")

        // A hold outranks it: both are true at once, and the hold is the one
        // with a paragraph behind it.
        let held = try order(
            status: "to_auth",
            authentication: """
            {"record_id": "r1", "number": "1041", "kind": "authentication",
             "stage": "in_hand", "step": "on_hold",
             "case": {"id": "c1", "status": "open", "awaiting_you": false, "has_proposal": false}}
            """
        )
        XCTAssertEqual(try step(held, "Authentication").line, "On hold")

        // And a verdict outranks both — the record is what actually happened.
        let passed = try order(
            status: "to_auth",
            authentication: """
            {"record_id": "r1", "number": "1041", "kind": "authentication",
             "stage": "in_hand", "step": "started", "verdict": "authenticated",
             "case": {"id": "c1", "status": "open", "awaiting_you": false, "has_proposal": false}}
            """
        )
        XCTAssertEqual(try step(passed, "Authentication").line, "Passed")

        // No case, no review: an absent fact is not a negative one.
        let plain = try order(status: "to_auth", authentication: record(stage: "intake"))
        XCTAssertNil(try step(plain, "Authentication").line)
    }

    /// The row's sentence is the page's own lead, punctuated to run on.
    func testTheRowSentenceIsTheLeadRunTogether() throws {
        let purchased = try order(status: "purchased")
        let step = purchased.nextStep()
        XCTAssertEqual(step.actor, .seller)
        XCTAssertEqual(
            step.sentence,
            "The seller is preparing your watch. We will tell you when it is on its way to authentication."
        )

        // A headline that already ends in a stop does not gain a second one.
        let onTheBench = try order(
            status: "to_auth",
            authentication: record(arrivedAt: "\"2026-08-04T18:00:00Z\"")
        )
        XCTAssertFalse(onTheBench.nextStep().sentence.contains(".."))

        // Nothing to add is nothing appended.
        XCTAssertEqual(try order(status: "cancelled").nextStep().sentence, "This order was cancelled.")
    }
}
