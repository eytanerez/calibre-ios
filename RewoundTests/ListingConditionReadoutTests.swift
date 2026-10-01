import XCTest

@testable import Rewound
@testable import RewoundKit

/// The condition card's logic (contracts, 2026-09-30, Parts A to D): the parts
/// against the overall grade, the history answers as words, the card facts,
/// the quick filters and the sell form's answers. Everything a screen draws
/// from is worked out in `ListingConditionReadout.swift`, so it is held here.
final class ListingConditionReadoutTests: XCTestCase {

    // MARK: - Building listings

    private func listing(
        condition: [String: String]? = nil,
        notes: [String: String]? = nil,
        history: [String: Any]? = nil,
        box: Bool? = nil,
        papers: Bool? = nil,
        booklets: Bool? = nil,
        boxPapers: Bool? = nil
    ) throws -> Listing {
        var json: [String: Any] = [
            "id": "readout-1", "listing_number": 9102, "seller_id": "seller-1",
            "title": "Rolex Submariner Date", "brand": "Rolex", "model": "Submariner Date",
            "price": "14200.00", "currency": "USD", "status": "active", "images": [],
        ]
        if let condition { json["condition"] = condition }
        if let notes { json["condition_notes"] = notes }
        if let history { json["history"] = history }
        if let box { json["box_included"] = box }
        if let papers { json["papers_included"] = papers }
        if let booklets { json["booklets_included"] = booklets }
        if let boxPapers { json["box_papers"] = boxPapers }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try APIClient.makeDecoder(origin: URL(string: "https://api.test")).decode(Listing.self, from: data)
    }

    private static let allVeryGood: [String: String] = [
        "overall": "Very Good", "case": "Very Good", "dial": "Very Good", "bezel": "Very Good",
        "crystal": "Very Good", "bracelet": "Very Good", "clasp": "Very Good", "caseback": "Very Good",
    ]

    // MARK: - Parts against the overall grade

    func testEveryPartMatchingIsOneGroupInTheContractsOrder() throws {
        let breakdown = ConditionBreakdown(listing: try listing(condition: Self.allVeryGood))
        guard case .allMatch(let parts) = breakdown.shape else {
            return XCTFail("expected all parts to match, got \(breakdown.shape)")
        }
        XCTAssertEqual(parts.map(\.label), ["Case", "Dial", "Bezel", "Crystal", "Bracelet", "Clasp", "Caseback"])
        XCTAssertEqual(breakdown.overall, "Very Good")
        XCTAssertNil(breakdown.cardChip)
        XCTAssertNil(breakdown.matchingLine)
        XCTAssertTrue(breakdown.differing.isEmpty)
    }

    /// Parts with no grade are left out of both groups.
    func testUngradedPartsAreInNoGroup() throws {
        let condition = ["overall": "Like New", "case": "Like New", "dial": "Like New", "bezel": ""]
        let breakdown = ConditionBreakdown(listing: try listing(condition: condition))
        guard case .allMatch(let parts) = breakdown.shape else {
            return XCTFail("expected all parts to match, got \(breakdown.shape)")
        }
        XCTAssertEqual(parts.map(\.key), ["case", "dial"])
    }

    func testOneDifferingPartIsWorthKnowingAndTheRestShareALine() throws {
        var condition = Self.allVeryGood
        condition["bracelet"] = "Good"
        let notes = ["bracelet": "Light stretch", "case": "Hairlines on the lugs", "overall": "Worn gently"]
        let breakdown = ConditionBreakdown(listing: try listing(condition: condition, notes: notes))

        guard case .differ(let differing, let matching) = breakdown.shape else {
            return XCTFail("expected a differing part, got \(breakdown.shape)")
        }
        XCTAssertEqual(differing.map(\.label), ["Bracelet"])
        XCTAssertEqual(differing.first?.note, "Light stretch")
        XCTAssertEqual(matching.count, 6)
        XCTAssertEqual(breakdown.direction(of: differing[0]), .worse)
        XCTAssertEqual(breakdown.matchingLine, "Case, dial, bezel, crystal, clasp, caseback: Very Good")
        // Notes on matching parts print under the line; the differing part's
        // note is inside its own card, and the overall note is the overall's.
        XCTAssertEqual(breakdown.lineNotes.map(\.label), ["Case"])
        XCTAssertEqual(ConditionBreakdown.noteLead(breakdown.lineNotes[0]), "Seller's note, Case:")
        XCTAssertEqual(breakdown.overallNote, "Worn gently")
        XCTAssertEqual(breakdown.cardChip, "Bracelet: Good")
        XCTAssertEqual(ConditionBreakdown.calloutTitle(differing[0]), "Bracelet graded Good")
    }

    func testOnlyWorsePartsReachTheCardAndBetterIsNeutral() throws {
        var condition = Self.allVeryGood
        condition["bracelet"] = "Good"
        condition["dial"] = "Like New"
        let breakdown = ConditionBreakdown(listing: try listing(condition: condition))
        XCTAssertEqual(breakdown.differing.map(\.label), ["Dial", "Bracelet"])
        XCTAssertEqual(breakdown.direction(of: breakdown.differing[0]), .better)
        XCTAssertEqual(breakdown.direction(of: breakdown.differing[1]), .worse)
        // The better dial is on the listing screen, never in a card's warning.
        XCTAssertEqual(breakdown.worseParts.map(\.label), ["Bracelet"])
        XCTAssertEqual(breakdown.cardChip, "Bracelet: Good")

        condition["clasp"] = "Worn"
        let two = ConditionBreakdown(listing: try listing(condition: condition))
        XCTAssertEqual(two.cardChip, "2 parts graded lower")

        var betterOnly = Self.allVeryGood
        betterOnly["crystal"] = "New"
        XCTAssertNil(ConditionBreakdown(listing: try listing(condition: betterOnly)).cardChip)
    }

    /// A word off the five-grade scale still differs, but nothing is said
    /// about which way.
    func testAnOffScaleGradeDiffersWithoutADirection() throws {
        let condition = ["overall": "Very Good", "case": "Excellent"]
        let breakdown = ConditionBreakdown(listing: try listing(condition: condition))
        XCTAssertEqual(breakdown.differing.map(\.grade), ["Excellent"])
        XCTAssertEqual(breakdown.direction(of: breakdown.differing[0]), .unranked)
    }

    /// Old listings with no overall grade: the parts as a plain list, and
    /// never an invented overall.
    func testNoOverallGradeIsAPlainListAndNeverAnInventedOverall() throws {
        let condition = ["case": "Good", "dial": "Very Good"]
        let breakdown = ConditionBreakdown(listing: try listing(condition: condition, notes: ["dial": "A speck at six"]))
        XCTAssertNil(breakdown.overall)
        guard case .noOverall(let parts) = breakdown.shape else {
            return XCTFail("expected the plain list, got \(breakdown.shape)")
        }
        XCTAssertEqual(parts.map(\.label), ["Case", "Dial"])
        XCTAssertEqual(parts[1].note, "A speck at six")
        XCTAssertNil(breakdown.cardChip)
    }

    func testNothingGradedIsNoParts() throws {
        XCTAssertEqual(ConditionBreakdown(listing: try listing()).shape, .noParts)
        XCTAssertEqual(ConditionBreakdown(listing: try listing(condition: ["overall": "Good"])).shape, .noParts)
    }

    // MARK: - History words

    func testTheListingPageRowWords() {
        XCTAssertEqual(ListingHistoryWords.polishRow("unpolished"), "Never polished")
        XCTAssertEqual(ListingHistoryWords.polishRow("polished"), "Polished")
        XCTAssertEqual(ListingHistoryWords.polishRow("unknown"), "Not known")
        XCTAssertNil(ListingHistoryWords.polishRow(nil))

        XCTAssertEqual(ListingHistoryWords.originalityRow("all_original", note: nil), "All original parts")
        XCTAssertEqual(ListingHistoryWords.originalityRow("replaced", note: nil), "Some parts replaced")
        XCTAssertEqual(ListingHistoryWords.originalityRow("replaced", note: " Crown "), "Some parts replaced: Crown")
        XCTAssertEqual(ListingHistoryWords.originalityRow("unknown", note: nil), "Not known")
        XCTAssertNil(ListingHistoryWords.originalityRow(nil, note: "ignored"))

        XCTAssertEqual(ListingHistoryWords.serviceRow("serviced", year: 2021), "Serviced in 2021")
        XCTAssertEqual(ListingHistoryWords.serviceRow("serviced", year: nil), "Serviced, year not known")
        XCTAssertEqual(ListingHistoryWords.serviceRow("never", year: nil), "Never serviced")
        XCTAssertEqual(ListingHistoryWords.serviceRow("unknown", year: nil), "Not known")
        XCTAssertNil(ListingHistoryWords.serviceRow(nil, year: 2021))
    }

    func testTheHistoryTableHidesWhatNobodyAnswered() throws {
        let answered = try listing(
            history: ["polish": "unpolished", "originality": NSNull(), "service_history": "serviced", "last_service_year": 2020],
            box: true, papers: false
        )
        let rows = ListingHistoryWords.rows(for: answered)
        XCTAssertEqual(rows.map(\.label), ["Polish", "Last service", "Box & papers"])
        XCTAssertEqual(rows.map(\.value), ["Never polished", "Serviced in 2020", "Box only"])
        XCTAssertTrue(rows.allSatisfy { $0.helpKey == nil })

        // Nothing known at all: no rows, so no section.
        XCTAssertTrue(ListingHistoryWords.rows(for: try listing()).isEmpty)
    }

    /// The History row and the Box & papers tile say it one way.
    func testBoxAndPapersIsTheAppsExistingPhrase() {
        XCTAssertEqual(BoxPapersPhrase.text(boxIncluded: true, papersIncluded: true, bookletsIncluded: nil, boxPapers: nil), "Full set")
        XCTAssertEqual(BoxPapersPhrase.text(boxIncluded: true, papersIncluded: false, bookletsIncluded: nil, boxPapers: nil), "Box only")
        XCTAssertEqual(BoxPapersPhrase.text(boxIncluded: false, papersIncluded: true, bookletsIncluded: nil, boxPapers: nil), "Papers only")
        XCTAssertEqual(BoxPapersPhrase.text(boxIncluded: false, papersIncluded: false, bookletsIncluded: false, boxPapers: nil), "Watch only")
        XCTAssertEqual(BoxPapersPhrase.text(boxIncluded: nil, papersIncluded: nil, bookletsIncluded: nil, boxPapers: true), "Full set")
        XCTAssertEqual(BoxPapersPhrase.text(boxIncluded: nil, papersIncluded: nil, bookletsIncluded: nil, boxPapers: false), "Watch only")
        XCTAssertNil(BoxPapersPhrase.text(boxIncluded: nil, papersIncluded: nil, bookletsIncluded: nil, boxPapers: nil))
    }

    // MARK: - Card facts

    func testCardFactsInTheContractsOrder() throws {
        let full = try listing(
            history: ["polish": "unpolished", "originality": "all_original"],
            box: true, papers: true
        )
        XCTAssertEqual(ListingHistoryWords.cardFacts(for: full), ["Unpolished", "All original", "Full set"])

        let polished = try listing(history: ["polish": "polished", "originality": "replaced"], box: true, papers: false)
        XCTAssertEqual(ListingHistoryWords.cardFacts(for: polished), ["Polished", "Box"])

        // Unknown, never and replaced print nothing on a card.
        let quiet = try listing(history: ["polish": "unknown", "originality": "unknown", "service_history": "never"])
        XCTAssertEqual(ListingHistoryWords.cardFacts(for: quiet), [])
    }

    func testTheBoxFactReadsTheLegacyBitOnlyWhenNeitherWasAsked() {
        XCTAssertEqual(ListingHistoryWords.boxFact(boxIncluded: nil, papersIncluded: nil, boxPapers: true), "Full set")
        XCTAssertNil(ListingHistoryWords.boxFact(boxIncluded: nil, papersIncluded: nil, boxPapers: false))
        XCTAssertEqual(ListingHistoryWords.boxFact(boxIncluded: false, papersIncluded: true, boxPapers: true), "Papers")
        XCTAssertNil(ListingHistoryWords.boxFact(boxIncluded: false, papersIncluded: false, boxPapers: nil))
    }

    /// The grid card gets the grade, the facts and the part chip from the one
    /// listing projection every grid and lane uses.
    func testTheCardProjectionCarriesGradeFactsAndChip() throws {
        var condition = Self.allVeryGood
        condition["bracelet"] = "Good"
        let card = try listing(
            condition: condition,
            history: ["polish": "unpolished"],
            boxPapers: true
        ).cardModel
        XCTAssertEqual(card.condition, "Very Good")
        XCTAssertEqual(card.facts, ["Unpolished", "Full set"])
        XCTAssertEqual(card.partException, "Bracelet: Good")

        let bare = try listing().cardModel
        XCTAssertNil(bare.condition)
        XCTAssertEqual(bare.facts, [])
        XCTAssertNil(bare.partException)
    }

    // MARK: - The grade guide

    func testEveryGradeHasItsCheckLine() {
        let checks = ConditionGrades.definitions.map { ($0.grade, $0.check) }
        XCTAssertEqual(checks.map(\.0), ["New", "Like New", "Very Good", "Good", "Worn"])
        XCTAssertEqual(checks.map(\.1), [
            "Check: stickers and film",
            "Check: at arm's length",
            "Check: with the naked eye",
            "Check: with the naked eye",
            "Check: every flaw listed",
        ])
        XCTAssertEqual(GradeScale.rank("New"), 0)
        XCTAssertEqual(GradeScale.rank("Worn"), 4)
        XCTAssertNil(GradeScale.rank("Excellent"))
    }

    // MARK: - The sell form's answers

    func testANewListingNeedsAllThreeAnswers() {
        var history = WizardHistory()
        XCTAssertFalse(history.isComplete)
        XCTAssertEqual(history.unanswered, [.polish, .originality, .service])
        history.setAnswer("unpolished", for: .polish)
        history.setAnswer("unknown", for: .originality)
        XCTAssertEqual(history.unanswered, [.service])
        history.setAnswer("never", for: .service)
        XCTAssertTrue(history.isComplete)
        XCTAssertTrue(history.isValid(currentYear: 2026))
    }

    /// An edit starts from what the listing holds, with nil answers unselected.
    func testAnEditStartsFromTheListingsAnswers() {
        let history = WizardHistory(ListingHistory(
            polish: "polished",
            originality: "replaced",
            replacedPartsNote: "Crown",
            serviceHistory: "serviced",
            lastServiceYear: 2019
        ))
        XCTAssertEqual(history.replacedNote, "Crown")
        XCTAssertEqual(history.serviceYearText, "2019")
        XCTAssertTrue(history.isComplete)

        let unasked = WizardHistory(nil)
        XCTAssertEqual(unasked.unanswered, HistoryQuestion.allCases)
    }

    /// The note and the year go out beside their answer only; empty is an
    /// explicit clear, and a value the server would refuse is left off.
    func testTheNoteAndYearFollowTheirAnswer() {
        var history = WizardHistory()
        history.replacedNote = "Crown"
        history.serviceYearText = "2021"
        history.setAnswer("all_original", for: .originality)
        history.setAnswer("never", for: .service)
        XCTAssertNil(history.notePayload)
        XCTAssertNil(history.yearPayload(currentYear: 2026))

        history.setAnswer("replaced", for: .originality)
        history.setAnswer("serviced", for: .service)
        XCTAssertEqual(history.notePayload, .value("Crown"))
        XCTAssertEqual(history.yearPayload(currentYear: 2026), .value(2021))

        history.replacedNote = "   "
        history.serviceYearText = ""
        XCTAssertEqual(history.notePayload, .null)
        XCTAssertEqual(history.yearPayload(currentYear: 2026), .null)

        history.serviceYearText = "1899"
        XCTAssertNil(history.yearPayload(currentYear: 2026))
        XCTAssertEqual(history.yearError(currentYear: 2026), "Enter a year from 1900 to 2026.")
        history.serviceYearText = "2027"
        XCTAssertNotNil(history.yearError(currentYear: 2026))
        XCTAssertFalse(history.isValid(currentYear: 2026))

        history.serviceYearText = "2026"
        history.replacedNote = String(repeating: "a", count: WizardHistory.noteLimit + 1)
        XCTAssertTrue(history.noteTooLong)
        XCTAssertNil(history.notePayload, "a note the server would refuse must not stop the rest saving")
        XCTAssertEqual(history.noteError, "Keep it to 120 characters.")
    }

    func testTheReviewStepSaysTheListingsWords() {
        var history = WizardHistory()
        history.setAnswer("unpolished", for: .polish)
        history.setAnswer("replaced", for: .originality)
        history.replacedNote = "Crown  and crystal"
        let rows = history.reviewRows(currentYear: 2026)
        XCTAssertEqual(rows.map(\.label), ["Polish", "Originality", "Last service"])
        XCTAssertEqual(rows.map(\.value), ["Never polished", "Some parts replaced: Crown and crystal", "Not answered"])
    }

    func testTheQuestionsAndAnswersAreTheContracts() {
        XCTAssertEqual(HistoryQuestion.polish.options.map(\.label), ["Never polished", "Polished", "I don't know"])
        XCTAssertEqual(HistoryQuestion.originality.options.map(\.label), ["All original", "Some parts replaced", "I don't know"])
        XCTAssertEqual(HistoryQuestion.service.options.map(\.label), ["Serviced", "Never serviced", "I don't know"])
        XCTAssertEqual(Set(HistoryQuestion.polish.options.map(\.value)), ListingHistory.polishValues)
        XCTAssertEqual(Set(HistoryQuestion.originality.options.map(\.value)), ListingHistory.originalityValues)
        XCTAssertEqual(Set(HistoryQuestion.service.options.map(\.value)), ListingHistory.serviceValues)
    }

    /// The standing copy rule on every new sentence: no em dashes.
    func testNoNewSentenceCarriesAnEmDash() {
        var all: [String] = ConditionGrades.definitions.map(\.check)
        for question in HistoryQuestion.allCases {
            all += [question.question, question.help, question.helpLabel, question.rowLabel, question.requiredMessage]
            all += question.options.map(\.label)
            if let followUp = question.followUpLabel { all.append(followUp) }
        }
        XCTAssertFalse(all.isEmpty)
        for sentence in all {
            XCTAssertFalse(sentence.contains("\u{2014}"), sentence)
        }
    }
}
