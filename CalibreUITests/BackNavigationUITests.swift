import XCTest

/// Back goes back to the screen you were on.
///
/// The defect this drives: every tab is a `NavigationStack` bound to a path
/// the router owns, and a push used to append to that path from screens that
/// had arrived by a plain `NavigationLink` — which are not in the path at all.
/// SwiftUI then rebuilt the stack as root-plus-path and the screen the reader
/// was standing on was gone, so Back landed on the tab's root.
///
/// Me → Orders → one order → Back is the shortest walk that has all three
/// parts: an untracked link (Me's `NavigationLink { OrdersListScreen() }`),
/// a routed push above it (the order), and a Back the reader expects to land
/// between them.
final class BackNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func signedInApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenIntro", "YES", "-guestChosen", "NO", "-disableTutorials"]
        return app
    }

    /// Signs in with the local demo buyer unless a session is already held.
    private func signInIfNeeded(_ app: XCUIApplication) {
        let signInRow = app.buttons["Sign in or create account"]
        guard signInRow.waitForExistence(timeout: 5) else { return }
        signInRow.tap()

        let identifier = app.textFields["you@example.com"]
        XCTAssertTrue(identifier.waitForExistence(timeout: 5))
        identifier.tap()
        identifier.typeText("buyer@demo.calibre.local")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("CalibreDemo123!")
        app.buttons["Sign In"].tap()

        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
    }

    func testBackFromAnOrderLandsOnTheOrdersList() throws {
        let app = signedInApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        tabBar.buttons["Me"].tap()
        signInIfNeeded(app)

        let ordersRow = app.buttons["Orders"]
        XCTAssertTrue(ordersRow.waitForExistence(timeout: 15), "the Me tab never showed its Orders row")
        ordersRow.tap()

        // The orders list, identified by the heading it draws itself rather
        // than by a title the screen that pushed it supplies.
        let ordersHeading = app.staticTexts["Your orders"]
        if !ordersHeading.waitForExistence(timeout: 15) {
            snap("30-orders-list-missing")
            XCTFail("Orders never opened\n\(app.debugDescription)")
        }
        snap("30-orders-list")

        // Any order row: they all carry the order number, and nothing else on
        // this screen does.
        let orderRow = app.buttons.matching(NSPredicate(format: "label CONTAINS '#'")).firstMatch
        XCTAssertTrue(orderRow.waitForExistence(timeout: 20), "no order rows to open")
        orderRow.tap()

        let orderTitle = app.navigationBars["Order"]
        XCTAssertTrue(orderTitle.waitForExistence(timeout: 20), "the order never opened")
        snap("31-order-detail")

        let backButton = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10), "the order screen drew no back button")
        backButton.tap()

        // The whole point: back is the orders list, not the Me tab's root.
        XCTAssertTrue(
            ordersHeading.waitForExistence(timeout: 15),
            "Back from an order left the orders list — the tab's path was rebuilt underneath it"
        )
        XCTAssertFalse(
            app.staticTexts["Preferences"].exists,
            "Back from an order dropped the reader at the Me tab's root"
        )
        snap("32-back-on-orders-list")
    }
}
