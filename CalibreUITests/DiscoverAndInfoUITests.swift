import XCTest

final class DiscoverAndInfoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func returningApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasSeenIntro", "YES",
            "-guestChosen", "YES",
            "-disableTutorials",
        ]
        return app
    }

    func testDiscoverExplainsGesturesAndExposesSaved() throws {
        let app = returningApp()
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        // The deck is no longer its own tab — Home's header opens it as a
        // full-screen cover (`HomeScreen.swift`'s "the deck lives one tap
        // from Home" comment). `DiscoverScreen` itself, and every string
        // below, is unchanged.
        app.buttons["Open the deck"].tap()

        XCTAssertTrue(app.staticTexts[
            "Swipe right to save, left to pass. Tap a watch for its details."
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["View all saved watches"].exists)
        XCTAssertTrue(app.buttons["Pass on this watch"].exists)
        XCTAssertTrue(app.buttons["Save this watch"].exists)
        snap("discover-explained")
    }

    func testJournalAndFeePagesAreFirstClassDestinations() throws {
        let app = returningApp()
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        // The "You" tab was renamed "Me" — same screen, same rows.
        tabs.buttons["Me"].tap()

        let journal = app.buttons["The Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stories from the world of watches, written by the Calibre desk."].exists)
        snap("journal-index")

        app.navigationBars["Journal"].buttons.element(boundBy: 0).tap()

        let fees = app.buttons["Fees and payments"]
        XCTAssertTrue(fees.waitForExistence(timeout: 5))
        fees.tap()
        XCTAssertTrue(app.navigationBars["Fees and payments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["6% seller fee"].exists)
        XCTAssertTrue(app.staticTexts["4% seller fee"].exists)
        XCTAssertFalse(app.staticTexts["8% seller fee"].exists)
        XCTAssertFalse(app.staticTexts["5% seller fee"].exists)
        snap("fees-breakdown")
    }
}
