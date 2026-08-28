import XCTest
@testable import CalibreKit

/// Record references in a support message body (contracts §12.9b).
///
/// Two promises are under test rather than one. That a record this customer
/// picked leaves the phone in the wire form all four clients agree on, and that
/// a body containing anything else — a legacy console path, a kind this build
/// has never heard of — reaches a reader as words rather than as markup.
final class RecordRefTests: XCTestCase {
    private let orderID = "9f3c0f1e-0000-4000-8000-000000000001"
    private let listingID = "9f3c0f1e-0000-4000-8000-000000000002"

    func testTargetIsSchemeQualifiedRatherThanAPath() {
        XCTAssertEqual(
            RecordRef(kind: .order, recordID: orderID, label: "Order #13").target,
            "calibre:order/\(orderID)"
        )
        XCTAssertEqual(
            RecordRef(kind: .listing, recordID: listingID, label: "Speedmaster").target,
            "calibre:listing/\(listingID)"
        )
    }

    func testAReferenceParsesIntoItsKindAndItsLabel() {
        let parts = RecordRefs.parts("Shipped — [Order #13](calibre:order/\(orderID)) has tracking.")
        XCTAssertEqual(parts.count, 3)
        guard case .reference(let ref) = parts[1] else {
            return XCTFail("the middle part is the reference")
        }
        XCTAssertEqual(ref.kind, .order)
        XCTAssertEqual(ref.recordID, orderID)
        XCTAssertEqual(ref.label, "Order #13")
        XCTAssertEqual(ref.route?.absoluteString, "calibre://order/\(orderID)")
    }

    func testAKindThisBuildDoesNotKnowDegradesToItsLabel() {
        let parts = RecordRefs.parts("See [Invoice 4](calibre:invoice/abc) please.")
        XCTAssertFalse(parts.contains { if case .reference = $0 { return true } else { return false } })
        XCTAssertEqual(RecordRefs.flatten("See [Invoice 4](calibre:invoice/abc) please."), "See Invoice 4 please.")
    }

    func testALegacyConsolePathFlattensRatherThanReachingACustomer() {
        let body = "Shipped — [Order 13](/orders/\(orderID)) has tracking."
        XCTAssertEqual(RecordRefs.flatten(body), "Shipped — Order 13 has tracking.")
        XCTAssertTrue(RecordRefs.references(in: body).isEmpty)
    }

    func testProseThatMerelyContainsBracketsIsLeftAlone() {
        let body = "I wrote [see photo] on the box."
        XCTAssertEqual(RecordRefs.flatten(body), body)
    }

    func testComposeReattachesThePickedRecordToTheWordsItWroteIn() {
        let ref = RecordRef(kind: .order, recordID: orderID, label: "Order #13")
        XCTAssertEqual(
            RecordRefs.compose(text: "Any update on Order #13 please?", refs: [ref]),
            "Any update on [Order #13](calibre:order/\(orderID)) please?"
        )
    }

    func testComposeGivesEachPickItsOwnOccurrence() {
        let order = RecordRef(kind: .order, recordID: orderID, label: "Order #13")
        let listing = RecordRef(kind: .listing, recordID: listingID, label: "Speedmaster")
        let composed = RecordRefs.compose(
            text: "Order #13 is the Speedmaster",
            refs: [order, listing]
        )
        XCTAssertEqual(
            composed,
            "[Order #13](calibre:order/\(orderID)) is the [Speedmaster](calibre:listing/\(listingID))"
        )
    }

    /// The customer deleted the words the chip was made of. What they are left
    /// with is the sentence they actually wrote — which is what the format
    /// degrades to anyway, so nothing is lost that they had not already removed.
    func testARecordWhoseWordsWereEditedAwayIsDropped() {
        let ref = RecordRef(kind: .order, recordID: orderID, label: "Order #13")
        XCTAssertEqual(
            RecordRefs.compose(text: "Never mind, sorted.", refs: [ref]),
            "Never mind, sorted."
        )
    }

    /// A body that names nothing must come back byte-identical: the composer
    /// runs `compose` over every message, not only the ones with a chip in them.
    func testAPlainMessageIsUntouched() {
        XCTAssertEqual(RecordRefs.compose(text: "Hello — is anyone there?", refs: []), "Hello — is anyone there?")
    }
}
