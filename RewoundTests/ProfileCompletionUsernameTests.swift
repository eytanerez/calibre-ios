import XCTest

@testable import Rewound

/// The completion gate's username box starts empty (b161807) and runs the
/// same live availability check as registration. That endpoint is
/// unauthenticated, so for the account's own handle it can only say "already
/// in use", and `canSubmit` waits on that check. Without a local answer for
/// the account's own name, a member who typed it back was held at the gate.
@MainActor
final class ProfileCompletionUsernameTests: XCTestCase {
    func testTheAccountsOwnUsernameIsRecognised() {
        XCTAssertTrue(ProfileCompletionView.isCurrentUsername("eytan_12", current: "eytan_12"))
        // Typed lowercase, as the field forces; stored however it was stored.
        XCTAssertTrue(ProfileCompletionView.isCurrentUsername("eytan_12", current: "Eytan_12"))
        XCTAssertTrue(ProfileCompletionView.isCurrentUsername(" eytan_12 ", current: "eytan_12"))
    }

    func testAnyOtherNameStillGoesToTheServer() {
        XCTAssertFalse(ProfileCompletionView.isCurrentUsername("eytan_13", current: "eytan_12"))
        XCTAssertFalse(ProfileCompletionView.isCurrentUsername("eytan", current: "eytan_12"))
    }

    /// An account with no username on file has nothing of its own to match.
    func testNoUsernameOnFileMatchesNothing() {
        XCTAssertFalse(ProfileCompletionView.isCurrentUsername("eytan_12", current: nil))
        XCTAssertFalse(ProfileCompletionView.isCurrentUsername("", current: ""))
        XCTAssertFalse(ProfileCompletionView.isCurrentUsername("   ", current: "  "))
    }
}
