import XCTest
@testable import RewoundKit

/// The half of the change that lives in the app.
///
/// Rewound's letters used to carry the explanation for every decision it made —
/// why a listing did not go live, what the bench found, why a return was
/// refused — and the app carried none of it. Eytan reversed that: the letter
/// states that something happened and says to open Rewound, and what it says
/// when you open it is what these tests read.
///
/// What is worth pinning is not the wording. It is that **the explanation is
/// here at all**, because a letter that says "open the order" over a screen
/// with nothing on it is strictly worse than the letter that used to say it.
final class DetailLivesInTheAppTests: XCTestCase {

    // MARK: - Our review, on the listing

    private func listing(status: String, events: String) throws -> Listing {
        let json = """
        {
          "id": "l1", "listing_number": 1, "seller_id": "s1", "title": "Rolex Submariner",
          "price": "10000.00", "currency": "USD", "status": "\(status)",
          "review_events": \(events), "images": []
        }
        """
        return try apiDecoder().decode(Listing.self, from: Data(json.utf8))
    }

    private func event(_ toStatus: String, _ notes: String?, at when: String = "2026-09-10T00:00:00+00:00") -> String {
        let note = notes.map { "\"\($0)\"" } ?? "null"
        return """
        {"from_status": "pending_review", "to_status": "\(toStatus)", "notes": \(note), "created_at": "\(when)"}
        """
    }

    func testTheCommonOutcomeIsExplained() throws {
        // `needs-more-info` lands the listing in drafts. This app, Android and
        // the site all used to check `to_status == "rejected"` and nothing
        // else, so the outcome a reviewer reaches a hundred times a week was
        // readable only in an inbox.
        let row = try listing(status: "draft", events: "[\(event("draft", "We still need the caseback."))]")

        XCTAssertEqual(row.review?.outcome, .needsMoreInfo)
        XCTAssertEqual(row.review?.notes, "We still need the caseback.")
    }

    func testATakeDownIsExplained() throws {
        let row = try listing(
            status: "archived",
            events: "[\(event("archived", "The papers are a different reference."))]"
        )

        XCTAssertEqual(row.review?.outcome, .takenDown)
        XCTAssertEqual(row.review?.notes, "The papers are a different reference.")
    }

    func testARejectionDoesNotOfferAResubmissionItCannotPromise() throws {
        let row = try listing(status: "rejected", events: "[\(event("rejected", "Not a watch Rewound carries."))]")

        XCTAssertEqual(row.review?.outcome, .rejected)
        XCTAssertNotNil(row.review?.next)
        XCTAssertFalse(row.review?.next?.lowercased().contains("resubmit") ?? true)
    }

    func testAReviewGoesQuietOnceTheListingHasMovedOn() throws {
        // Sent back for photos, resubmitted, approved, and unlisted by the
        // seller months later. Matching the status against any event that ever
        // set it would show them the old photo note as today's answer.
        let stale = try listing(
            status: "draft",
            events: """
            [\(event("draft", nil, at: "2026-09-12T00:00:00+00:00")),
             \(event("active", nil, at: "2026-09-11T00:00:00+00:00")),
             \(event("draft", "We still need the caseback.", at: "2026-09-10T00:00:00+00:00"))]
            """
        )

        XCTAssertNil(stale.review)
    }

    func testAListingNobodyReviewedSaysNothing() throws {
        XCTAssertNil(try listing(status: "draft", events: "[]").review)
    }

    // MARK: - What the bench found, on the order

    private func order(authResult: String, returnSummary: String = "null") throws -> Order {
        let json = """
        {
          "id": "o1", "order_number": 1041, "buyer_id": "b1", "listing_id": "l1",
          "status": "auth_fail", "currency": "USD",
          "subtotal": "10000.00", "fees_total": "0.00", "grand_total": "10000.00",
          "auth_result": \(authResult), "return": \(returnSummary),
          "created_at": "2026-09-10T00:00:00+00:00", "updated_at": "2026-09-10T00:00:00+00:00"
        }
        """
        return try apiDecoder().decode(Order.self, from: Data(json.utf8))
    }

    private func failedResult(_ summary: String?) -> String {
        let value = summary.map { "\"\($0)\"" } ?? "null"
        return """
        {"id": "ar1", "intake_id": "in1", "outcome": "counterfeit", "buyer_summary": \(value),
         "aftermarket_flag": false, "created_at": "2026-09-10T00:00:00+00:00",
         "updated_at": "2026-09-10T00:00:00+00:00"}
        """
    }

    func testTheFindingReachesTheOrderScreen() throws {
        let row = try order(authResult: failedResult("The movement is not the calibre the listing described."))

        XCTAssertEqual(row.authenticationFinding, "The movement is not the rewound the listing described.")

        let step = row.nextStep()
        XCTAssertEqual(step.headline, "This watch did not pass")
        XCTAssertEqual(step.next, "The movement is not the rewound the listing described.")
        // And the screen no longer answers the question by promising an email.
        XCTAssertFalse(step.next?.contains("will write to you") ?? true)
    }

    func testAFailureWithNothingWrittenPointsAtAPersonRatherThanInventingOne() throws {
        // Every failure recorded before this build has no such sentence, and
        // deriving one from the verdict would be a claim Rewound never made.
        let step = try order(authResult: failedResult(nil)).nextStep()

        XCTAssertEqual(step.next, "Your Rewound contact has the detail of what we found and will go through it with you.")
    }

    func testAPassingOrderHasNoFinding() throws {
        let passing = """
        {"id": "ar1", "intake_id": "in1", "outcome": "pass", "buyer_summary": null,
         "aftermarket_flag": false, "created_at": "2026-09-10T00:00:00+00:00",
         "updated_at": "2026-09-10T00:00:00+00:00"}
        """
        XCTAssertNil(try order(authResult: passing).authenticationFinding)
    }

    // MARK: - Why a return was refused

    func testARefusedReturnExplainsItselfOnTheOrder() throws {
        // `failure_reasons` was stored by the admin who refused the return and
        // serialised to nobody, so the letter was the only copy in existence.
        let refused = """
        {"state": "rejected_failed_verification",
         "failure_reasons": "The watch returned is not the watch that was sent.",
         "ship_deadline_at": null}
        """
        let step = try order(authResult: "null", returnSummary: refused).nextStep()

        XCTAssertEqual(step.headline, "We could not accept this return")
        XCTAssertEqual(step.next, "The watch returned is not the watch that was sent.")
    }

    func testARefusalWithNothingRecordedPointsAtAPerson() throws {
        let refused = """
        {"state": "rejected_failed_verification", "failure_reasons": null, "ship_deadline_at": null}
        """
        let step = try order(authResult: "null", returnSummary: refused).nextStep()

        XCTAssertEqual(step.next, "Someone from Rewound will contact you directly about what happens next.")
    }
}
