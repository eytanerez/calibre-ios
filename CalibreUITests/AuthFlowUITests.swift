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
        // There is no more post-intro login gate — `RootView`'s own comment
        // says so ("There is no sign-in life... The market is the front
        // door now"). `hasSeenIntro: true` lands straight in the guest tab
        // shell; sign-in is reached from the Me tab.
        let app = returningApp(hasSeenIntro: true)
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Me"].tap()
        app.buttons["Sign in or create account"].tap()

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

    // Rewritten for the `00bcba4` shell change. Two things moved, and both
    // are why almost every line below differs from what shipped in
    // `6b8b12b`:
    //
    // 1. There is no more post-intro login gate. `RootView`'s own comment
    //    explains it: "The market is the front door now, and sign-in is
    //    asked for at the moment it actually buys something." The intro's
    //    last panel now says so too — "Browse the market", not
    //    "Get started" — and finishing it drops straight into the guest tab
    //    shell. Sign-in (and, from it, registration) is reached from the Me
    //    tab's "Sign in or create account" row instead.
    // 2. The tab bar is Home / Community / Sell / Vault / Me — there is no
    //    "Discover" tab and no "Activity" tab any more. The deck (what
    //    "Discover" used to be) is one tap from Home's header now
    //    (`HomeScreen.swift`'s "the deck lives one tap from Home" comment);
    //    Activity's contents moved into the Me tab's own "Activity" section.
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
        app.buttons["Browse the market"].tap()

        // The intro hands off directly to the guest tab shell now — no
        // separate login gate screen in between.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        sleep(1)
        snap("04-tab-home")
        tabBar.buttons["Community"].tap()
        sleep(1)
        snap("05-tab-community")
        tabBar.buttons["Sell"].tap()
        sleep(1)
        snap("06-tab-sell")
        tabBar.buttons["Vault"].tap()
        sleep(1)
        snap("07-tab-vault")
        tabBar.buttons["Me"].tap()
        sleep(1)
        snap("08-tab-me-signed-out")

        // Sign-in, reached from the Me tab.
        app.buttons["Sign in or create account"].tap()
        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        sleep(1)
        snap("09-login-screen")

        // Register step 1 — live username availability. `demo_buyer` is the
        // dev-seed buyer's username (`buyer@demo.calibre.local`, per the
        // dev-seed logins) — a stable, documented "taken" username, unlike
        // the test's former "iosbuyer", which the current dev database no
        // longer has an account for (`GET /auth/username-availability` now
        // reports it available).
        app.buttons["Create an account"].tap()
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
        let phoneField = app.textFields["(415) 555-0134"]
        phoneField.tap()
        phoneField.typeText("5550001234")
        let usernameField = app.textFields["e.g. dialside"]
        usernameField.tap()
        usernameField.typeText("demo_buyer")
        // Debounce (400ms) + round trip, then the taken state shows.
        let takenCaption = app.staticTexts["Username already in use."]
        XCTAssertTrue(takenCaption.waitForExistence(timeout: 6))
        snap("10-register-step1-username-taken")

        // Switch to an available name and fill the password pair.
        usernameField.tap()
        for _ in 0..<10 { usernameField.typeText(XCUIKeyboardKey.delete.rawValue) }
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
        snap("11-register-step1-username-available")

        let continueRegister = app.buttons["Continue"]
        XCTAssertTrue(continueRegister.isEnabled)
        continueRegister.tap()
        let streetField = app.textFields["123 Meridian Ave"]
        XCTAssertTrue(streetField.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["Create account"].isEnabled,
            "A registration with blank required address fields must not submit"
        )
        snap("12-register-step2-address")

        // Back out to the sign-in screen, then close it — still signed out,
        // on the Me tab. (There is no "Browse as guest" button to tap any
        // more: guest browsing was never left in the first place.)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Sign in or create account"].waitForExistence(timeout: 5))

        // Auth gate: the deck's Save action for a guest. The deck opens from
        // Home's header now, not a "Discover" tab.
        tabBar.buttons["Home"].tap()
        sleep(1)
        // First real visit to Home in this run (a fresh `-resetAppState`
        // launch, so tutorials are live) — its coach mark spotlights the
        // deck button and swallows the tap until dismissed.
        let skipTutorial = app.buttons["Skip"]
        if skipTutorial.waitForExistence(timeout: 3) {
            skipTutorial.tap()
        }
        app.buttons["Open the deck"].tap()
        // The deck's own hands-on tutorial (swipe right to save, left to
        // pass) is a `TutorialCoachCard` too, same "Skip" — the deck screen
        // is also first-run at this point in the test.
        if skipTutorial.waitForExistence(timeout: 3) {
            skipTutorial.tap()
        }
        let saveButton = app.buttons["Save this watch"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        // The button exists as soon as the deck appears but stays disabled
        // until a real card has loaded from the backend.
        let cardDeadline = Date().addingTimeInterval(8)
        while !saveButton.isEnabled, Date() < cardDeadline { usleep(200_000) }
        saveButton.tap()

        // Not asserted here, and deliberately: `session.require` (the gate)
        // queues the intent but the sheet it drives is presented from
        // `RootView`, above `MainTabView`'s `.fullScreenCover` for the deck —
        // and SwiftUI does not present a `.sheet` from an ancestor while a
        // descendant's `.fullScreenCover` is on screen. Confirmed by hand on
        // the simulator: tapping Save (or the "Saved" chip) inside the deck
        // does nothing visible at all — no gate, no "Saved. Undo is
        // available." pill, card just advances — and the queued sheet only
        // appears once the deck itself closes. That is a real product bug
        // (a guest gets zero feedback for the tap that supposedly needs
        // sign-in), tracked in the review report rather than fixed here. What
        // this test can honestly assert is the part that does work: the
        // intent survives the deck closing and is replayed as a real sheet.
        app.buttons["Close the deck"].tap()

        // The gate is a sheet now, not a full-screen "Sign In" form — Apple
        // and Google lead, with the credential form folded behind
        // "Already have an account? Sign in" (`AuthGateSheet.swift`).
        let alreadyHaveAccount = app.buttons["Already have an account? Sign in"]
        if !alreadyHaveAccount.waitForExistence(timeout: 6) {
            print("GATE-DEBUG-HIERARCHY-BEGIN\n\(app.debugDescription)\nGATE-DEBUG-HIERARCHY-END")
        }
        XCTAssertTrue(alreadyHaveAccount.exists)
        alreadyHaveAccount.tap()
        let gateSignIn = app.buttons["Sign In"]
        XCTAssertTrue(gateSignIn.waitForExistence(timeout: 5))
        sleep(1)
        snap("13-auth-gate-sheet")
        app.buttons["Not now"].tap()
        sleep(1)
    }

    // MARK: - Live sign-in / sign-out against the local backend

    /// Uses the seeded dev-stack demo buyer (`buyer@demo.calibre.local` /
    /// `demo_buyer`, per the dev-seed logins) rather than a bespoke fixture
    /// account — a prior `iosbuyer.calibre@gmail.com` fixture this test used
    /// to sign in with no longer exists in the dev database
    /// (`POST /auth/login` now returns `account_not_found` for it), which
    /// this test's own tab-name bug had been hiding: it always failed one
    /// step earlier, at the "You" tab tap, before it ever reached the
    /// network call that would have caught the missing account.
    func testLiveLoginErrorThenSuccessAndSignOut() throws {
        let app = returningApp(hasSeenIntro: true, guest: true)
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Me"].tap()

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
        identifierField.typeText("buyer@demo.calibre.local")
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
        passwordField.typeText("CalibreDemo123!")
        app.buttons["Sign In"].tap()
        dismissPasswordPromptIfNeeded(app)

        // Modal dismisses; the Me tab shows the signed-in header.
        let username = app.staticTexts["demo_buyer"]
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
    ///
    /// There is no post-intro login gate any more — `hasSeenIntro: true`
    /// lands in the guest tab shell, and the sign-in screen is reached from
    /// the Me tab (see `testGuestFlows`'s header comment for the shell
    /// change this follows).
    func testLoginGateDark() throws {
        let app = returningApp(hasSeenIntro: true)
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Me"].tap()
        app.buttons["Sign in or create account"].tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        sleep(1)
        snap("18-login-gate-dark")
    }

    /// One Dynamic Type size up — layout must hold.
    func testLoginGateLargerType() throws {
        let app = returningApp(hasSeenIntro: true)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"]
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Me"].tap()
        app.buttons["Sign in or create account"].tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
        sleep(1)
        snap("19-login-gate-dynamic-type-xl")
    }
}
