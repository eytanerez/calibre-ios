import XCTest

/// The browse track's own pushes, which share a host with the route pushes.
///
/// `BrowseDestinationView` hosts two levels on one view — a browse destination
/// and a `Route` — because a browse screen can open either: a watch from the
/// grid, and the seller or the order behind it. This walks the browse half so
/// a change to the route half cannot quietly kill it.
final class BrowseNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAWatchOpensFromTheInventoryAndBackReturns() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenIntro", "YES", "-guestChosen", "NO", "-disableTutorials"]
        app.launch()

        let search = app.staticTexts["Search watches"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))

        let all = app.buttons["View all inventory"]
        XCTAssertTrue(all.waitForExistence(timeout: 20))
        all.tap()

        // Any watch on the grid: the price is on the card and on nothing else
        // that is tappable there.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS '$'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25), "the results grid drew no watches")
        card.tap()

        let detail = app.descendants(matching: .any)["listing-detail-screen"]
        XCTAssertTrue(detail.waitForExistence(timeout: 25), "the listing never opened")
        snap("50-listing-from-inventory")

        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Back from a listing left the results grid")
        snap("51-back-on-inventory")
    }
}
