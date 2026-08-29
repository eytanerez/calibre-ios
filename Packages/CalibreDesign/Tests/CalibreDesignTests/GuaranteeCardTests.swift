import XCTest

@testable import CalibreDesign

/// The guarantee card draws every brand mark locally, because Stripe's API
/// carries no imagery for payment cards. That makes the brand string the only
/// thing standing between a seller and a card wearing somebody else's mark.
final class GuaranteeCardTests: XCTestCase {
    func testStripeBrandSpellingsMapToTheirMarks() {
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: "visa"), .visa)
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: "mastercard"), .mastercard)
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: "discover"), .discover)
        // Stripe says "amex" on a PaymentMethod and "American Express" in
        // places that render for humans; both reach this initializer.
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: "amex"), .amex)
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: "American Express"), .amex)
    }

    func testBrandMatchingIgnoresCase() {
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: "VISA"), .visa)
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: "MasterCard"), .mastercard)
    }

    /// A network we have no drawing for gets the plain card device. Falling
    /// through to any *particular* brand would put a mark on the seller's card
    /// that isn't theirs, and it would look entirely convincing.
    func testUnknownNetworksGetThePlainDeviceRatherThanAGuess() {
        for unknown in ["jcb", "unionpay", "diners", "cartes_bancaires", "", "  "] {
            XCTAssertEqual(
                GuaranteeCard.Brand(stripeBrand: unknown),
                .other,
                "\(unknown) should not be drawn as a named network"
            )
        }
        XCTAssertEqual(GuaranteeCard.Brand(stripeBrand: nil), .other)
    }

    /// VoiceOver reads the brand out of the card's label. An unknown network
    /// must not be spoken as a named one either.
    func testTheUnknownBrandIsNotSpokenAsANetwork() {
        let spoken = GuaranteeCard.Brand.other.spokenName
        for named in ["visa", "mastercard", "american express", "discover"] {
            XCTAssertFalse(
                spoken.lowercased().contains(named),
                "the unknown brand should not be announced as \(named)"
            )
        }
    }
}
