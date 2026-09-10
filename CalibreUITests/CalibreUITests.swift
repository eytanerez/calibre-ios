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

/// Exercise the exact wizard → capture stack, including a second selection.
final class ListingPhotoLibraryUITests: XCTestCase {
    @MainActor
    func testLibraryStaysOpenAfterCancelReopenAndReplacement() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-photoPickerSmokeTest", "-disableTutorials"]
        app.launch()
        app.buttons["Open listing wizard"].tap()
        app.buttons["Add front photo"].tap()
        let library = app.buttons["Choose from library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
        // The regression closed the library shortly after it appeared.
        let holdUntil = Date().addingTimeInterval(8)
        let holds = NSPredicate { _, _ in Date() >= holdUntil && cancel.exists && cancel.isHittable }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: holds, object: nil)], timeout: 10) == .completed)
        snap("photo-library-open")
        cancel.tap()
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let photo = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo' OR label CONTAINS 'photo'")).firstMatch
        guard photo.waitForExistence(timeout: 3) else {
            XCTFail("The simulator needs at least one sample photo to verify selection.")
            return
        }
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let use = app.buttons["Use photo"]
        XCTAssertTrue(use.waitForExistence(timeout: 10), app.debugDescription)
        snap("photo-library-preview")
        use.tap()
        XCTAssertTrue(app.staticTexts["Photo received"].waitForExistence(timeout: 5))
        app.buttons["Replace front photo"].tap()
        app.buttons["Choose from library"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Replace front photo"].waitForExistence(timeout: 10))
        snap("photo-library-replaced")
        // Replacement can also enter through the camera before the library.
        app.buttons["Replace front photo"].tap()
        app.buttons["Take a new photo"].tap()
        app.buttons["Choose from library"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(use.waitForExistence(timeout: 10))
        app.buttons["Retake"].tap()
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(use.waitForExistence(timeout: 10))
        use.tap()
        XCTAssertTrue(app.buttons["Replace front photo"].waitForExistence(timeout: 5), "Returning a replacement must leave the wizard open")
    }
}

final class ConsumerPageSwipeUITests: XCTestCase {
    @MainActor
    func testHorizontalDiagonalSwipeDoesNotScrollAndVerticalAndRailDoNotSwitch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-pageSwipeSmokeTest"]
        app.launch()
        let status = app.staticTexts["swipe-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.51))
        start.press(forDuration: 0.05, thenDragTo: finish)
        XCTAssertEqual(status.label, "Page 1, offset 0")
        let rail = app.scrollViews["swipe-rail"]
        rail.swipeLeft()
        XCTAssertEqual(status.label, "Page 1, offset 0", "The horizontal filter rail must not change the page")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.54, dy: 0.4)))
        XCTAssertTrue(status.label.hasPrefix("Page 1,"))
        XCTAssertNotEqual(status.label, "Page 1, offset 0", "Vertical scrolling must still work")
        snap("consumer-page-swipe-direction-lock")
    }
}
