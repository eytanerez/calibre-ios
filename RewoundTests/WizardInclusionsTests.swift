import XCTest

@testable import Rewound

/// "Nobody was asked" is not "no".
///
/// The wizard saves a draft the moment it opens. Before `WizardInclusions`,
/// an older draft that had only the combined `box_papers` answer came back
/// from that save with `booklets_included = false`: a "not included" the
/// seller never gave, which the bench then compares the delivered box against.
final class WizardInclusionsTests: XCTestCase {
    func testAnOlderDraftSendsNoBookletsAnswerItNeverHad() {
        let inclusions = WizardInclusions(boxPapers: true)

        XCTAssertEqual(inclusions.boxAnswer, true)
        XCTAssertEqual(inclusions.papersAnswer, true)
        XCTAssertNil(inclusions.bookletsAnswer)
        XCTAssertEqual(inclusions.boxPapersAnswer, true)
    }

    func testAFalseCombinedAnswerAnswersNeitherHalf() {
        // `box_papers = false` was written on every listing, asked or not.
        let inclusions = WizardInclusions(boxPapers: false)

        XCTAssertNil(inclusions.boxAnswer)
        XCTAssertNil(inclusions.papersAnswer)
        XCTAssertNil(inclusions.bookletsAnswer)
        XCTAssertNil(inclusions.boxPapersAnswer)
    }

    func testTheListingsOwnColumnsAreAnswers() {
        let inclusions = WizardInclusions(boxPapers: false, box: true, papers: false, booklets: false)

        XCTAssertEqual(inclusions.boxAnswer, true)
        XCTAssertEqual(inclusions.papersAnswer, false)
        XCTAssertEqual(inclusions.bookletsAnswer, false)
        XCTAssertEqual(inclusions.boxPapersAnswer, false)
    }

    func testAToggleIsAnAnswerAndOnlyThatOne() {
        var inclusions = WizardInclusions()
        inclusions.setBooklets(true)

        XCTAssertEqual(inclusions.bookletsAnswer, true)
        XCTAssertNil(inclusions.boxAnswer)
        XCTAssertNil(inclusions.papersAnswer)
        XCTAssertNil(inclusions.boxPapersAnswer)
    }

    func testSeeingTheQuestionTurnsWhatIsOffIntoANo() {
        var inclusions = WizardInclusions(boxPapers: true)
        inclusions.markSeen()

        XCTAssertEqual(inclusions.boxAnswer, true)
        XCTAssertEqual(inclusions.papersAnswer, true)
        XCTAssertEqual(inclusions.bookletsAnswer, false)
    }

    func testASnapshotLayersOnlyTheAnswersItCarries() {
        var inclusions = WizardInclusions(boxPapers: true)
        inclusions.apply(box: nil, papers: false, booklets: nil)

        XCTAssertEqual(inclusions.boxAnswer, true)
        XCTAssertEqual(inclusions.papersAnswer, false)
        XCTAssertNil(inclusions.bookletsAnswer)
        XCTAssertEqual(inclusions.boxPapersAnswer, false)
    }
}
