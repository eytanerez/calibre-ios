import Foundation
import XCTest
@testable import CalibreKit

/// The payload shapes the 2026-08 system-changes build added or altered, each
/// read from a fixture recorded against the pinned contract
/// (Backend/docs/admin-contracts.md §11–§11.8).
final class SystemChangesDecodingTests: XCTestCase {

    // MARK: - Order numbers

    func testOrderCarriesItsHumanNumber() throws {
        let order = try apiDecoder().decode(
            Envelope<Order>.self,
            from: fixtureData("order-return")
        ).data
        XCTAssertEqual(order.orderNumber, 1041)
        XCTAssertEqual(order.displayNumber, "#1041")
    }

    func testOrderWithoutANumberFallsBackToTheUUID() throws {
        // Only ever true of a payload recorded before numbering existed. The
        // uuid stays the API identifier either way.
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "purchased",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD"
        }
        """
        let order = try apiDecoder().decode(Order.self, from: Data(json.utf8))
        XCTAssertNil(order.orderNumber)
        XCTAssertEqual(order.displayNumber, "#49E52179")
    }

    // MARK: - The payout ledger

    func testPayoutBreakdownIsTheServersOwnLedger() throws {
        let order = try apiDecoder().decode(
            Envelope<Order>.self,
            from: fixtureData("order-return")
        ).data
        let breakdown = try XCTUnwrap(order.payoutBlock?.breakdown)
        XCTAssertEqual(breakdown.salePrice?.value, Decimal(string: "10000.00"))
        XCTAssertEqual(breakdown.commission?.percent?.value, Decimal(string: "6.00"))
        XCTAssertEqual(breakdown.commission?.amount?.value, Decimal(string: "600.00"))
        XCTAssertEqual(breakdown.commission?.minimumApplied, false)
        // The label Calibre bought, not one the seller paid for.
        XCTAssertEqual(breakdown.shippingLabel?.value, Decimal(string: "38.40"))
        XCTAssertEqual(breakdown.amount?.value, Decimal(string: "9400.00"))
    }

    func testShippingQuoteAnswersWithThePayoutItWouldLeave() throws {
        let quote = try apiDecoder().decode(
            Envelope<FulfillmentShippingQuote>.self,
            from: fixtureData("fulfillment-shipping-quote")
        ).data
        XCTAssertNil(quote.alreadyCreated)
        XCTAssertEqual(quote.amount?.value, Decimal(string: "38.40"))
        XCTAssertEqual(quote.package?.boxLengthIn?.value, Decimal(string: "9.00"))
        XCTAssertEqual(quote.payoutPreview?.amount?.value, Decimal(string: "9361.60"))
    }

    func testShippingDetailsAnswersWithTheLabelCalibreBought() throws {
        let result = try apiDecoder().decode(
            Envelope<FulfillmentShippingDetails>.self,
            from: fixtureData("fulfillment-shipping-details")
        ).data
        XCTAssertFalse(result.alreadyCreated)
        XCTAssertEqual(result.label?.trackingNumber, "794612345098")
        XCTAssertEqual(result.shipment?.shipmentType, .toAuth)
        // The minimum applying instead of the percentage is a fact the seller
        // is owed, and it rides on the breakdown rather than being inferred.
        XCTAssertEqual(result.payoutPreview?.commission?.minimumApplied, true)
    }

    func testOrderCarriesTheBoxAndTheCarrierLimits() throws {
        let order = try apiDecoder().decode(
            Envelope<Order>.self,
            from: fixtureData("order-return")
        ).data
        let box = try XCTUnwrap(order.sellerLabelPackage)
        XCTAssertFalse(box.isEmpty)
        XCTAssertEqual(box.weightLb?.value, Decimal(string: "2.00"))
        XCTAssertEqual(order.shippingPackageLimits?.maxLengthIn, 22)
        XCTAssertEqual(order.shippingPackageLimits?.maxGirthPlusLengthIn, 130)
    }

    // MARK: - Returns

    func testReturnReasonVocabularyIsExactlyTheSeven() {
        XCTAssertEqual(
            OrderReturnReason.allCases.map(\.rawValue),
            [
                "condition_not_as_described",
                "wrong_reference",
                "missing_box_papers",
                "does_not_fit",
                "changed_mind",
                "arrived_damaged",
                "other",
            ]
        )
        // A note is required on exactly one of them.
        XCTAssertEqual(OrderReturnReason.allCases.filter(\.requiresNote), [.other])
    }

    func testReturnReasonLabelsMatchTheOneVocabularyVerbatim() {
        // Pinned across web, iOS and Android (admin-contracts §11.9), and
        // copied from frontend/src/lib/api.ts::ORDER_RETURN_REASONS. The
        // dashes are em dashes and the apostrophes are typographic; a label
        // that drifts by one character is a label that no longer matches.
        XCTAssertEqual(
            OrderReturnReason.allCases.map(\.label),
            [
                "Not as described \u{2014} condition worse than listed",
                "Not as described \u{2014} wrong reference, model, or year",
                "Missing box, papers, or accessories",
                "Doesn\u{2019}t fit / doesn\u{2019}t suit me",
                "Changed my mind",
                "Arrived damaged",
                "Other",
            ]
        )
    }

    func testReturnQuoteCarriesTheStagedPhotographs() throws {
        let quote = try apiDecoder().decode(
            Envelope<ReturnQuote>.self,
            from: fixtureData("return-quote")
        ).data
        XCTAssertEqual(quote.stagedImages.count, 6)
        XCTAssertEqual(
            quote.stagedImages.compactMap(\.slot),
            ListingImageCategory.allCases
        )
        // Relative media paths are absolutized like every other image.
        XCTAssertEqual(
            quote.stagedImages.first?.url?.url?.absoluteString,
            "https://api.test/media/return_images/o1/front.jpg"
        )
    }

    func testOpenReturnNamesItsReason() throws {
        let order = try apiDecoder().decode(
            Envelope<Order>.self,
            from: fixtureData("order-return")
        ).data
        let summary = try XCTUnwrap(order.returnSummary)
        XCTAssertEqual(summary.reason, .conditionNotAsDescribed)
        XCTAssertEqual(summary.reason?.label, "Not as described \u{2014} condition worse than listed")
        XCTAssertNotNil(summary.reasonNote)
    }

    func testAnUnknownReasonCostsTheReasonAndNotTheScreen() throws {
        // A word this build has never heard of must not take the return
        // screen down with it.
        let json = """
        {"state": "requested", "reason": "abducted_by_aliens"}
        """
        let summary = try apiDecoder().decode(OrderReturnSummary.self, from: Data(json.utf8))
        XCTAssertEqual(summary.state, "requested")
        XCTAssertNil(summary.reason)
    }

    // MARK: - Listings

    func testSellerListingsCarrySKUAndThePausedStatus() throws {
        let listings = try apiDecoder().decode(
            Envelope<[Listing]>.self,
            from: fixtureData("account-listings-seller")
        ).data
        XCTAssertEqual(listings.count, 2)

        let live = try XCTUnwrap(listings.first)
        XCTAssertEqual(live.sellerSku, "CAL-001")
        XCTAssertEqual(live.status, .active)
        // All eight grades, and every one of them the seller's own.
        XCTAssertEqual(live.condition?.caseCondition, "Very Good")
        XCTAssertEqual(live.condition?.dial, "Like New")

        let paused = listings[1]
        XCTAssertEqual(paused.status, .pausedCard)
        XCTAssertEqual(paused.sellerStatus, "paused_card")
        // Never the same thing as archived: Calibre took this one down.
        XCTAssertNotEqual(paused.status, .archived)
        // A half-graded draft reads back with real blanks — nothing is
        // back-filled from the grades that are there.
        XCTAssertNil(paused.condition?.clasp)
        XCTAssertNil(paused.condition?.dial)
        XCTAssertEqual(paused.condition?.crystal, "Like New")
    }

    func testDraftPayloadCarriesTheSKUAndAllEightGradesSeparately() throws {
        let payload = ListingDraftPayload(
            title: "Tudor Black Bay Pro",
            sellerSku: "CAL-001",
            conditionOverall: "Very Good",
            conditionCase: "Good",
            conditionBracelet: "Worn",
            conditionDial: "New",
            conditionBezel: "Very Good",
            conditionCrystal: "Like New",
            conditionClasp: "Good",
            conditionCaseback: "Very Good"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(
            with: try encoder.encode(payload)
        ) as? [String: Any]
        XCTAssertEqual(json?["seller_sku"] as? String, "CAL-001")
        // The case is not the caseback and the dial is not the crystal.
        XCTAssertEqual(json?["condition_case"] as? String, "Good")
        XCTAssertEqual(json?["condition_caseback"] as? String, "Very Good")
        XCTAssertEqual(json?["condition_dial"] as? String, "New")
        XCTAssertEqual(json?["condition_crystal"] as? String, "Like New")
    }

    // MARK: - Import progress

    func testImportJobsCarryTheServedDraftCounters() throws {
        let jobs = try apiDecoder().decode(
            Envelope<[ListingImportJob]>.self,
            from: fixtureData("listing-import-jobs")
        ).data
        XCTAssertEqual(jobs.count, 3)

        let inFlight = jobs[0]
        XCTAssertEqual(inFlight.draftsTotal, 40)
        XCTAssertEqual(inFlight.draftsRemaining, 17)
        XCTAssertEqual(inFlight.draftsFinished, 23)
        // Deliberately not created + updated (34) and not processed_rows (42):
        // one counts rows an import wrote, the other counts rows it read, and
        // neither is the number of listings a seller has finished.
        XCTAssertNotEqual(inFlight.draftsTotal, (inFlight.createdCount ?? 0) + (inFlight.updatedCount ?? 0))

        XCTAssertEqual(jobs[1].draftsRemaining, 0)
        XCTAssertEqual(jobs[1].draftsFinished, 5)

        // A payload written before the counters existed states nothing, and
        // no figure is reconstructed from the counts it does carry.
        XCTAssertNil(jobs[2].draftsTotal)
        XCTAssertNil(jobs[2].draftsRemaining)
        XCTAssertNil(jobs[2].draftsFinished)
    }

    // MARK: - The wire deposit

    func testWireCheckoutCarriesTheDepositAndItsChallenge() throws {
        let wire = try apiDecoder().decode(
            Envelope<WireCheckout>.self,
            from: fixtureData("checkout-create-intent-wire")
        ).data
        let hold = try XCTUnwrap(wire.wireHold)
        XCTAssertEqual(hold.amount?.value, Decimal(string: "250.00"))
        XCTAssertEqual(hold.disclosureKey, WireHold.disclosureKey)
        XCTAssertTrue(hold.requiresAction)
        XCTAssertFalse(hold.isAuthorized)
        XCTAssertEqual(hold.clientSecret, "pi_3PxWireHold001_secret_zzz")
        // A native SDK has to be keyed before it can confirm anything, and
        // the wire path may never have priced a card.
        XCTAssertEqual(hold.publishableKey, "pk_test_calibre")
        // The instructions are already in hand, which is what makes
        // confirming that same intent — rather than opening a second
        // checkout — the whole of what is left to do.
        XCTAssertEqual(wire.wire.instructions?.reference, "CAL-3099-7C21")
    }

    func testAnOrderPaidByWireReportsItsAuthorization() throws {
        let json = """
        {
          "id": "o1", "buyer_id": "b1", "listing_id": "l1", "status": "awaiting_wire",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00", "currency": "USD",
          "wire_hold": {
            "amount": "250.00", "status": "requires_capture",
            "authorized_at": "2026-08-18T09:00:00+00:00",
            "released_at": null, "captured_at": null
          }
        }
        """
        let order = try apiDecoder().decode(Order.self, from: Data(json.utf8))
        let hold = try XCTUnwrap(order.wireHold)
        XCTAssertTrue(hold.isLive)
        XCTAssertEqual(hold.amount?.value, Decimal(string: "250.00"))
    }

    // MARK: - The seller's effective rate

    func testDealerApplicationPrefersTheServersResolvedRate() throws {
        let result = try apiDecoder().decode(
            Envelope<DealerApplicationResult>.self,
            from: fixtureData("dealer-application")
        ).data
        // A negotiated override, which neither published tier rate would
        // have produced.
        XCTAssertEqual(result.application.effectiveFeePercent?.value, Decimal(string: "5.50"))
        XCTAssertEqual(result.application.memberFeePercent?.value, Decimal(string: "6.00"))
    }

    func testDealerApplicationFallsBackToTheTierRate() throws {
        let json = """
        {"status": "verified", "member_fee_percent": "6.00", "dealer_fee_percent": "4.00"}
        """
        let application = try apiDecoder().decode(DealerApplication.self, from: Data(json.utf8))
        XCTAssertEqual(application.effectiveFeePercent?.value, Decimal(string: "4.00"))
    }

    // MARK: - Support attachments

    func testSupportMessageCarriesItsAttachments() throws {
        let thread = try apiDecoder().decode(
            Envelope<SupportConversation>.self,
            from: fixtureData("support-thread-attachments")
        ).data
        let message = try XCTUnwrap(thread.messages.first)
        XCTAssertEqual(message.attachments.count, 2)
        XCTAssertTrue(message.attachments[0].isImage)
        XCTAssertTrue(message.attachments[1].isPDF)
        XCTAssertNotNil(message.attachments[0].sizeText)
        XCTAssertEqual(SupportAttachment.maxBytesPerFile, 10 * 1024 * 1024)
        XCTAssertEqual(SupportAttachment.maxBytesPerMessage, 20 * 1024 * 1024)
    }

    func testAMessageWithoutAttachmentsStillDecodes() throws {
        let json = """
        {"id": "m1", "sender": "admin", "body": "On it.", "created_at": null}
        """
        let message = try apiDecoder().decode(SupportMessage.self, from: Data(json.utf8))
        XCTAssertTrue(message.attachments.isEmpty)
    }
}
