import Foundation
import XCTest
@testable import CalibreKit

/// `POST /billing/setup-intent` — real shape confirmed against
/// Backend/docs/mobile-api.md §"POST /billing/setup-intent (response
/// extended)" and Backend/app/api/views/offers.py's
/// `AccountBillingSetupIntentView`. Two traps the earlier synthetic sample
/// got wrong: the CustomerSession secret PaymentSheet needs lives at
/// `customer_session_mobile.client_secret` (the flat `customer_session` is
/// web-only and won't work with PaymentSheet), and the payload also carries
/// the buyer's *current* card (`payment_method`, stale until the async
/// webhook lands).
final class PaymentMethodDecodingTests: XCTestCase {
    func testBillingSetupIntentDecodes() throws {
        let json = """
        {
          "setup_intent": {"id": "seti_1", "client_secret": "seti_1_secret_xyz", "status": "requires_payment_method"},
          "customer_session": {"client_secret": "web_cuss_secret", "expires_at": 0},
          "customer_session_mobile": {"client_secret": "mobile_cuss_secret", "expires_at": 1234567890},
          "customer_id": "cus_9",
          "publishable_key": "pk_test_123",
          "payment_method": {"id": "pm_1", "brand": "visa", "last4": "4242", "exp_month": 12, "exp_year": 2034, "added_at": null}
        }
        """
        let intent = try apiDecoder().decode(BillingSetupIntent.self, from: Data(json.utf8))
        XCTAssertEqual(intent.setupIntent.id, "seti_1")
        XCTAssertEqual(intent.setupIntent.clientSecret, "seti_1_secret_xyz")
        XCTAssertEqual(intent.publishableKey, "pk_test_123")
        XCTAssertEqual(intent.customerId, "cus_9")
        // Must read the mobile-specific secret, never the flat/web one.
        XCTAssertEqual(intent.customerSessionMobile?.clientSecret, "mobile_cuss_secret")
        XCTAssertEqual(intent.paymentMethod?.id, "pm_1")
        XCTAssertEqual(intent.paymentMethod?.last4, "4242")
    }

    func testBillingSetupIntentWithNullCustomerSessionMobileAndNilPaymentMethodDecodes() throws {
        // Stripe hiccuped and no mobile CustomerSession was minted; the buyer
        // has no card on file yet. PaymentSheet still works without a
        // CustomerSession — just without the saved-payment-method UI polish.
        let json = """
        {
          "setup_intent": {"id": "seti_2", "client_secret": "seti_2_secret", "status": "requires_payment_method"},
          "customer_session": {"client_secret": "web_cuss_secret", "expires_at": 0},
          "customer_session_mobile": null,
          "customer_id": "cus_9",
          "publishable_key": "pk_test_123",
          "payment_method": null
        }
        """
        let intent = try apiDecoder().decode(BillingSetupIntent.self, from: Data(json.utf8))
        XCTAssertEqual(intent.setupIntent.id, "seti_2")
        XCTAssertNil(intent.customerSessionMobile)
        XCTAssertNil(intent.paymentMethod)
    }
}

/// `GET /account/payment-method` — a wrapper envelope, not a bare
/// `SavedPaymentMethod?`, confirmed against `AccountPaymentMethodView.get`
/// in Backend/app/api/views/offers.py.
final class PaymentMethodInfoDecodingTests: XCTestCase {
    func testPaymentMethodInfoWithCardDecodes() throws {
        let json = """
        {
          "stripe_customer_id": "cus_9",
          "payment_method": {"id": "pm_1", "brand": "visa", "last4": "4242", "exp_month": 12, "exp_year": 2034, "added_at": "2026-01-01T00:00:00Z"},
          "can_remove": true,
          "remove_blocked_reason": null
        }
        """
        let info = try apiDecoder().decode(PaymentMethodInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.stripeCustomerId, "cus_9")
        XCTAssertEqual(info.paymentMethod?.id, "pm_1")
        XCTAssertEqual(info.paymentMethod?.brand, "visa")
        XCTAssertTrue(info.canRemove)
        XCTAssertNil(info.removeBlockedReason)
    }

    func testPaymentMethodInfoWithNoCardAndBlockedRemovalDecodes() throws {
        let json = """
        {
          "stripe_customer_id": null,
          "payment_method": null,
          "can_remove": false,
          "remove_blocked_reason": "Active offer holds or accepted unpaid offers require a card on file."
        }
        """
        let info = try apiDecoder().decode(PaymentMethodInfo.self, from: Data(json.utf8))
        XCTAssertNil(info.stripeCustomerId)
        XCTAssertNil(info.paymentMethod)
        XCTAssertFalse(info.canRemove)
        XCTAssertEqual(info.removeBlockedReason, "Active offer holds or accepted unpaid offers require a card on file.")
    }
}

/// `CommerceStore.setupIntent()` / `CommerceStore.paymentMethod()` — confirm
/// they POST/GET the right path and unwrap the envelope, the same contract
/// every other store method relies on (see `APIClientTests`).
final class CommerceStorePaymentMethodTests: XCTestCase {
    private func mockConfiguration() -> APIConfiguration {
        APIConfiguration(
            baseURL: URL(string: "https://mock.calibre.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
    }

    @MainActor
    func testSetupIntentPostsToBillingSetupIntent() async throws {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/billing/setup-intent")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = Data("""
            {"ok": true, "data": {
              "setup_intent": {"id": "seti_1", "client_secret": "seti_1_secret_xyz", "status": "requires_payment_method"},
              "customer_session": {"client_secret": "web_cuss_secret", "expires_at": 0},
              "customer_session_mobile": {"client_secret": "mobile_cuss_secret", "expires_at": 0},
              "customer_id": "cus_9",
              "publishable_key": "pk_test_123",
              "payment_method": null
            }}
            """.utf8)
            return (200, body)
        }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        let commerce = CommerceStore(client: client)
        let intent = try await commerce.setupIntent()

        XCTAssertEqual(intent.setupIntent.clientSecret, "seti_1_secret_xyz")
        XCTAssertEqual(intent.publishableKey, "pk_test_123")
        XCTAssertEqual(intent.customerSessionMobile?.clientSecret, "mobile_cuss_secret")
    }

    @MainActor
    func testPaymentMethodGetsAccountPaymentMethodAndUnwrapsEnvelope() async throws {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/account/payment-method")
            XCTAssertEqual(request.httpMethod, "GET")
            let body = Data("""
            {"ok": true, "data": {
              "stripe_customer_id": "cus_9",
              "payment_method": {"id": "pm_1", "brand": "visa", "last4": "4242", "exp_month": 12, "exp_year": 2034, "added_at": null},
              "can_remove": true,
              "remove_blocked_reason": null
            }}
            """.utf8)
            return (200, body)
        }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        let commerce = CommerceStore(client: client)
        let info = try await commerce.paymentMethod()

        XCTAssertEqual(info.paymentMethod?.last4, "4242")
        XCTAssertTrue(info.canRemove)
    }
}
