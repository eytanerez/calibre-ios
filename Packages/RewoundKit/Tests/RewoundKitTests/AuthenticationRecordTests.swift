import Foundation
import XCTest
@testable import CalibreKit

/// `order.authentication` — the block every new order surface is gated on.
///
/// Two things here are easy to get silently wrong and expensive when they are.
/// The first is the `case` key: `case` is a Swift keyword, so the property is
/// spelled `authCase` and the snake-case converter would look for `auth_case`
/// unless the coding key names the wire field. The second is that an order
/// served by a deployment predating the record must still decode — a screen
/// that throws away the whole order because one new key is missing is worse
/// than one that shows the old copy.
final class AuthenticationRecordTests: XCTestCase {

    private func order(_ authentication: String) throws -> Order {
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "to_auth",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD",
          "authentication": \(authentication)
        }
        """
        return try apiDecoder().decode(Order.self, from: Data(json.utf8))
    }

    func testTheRecordDecodesIncludingTheCaseKey() throws {
        let decoded = try order("""
        {
          "record_id": "r1", "number": "1041", "kind": "authentication",
          "stage": "in_hand", "step": "on_hold", "hold_reason": "not_as_described",
          "verdict": null, "service_recommended": false,
          "arrived_at": "2026-08-04T18:00:00Z", "expected_out_on": null,
          "shipped_at": null,
          "report": {"version": 2, "issued_at": "2026-08-09T00:00:00Z",
                     "pdf_url": "/secure-media/auth_reports/r1/v2.pdf"},
          "case": {"id": "c1", "status": "open", "awaiting_you": true, "has_proposal": true}
        }
        """)
        let record = try XCTUnwrap(decoded.authentication)
        XCTAssertEqual(record.number, "1041")
        XCTAssertEqual(record.stage, .inHand)
        XCTAssertEqual(record.step, .onHold)
        XCTAssertEqual(record.report?.version, 2)
        // The one that would fail silently and leave the case unreachable.
        XCTAssertEqual(record.authCase?.id, "c1")
        XCTAssertEqual(record.authCase?.awaitingYou, true)
        XCTAssertNotNil(record.arrivedAt)
    }

    /// Held is a state of the RECORD. The order sits at `to_auth` throughout,
    /// which is why nothing before this could tell a hold from progress.
    func testHeldIsTheStageAndStepTogether() throws {
        let held = try order("""
        {"record_id": "r1", "number": "1041", "kind": "authentication",
         "stage": "in_hand", "step": "on_hold"}
        """)
        XCTAssertEqual(held.authentication?.isHeld, true)

        let working = try order("""
        {"record_id": "r1", "number": "1041", "kind": "authentication",
         "stage": "in_hand", "step": "investigating"}
        """)
        XCTAssertEqual(working.authentication?.isHeld, false)

        // Ready and on hold is not a state the machine produces, and the
        // predicate must not accept it if one ever leaks through.
        let ready = try order("""
        {"record_id": "r1", "number": "1041", "kind": "authentication",
         "stage": "ready", "step": "on_hold"}
        """)
        XCTAssertEqual(ready.authentication?.isHeld, false)
    }

    /// A stage or step this build has never heard of must not throw away the
    /// order. The app degrades to "we do not know"; it does not fail to load.
    func testAnUnknownStageDecodesRatherThanThrowing() throws {
        let decoded = try order("""
        {"record_id": "r1", "number": "1041", "kind": "authentication",
         "stage": "quarantined", "step": "sandblasting"}
        """)
        XCTAssertEqual(decoded.authentication?.stage, .unknown)
        XCTAssertEqual(decoded.authentication?.step, .unknown)
        XCTAssertEqual(decoded.authentication?.isHeld, false)
    }

    func testAnOrderWithoutTheBlockStillDecodes() throws {
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "purchased",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD"
        }
        """
        let decoded = try apiDecoder().decode(Order.self, from: Data(json.utf8))
        // Nil is "the server said nothing", never "no".
        XCTAssertNil(decoded.authentication)
        XCTAssertEqual(decoded.status, .purchased)
    }

    /// Both parties are shown both figures, and Calibre's remainder is in
    /// neither payload. A `calibre_take` appearing here would be a leak, and
    /// the model has nowhere to put it — this asserts the shape stays that way.
    func testTheProposalCarriesBothSidesAndNotCalibresRemainder() throws {
        let json = """
        {
          "case_id": "c1", "status": "open", "order_number": 1041,
          "you_are": "buyer", "summary": "The dial has been refinished.",
          "awaiting_you": true,
          "proposal": {
            "id": "p1", "refund_amount": "1029.00", "payout_amount": "12500.00",
            "stripe_fee": "29.84", "stripe_fee_bearer": "calibre",
            "buyer_receives": "1029.00", "seller_receives": "12500.00",
            "currency": "USD",
            "service": {"amount": "0.00", "payer": null, "your_share": "0.00",
                        "payment_url": null, "paid_at": null,
                        "paid_directly_to": "WPB Watch Co",
                        "statement_descriptor_note": "", "warranty": ""},
            "you_accepted_at": null, "other_party_accepted": false,
            "declined_by": null, "declined_at": null, "can_respond": true,
            "created_at": "2026-08-06T00:00:00Z"
          }
        }
        """
        let payload = try apiDecoder().decode(AuthCaseProposalPayload.self, from: Data(json.utf8))
        let proposal = try XCTUnwrap(payload.proposal)
        XCTAssertEqual(proposal.buyerReceives, "1029.00")
        XCTAssertEqual(proposal.sellerReceives, "12500.00")
        XCTAssertEqual(payload.youAre, "buyer")
        XCTAssertTrue(payload.awaitingYou == true)

        let mirror = Mirror(reflecting: proposal)
        let names = mirror.children.compactMap(\.label)
        XCTAssertFalse(names.isEmpty)
        for forbidden in ["calibreTake", "calibreLosesMoney", "commissionAmount"] {
            XCTAssertFalse(names.contains(forbidden), "\(forbidden) has no business on a party's proposal")
        }
    }

    /// A settlement that failed still comes back 200 with the acceptance
    /// recorded. The client must be able to read that apart from a success,
    /// because the two say different things to the person who just agreed.
    func testAFailedSettlementDecodesAsAnAcceptanceThatStands() throws {
        let json = """
        {"case_id": "c1", "status": "open", "you_are": "buyer", "accepted": true,
         "proposal": null, "settlement": {"status": "failed"}}
        """
        let response = try apiDecoder().decode(AuthCaseResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.accepted)
        XCTAssertEqual(response.settlement?.status, "failed")
    }
}
