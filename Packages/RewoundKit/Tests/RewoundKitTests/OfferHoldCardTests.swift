import Foundation
import XCTest
@testable import CalibreKit

/// What `POST /listings/<id>/offers` is actually sent, and what comes back
/// when the card behind the $250 deposit is refused.
///
/// Both halves are wire contracts the offer screen is built on: it sends the
/// card up front so a refusal can arrive before anything is authorized, and
/// it reads the funding type out of the 402 to say *which* kind of card it
/// was. Neither is visible from a screenshot, and both break silently.
final class OfferHoldCardTests: XCTestCase {
    private static let offerResponse = Data("""
        {"ok": true, "data": {
            "id": "o1", "listing_id": "l1", "buyer_id": "b1", "seller_id": "s1",
            "amount": "8700.00", "currency": "USD", "status": "hold_pending",
            "negotiation_history": [],
            "hold": {"amount": "250.00", "currency": "USD", "client_secret": "pi_1_secret"},
            "publishable_key": "pk_test_1"
        }}
        """.utf8)

    /// The card the buyer chose rides along with the offer, and so does the
    /// consent. `penalty_consent` is not decoration: `ListingOfferCreatePayload`
    /// refuses the whole request without it, which is exactly how iOS offers
    /// were failing before the field was sent at all.
    @MainActor
    func testCreateOfferSendsConsentAndTheChosenCard() async throws {
        let seen = SeenOfferRequest()
        let response = Self.offerResponse
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (201, response)
        }
        let commerce = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        _ = try await commerce.createOffer(
            listingID: "l1",
            amount: 8700,
            currency: "USD",
            message: "Ready when you are",
            penaltyConsent: true,
            paymentMethodID: "pm_123"
        )

        XCTAssertEqual(seen.path, "/listings/l1/offers")
        let body = seen.jsonBody
        XCTAssertEqual(body["penalty_consent"] as? Bool, true)
        XCTAssertEqual(body["payment_method_id"] as? String, "pm_123")
        XCTAssertEqual(body["amount"] as? String, "8700")
        XCTAssertEqual(body["currency"] as? String, "USD")
        XCTAssertEqual(body["buyer_message"] as? String, "Ready when you are")
    }

    /// With no card to offer, the key is absent rather than null — the older
    /// shape, where the deposit is checked only once it has been authorized.
    /// A `payment_method_id: null` would read the same to the server today,
    /// but "we did not collect a card" and "we collected nothing" are
    /// different claims and only one of them is true.
    @MainActor
    func testCreateOfferOmitsTheCardWhenThereIsNoneYet() async throws {
        let seen = SeenOfferRequest()
        let response = Self.offerResponse
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (201, response)
        }
        let commerce = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        _ = try await commerce.createOffer(
            listingID: "l1",
            amount: 8700,
            penaltyConsent: true
        )

        let body = seen.jsonBody
        XCTAssertNil(body["payment_method_id"])
        XCTAssertEqual(body["penalty_consent"] as? Bool, true)
    }

    /// The refusal the offer screen reads. Both fields matter: the code
    /// decides the sentence, and `funding` is the only place the word
    /// "prepaid" can honestly come from — the client never guesses it.
    @MainActor
    func testPrepaidRefusalCarriesItsCodeAndFunding() async throws {
        MockURLProtocol.setHandler { _ in
            (402, Data("""
            {"ok": false,
             "error": "Making an offer needs a credit card; debit and prepaid cards cannot carry the refundable $250 hold.",
             "details": {"code": "offer_hold_card_must_be_credit",
                         "funding": "prepaid",
                         "accepted_card_funding": ["credit"]}}
            """.utf8))
        }
        let commerce = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        do {
            _ = try await commerce.createOffer(
                listingID: "l1",
                amount: 8700,
                penaltyConsent: true,
                paymentMethodID: "pm_prepaid"
            )
            XCTFail("A prepaid card must not produce an offer.")
        } catch let error as APIError {
            guard case .server(let message, let code, let status, let details) = error else {
                return XCTFail("Expected a server error, got \(error)")
            }
            XCTAssertEqual(status, 402)
            XCTAssertEqual(code, "offer_hold_card_must_be_credit")
            XCTAssertEqual(details?["funding"], "prepaid")
            XCTAssertTrue(message.contains("credit card"))
        }
    }

    /// The other refusal: Stripe could not be asked about the card. It has no
    /// funding to name, and the screen has to cope with that rather than
    /// printing an empty word into the middle of a sentence.
    @MainActor
    func testUnreadableCardRefusalNamesNoFunding() async throws {
        MockURLProtocol.setHandler { _ in
            (402, Data("""
            {"ok": false,
             "error": "We could not confirm what kind of card this is, and the refundable $250 offer hold needs a credit card. Try another card.",
             "details": {"code": "offer_hold_card_required",
                         "funding": null,
                         "accepted_card_funding": ["credit"]}}
            """.utf8))
        }
        let commerce = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        do {
            _ = try await commerce.createOffer(
                listingID: "l1",
                amount: 8700,
                penaltyConsent: true,
                paymentMethodID: "pm_unknown"
            )
            XCTFail("An unreadable card must not produce an offer.")
        } catch let error as APIError {
            XCTAssertEqual(error.serverCode, "offer_hold_card_required")
            guard case .server(_, _, let status, let details) = error else {
                return XCTFail("Expected a server error, got \(error)")
            }
            XCTAssertEqual(status, 402)
            // A null funding must not arrive as the string "null".
            XCTAssertNil(details?["funding"])
        }
    }
}

/// The one request the mock saw. The handler runs on URLSession's thread, so
/// every field is lock-guarded, and the body is drained while the handler
/// still has it — `httpBody` is nil by the time a request reaches a
/// URLProtocol.
private final class SeenOfferRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var body: Data?

    func record(_ request: URLRequest) {
        let drained = request.httpBody ?? request.httpBodyStream.map(drainHTTPBodyStream)
        lock.withLock {
            self.request = request
            self.body = drained
        }
    }

    var path: String? { lock.withLock { request?.url?.path } }

    var jsonBody: [String: Any] {
        let data = lock.withLock { body }
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }
}
