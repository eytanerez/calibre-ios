import XCTest
@testable import RewoundKit

/// When setup hands a seller to their dashboard (Eytan, 2026-10-06: "you do
/// the card and straight to dashboard"). The web's `sellerFinishedSetup` is
/// the authority; these pin the same answers.
final class SellerFinishedSetupTests: XCTestCase {

    private func readiness(
        status: String,
        onboardingComplete: Bool = false,
        payoutsEnabled: Bool = false,
        missingRequirements: String? = nil,
        canList: Bool = false
    ) throws -> SellerReadiness {
        let missing = missingRequirements.map { ",\n  \"missing_requirements\": \($0)" } ?? ""
        let json = """
        {
          "connect": {
            "account_id": "acct_test",
            "onboarding_complete": \(onboardingComplete),
            "details_submitted": \(onboardingComplete),
            "charges_enabled": \(payoutsEnabled),
            "payouts_enabled": \(payoutsEnabled),
            "last_checked_at": null,
            "requirements_currently_due": [],
            "requirements_eventually_due": [],
            "status": "\(status)",
            "status_basis": "live",
            "missing_items": [],
            "upcoming_items": [],
            "review_items": [],
            "disabled_reason": null
          },
          "can_list": \(canList)\(missing)
        }
        """
        return try apiDecoder().decode(SellerReadiness.self, from: Data(json.utf8))
    }

    private func card(present: Bool, valid: Bool = true) throws -> SellerCardState {
        let json = """
        {"present": \(present), "brand": "visa", "last4": "4242", "exp_month": 4, "exp_year": 2030,
         "funding": "credit", "valid": \(valid), "expiring_soon": false}
        """
        return try apiDecoder().decode(SellerCardState.self, from: Data(json.utf8))
    }

    func testMissingRequirementsDecodes() throws {
        let decoded = try readiness(status: "complete", missingRequirements: #"["seller_card"]"#)
        XCTAssertEqual(decoded.missingRequirements, ["seller_card"])
        XCTAssertNil(try readiness(status: "complete").missingRequirements)
    }

    func testCanListIsFinished() throws {
        XCTAssertTrue(SellerSetupSteps.finishedBySeller(
            try readiness(status: "complete", onboardingComplete: true, payoutsEnabled: true,
                          missingRequirements: "[]", canList: true),
            card: nil
        ))
    }

    /// Payouts through, card still owed: the card is the last step, so this
    /// seller stays in setup rather than being dropped on the dashboard.
    func testPayoutsWithoutTheCardIsNotFinished() throws {
        let payoutsOnly = try readiness(
            status: "complete", onboardingComplete: true, payoutsEnabled: true,
            missingRequirements: #"["seller_card"]"#
        )
        XCTAssertFalse(SellerSetupSteps.finishedBySeller(payoutsOnly, card: nil))
        // It used to be enough to open the shop.
        XCTAssertTrue(payoutsOnly.canAccessDashboard)
    }

    /// Card on file and Stripe still verifying: nothing left for the seller,
    /// so the dashboard opens and says the wait at its top.
    func testOnlyWaitingOnStripeIsFinished() throws {
        XCTAssertTrue(SellerSetupSteps.finishedBySeller(
            try readiness(status: "under_review", onboardingComplete: true,
                          missingRequirements: #"["payouts_enabled"]"#),
            card: nil
        ))
    }

    func testPayoutsStillTheSellersToDoIsNotFinished() throws {
        XCTAssertFalse(SellerSetupSteps.finishedBySeller(
            try readiness(status: "in_progress", missingRequirements: #"["connect_onboarding","payouts_enabled"]"#),
            card: try card(present: true)
        ))
    }

    func testRejectedIsNeverFinished() throws {
        XCTAssertFalse(SellerSetupSteps.finishedBySeller(
            try readiness(status: "rejected", onboardingComplete: true, missingRequirements: #"["payouts_enabled"]"#),
            card: try card(present: true)
        ))
    }

    /// A server that does not send `missing_requirements`: payouts from the
    /// status, the card from the card read — and an unread card is no card.
    func testWithoutMissingRequirementsTheCardDecides() throws {
        let underReview = try readiness(status: "under_review", onboardingComplete: true)
        XCTAssertTrue(SellerSetupSteps.finishedBySeller(underReview, card: try card(present: true)))
        XCTAssertFalse(SellerSetupSteps.finishedBySeller(underReview, card: try card(present: true, valid: false)))
        XCTAssertFalse(SellerSetupSteps.finishedBySeller(underReview, card: try card(present: false)))
        XCTAssertFalse(SellerSetupSteps.finishedBySeller(underReview, card: nil))
    }

    func testUnderReviewNeedsNothingFromTheSeller() throws {
        let step = try readiness(status: "under_review", onboardingComplete: true).connect.payoutStep
        XCTAssertFalse(step.isComplete)
        XCTAssertTrue(SellerSetupSteps.payoutsNeedNothingFromSeller(step))
        let inProgress = try readiness(status: "in_progress").connect.payoutStep
        XCTAssertFalse(SellerSetupSteps.payoutsNeedNothingFromSeller(inProgress))
    }
}

/// Setup's finish, and the card hold that stopped the flash behind the card
/// sheet. The web's `startFinish` / `SellerSetupFinish` are the authority.
final class SellerSetupFinishTests: XCTestCase {

    private func readiness(status: String, onboardingComplete: Bool = true, missing: String = #"["seller_card"]"#) throws -> SellerReadiness {
        let json = """
        {
          "connect": {
            "account_id": "acct_test", "onboarding_complete": \(onboardingComplete),
            "details_submitted": \(onboardingComplete), "charges_enabled": false, "payouts_enabled": false,
            "last_checked_at": null, "requirements_currently_due": [], "requirements_eventually_due": [],
            "status": "\(status)", "status_basis": "live", "missing_items": [], "upcoming_items": [],
            "review_items": [], "disabled_reason": null
          },
          "can_list": false,
          "missing_requirements": \(missing)
        }
        """
        return try apiDecoder().decode(SellerReadiness.self, from: Data(json.utf8))
    }

    private func card(present: Bool = true, valid: Bool = true, last4: String = "4242") throws -> SellerCardState {
        let json = """
        {"present": \(present), "brand": "visa", "last4": "\(last4)", "exp_month": 4, "exp_year": 2030,
         "funding": "credit", "valid": \(valid), "expiring_soon": false}
        """
        return try apiDecoder().decode(SellerCardState.self, from: Data(json.utf8))
    }

    // MARK: When it plays

    func testTheCardThatCompletesSetupPlaysTheFinish() throws {
        XCTAssertTrue(SellerSetupFinishRule.playsFinish(
            enabled: true, readiness: try readiness(status: "complete"), cardBefore: nil, saved: try card()
        ))
        // Under review counts: the seller has nothing left to give Stripe.
        XCTAssertTrue(SellerSetupFinishRule.playsFinish(
            enabled: true, readiness: try readiness(status: "under_review"), cardBefore: nil, saved: try card()
        ))
    }

    func testReplacingAWorkingCardDoesNotPlayIt() throws {
        XCTAssertFalse(SellerSetupFinishRule.playsFinish(
            enabled: true, readiness: try readiness(status: "complete", missing: "[]"),
            cardBefore: try card(last4: "1111"), saved: try card()
        ))
        // A lapsed card being replaced is the last step again, so it does.
        XCTAssertTrue(SellerSetupFinishRule.playsFinish(
            enabled: true, readiness: try readiness(status: "complete"),
            cardBefore: try card(valid: false, last4: "1111"), saved: try card()
        ))
    }

    func testTheDashboardSheetPayoutsStillOwedAndRejectionNeverPlayIt() throws {
        XCTAssertFalse(SellerSetupFinishRule.playsFinish(
            enabled: false, readiness: try readiness(status: "complete"), cardBefore: nil, saved: try card()
        ))
        XCTAssertFalse(SellerSetupFinishRule.playsFinish(
            enabled: true, readiness: try readiness(status: "in_progress", onboardingComplete: false),
            cardBefore: nil, saved: try card()
        ))
        XCTAssertFalse(SellerSetupFinishRule.playsFinish(
            enabled: true, readiness: try readiness(status: "rejected"), cardBefore: nil, saved: try card()
        ))
        XCTAssertFalse(SellerSetupFinishRule.playsFinish(
            enabled: true, readiness: try readiness(status: "complete"), cardBefore: nil, saved: try card(valid: false)
        ))
    }

    // MARK: Exactly once

    func testTheDashboardOpensOnceWhenBothHalvesAreIn_animationFirst() {
        var run = SellerSetupFinishRun()
        XCTAssertEqual(run.endAnimation(), .wait)
        XCTAssertEqual(run.readinessLanded(finished: true), .openDashboard)
        // A tap after the timer, or a second re-read, resolves nothing again.
        XCTAssertEqual(run.endAnimation(), .wait)
        XCTAssertEqual(run.readinessLanded(finished: true), .wait)
    }

    func testTheReReadLandingMidFlourishDoesNotOpenTheDashboard() {
        var run = SellerSetupFinishRun()
        XCTAssertEqual(run.readinessLanded(finished: true), .wait)
        XCTAssertFalse(run.resolved)
        XCTAssertEqual(run.endAnimation(), .openDashboard)
        XCTAssertEqual(run.endAnimation(), .wait)
    }

    func testAServerThatDisagreesPutsTheGateBack() {
        var run = SellerSetupFinishRun()
        XCTAssertEqual(run.readinessLanded(finished: false), .wait)
        XCTAssertEqual(run.endAnimation(), .returnToGate)
        // The first answer stands; a later one cannot reopen the run.
        XCTAssertEqual(run.readinessLanded(finished: true), .wait)
    }

    // MARK: No flash

    /// The flash: the saved card drawn on the gate while readiness still said
    /// the card was owed. Held, it is not drawn until readiness lands.
    func testASavedCardIsNotDrawnUntilReadinessLands() throws {
        var hold = SellerCardSaveHold(shown: nil)
        hold.cardSaved(try card())
        XCTAssertNil(hold.shown)
        XCTAssertEqual(hold.pending?.last4, "4242")
        // A plain read arriving mid-save does not jump the queue either.
        hold.show(try card(present: false))
        XCTAssertNil(hold.shown)
        hold.readinessLanded(cardRead: nil)
        XCTAssertEqual(hold.shown?.last4, "4242")
        XCTAssertNil(hold.pending)
    }

    func testAFresherReadWinsWhenReadinessLands() throws {
        var hold = SellerCardSaveHold(shown: nil)
        hold.cardSaved(try card(last4: "4242"))
        hold.readinessLanded(cardRead: try card(last4: "9999"))
        XCTAssertEqual(hold.shown?.last4, "9999")
        hold.show(try card(last4: "0000"))
        XCTAssertEqual(hold.shown?.last4, "0000")
    }
}

