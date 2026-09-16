import XCTest

@testable import CalibreDesign

@MainActor
final class TutorialEngineTests: XCTestCase {
    private func freshDefaults(_ label: String = #function) -> UserDefaults {
        let suite = "tutorial.test.\(label)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testLedgerRemembersAndResets() {
        let ledger = TutorialLedger(defaults: freshDefaults())
        XCTAssertFalse(ledger.hasCompleted("deck"))
        ledger.markCompleted("deck")
        XCTAssertTrue(ledger.hasCompleted("deck"))
        ledger.reset("deck")
        XCTAssertFalse(ledger.hasCompleted("deck"))
    }

    /// A completed lesson must stay completed for a fresh ledger — the
    /// stand-in for relaunching after an app update.
    func testCompletionSurvivesANewLedgerInstance() {
        let defaults = freshDefaults()
        TutorialLedger(defaults: defaults).markCompleted("discover.deck")
        XCTAssertTrue(TutorialLedger(defaults: defaults).hasCompleted("discover.deck"))
    }

    func testResetAllClearsOnlyTutorialKeys() {
        let defaults = freshDefaults()
        defaults.set("keep-me", forKey: "unrelated")
        let ledger = TutorialLedger(defaults: defaults)
        ledger.markCompleted("a")
        ledger.markCompleted("b")
        ledger.resetAll()
        XCTAssertFalse(ledger.hasCompleted("a"))
        XCTAssertFalse(ledger.hasCompleted("b"))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep-me")
    }

    func testControllerAdvancesOnlyOnTheMatchingEvent() {
        let ledger = TutorialLedger(defaults: freshDefaults())
        let controller = TutorialController(
            id: "t",
            steps: [
                TutorialStep(id: "a", title: "A", message: "", advance: .perform(event: "save")),
                TutorialStep(id: "b", title: "B", message: "", advance: .tapToContinue),
            ],
            ledger: ledger
        )

        controller.startIfNeeded()
        XCTAssertEqual(controller.currentStep?.id, "a")

        controller.fire("pass")   // wrong event — no movement
        XCTAssertEqual(controller.currentStep?.id, "a")
        controller.advance()      // wrong advance kind — no movement
        XCTAssertEqual(controller.currentStep?.id, "a")

        controller.fire("save")   // the real action
        XCTAssertEqual(controller.currentStep?.id, "b")

        controller.advance()      // finishes the last step
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(ledger.hasCompleted("t"))
    }

    func testStartIsANoOpOnceCompleted() {
        let ledger = TutorialLedger(defaults: freshDefaults())
        ledger.markCompleted("t")
        let controller = TutorialController(
            id: "t",
            steps: [TutorialStep(id: "a", title: "A", message: "")],
            ledger: ledger
        )
        controller.startIfNeeded()
        XCTAssertFalse(controller.isActive)
    }

    func testSkipEndsAndRemembers() {
        let ledger = TutorialLedger(defaults: freshDefaults())
        let controller = TutorialController(
            id: "t",
            steps: [
                TutorialStep(id: "a", title: "A", message: ""),
                TutorialStep(id: "b", title: "B", message: ""),
            ],
            ledger: ledger
        )
        controller.startIfNeeded()
        controller.skip()
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(ledger.hasCompleted("t"))
    }

    func testPositionReportsOneBasedProgress() {
        let ledger = TutorialLedger(defaults: freshDefaults())
        let controller = TutorialController(
            id: "t",
            steps: [
                TutorialStep(id: "a", title: "A", message: ""),
                TutorialStep(id: "b", title: "B", message: ""),
            ],
            ledger: ledger
        )
        controller.startIfNeeded()
        XCTAssertEqual(controller.position?.step, 1)
        XCTAssertEqual(controller.position?.total, 2)
    }
}
