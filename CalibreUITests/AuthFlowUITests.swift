import XCTest

/// P2 critical-path flows: intro pager, login gate, register step 1 with the
/// live username check, guest tab shell, the auth-gate sheet, and the real
/// sign-in / sign-out round trip against the local backend. Screenshots are
/// attached (`keepAlways`) so `xcresulttool export attachments` can pull the
/// full visual record out of the result bundle.
final class AuthFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// A launch that starts at the intro. `-resetAppState` clears the
    /// persisted onboarding keys in-app; argument-domain defaults would
    /// shadow the app's own writes and freeze the phase machine.
    private func firstLaunchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAppState", "-uiTesting"]
        return app
    }

    /// A launch that reads (never writes) the given onboarding state.
    private func returningApp(hasSeenIntro: Bool, guest: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-hasSeenIntro", hasSeenIntro ? "YES" : "NO",
            "-guestChosen", guest ? "YES" : "NO",
            "-disableTutorials",
        ]
        return app
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Types into a text field, verifying the result — synthesized typing
    /// can race SwiftUI field-swap animations, so retry until the value
    /// sticks.
    private func fill(_ field: XCUIElement, with text: String) {
        for _ in 0..<3 {
            field.tap()
            usleep(400_000)
            if let current = field.value as? String,
               !current.isEmpty,
               current != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4))
            }
            field.typeText(text)
            usleep(300_000)
            if (field.value as? String) == text { return }
        }
        XCTFail("Field never accepted the text \(text)")
    }

    /// Dismisses the system save-password prompt if it slides in.
    private func dismissPasswordPromptIfNeeded(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
    }

    // MARK: - Guest flows (light appearance)

    func testCredentialFormsRejectBlankAndMalformedInput() throws {
        let app = returningApp(hasSeenIntro: true)
        app.launch()

        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertFalse(signIn.isEnabled, "Blank credentials must never submit")

        let identifier = app.textFields["you@example.com"]
        identifier.tap()
        identifier.typeText("   ")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("Calibre1")
        XCTAssertFalse(signIn.isEnabled, "Whitespace-only identifiers must never submit")

        app.buttons["Forgot password?"].tap()
        let send = app.buttons["Send reset link"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled)

        let email = app.textFields["you@example.com"]
        email.tap()
        email.typeText("buyer@example")
        XCTAssertFalse(send.isEnabled, "An incomplete email host must be rejected")

        for _ in 0..<13 { email.typeText(XCUIKeyboardKey.delete.rawValue) }
        email.typeText("buyer@example.com")
        XCTAssertTrue(send.isEnabled, "A complete email should enable reset submission")
    }

    func testGuestFlows() throws {
        let app = firstLaunchApp()
        app.launch()

        // Intro pager — three panels.
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        sleep(1)
        snap("01-intro-panel-1")
        continueButton.tap()
        sleep(1)
        snap("02-intro-panel-2")
        continueButton.tap()
        sleep(1)
        snap("03-intro-panel-3")
        app.buttons["Get started"].tap()

        // Login gate.
        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Browse as guest"].exists)
        sleep(1)
        snap("04-login-gate-light")

        // Register step 1 — live username availability (iosbuyer is taken).
        app.buttons["Create an account"].firstMatch.tap()
        let firstNameField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 5))
        firstNameField.tap()
        firstNameField.typeText("Ada")
        let lastNameField = app.textFields.element(boundBy: 1)
        lastNameField.tap()
        lastNameField.typeText("Lovelace")
        let emailField = app.textFields["you@example.com"]
        emailField.tap()
        emailField.typeText("ada.lovelace@example.com")
        let phoneField = app.textFields["+1 555 000 1234"]
        phoneField.tap()
        phoneField.typeText("5550001234")
        let usernameField = app.textFields["e.g. dialside"]
        usernameField.tap()
        usernameField.typeText("iosbuyer")
        // Debounce (400ms) + round trip, then the taken state shows.
        let takenCaption = app.staticTexts["Username already in use."]
        XCTAssertTrue(takenCaption.waitForExistence(timeout: 6))
        snap("05-register-step1-username-taken")

        // Switch to an available name and fill the password pair.
        usernameField.tap()
        for _ in 0..<8 { usernameField.typeText(XCUIKeyboardKey.delete.rawValue) }
        usernameField.typeText("adadial\(Int.random(in: 1000...9999))")
        let availableCaption = app.staticTexts["Username is available."]
        XCTAssertTrue(availableCaption.waitForExistence(timeout: 6))

        // Reveal both password fields before typing — the system's Automatic
        // Strong Password cover swallows synthesized typing into secure
        // fields. Revealed fields are plain text fields, which type cleanly.
        app.buttons["Show password"].firstMatch.tap() // reveal password
        sleep(1)
        fill(app.textFields.element(boundBy: 5), with: "Meridian88")
        app.buttons["Show password"].firstMatch.tap() // reveal confirm (only one left)
        sleep(1)
        fill(app.textFields.element(boundBy: 6), with: "Meridian88")
        // The match indicator confirms both bindings agree.
        XCTAssertTrue(app.images["Passwords match"].waitForExistence(timeout: 4))
        app.swipeUp()
        sleep(1)
        snap("06-register-step1-username-available")

        let continueRegister = app.buttons["Continue"]
        XCTAssertTrue(continueRegister.isEnabled)
        continueRegister.tap()
        let streetField = app.textFields["123 Meridian Ave"]
        XCTAssertTrue(streetField.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["Create account"].isEnabled,
            "A registration with blank required address fields must not submit"
        )
        snap("07-register-step2-address")

        // Back out to the login gate and continue as a guest.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Browse as guest"].waitForExistence(timeout: 5))
        app.buttons["Browse as guest"].tap()

        // Tab shell — all five tabs.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        sleep(1)
        snap("08-tab-home")
        tabBar.buttons["Discover"].tap()
        sleep(1)
        snap("09-tab-discover")
        tabBar.buttons["Sell"].tap()
        sleep(1)
        snap("10-tab-sell")
        tabBar.buttons["Activity"].tap()
        sleep(1)
        snap("11-tab-activity")
        tabBar.buttons["You"].tap()
        sleep(1)
        snap("12-tab-you-signed-out")

        // Auth gate: the Discover demo Save action for a guest.
        tabBar.buttons["Discover"].tap()
        sleep(1)
        app.buttons["Save this watch"].tap()
        let gateSignIn = app.buttons["Sign In"]
        if !gateSignIn.waitForExistence(timeout: 6) {
            print("GATE-DEBUG-HIERARCHY-BEGIN\n\(app.debugDescription)\nGATE-DEBUG-HIERARCHY-END")
        }
        XCTAssertTrue(gateSignIn.exists)
        sleep(1)
        snap("13-auth-gate-sheet")
        app.buttons["Not now"].tap()
        sleep(1)
    }

    // MARK: - Live sign-in / sign-out against the local backend

    func testLiveLoginErrorThenSuccessAndSignOut() throws {
        let app = returningApp(hasSeenIntro: true, guest: true)
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["You"].tap()

        // A prior aborted run may have left a session in the Keychain —
        // start from a clean signed-out state.
        let signInRow = app.buttons["Sign in or create account"]
        if !signInRow.waitForExistence(timeout: 3) {
            app.swipeUp()
            app.buttons["Sign out"].tap()
            app.buttons["Sign Out"].tap()
            XCTAssertTrue(signInRow.waitForExistence(timeout: 10))
            app.swipeDown()
        }
        signInRow.tap()

        let identifierField = app.textFields["you@example.com"]
        XCTAssertTrue(identifierField.waitForExistence(timeout: 5))
        identifierField.tap()
        identifierField.typeText("iosbuyer.calibre@gmail.com")
        let passwordField = app.secureTextFields.firstMatch
        passwordField.tap()
        passwordField.typeText("wrong-password")
        app.buttons["Sign In"].tap()

        // The backend's own message must surface.
        let backendError = app.staticTexts["Invalid credentials"]
        XCTAssertTrue(backendError.waitForExistence(timeout: 10))
        snap("14-login-error-backend-message")

        // Now the real credentials.
        passwordField.tap()
        for _ in 0..<14 { passwordField.typeText(XCUIKeyboardKey.delete.rawValue) }
        passwordField.typeText("CalibreiOS123!")
        app.buttons["Sign In"].tap()
        dismissPasswordPromptIfNeeded(app)

        // Modal dismisses; the You tab shows the signed-in header.
        let username = app.staticTexts["iosbuyer"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        sleep(1)
        snap("15-you-signed-in")

        // Sign out with the confirm dialog.
        app.swipeUp()
        let signOutRow = app.buttons["Sign out"]
        XCTAssertTrue(signOutRow.waitForExistence(timeout: 5))
        signOutRow.tap()
        let confirm = app.buttons["Sign Out"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snap("16-sign-out-confirm")
        confirm.tap()

        let guestHeader = app.staticTexts["You're browsing as a guest"]
        XCTAssertTrue(guestHeader.waitForExistence(timeout: 10))
        sleep(1)
        snap("17-you-after-sign-out")
    }

    // MARK: - Deep links

    /// calibre://listing/:id selects the Home tab and pushes the listing route.
    func testDeepLinkOpensListingRoute() throws {
        let app = returningApp(hasSeenIntro: true, guest: true)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))

        XCUIDevice.shared.system.open(URL(string: "calibre://listing/rolex-sub-116610")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openButton = springboard.buttons["Open"]
        if openButton.waitForExistence(timeout: 4) {
            openButton.tap()
        }

        let detailScreen = app.descendants(matching: .any)["listing-detail-screen"]
        XCTAssertTrue(detailScreen.waitForExistence(timeout: 8))
        sleep(1)
        snap("20-deeplink-listing-route")
    }

    // MARK: - Dark appearance + Dynamic Type

    /// Run with the simulator already in dark appearance
    /// (`xcrun simctl ui booted appearance dark`).
    func testLoginGateDark() throws {
        let app = returningApp(hasSeenIntro: true)
        app.launch()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        sleep(1)
        snap("18-login-gate-dark")
    }

    /// One Dynamic Type size up — layout must hold.
    func testLoginGateLargerType() throws {
        let app = returningApp(hasSeenIntro: true)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        sleep(1)
        snap("19-login-gate-dynamic-type-xl")
    }
}
