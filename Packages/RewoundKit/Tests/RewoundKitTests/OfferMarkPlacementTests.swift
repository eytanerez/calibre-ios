import Foundation
import XCTest
@testable import RewoundKit

/// Which illustrated mark the offer screen is allowed to draw for the seller's
/// first-round window.
///
/// Written as behavior rather than as a count: every failure here is a gauge
/// asserting a window the server did not describe — a reading on a countered
/// offer, a needle on a closed window, a denominator that was guessed.
final class OfferMarkPlacementTests: XCTestCase {

    private func offer(
        status: String,
        history: String = "[]",
        created: String? = "1970-01-01T00:00:00Z",
        expires: String? = "1970-01-01T00:01:40Z"
    ) throws -> Offer {
        func value(_ raw: String?) -> String { raw.map { "\"\($0)\"" } ?? "null" }
        let json = """
        {"id": "of1", "listing_id": "l1", "buyer_id": "b1", "seller_id": "s1",
         "amount": "8700.00", "currency": "USD", "status": "\(status)",
         "negotiation_history": \(history),
         "created_at": \(value(created)), "expires_at": \(value(expires))}
        """
        return try apiDecoder().decode(Offer.self, from: Data(json.utf8))
    }

    private let start = Date(timeIntervalSince1970: 0)
    private let end = Date(timeIntervalSince1970: 100)

    func testTheGaugeReadsTheWindowsOwnTwoTimestamps() throws {
        let first = try offer(status: "pending_seller")
        XCTAssertEqual(try XCTUnwrap(first.firstRoundWindowRemaining(now: start)), 1, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(first.firstRoundWindowRemaining(now: Date(timeIntervalSince1970: 25))),
            0.75,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(first.firstRoundWindowRemaining(now: Date(timeIntervalSince1970: 99))),
            0.01,
            accuracy: 0.001
        )
    }

    /// The first round only. A countered offer has a history, and the band on
    /// the list screens owns that conversation.
    func testTheGaugeDrawsForTheFirstRoundAlone() throws {
        let countered = try offer(
            status: "pending_seller",
            history: #"[{"by": "seller", "amount": "8900.00", "message": null, "at": "1970-01-01T00:00:10Z"}]"#
        )
        XCTAssertNil(countered.firstRoundWindowRemaining(now: start))

        for status in ["hold_pending", "countered", "accepted_pending_payment", "paid", "declined", "expired"] {
            XCTAssertNil(try offer(status: status).firstRoundWindowRemaining(now: start), "\(status) is not the seller's first look")
        }
    }

    /// A window that has closed is not a reading — the chip beside it has
    /// gone, and a needle at zero would stand at a deadline that has passed.
    func testAClosedWindowHasNoReading() throws {
        let first = try offer(status: "pending_seller")
        XCTAssertNil(first.firstRoundWindowRemaining(now: end))
        XCTAssertNil(first.firstRoundWindowRemaining(now: Date(timeIntervalSince1970: 10_000)))
    }

    /// A gauge with a guessed denominator is worse than no gauge.
    func testAWindowMissingEitherEndHasNoReading() throws {
        XCTAssertNil(try offer(status: "pending_seller", created: nil).firstRoundWindowRemaining(now: start))
        XCTAssertNil(try offer(status: "pending_seller", expires: nil).firstRoundWindowRemaining(now: start))
        XCTAssertNil(
            try offer(status: "pending_seller", created: "1970-01-01T00:01:40Z", expires: "1970-01-01T00:00:00Z")
                .firstRoundWindowRemaining(now: Date(timeIntervalSince1970: -50)),
            "a pair that describes no window is not a reading"
        )
    }

    /// The needle cannot travel past the far stop: a clock behind the server's
    /// `created_at` still reads a full window.
    func testTheReadingIsClamped() throws {
        let first = try offer(status: "pending_seller")
        XCTAssertEqual(try XCTUnwrap(first.firstRoundWindowRemaining(now: Date(timeIntervalSince1970: -10_000))), 1)
    }
}
