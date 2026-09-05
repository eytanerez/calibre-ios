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

extension XCTestCase {
    /// Attaches a full-screen screenshot to the test's result bundle, kept
    /// permanently so `xcresulttool export attachments` can pull the whole
    /// visual record out later. Shared across every UI test case in this
    /// target — it used to be a byte-identical private copy in each one.
    func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
