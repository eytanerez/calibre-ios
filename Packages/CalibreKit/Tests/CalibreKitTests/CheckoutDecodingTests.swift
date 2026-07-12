import Foundation
import XCTest
@testable import CalibreKit

/// Synthetic wire samples for the checkout models, hand-built from
/// `CheckoutPaymentIntentView` / `CheckoutIntentView` in
/// app/api/views/orders.py (no recorded fixture exists yet — creating one
/// would create a real Stripe PaymentIntent per record run).
final class CheckoutDecodingTests: XCTestCase {

    func testNativeCheckoutIntentDecodes() throws {
        let json = """
        {
          "payment_intent": {"id": "pi_3Nabc", "client_secret": "pi_3Nabc_secret_xyz"},
          "publishable_key": "pk_test_123",
          "customer_id": "cus_9",
          "customer_session_client_secret": "cuss_secret",
          "breakdown": {
            "subtotal": "1000.00",
            "fees": "33.60",
            "card_convenience_fee": "33.60",
            "card_convenience_fee_percent": "3.00",
            "payment_method": "card",
            "seller_fee_percent_applied": "8.00",
            "seller_fee_amount": "80.00",
            "shipping": "120.00",
            "tax": "40.00",
            "tax_calculated_upfront": true,
            "grand_total": "1193.60",
            "currency": "USD",
            "shipping_provider": "mock",
            "offer_id": null
          }
        }
        """
        let intent = try apiDecoder().decode(NativeCheckoutIntent.self, from: Data(json.utf8))
        XCTAssertEqual(intent.paymentIntent.id, "pi_3Nabc")
        XCTAssertEqual(intent.paymentIntent.clientSecret, "pi_3Nabc_secret_xyz")
        XCTAssertEqual(intent.publishableKey, "pk_test_123")
        XCTAssertEqual(intent.customerId, "cus_9")
        XCTAssertEqual(intent.customerSessionClientSecret, "cuss_secret")
        XCTAssertEqual(intent.breakdown.subtotal.value, Decimal(string: "1000.00"))
        XCTAssertEqual(intent.breakdown.cardConvenienceFee?.value, Decimal(string: "33.60"))
        XCTAssertEqual(intent.breakdown.cardConvenienceFeePercent?.value, Decimal(string: "3.00"))
        XCTAssertEqual(intent.breakdown.shipping.value, Decimal(120))
        XCTAssertEqual(intent.breakdown.tax?.value, Decimal(40))
        XCTAssertEqual(intent.breakdown.grandTotal.value, Decimal(string: "1193.60"))
        XCTAssertEqual(intent.breakdown.taxCalculatedUpfront, true)
        XCTAssertNil(intent.breakdown.offerId)
    }

    func testNativeCheckoutIntentNullCustomerSessionDecodes() throws {
        let json = """
        {
          "payment_intent": {"id": "pi_1", "client_secret": "pi_1_secret"},
          "publishable_key": "pk_test_123",
          "customer_id": "cus_9",
          "customer_session_client_secret": null,
          "breakdown": {
            "subtotal": "500.00", "fees": "16.80", "payment_method": "card",
            "shipping": "60.00", "grand_total": "576.80", "currency": "USD"
          }
        }
        """
        let intent = try apiDecoder().decode(NativeCheckoutIntent.self, from: Data(json.utf8))
        XCTAssertNil(intent.customerSessionClientSecret)
        XCTAssertNil(intent.breakdown.tax)
        XCTAssertEqual(intent.breakdown.grandTotal.value, Decimal(string: "576.80"))
    }

    func testWireCheckoutDecodes() throws {
        let json = """
        {
          "session": {"id": null, "client_secret": null, "expires_at": 1789000000},
          "wire": {
            "payment_intent_id": "pi_wire_1",
            "status": "requires_action",
            "instructions": {
              "type": "us_bank_transfer",
              "reference": "CALIBRE-3099",
              "amount_remaining": "4532.00",
              "currency": "USD",
              "hosted_instructions_url": "https://payments.stripe.com/instructions/x",
              "financial_addresses": [
                {
                  "type": "aba",
                  "supported_networks": ["ach", "domestic_wire_us"],
                  "aba": {
                    "account_holder_type": "company",
                    "account_number": "000123456789",
                    "account_type": "checking",
                    "bank_name": "Test Bank",
                    "routing_number": "110000000"
                  }
                },
                {
                  "type": "swift",
                  "supported_networks": ["swift"],
                  "swift": {
                    "account_number": "000123456789",
                    "bank_name": "Test Bank",
                    "swift_code": "TSTEUS66XXX"
                  }
                }
              ]
            }
          },
          "breakdown": {
            "subtotal": "4400.00", "fees": "0.00", "payment_method": "wire",
            "shipping": "72.00", "tax": "60.00", "tax_calculated_upfront": true,
            "grand_total": "4532.00", "currency": "USD"
          }
        }
        """
        let checkout = try apiDecoder().decode(WireCheckout.self, from: Data(json.utf8))
        XCTAssertEqual(checkout.wire.paymentIntentId, "pi_wire_1")
        XCTAssertEqual(checkout.wire.status, "requires_action")
        XCTAssertEqual(checkout.session?.expiresAt, 1_789_000_000)
        XCTAssertNotNil(checkout.session?.expiresAtDate)

        let instructions = try XCTUnwrap(checkout.wire.instructions)
        XCTAssertEqual(instructions.reference, "CALIBRE-3099")
        XCTAssertEqual(instructions.amountRemaining?.value, Decimal(4532))
        XCTAssertEqual(instructions.financialAddresses.count, 2)

        let aba = try XCTUnwrap(instructions.financialAddresses.first?.details)
        XCTAssertEqual(aba.bankName, "Test Bank")
        XCTAssertEqual(aba.routingNumber, "110000000")
        XCTAssertEqual(aba.accountNumber, "000123456789")

        let swift = try XCTUnwrap(instructions.financialAddresses.last)
        XCTAssertEqual(swift.type, "swift")
        XCTAssertEqual(swift.details?.swiftCode, "TSTEUS66XXX")
    }

    func testWireCheckoutWithoutInstructionsDecodes() throws {
        // A succeeded intent (test clocks / replays) can arrive with no
        // display instructions — the model must not fail the whole checkout.
        let json = """
        {
          "session": {"id": null, "client_secret": null, "expires_at": null},
          "wire": {"payment_intent_id": "pi_wire_2", "status": "succeeded", "instructions": null},
          "breakdown": {
            "subtotal": "100.00", "fees": "0.00", "payment_method": "wire",
            "shipping": "10.00", "grand_total": "110.00", "currency": "USD"
          }
        }
        """
        let checkout = try apiDecoder().decode(WireCheckout.self, from: Data(json.utf8))
        XCTAssertNil(checkout.wire.instructions)
        XCTAssertNil(checkout.session?.expiresAtDate)
        XCTAssertEqual(checkout.breakdown.grandTotal.value, Decimal(110))
    }
}
