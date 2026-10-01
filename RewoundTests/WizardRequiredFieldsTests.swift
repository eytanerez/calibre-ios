import XCTest

@testable import Rewound

/// Model and reference became required on the first step (5cb9343), and
/// Continue refusing over them has to land on them.
///
/// `firstInvalidField` is what Continue scrolls to and what it speaks to a
/// screen reader. When the two new requirements were added it still knew only
/// brand, year and the grades, so a missing model scrolled to the first
/// ungraded part (or nowhere) and VoiceOver said nothing about the model.
@MainActor
final class WizardRequiredFieldsTests: XCTestCase {
    private func wizard() -> WizardModel {
        // No request is made: these only read the model's own fields.
        let services = AppServices()
        return WizardModel(
            kind: .new(prefill: nil),
            seller: services.seller,
            sell: SellSession(services: services),
            config: services.config,
            vault: services.vault
        )
    }

    func testAMissingModelIsWhereContinueLands() {
        let model = wizard()
        model.brand = "Rolex"
        model.reference = "126610LN"
        model.markAttempted(0)

        XCTAssertEqual(model.modelError, "Enter the model.")
        XCTAssertEqual(model.firstInvalidField(onStep: 0), .model)
    }

    func testAMissingReferenceIsWhereContinueLands() {
        let model = wizard()
        model.brand = "Rolex"
        model.model = "Submariner"
        model.markAttempted(0)

        XCTAssertEqual(model.referenceError, "Enter the reference number.")
        XCTAssertEqual(model.firstInvalidField(onStep: 0), .reference)
    }

    /// Top to bottom, as the fields sit on screen: brand, then model, then
    /// reference, then the year.
    func testTheFieldsAreVisitedInScreenOrder() {
        let model = wizard()
        model.markAttempted(0)
        XCTAssertEqual(model.firstInvalidField(onStep: 0), .brand)

        model.brand = "Rolex"
        XCTAssertEqual(model.firstInvalidField(onStep: 0), .model)

        model.model = "Submariner"
        XCTAssertEqual(model.firstInvalidField(onStep: 0), .reference)

        model.reference = "126610LN"
        XCTAssertNotEqual(model.firstInvalidField(onStep: 0), .reference)
        XCTAssertNil(model.modelError)
        XCTAssertNil(model.referenceError)
    }
}
