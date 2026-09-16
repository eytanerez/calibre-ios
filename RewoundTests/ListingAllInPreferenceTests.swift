import CalibreKit
import Foundation
import XCTest
@testable import Calibre

/// The all-in toggle is the buyer's, not the listing's.
///
/// Eytan, 2026-09-09: *"in the apps the toggle for all in does not remember so
/// turning it on then going to a new watch does not work."* A pricing model is
/// built fresh for every watch — the quote is that watch's — and the toggle
/// used to be a stored property on it, so somebody who shops for totals had to
/// ask for the total again on every single listing.
@MainActor
final class ListingAllInPreferenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // A suite of this test's own: the real one belongs to the app and the
        // simulator keeps it between runs.
        suiteName = "listing-all-in-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func model(_ listingID: String) -> ListingPricingModel {
        // No request is made here — every one of these reads the preference
        // and nothing else — so the client only has to exist.
        let client = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://mock.calibre.test")!),
            auth: nil
        )
        return ListingPricingModel(
            listingID: listingID,
            catalog: CatalogStore(client: client),
            commerce: CommerceStore(client: client),
            defaults: defaults
        )
    }

    /// The reported bug, as the two screens that produce it.
    func testTurningItOnCarriesToTheNextWatch() {
        let first = model("watch-one")
        XCTAssertFalse(first.allInShown, "a buyer who has never asked for it should see the listed price")

        first.allInShown = true

        let next = model("watch-two")
        XCTAssertTrue(next.allInShown, "the next watch opened with the toggle back off")
    }

    /// And off is a choice too — turning it off has to carry the same way, or
    /// the fix is a toggle that can only ever be turned on.
    func testTurningItOffCarriesAsWell() {
        let first = model("watch-one")
        first.allInShown = true
        first.allInShown = false

        XCTAssertFalse(model("watch-two").allInShown)
    }

    /// The preference outlives the app. It is stored where the address is, and
    /// a fresh read of the same defaults is what the next launch does.
    func testItSurvivesTheAppBeingClosed() throws {
        model("watch-one").allInShown = true

        let relaunched = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(relaunched.bool(forKey: ListingPricingModel.allInPreferenceKey))
    }

    /// A signed-out visitor, and a watch with no address to price against,
    /// both reset the pricing panel. Neither is the buyer changing their mind,
    /// and a reset that wrote `false` would erase the preference on the way
    /// past — silently, because the toggle is not on screen in either state.
    func testResettingThePanelDoesNotErasePreference() async {
        let model = model("watch-one")
        model.allInShown = true

        await model.load(isAuthenticated: false)

        XCTAssertEqual(model.phase, .listedPriceOnly)
        XCTAssertTrue(model.allInShown, "signing out wiped the buyer's preference")
    }
}
