import XCTest

/// Critical-path UI tests land with their features (guest gate, deck save,
/// wizard-to-review, cart swap). This smoke test keeps the target non-empty.
final class RewoundUITests: XCTestCase {
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
///
/// The camera no longer opens the library over itself: it closes and the
/// screen underneath presents Photos, the way Vault does from its sheet
/// (`ListingPhotoCapture`). So a library photo lands in the slot with no
/// "Use photo" step, and cancelling the library returns to the photo grid
/// rather than to the camera.
///
/// On the simulator the camera is unavailable and the capture screen shows its
/// fallback, so this cannot reproduce a live capture session. What it does
/// prove is the part that is new: the handoff out of the camera cover, the
/// picker appearing only after that cover has gone, and the photo arriving in
/// the slot it was meant for.
final class ListingPhotoLibraryUITests: XCTestCase {
    @MainActor
    func testLibraryOpensFromUnderTheCameraAndFillsTheSlot() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-photoPickerSmokeTest", "-disableTutorials"]
        app.launch()
        app.buttons["Open listing wizard"].tap()

        // 1. Out of the camera and into Photos, and Photos stays open.
        let addFront = app.buttons["Add front photo"]
        addFront.tap()
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

        // Cancelling lands on the grid, with the camera already gone.
        cancel.tap()
        XCTAssertTrue(addFront.waitForExistence(timeout: 5), "cancelling the library must return to the photo grid")
        XCTAssertFalse(app.staticTexts["Photo received"].exists)

        // 2. A picked photo goes straight into the slot.
        addFront.tap()
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        let photo = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo' OR label CONTAINS 'photo'")).firstMatch
        guard photo.waitForExistence(timeout: 3) else {
            XCTFail("The simulator needs at least one sample photo to verify selection.")
            return
        }
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Photo received"].waitForExistence(timeout: 10), app.debugDescription)
        snap("photo-library-received")

        // 3. Replacing from the preview, which never had a camera.
        let replace = app.buttons["Replace front photo"]
        replace.tap()
        app.buttons["Choose from library"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(replace.waitForExistence(timeout: 10))
        snap("photo-library-replaced")

        // 4. Replacing through the camera first: the inline camera hands the
        //    library back to the preview rather than opening it over itself.
        replace.tap()
        app.buttons["Take a new photo"].tap()
        let cameraLibrary = app.buttons["Choose from library"]
        XCTAssertTrue(cameraLibrary.waitForExistence(timeout: 5))
        cameraLibrary.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(replace.waitForExistence(timeout: 10), "returning a replacement must leave the wizard open")
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
