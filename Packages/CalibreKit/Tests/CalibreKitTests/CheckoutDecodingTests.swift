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
        let breakdown = try XCTUnwrap(intent.breakdown)
        XCTAssertEqual(breakdown.subtotal.value, Decimal(string: "1000.00"))
        XCTAssertEqual(breakdown.cardConvenienceFee?.value, Decimal(string: "33.60"))
        XCTAssertEqual(breakdown.cardConvenienceFeePercent?.value, Decimal(string: "3.00"))
        XCTAssertEqual(breakdown.shipping.value, Decimal(120))
        XCTAssertEqual(breakdown.tax?.value, Decimal(40))
        XCTAssertEqual(breakdown.grandTotal.value, Decimal(string: "1193.60"))
        XCTAssertEqual(breakdown.taxCalculatedUpfront, true)
        XCTAssertNil(breakdown.offerId)
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
        let breakdown = try XCTUnwrap(intent.breakdown)
        XCTAssertNil(breakdown.tax)
        XCTAssertEqual(breakdown.grandTotal.value, Decimal(string: "576.80"))
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
        XCTAssertEqual(checkout.breakdown?.grandTotal.value, Decimal(110))
    }

    // MARK: - Multi-item checkout

    /// A wire checkout covering two watches: one transfer, one amount, and no
    /// legacy `breakdown` — the combined column is what the buyer sends.
    func testWireCheckoutGroupDecodes() throws {
        let json = """
        {
          "session": {"id": null, "expires_at": 1789000000},
          "wire": {
            "payment_intent_id": "pi_wire_group",
            "status": "requires_action",
            "instructions": {
              "type": "us_bank_transfer",
              "reference": "CALIBRE-8801",
              "amount_remaining": "12262.85",
              "currency": "USD",
              "financial_addresses": []
            }
          },
          "breakdown_group": {
            "items": [
              {
                "listing_id": "l-1", "subtotal": "4400.00", "fees": "0.00",
                "payment_method": "wire", "shipping": "72.00", "tax": "39.05",
                "grand_total": "4511.05", "currency": "USD"
              },
              {
                "listing_id": "l-2", "subtotal": "7600.00", "fees": "0.00",
                "payment_method": "wire", "shipping": "84.00", "tax": "67.80",
                "grand_total": "7751.80", "currency": "USD"
              }
            ],
            "combined": {
              "subtotal": "12000.00", "shipping": "156.00", "tax": "106.85",
              "card_fee": {"percent": "2.90", "fixed": "0.30", "amount": "362.94"},
              "totals": {"card": "12628.94", "wire": "12262.85"},
              "grand_total": "12262.85", "pricing_mode": "surcharge",
              "accepted_card_funding": ["credit"],
              "display": {"price": "12000.00", "wire_price": null},
              "currency": "USD", "item_count": 2, "payment_method": "wire"
            },
            "checkout_group_id": "grp-1"
          }
        }
        """
        let checkout = try apiDecoder().decode(WireCheckout.self, from: Data(json.utf8))
        XCTAssertNil(checkout.breakdown)
        XCTAssertEqual(checkout.breakdownGroup?.items.count, 2)
        // One transfer for the group, for the combined wire amount.
        let payable = try XCTUnwrap(checkout.payableBreakdown)
        XCTAssertEqual(payable.grandTotal.value, Decimal(string: "12262.85"))
        XCTAssertEqual(
            checkout.breakdownGroup?.items.map(\.grandTotal.value).reduce(Decimal(0), +),
            Decimal(string: "12262.85")
        )
        XCTAssertEqual(checkout.wire.instructions?.amountRemaining?.value, Decimal(string: "12262.85"))
    }

    /// Materialization: today's single-order payload at the top level, with
    /// every order of the purchase in `orders`.
    func testOrderMaterializationDecodesGroup() throws {
        let json = """
        {
          "id": "o-1", "buyer_id": "b-1", "listing_id": "l-1", "status": "purchased",
          "subtotal": "4400.00", "fees_total": "133.52", "grand_total": "4645.52",
          "currency": "USD", "checkout_group_id": "grp-1",
          "group": {"order_ids": ["o-1", "o-2"], "count": 2},
          "orders": [
            {
              "id": "o-1", "buyer_id": "b-1", "listing_id": "l-1", "status": "purchased",
              "subtotal": "4400.00", "fees_total": "133.52", "grand_total": "4645.52",
              "currency": "USD", "checkout_group_id": "grp-1",
              "group": {"order_ids": ["o-1", "o-2"], "count": 2}
            },
            {
              "id": "o-2", "buyer_id": "b-1", "listing_id": "l-2", "status": "purchased",
              "subtotal": "7600.00", "fees_total": "229.42", "grand_total": "7983.42",
              "currency": "USD", "checkout_group_id": "grp-1",
              "group": {"order_ids": ["o-1", "o-2"], "count": 2}
            }
          ]
        }
        """
        let result = try apiDecoder().decode(OrderMaterialization.self, from: Data(json.utf8))
        XCTAssertEqual(result.first.id, "o-1")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.orders.map(\.id), ["o-1", "o-2"])
        XCTAssertEqual(result.first.checkoutGroupId, "grp-1")
        XCTAssertEqual(result.first.group?.count, 2)
        XCTAssertEqual(result.first.purchaseItemCount, 2)
        XCTAssertEqual(result.first.group?.siblingIDs(of: "o-1"), ["o-2"])
        // Each order's grand total is its own share — summing them across the
        // group is what the buyer paid.
        XCTAssertEqual(
            result.orders.map(\.grandTotal.value).reduce(Decimal(0), +),
            Decimal(string: "12628.94")
        )
    }

    /// A purchase of one watch: no `group` to render a "part of a purchase"
    /// affordance from, and an `orders` array of one so a client polling for a
    /// count has a single shape either way.
    func testOrderMaterializationDecodesSingle() throws {
        let json = """
        {
          "id": "o-9", "buyer_id": "b-1", "listing_id": "l-9", "status": "purchased",
          "subtotal": "4400.00", "fees_total": "129.99", "grand_total": "4601.99",
          "currency": "USD", "checkout_group_id": "grp-9", "group": null,
          "orders": [
            {
              "id": "o-9", "buyer_id": "b-1", "listing_id": "l-9", "status": "purchased",
              "subtotal": "4400.00", "fees_total": "129.99", "grand_total": "4601.99",
              "currency": "USD", "checkout_group_id": "grp-9", "group": null
            }
          ]
        }
        """
        let result = try apiDecoder().decode(OrderMaterialization.self, from: Data(json.utf8))
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first.group)
        XCTAssertEqual(result.first.purchaseItemCount, 1)
        XCTAssertEqual(result.first.checkoutGroupId, "grp-9")
    }

    /// An order recorded before groups existed carries neither key, and must
    /// still decode — and still count as a purchase of one.
    func testOrderMaterializationWithoutGroupKeysDecodes() throws {
        let json = """
        {
          "id": "o-legacy", "buyer_id": "b-1", "listing_id": "l-1", "status": "delivered",
          "subtotal": "1000.00", "fees_total": "0.00", "grand_total": "1000.00",
          "currency": "USD"
        }
        """
        let result = try apiDecoder().decode(OrderMaterialization.self, from: Data(json.utf8))
        XCTAssertEqual(result.count, 1, "a payload with no orders array is a purchase of one")
        XCTAssertEqual(result.orders.first?.id, "o-legacy")
        XCTAssertNil(result.first.checkoutGroupId)
        XCTAssertNil(result.first.group)
        XCTAssertEqual(result.first.purchaseItemCount, 1)
    }
}
