import XCTest
@testable import Calibre

/// Going somewhere that is a whole tab rather than a screen.
///
/// A feed card that says "go to the Vault", the Vault's "list this watch" —
/// neither can be an ordinary push, because the Vault's stack sits under a
/// biometric gate only the tab raises and the wizard needs the Sell tab's own
/// session. They were therefore plain tab selections, which threw away the
/// place the reader had come from: Back had nothing to return to and the tab
/// bar dropped them at a root.
///
/// So the jump remembers its origin, and the destination's root draws a way
/// back while it is set.
@MainActor
final class TabJumpTests: XCTestCase {
    func testAJumpRemembersWhereItCameFrom() {
        let router = AppRouter()
        router.selectedTab = .home

        router.jump(to: .collection)

        XCTAssertEqual(router.selectedTab, .collection)
        XCTAssertEqual(router.tabOrigin, .home, "the jump forgot the tab it came from")
    }

    func testReturningGoesBackAndEndsTheJump() {
        let router = AppRouter()
        router.selectedTab = .home
        router.jump(to: .collection)

        router.returnFromJump()

        XCTAssertEqual(router.selectedTab, .home)
        XCTAssertNil(router.tabOrigin, "the way back stayed on screen after it was taken")
    }

    /// The origin tab's stack is not touched by the round trip: coming back
    /// means coming back to the screen they were reading, not to a root.
    func testTheOriginKeepsItsStack() {
        let router = AppRouter()
        router.selectedTab = .home
        router.push(.listing("sub-116610"))
        XCTAssertEqual(router.homePath, [.listing("sub-116610")])

        router.jump(to: .collection)
        router.returnFromJump()

        XCTAssertEqual(router.homePath, [.listing("sub-116610")])
    }

    /// Selecting the tab you are already on is not a jump, and must not
    /// overwrite an origin a real jump is still holding.
    func testJumpingToTheTabYouAreOnIsNotAJump() {
        let router = AppRouter()
        router.selectedTab = .home
        router.jump(to: .collection)

        router.jump(to: .collection)

        XCTAssertEqual(router.tabOrigin, .home)
    }

    /// Choosing a tab by hand ends the jump: the reader has just said where
    /// they are, and a back button pointing at a card they left two taps ago
    /// would be a lie.
    func testChoosingATabByHandEndsTheJump() {
        let router = AppRouter()
        router.selectedTab = .home
        router.jump(to: .collection)

        router.tabSelection.wrappedValue = .community

        XCTAssertEqual(router.selectedTab, .community)
        XCTAssertNil(router.tabOrigin)
    }

    /// A push notification or a link is not a place inside the app, so there
    /// is nothing behind it to offer a way back to.
    func testALinkLeavesNoWayBackAcrossTabs() {
        let router = AppRouter()
        router.selectedTab = .home
        router.jump(to: .collection)

        router.open(.order("o-1"))

        XCTAssertEqual(router.selectedTab, .you)
        XCTAssertNil(router.tabOrigin)
    }

    /// "List this watch" from the Vault. The wizard needs the Sell tab's own
    /// session, so this stays a tab switch — and the Vault the seller left is
    /// what Back has to return to.
    func testListingAVaultWatchKeepsTheVaultBehindIt() {
        let router = AppRouter()
        router.selectedTab = .collection

        router.startListing(prefill: ListingPrefill(brand: "Omega"))

        XCTAssertEqual(router.selectedTab, .sell)
        XCTAssertEqual(router.tabOrigin, .collection)
        XCTAssertEqual(router.pendingListingPrefill?.brand, "Omega")
    }
}
