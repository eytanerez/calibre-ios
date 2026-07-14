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
        ]
        return app
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDiscoverExplainsGesturesAndExposesSaved() throws {
        let app = returningApp()
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["Discover"].tap()

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
        tabs.buttons["You"].tap()

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
