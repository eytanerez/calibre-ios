import XCTest
@testable import RewoundKit

/// The stand-in models the loading skeletons draw real views with.
///
/// `VaultWatch.skeleton` decodes a fixed literal with `try!`, so this is the
/// test that keeps it from ever crashing a screen that is only trying to show
/// it is loading.
final class SkeletonStandInTests: XCTestCase {
    func testTheVaultStandInDecodesAndIsNumbered() {
        let first = VaultWatch.skeleton(0)
        let third = VaultWatch.skeleton(3)
        XCTAssertEqual(first.id, "skeleton-0")
        XCTAssertEqual(third.id, "skeleton-3")
        // A row's shape depends on these: the authenticated chip, the brand
        // line, the title and the value line.
        XCTAssertTrue(first.authenticated)
        XCTAssertEqual(first.brand, "Brand")
        XCTAssertNotNil(first.estimatedValue)
    }

    func testTheCommunityStandInIsTheShapeOfATodayQuestion() {
        let prompt = CommunityPrompt.skeleton(kind: .siteFeedback)
        XCTAssertEqual(prompt.kind, "site_feedback")
        XCTAssertEqual(prompt.options.count, 3)
        XCTAssertFalse(prompt.closed)
        XCTAssertNil(prompt.myVote)
    }
}
