import Foundation
import XCTest
@testable import CalibreKit

/// The two seller-side readings the shop's Orders & payouts tab prints, and the
/// setup rule the gate reads.
///
/// Every case here is one where saying the obvious thing would have said
/// something untrue to a seller: a payout that failed reading as one still
/// scheduled, a closed sale reading as one still to be released, a finished
/// step asking to be finished again.
final class SellerSaleStateTests: XCTestCase {

    // MARK: - Building the payloads

    /// An order payload carrying only what a case needs, decoded through the
    /// client's own decoder — so a test can never pass on a shape the app
    /// would refuse.
    private func order(
        status: String = "to_auth",
        payoutStatus: String = "null",
        sellerActionState: String = "null",
        payout: String = "null"
    ) throws -> Order {
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "\(status)",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD",
          "created_at": "2026-08-01T12:00:00Z",
          "payout_status": \(payoutStatus),
          "seller_action_state": \(sellerActionState),
          "payout": \(payout)
        }
        """
        return try apiDecoder().decode(Order.self, from: Data(json.utf8))
    }

    private func card(
        present: Bool = true,
        valid: String = "true",
        expiringSoon: String = "false"
    ) throws -> SellerCardState {
        let json = """
        {"present": \(present), "brand": "visa", "last4": "4242",
         "exp_month": 4, "exp_year": 2030,
         "valid": \(valid), "expiring_soon": \(expiringSoon)}
        """
        return try apiDecoder().decode(SellerCardState.self, from: Data(json.utf8))
    }

    // MARK: - Payout state

    func testEveryHoldingWordFoldsToOnHold() {
        XCTAssertEqual(SellerPayoutState(wireValue: "pending_connect"), .held)
        XCTAssertEqual(SellerPayoutState(wireValue: "blocked_dispute"), .held)
    }

    func testBothFailureWordsFoldToFailed() {
        XCTAssertEqual(SellerPayoutState(wireValue: "failed"), .failed)
        XCTAssertEqual(SellerPayoutState(wireValue: "failed_at_bank"), .failed)
    }

    func testEveryClosingWordFoldsToClosed() {
        for word in ["cancelled", "refunded", "reversed", "partially_reversed"] {
            XCTAssertEqual(SellerPayoutState(wireValue: word), .closed, "\(word) should close the row")
        }
    }

    /// The state this enum exists to keep separate. A word this build has not
    /// been taught must not be folded into `scheduled`, which is a promise that
    /// money is coming.
    func testAnUnknownWordIsNotAPromise() {
        let state = SellerPayoutState(wireValue: "clawed_back_by_legal")
        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(state.label, "Status unclear")
        XCTAssertFalse(state.isStillComing)
        XCTAssertNotEqual(state, .scheduled)
    }

    /// A missing `payout_status` is the same "we cannot speak for this" case as
    /// an unrecognised one — the old reading printed "Scheduled" for it.
    func testAMissingStatusIsNotScheduled() throws {
        XCTAssertEqual(try order().sellerPayoutState, .unknown)
    }

    func testClosedAndUnknownAreNotStillComing() {
        XCTAssertFalse(SellerPayoutState.closed.isStillComing)
        XCTAssertFalse(SellerPayoutState.unknown.isStillComing)
        for state in [SellerPayoutState.scheduled, .held, .released, .failed] {
            XCTAssertTrue(state.isStillComing, "\(state.rawValue) is still owed to the seller")
        }
    }

    // MARK: - The status line

    /// The server's own sentence wins wherever it sent one.
    func testTheServersOwnSentenceIsPrinted() throws {
        let sale = try order(
            payoutStatus: "\"released\"",
            payout: """
            {"status_label": "Released to your bank on 2 September"}
            """
        )
        XCTAssertEqual(sale.sellerPayoutStatusLine, "Released to your bank on 2 September")
    }

    /// The defect: a failed payout with no sentence on the payload used to fall
    /// through to "Scheduled" and tell a seller money was on its way.
    func testAFailedPayoutWithNoSentenceSaysItFailed() throws {
        let sale = try order(payoutStatus: "\"failed_at_bank\"")
        XCTAssertEqual(sale.sellerPayoutState, .failed)
        XCTAssertEqual(sale.sellerPayoutStatusLine, "Did not go through")
    }

    // MARK: - Whose move it is

    func testAnUnshippedSaleIsWaitingOnTheSeller() throws {
        let sale = try order(status: "purchased", sellerActionState: "\"sold_awaiting_label_creation\"")
        XCTAssertEqual(sale.sellerNextStep.who, "Waiting on you")
        XCTAssertTrue(sale.sellerNextStep.needsShippingDetails)
    }

    /// An unpaid wire is the buyer's move, and the seller owes nothing — the
    /// row must not put a form in front of them for it.
    func testAnUnpaidWireIsTheBuyersMove() throws {
        let sale = try order(status: "awaiting_wire")
        XCTAssertEqual(sale.sellerNextStep.who, "Waiting on the buyer")
        XCTAssertFalse(sale.sellerNextStep.needsShippingDetails)
    }

    func testAFinishedSaleAsksNothingOfTheSeller() throws {
        XCTAssertEqual(try order(status: "delivered").sellerNextStep.who, "Nothing needed from you")
        XCTAssertEqual(try order(status: "refunded").sellerNextStep.who, "Nothing needed from you")
        XCTAssertEqual(try order(status: "cancelled").sellerNextStep.who, "Nothing needed from you")
    }

    /// The shipping form is the seller's only action on this list, so it is the
    /// server's `seller_action_state` and nothing else that offers it.
    func testOnlyTheServerPutsTheShippingFormOnARow() throws {
        for status in ["purchased", "to_auth", "auth_pass", "to_buyer", "delivered"] {
            XCTAssertFalse(
                try order(status: status).sellerNextStep.needsShippingDetails,
                "\(status) must not offer the shipping form on its own"
            )
        }
    }

    /// A status word this build has not been taught still gets a line, and the
    /// line claims nothing about where the watch is.
    func testAnUnknownStatusStillNamesWhoHasIt() throws {
        let sale = try order(status: "escheated")
        XCTAssertEqual(sale.sellerNextStep.who, "Waiting on Calibre")
        XCTAssertFalse(sale.sellerNextStep.what.isEmpty)
    }

    // MARK: - The card step that is not a step

    /// The case the rule exists for: a card given in an earlier pass, payouts
    /// still outstanding.
    func testAFinishedCardBesideOutstandingPayoutsIsNotAStep() throws {
        XCTAssertTrue(
            SellerSetupSteps.cardStepIsRedundant(card: try card(), payoutsComplete: false)
        )
    }

    /// The carve-out. A card about to lapse is a live problem of its own, and
    /// this rule must never be what hides it.
    func testAnExpiringCardIsAlwaysShown() throws {
        XCTAssertFalse(
            SellerSetupSteps.cardStepIsRedundant(
                card: try card(expiringSoon: "true"),
                payoutsComplete: false
            )
        )
    }

    func testALapsedCardIsAlwaysShown() throws {
        XCTAssertFalse(
            SellerSetupSteps.cardStepIsRedundant(card: try card(valid: "false"), payoutsComplete: false)
        )
    }

    func testNoCardIsAlwaysAStep() throws {
        XCTAssertFalse(
            SellerSetupSteps.cardStepIsRedundant(card: try card(present: false), payoutsComplete: false)
        )
        XCTAssertFalse(SellerSetupSteps.cardStepIsRedundant(card: nil, payoutsComplete: false))
    }

    /// With payouts finished the card is the only thing left to do or the last
    /// thing done — either way it stays on screen.
    func testTheCardStaysOncePayoutsAreFinished() throws {
        XCTAssertFalse(
            SellerSetupSteps.cardStepIsRedundant(card: try card(), payoutsComplete: true)
        )
    }
}
