import RewoundKit
import Foundation
import XCTest
@testable import Rewound

/// The two things `CheckoutModel` had to keep after checkout moved from an
/// inline card field to Stripe's PaymentSheet:
///
/// * the funding gate. `confirmForPaymentSheet` is what PaymentSheet's
///   deferred confirm handler calls once the buyer taps its own Pay button —
///   a refusal has to throw from there, naming credit-only and wire, so
///   Stripe can show it inside the sheet it owns.
/// * test-mode detection. The review step's banner is driven by
///   `isTestModePayment`, derived from the publishable key the server priced
///   the checkout with — never `#if DEBUG` — so it has to answer correctly
///   for both a `pk_test_` and a `pk_live_` key.
///
/// `CheckoutMockURLProtocol` and its `priced(_:)`-shaped fixture are borrowed
/// from `CheckoutRecoveryTests`, which defines the transport this suite
/// reuses.
@MainActor
final class CheckoutPaymentSheetTests: XCTestCase {
    /// `static`, not an instance property: `CheckoutMockURLProtocol`'s
    /// handler closure is nonisolated, and the fixture builders below run
    /// inside it — a plain `let` here would make them main-actor-isolated
    /// and uncallable from that closure.
    private static let watch = "49e52179-1035-46f9-abe0-443d915d8c3b"
    private var watch: String { Self.watch }

    override func tearDown() {
        CheckoutMockURLProtocol.reset()
        super.tearDown()
    }

    private func model(publishableKey: String) -> CheckoutModel {
        let client = APIClient(configuration: CheckoutMockURLProtocol.configuration(), auth: nil)
        let model = CheckoutModel(
            listingIDs: [watch],
            offerID: nil,
            catalog: CatalogStore(client: client),
            commerce: CommerceStore(client: client),
            client: client
        )
        model.selectedAddressID = "addr-1"
        return model
    }

    /// The same shape `CheckoutRecoveryTests.priced(_:)` uses, with the
    /// publishable key exposed as a parameter since that is exactly what
    /// this suite varies. `nonisolated static`, like its two siblings below:
    /// `CheckoutMockURLProtocol`'s handler closure is nonisolated, and these
    /// are what build the bodies it returns.
    nonisolated private static func pricedResponse(publishableKey: String) -> Data {
        Data("""
        {"ok": true, "data": {
          "payment_intent": {"id": "pi_test", "client_secret": "pi_test_secret"},
          "publishable_key": "\(publishableKey)",
          "customer_id": "cus_test",
          "breakdown_group": {
            "items": [{"listing_id": "\(watch)", "subtotal": "4400.00", "shipping": "72.00",
                       "grand_total": "4645.52", "currency": "USD"}],
            "combined": {"subtotal": "4400.00", "shipping": "72.00", "grand_total": "4645.52",
                         "currency": "USD", "item_count": 1}
          }
        }}
        """.utf8)
    }

    nonisolated private static func validationResponse(accepted: Bool, reason: String? = nil) -> Data {
        let reasonJSON = reason.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {"ok": true, "data": {"accepted": \(accepted), "reason": \(reasonJSON)}}
        """.utf8)
    }

    nonisolated private static func confirmResponse(requiresAction: Bool = false) -> Data {
        Data("""
        {"ok": true, "data": {"status": "succeeded", "requires_action": \(requiresAction)}}
        """.utf8)
    }

    // MARK: - The funding gate inside the deferred confirm handler

    /// PaymentSheet's confirm handler calls this the moment the buyer taps
    /// its own Pay button, with the PaymentMethod it just created — for a
    /// card the server judges is not credit, this has to throw a message
    /// PaymentSheet can show inside its own sheet, naming the way out.
    func testConfirmForPaymentSheetRefusesADebitCard() async throws {
        let model = model(publishableKey: "pk_test_rewound")
        CheckoutMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/checkout/payment-intent":
                return (200, Self.pricedResponse(publishableKey: "pk_test_rewound"))
            case "/checkout/validate-payment-method":
                return (200, Self.validationResponse(accepted: false, reason: "debit_not_accepted_in_state"))
            default:
                return (404, Data())
            }
        }

        await model.prepareCardIntent()
        XCTAssertNotNil(model.cardIntent, "the intent has to exist before a confirm handler could ever be called")

        do {
            _ = try await model.confirmForPaymentSheet(paymentMethodID: "pm_debit")
            XCTFail("a debit card must not confirm")
        } catch let error as LocalizedError {
            let message = (error.errorDescription ?? "").lowercased()
            XCTAssertTrue(message.contains("credit"), "the refusal has to name the way out: credit cards. Got: \(message)")
            XCTAssertTrue(message.contains("wire"), "the refusal has to name the way out: wire, at any price. Got: \(message)")
        }

        XCTAssertEqual(
            CheckoutMockURLProtocol.seen(path: "/checkout/confirm"), 0,
            "a refused card must never reach the server's confirm — the gate stops it first"
        )
    }

    /// The same handler, for a card the server accepts: it has to confirm
    /// and hand PaymentSheet the PaymentIntent's own client secret, so the
    /// SDK can finish the payment (and any 3-D Secure challenge) itself.
    func testConfirmForPaymentSheetConfirmsAnAcceptedCard() async throws {
        let model = model(publishableKey: "pk_test_rewound")
        CheckoutMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/checkout/payment-intent":
                return (200, Self.pricedResponse(publishableKey: "pk_test_rewound"))
            case "/checkout/validate-payment-method":
                return (200, Self.validationResponse(accepted: true))
            case "/checkout/confirm":
                return (200, Self.confirmResponse())
            default:
                return (404, Data())
            }
        }

        await model.prepareCardIntent()
        let secret = try await model.confirmForPaymentSheet(paymentMethodID: "pm_credit")

        XCTAssertEqual(secret, "pi_test_secret", "PaymentSheet needs the PaymentIntent's own client secret back")
        XCTAssertEqual(CheckoutMockURLProtocol.seen(path: "/checkout/confirm"), 1)
    }

    // MARK: - Test-mode detection

    /// The review step's test-mode banner reads `isTestModePayment`, and it
    /// has to be true the moment the checkout is priced against a `pk_test_`
    /// key — derived from the key itself, never from `#if DEBUG`.
    func testIsTestModePaymentTrueForATestKey() async {
        let model = model(publishableKey: "pk_test_rewound")
        CheckoutMockURLProtocol.setHandler { request in
            guard request.url?.path == "/checkout/payment-intent" else { return (404, Data()) }
            return (200, Self.pricedResponse(publishableKey: "pk_test_rewound"))
        }

        await model.prepareCardIntent()

        XCTAssertTrue(model.isTestModePayment)
    }

    /// The same checkout, priced against a live key, must never show the
    /// banner — a real-looking total in a build pointed at production has to
    /// stay quiet.
    func testIsTestModePaymentFalseForALiveKey() async {
        let model = model(publishableKey: "pk_live_rewound")
        CheckoutMockURLProtocol.setHandler { request in
            guard request.url?.path == "/checkout/payment-intent" else { return (404, Data()) }
            return (200, Self.pricedResponse(publishableKey: "pk_live_rewound"))
        }

        await model.prepareCardIntent()

        XCTAssertFalse(model.isTestModePayment)
    }

    // MARK: - The key-prefix check itself

    func testRewoundStripeIsTestKey() {
        XCTAssertTrue(RewoundStripe.isTestKey("pk_test_51ABC"))
        XCTAssertFalse(RewoundStripe.isTestKey("pk_live_51ABC"))
        XCTAssertFalse(RewoundStripe.isTestKey(nil))
        XCTAssertFalse(RewoundStripe.isTestKey(""))
    }
}
