import XCTest

/// Critical-path UI tests land with their features (guest gate, deck save,
/// wizard-to-review, cart swap). This smoke test keeps the target non-empty.
final class CalibreUITests: XCTestCase {
    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
