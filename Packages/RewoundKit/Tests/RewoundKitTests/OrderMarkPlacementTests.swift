import Foundation
import XCTest
@testable import RewoundKit

/// Which illustrated mark the buyer's order screen is allowed to draw.
///
/// Written as behavior rather than as a count: what matters is which mark a
/// given order reaches, not how many placements exist. Every failure here is a
/// mark asserting something the server did not say — a parcel on a delivered
/// order, a stamp on a watch that failed the bench, a gauge on a window with a
/// guessed denominator.
final class OrderMarkPlacementTests: XCTestCase {

    private func order(
        status: String,
        authentication: String? = nil,
        returns: String? = nil
    ) throws -> Order {
        var extras = ""
        if let authentication { extras += ", \"authentication\": \(authentication)" }
        if let returns { extras += ", \"returns\": \(returns)" }
        let json = """
        {"id": "o1", "buyer_id": "b1", "listing_id": "l1", "status": "\(status)",
         "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
         "currency": "USD"\(extras)}
        """
        return try apiDecoder().decode(Order.self, from: Data(json.utf8))
    }

    private func record(verdict: String?) -> String {
        let value = verdict.map { "\"\($0)\"" } ?? "null"
        return """
        {"record_id": "r1", "number": "1041", "kind": "intake", "stage": "closed",
         "step": "completed", "hold_reason": null, "verdict": \(value),
         "service_recommended": null, "arrived_at": null, "expected_out_on": null,
         "shipped_at": null, "report": null, "case": null}
        """
    }

    // MARK: - The parcel

    func testTheParcelDrawsForExactlyTheTravellingStatuses() throws {
        XCTAssertEqual(try order(status: "to_auth").mark(), .box)
        XCTAssertEqual(try order(status: "to_buyer").mark(), .box)
    }

    /// A carton leaving the frame on a delivered order reads as the watch
    /// going away again, and on a canceled one as a watch still coming.
    func testTheParcelDrawsForNothingElse() throws {
        for status in ["awaiting_wire", "purchased", "auth_fail", "cancelled", "refunded"] {
            XCTAssertNotEqual(try order(status: status).mark(), .box, "\(status) is not traveling")
        }
        XCTAssertNotEqual(try order(status: "delivered").mark(), .box)
        // `auth_pass` is the bench's verdict, not a leg of the journey.
        XCTAssertNotEqual(
            try order(status: "auth_pass", authentication: record(verdict: "authenticated")).mark(),
            .box
        )
    }

    /// The key is the milestone, so the sixty-second refetch cannot re-seal
    /// the same parcel while a status that moves under the buyer still sends
    /// it off again.
    func testTheParcelsKeyMovesOnlyWithTheStatus() throws {
        let toAuth = try order(status: "to_auth")
        let toBuyer = try order(status: "to_buyer")
        XCTAssertEqual(toAuth.transitMarkKey, try order(status: "to_auth").transitMarkKey)
        XCTAssertNotEqual(toAuth.transitMarkKey, toBuyer.transitMarkKey)
    }

    // MARK: - The checkout moment

    /// Paid and nothing shipped: the parcel is being packed, and the lead says
    /// so. The journey header has nothing to draw at the same moment, which is
    /// what keeps the screen at one mark.
    func testTheCheckoutMomentDrawsForAPaidOrderThatHasNotShipped() throws {
        let paid = try order(status: "purchased")
        XCTAssertEqual(paid.checkoutMarkKey(), "checkout:o1")
        XCTAssertNil(paid.mark(), "the journey header stands down while the lead carries the parcel")
    }

    func testTheCheckoutMomentDrawsForNothingElse() throws {
        for status in ["awaiting_wire", "to_auth", "auth_pass", "auth_fail", "to_buyer", "delivered", "cancelled", "refunded"] {
            XCTAssertNil(try order(status: status).checkoutMarkKey(), "\(status) is not the checkout moment")
        }
    }

    /// The precedence is the helper's, not the view's: a paid order that
    /// somehow carries the bench's verdict is the stamp's, and the lead's
    /// parcel stands down rather than making a second mark.
    func testAnotherMarkOutranksTheCheckoutMoment() throws {
        let stamped = try order(status: "purchased", authentication: record(verdict: "authenticated"))
        XCTAssertEqual(stamped.mark(), .stamp)
        XCTAssertNil(stamped.checkoutMarkKey())
    }

    // MARK: - The stamp

    func testTheStampReadsTheVerdictAndNotTheStatus() throws {
        XCTAssertEqual(
            try order(status: "auth_pass", authentication: record(verdict: "authenticated")).mark(),
            .stamp
        )
        // The rail puts a failed order on the same dot as a passed one, so a
        // mark keyed to it would stamp a watch that failed.
        XCTAssertNil(try order(status: "auth_fail", authentication: record(verdict: "counterfeit")).mark())
        XCTAssertNil(try order(status: "auth_fail", authentication: record(verdict: "misrepresented")).mark())
    }

    /// An absent record is not a negative one — it is what a deployment that
    /// predates the record sends — and a null verdict is not a pass.
    func testAnAbsentOrNullVerdictIsNotAPass() throws {
        XCTAssertNil(try order(status: "auth_pass").mark())
        XCTAssertNil(try order(status: "auth_pass", authentication: record(verdict: nil)).mark())
        XCTAssertNil(try order(status: "auth_pass").verdictMarkKey)
    }

    // MARK: - The return window

    private func terms(started: String?, ends: String?, accepted: Bool = true) -> String {
        func value(_ raw: String?) -> String { raw.map { "\"\($0)\"" } ?? "null" }
        return """
        {"accepted": \(accepted), "window_hours": 72,
         "window_started_at": \(value(started)), "window_ends_at": \(value(ends))}
        """
    }

    func testTheGaugeReadsTheWindowsOwnTwoTimestamps() throws {
        let started = Date(timeIntervalSince1970: 0)
        let ends = Date(timeIntervalSince1970: 100)
        let window = try apiDecoder().decode(
            OrderReturnTerms.self,
            from: Data(terms(
                started: ISO8601DateFormatter().string(from: started),
                ends: ISO8601DateFormatter().string(from: ends)
            ).utf8)
        )

        XCTAssertEqual(try XCTUnwrap(window.remainingFraction(now: started)), 1, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(window.remainingFraction(now: Date(timeIntervalSince1970: 25))),
            0.75,
            accuracy: 0.001
        )
        XCTAssertEqual(try XCTUnwrap(window.remainingFraction(now: ends)), 0, accuracy: 0.001)
    }

    /// A needle cannot travel past either stop, and a window that closed while
    /// the screen was open reads below zero.
    func testTheReadingIsClamped() throws {
        let window = try apiDecoder().decode(
            OrderReturnTerms.self,
            from: Data(terms(started: "1970-01-01T00:00:00Z", ends: "1970-01-01T00:01:40Z").utf8)
        )
        XCTAssertEqual(window.remainingFraction(now: Date(timeIntervalSince1970: 10_000)), 0)
        XCTAssertEqual(window.remainingFraction(now: Date(timeIntervalSince1970: -10_000)), 1)
    }

    /// A gauge with a guessed denominator is worse than no gauge, so a missing
    /// end draws nothing rather than assuming what the window ought to be.
    func testAWindowMissingEitherEndHasNoReading() throws {
        let noStart = try apiDecoder().decode(
            OrderReturnTerms.self,
            from: Data(terms(started: nil, ends: "2026-09-09T00:00:00Z").utf8)
        )
        let noEnd = try apiDecoder().decode(
            OrderReturnTerms.self,
            from: Data(terms(started: "2026-09-06T00:00:00Z", ends: nil).utf8)
        )
        let inverted = try apiDecoder().decode(
            OrderReturnTerms.self,
            from: Data(terms(started: "2026-09-09T00:00:00Z", ends: "2026-09-06T00:00:00Z").utf8)
        )
        XCTAssertNil(noStart.remainingFraction())
        XCTAssertNil(noEnd.remainingFraction())
        XCTAssertNil(inverted.remainingFraction(), "a pair that describes no window is not a reading")
    }

    func testTheGaugeDrawsOnADeliveredOrderWithAnOpenWindow() throws {
        let ends = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
        let started = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3_600))
        XCTAssertEqual(
            try order(status: "delivered", returns: terms(started: started, ends: ends)).mark(),
            .dialArc
        )
        XCTAssertNil(
            try order(status: "delivered", returns: terms(started: started, ends: ends, accepted: false)).mark(),
            "a listing sold without returns has no window to read"
        )
        XCTAssertNil(
            try order(status: "delivered", returns: terms(started: nil, ends: ends)).mark()
        )
        XCTAssertNil(try order(status: "delivered").mark(), "and a payload with no return terms at all")
    }

    /// The precedence is followed literally rather than reasoned about at each
    /// call site: on a delivered watch the bench passed, the stamp is the mark
    /// and the window's gauge stands down.
    func testTheStampOutranksTheGauge() throws {
        let ends = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
        let started = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3_600))
        XCTAssertEqual(
            try order(
                status: "delivered",
                authentication: record(verdict: "authenticated"),
                returns: terms(started: started, ends: ends)
            ).mark(),
            .stamp
        )
    }
}
