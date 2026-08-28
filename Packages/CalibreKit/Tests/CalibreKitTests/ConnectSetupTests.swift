import Foundation
import XCTest
@testable import CalibreKit

/// The seller-setup status model: the six words the backend can send, the
/// seventh it might send one day, and the screen each one asks for.
///
/// The contract under test is `app/services/connect_status.py` plus
/// `_readiness_payload` in `app/api/views/stripe.py`.
final class ConnectSetupDecodingTests: XCTestCase {

    /// The readiness payload wrapped around one connect block, so a test can
    /// state only the fields it is about.
    private func readiness(
        status: String,
        basis: String = "live",
        accountId: String? = "acct_1U99HdAz6CESsQ2g",
        detailsSubmitted: Bool = false,
        missing: String = "[]",
        upcoming: String = "[]",
        review: String = "[]",
        disabledReason: String = "null",
        canList: Bool = false
    ) throws -> SellerReadiness {
        let account = accountId.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "connect": {
            "account_id": \(account),
            "onboarding_complete": false,
            "details_submitted": \(detailsSubmitted),
            "charges_enabled": false,
            "payouts_enabled": false,
            "last_checked_at": null,
            "requirements_currently_due": [],
            "requirements_eventually_due": [],
            "status": "\(status)",
            "status_basis": "\(basis)",
            "missing_items": \(missing),
            "upcoming_items": \(upcoming),
            "review_items": \(review),
            "disabled_reason": \(disabledReason)
          },
          "can_list": \(canList)
        }
        """
        return try apiDecoder().decode(SellerReadiness.self, from: Data(json.utf8))
    }

    // MARK: - The six words

    func testEveryStatusTheBackendCanSendDecodesToItsOwnCase() throws {
        let expected: [(String, ConnectSetupStatus)] = [
            ("not_started", .notStarted),
            ("in_progress", .inProgress),
            ("under_review", .underReview),
            ("needs_more", .needsMore),
            ("rejected", .rejected),
            ("complete", .complete),
        ]
        for (word, status) in expected {
            let decoded = try readiness(status: word).connect.status
            XCTAssertEqual(decoded, status, "\(word) decoded to \(decoded)")
            // Round-trips: the word we would send back is the word we read.
            XCTAssertEqual(decoded.wireValue, word)
        }
    }

    /// The list above is the backend's `STATUSES` tuple. If a seventh word is
    /// added there, this fails and someone has to decide what it looks like
    /// rather than discovering it in production.
    func testTheKnownStatusesAreExactlyTheSix() {
        let known: Set<String> = [
            ConnectSetupStatus.notStarted, .inProgress, .underReview,
            .needsMore, .rejected, .complete,
        ].map(\.wireValue).reduce(into: Set<String>()) { $0.insert($1) }
        XCTAssertEqual(
            known,
            ["not_started", "in_progress", "under_review", "needs_more", "rejected", "complete"]
        )
    }

    // MARK: - The seventh word

    func testAWordThisBuildHasNeverHeardOfDecodesAndKeepsItself() throws {
        let connect = try readiness(status: "awaiting_treasury_review").connect
        XCTAssertEqual(connect.status, .unknown("awaiting_treasury_review"))
        XCTAssertEqual(connect.status.wireValue, "awaiting_treasury_review")
    }

    func testAnUnknownStatusEncodesBackAsTheWordItArrivedAs() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(ConnectSetupStatus.unknown("awaiting_treasury_review"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"awaiting_treasury_review\"")
    }

    /// `status_basis` is a badge rather than a screen, so it takes the ordinary
    /// `decodeWireStatus` fallback the other wire enums use.
    func testAnUnknownBasisFallsBackRatherThanFailing() throws {
        XCTAssertEqual(try readiness(status: "complete", basis: "live").connect.statusBasis, .live)
        XCTAssertEqual(try readiness(status: "complete", basis: "cached").connect.statusBasis, .cached)
        XCTAssertEqual(try readiness(status: "complete", basis: "replica").connect.statusBasis, .unknown)
    }

    // MARK: - Items

    func testItemsArriveAlreadyHumanizedAndKeepTheirKeys() throws {
        let connect = try readiness(
            status: "needs_more",
            detailsSubmitted: true,
            missing: """
            [{"key": "external_account", "label": "Bank account for payouts"},
             {"key": "photo_id", "label": "Photo ID"}]
            """,
            upcoming: """
            [{"key": "individual.tax id", "label": "Individual tax id"}]
            """
        ).connect
        XCTAssertEqual(connect.missingItems.map(\.key), ["external_account", "photo_id"])
        XCTAssertEqual(connect.missingItems.map(\.label), ["Bank account for payouts", "Photo ID"])
        XCTAssertEqual(connect.upcomingItems.first?.label, "Individual tax id")
        XCTAssertTrue(connect.reviewItems.isEmpty)
    }

    func testTheRecordedFixtureStillDecodes() throws {
        let readiness = try apiDecoder().decode(
            Envelope<SellerReadiness>.self,
            from: fixtureData("seller-readiness")
        ).data
        XCTAssertEqual(readiness.connect.status, .notStarted)
        XCTAssertEqual(readiness.connect.statusBasis, .cached)
        XCTAssertFalse(readiness.canList)
    }

    // MARK: - The gate is still the gate

    /// `can_list` is untouched by any of this. The status says how setup is
    /// going; it never decides whether a seller may list.
    func testStatusDoesNotSpeakForCanList() throws {
        XCTAssertFalse(try readiness(status: "complete", canList: false).canList)
        XCTAssertTrue(try readiness(status: "under_review", canList: true).canList)
    }
}

/// One status in, one screen out.
final class PayoutSetupStepTests: XCTestCase {

    private func connect(
        _ status: ConnectSetupStatus,
        accountId: String? = "acct_1U99HdAz6CESsQ2g",
        basis: ConnectStatusBasis = .live,
        missing: [ConnectRequirementItem] = [],
        upcoming: [ConnectRequirementItem] = [],
        review: [ConnectRequirementItem] = [],
        disabledReason: String? = nil
    ) -> ConnectStatus {
        ConnectStatus(
            accountId: accountId,
            onboardingComplete: status == .complete,
            detailsSubmitted: false,
            chargesEnabled: false,
            payoutsEnabled: false,
            status: status,
            statusBasis: basis,
            missingItems: missing,
            upcomingItems: upcoming,
            reviewItems: review,
            disabledReason: disabledReason
        )
    }

    private let bank = ConnectRequirementItem(key: "external_account", label: "Bank account for payouts")
    private let photo = ConnectRequirementItem(key: "photo_id", label: "Photo ID")

    // MARK: - Every state maps to exactly one action

    func testEachStatusOffersTheOneActionItShould() {
        let cases: [(ConnectSetupStatus, PayoutSetupStep.Action)] = [
            (.notStarted, .collectSSN(title: "Set up payouts")),
            (.inProgress, .openForm(title: "Continue setting up payouts")),
            (.underReview, .refresh(title: "Check again")),
            (.needsMore, .openForm(title: "Finish with Stripe")),
            (.rejected, .contactSupport(title: "Talk to us about this")),
            (.complete, .none),
        ]
        for (status, action) in cases {
            let accountId: String? = status == .notStarted ? nil : "acct_1U99HdAz6CESsQ2g"
            let step = connect(status, accountId: accountId).payoutStep
            XCTAssertEqual(step.action, action, "\(status.wireValue) offered \(step.action)")
            XCTAssertEqual(step.status, status)
        }
    }

    /// The rule the whole rejected branch exists for: no form, no retry, no
    /// second SSN. A rejected account cannot be re-entered into.
    func testRejectedNeverReachesTheFormAndNeverRetries() {
        let step = connect(.rejected, disabledReason: "rejected.fraud").payoutStep
        XCTAssertEqual(step.action, .contactSupport(title: "Talk to us about this"))
        XCTAssertTrue(step.items.isEmpty)
        XCTAssertNil(step.itemsWithheldNote)
        XCTAssertFalse(step.isComplete)
        XCTAssertEqual(step.tone, .attention)
        XCTAssertEqual(
            step.body,
            "Stripe wasn't able to approve payouts for this account. This usually can't be fixed by re-entering details."
        )
        XCTAssertNotNil(step.footnote)
    }

    /// Stripe's machine reason is for support. `"rejected.fraud"` is an
    /// accusation in a string, and it must not appear in any field a seller
    /// reads — checked across every one of them, so adding a seventh field
    /// and piping the reason into it fails here rather than on someone's
    /// screen.
    func testTheDisabledReasonNeverReachesAnythingTheSellerReads() {
        for status in [ConnectSetupStatus.rejected, .needsMore, .inProgress, .underReview, .complete] {
            let step = connect(status, missing: [bank], disabledReason: "rejected.fraud").payoutStep
            let shown = [step.title, step.body, step.itemsTitle, step.itemsWithheldNote,
                         step.upcomingNote, step.footnote].compactMap { $0 }
                + step.items.flatMap { [$0.key, $0.label] }
            for sentence in shown {
                XCTAssertFalse(
                    sentence.lowercased().contains("rejected."),
                    "\(status.wireValue) leaked Stripe's reason into: \(sentence)"
                )
                XCTAssertFalse(sentence.lowercased().contains("fraud"))
            }
        }
    }

    /// Mutation check: swap the rejected branch for the needs_more one and this
    /// fails on the action, the tone and the copy independently.
    func testRejectedIsNotJustNeedsMoreWithDifferentWords() {
        let rejected = connect(.rejected).payoutStep
        let needsMore = connect(.needsMore, missing: [bank]).payoutStep
        XCTAssertNotEqual(rejected.action, needsMore.action)
        XCTAssertNotEqual(rejected.body, needsMore.body)
        if case .openForm = rejected.action {
            XCTFail("A rejected account must never be handed the form")
        }
        if case .contactSupport = needsMore.action {
            XCTFail("needs_more is fixable in the form, not by support")
        }
    }

    // MARK: - Under review is calm and does not push the form

    func testUnderReviewAsksNothingOfTheSeller() {
        let step = connect(.underReview, review: [photo]).payoutStep
        XCTAssertEqual(step.action, .refresh(title: "Check again"))
        XCTAssertEqual(step.tone, .calm)
        XCTAssertEqual(step.items, [photo])
        XCTAssertEqual(step.itemsTitle, "What they're looking at:")
        XCTAssertTrue(step.body.contains("Nothing needed from you"))
    }

    // MARK: - The cached read

    /// A cached read sends empty item lists on purpose. Rendering that as an
    /// empty checklist would say "nothing left to do", which is the opposite
    /// of what the payload means.
    func testACachedReadWithNoItemsSaysSoInsteadOfShowingAnEmptyChecklist() {
        let step = connect(.inProgress, basis: .cached).payoutStep
        XCTAssertTrue(step.items.isEmpty)
        XCTAssertNil(step.itemsTitle)
        XCTAssertEqual(
            step.itemsWithheldNote,
            "A few details are still needed — open the form to see them."
        )
    }

    func testCachedNeedsMoreAlsoGetsTheStandInSentence() {
        let step = connect(.needsMore, basis: .cached).payoutStep
        XCTAssertNotNil(step.itemsWithheldNote)
        XCTAssertTrue(step.items.isEmpty)
    }

    /// The sentence is keyed on the empty list, not on the basis word — so a
    /// live read that names nothing gets it too, and a basis this build has
    /// never seen cannot switch it off.
    func testTheStandInSentenceFollowsTheEmptyListAndNotTheBasisWord() {
        for basis in [ConnectStatusBasis.live, .cached, .unknown] {
            XCTAssertNotNil(
                connect(.inProgress, basis: basis).payoutStep.itemsWithheldNote,
                "basis \(basis.rawValue) lost the stand-in sentence"
            )
        }
    }

    /// A review with nothing listed is a review, not a hidden chore. Telling
    /// that seller to open the form would invent work Stripe has not asked for.
    func testUnderReviewWithNothingListedIsNotToldToOpenTheForm() {
        let step = connect(.underReview, basis: .cached).payoutStep
        XCTAssertNil(step.itemsWithheldNote)
        XCTAssertTrue(step.items.isEmpty)
        XCTAssertEqual(step.action, .refresh(title: "Check again"))
    }

    /// The state every new seller is in: no account, so no live read is even
    /// possible and `cached` is the ordinary answer rather than an outage.
    /// Nothing here may read as a chore list, withheld or otherwise.
    func testNotStartedIsCachedByNatureAndSaysNothingAboutHiddenDetails() {
        let step = connect(.notStarted, accountId: nil, basis: .cached).payoutStep
        XCTAssertNil(step.itemsWithheldNote)
        XCTAssertNil(step.itemsTitle)
        XCTAssertTrue(step.items.isEmpty)
        XCTAssertEqual(step.action, .collectSSN(title: "Set up payouts"))
    }

    /// A live read that genuinely has items shows them, and never the stand-in.
    func testALiveReadWithItemsShowsThemAndNotTheStandIn() {
        let step = connect(.needsMore, basis: .live, missing: [bank, photo]).payoutStep
        XCTAssertEqual(step.items, [bank, photo])
        XCTAssertNil(step.itemsWithheldNote)
    }

    // MARK: - No count beside a list

    func testTheOneMoreThingSentenceOnlyAppearsWhenThereIsOneMoreThing() {
        let single = connect(.needsMore, missing: [bank]).payoutStep
        XCTAssertTrue(single.body.hasSuffix("Stripe needs one more thing:"))

        // Two is the common case off a real Stripe account, and is exactly
        // where the literal sentence would have been wrong on screen.
        let several = connect(.needsMore, missing: [bank, photo]).payoutStep
        XCTAssertFalse(several.body.contains("one more thing"))
        XCTAssertTrue(several.body.hasSuffix("Stripe needs a few more details:"))
    }

    /// With the names withheld there is no list to introduce, so the sentence
    /// drops its colon along with its number.
    func testWithNoNamesToListTheLeadInLosesItsColon() {
        let withheld = connect(.needsMore, basis: .cached).payoutStep
        XCTAssertTrue(withheld.body.hasSuffix("Stripe needs a little more."))
        XCTAssertFalse(withheld.body.contains(":"))
        XCTAssertFalse(withheld.body.contains("one more thing"))
    }

    // MARK: - The forewarning line

    func testUpcomingItemsBecomeOneQuietLineAndNotASecondChecklist() {
        let step = connect(.inProgress, missing: [bank], upcoming: [photo]).payoutStep
        XCTAssertEqual(step.upcomingNote, "Stripe may ask for this later: Photo ID")
        // The forewarning is a sentence, not a row in the list of things to do.
        XCTAssertEqual(step.items, [bank])
    }

    func testNoUpcomingItemsMeansNoLine() {
        XCTAssertNil(connect(.inProgress, missing: [bank]).payoutStep.upcomingNote)
    }

    /// The reviewing state is not a to-do list, so it does not forewarn either.
    func testUnderReviewCarriesNoForewarning() {
        XCTAssertNil(connect(.underReview, upcoming: [photo], review: [photo]).payoutStep.upcomingNote)
    }

    // MARK: - Complete

    func testCompleteIsTheOnlyStateThatMarksTheStepDone() {
        for status in [ConnectSetupStatus.notStarted, .inProgress, .underReview, .needsMore, .rejected] {
            XCTAssertFalse(connect(status).payoutStep.isComplete, "\(status.wireValue) claimed done")
        }
        let done = connect(.complete).payoutStep
        XCTAssertTrue(done.isComplete)
        XCTAssertEqual(done.action, .none)
        XCTAssertEqual(done.tone, .done)
    }

    // MARK: - The seventh word

    /// A status this build cannot read must not strand a seller who has an
    /// account, and must not offer an SSN to one who already gave it.
    func testAnUnknownStatusWithAnAccountStillOpensTheForm() {
        let step = connect(.unknown("awaiting_treasury_review")).payoutStep
        XCTAssertEqual(step.action, .openForm(title: "Open payout setup"))
        XCTAssertFalse(step.isComplete)
        XCTAssertEqual(step.status, .unknown("awaiting_treasury_review"))
    }

    /// With no account there is nothing an unknown word can mean but the first
    /// screen — and that screen is the one that collects the SSN.
    func testAnUnknownStatusWithNoAccountIsTheFirstScreen() {
        let step = connect(.unknown("awaiting_treasury_review"), accountId: nil).payoutStep
        XCTAssertEqual(step.action, .collectSSN(title: "Set up payouts"))
        // No headline: the step is named "Payouts with Stripe" on the card
        // already, and saying it twice is not saying more.
        XCTAssertNil(step.title)
    }

    /// A blank account id is the same absence as a missing one — Stripe's own
    /// rule 1 keys on "no account id", not on the JSON null.
    func testABlankAccountIdCountsAsNoAccount() {
        let step = connect(.unknown("mystery"), accountId: "   ").payoutStep
        XCTAssertEqual(step.action, .collectSSN(title: "Set up payouts"))
    }

    // MARK: - The support hand-off

    func testTheRejectedSellerHasTheirFirstMessageWrittenForThem() {
        XCTAssertEqual(
            payoutRejectedSupportMessage,
            "My payout account couldn't be approved and I'd like help understanding why."
        )
    }
}
