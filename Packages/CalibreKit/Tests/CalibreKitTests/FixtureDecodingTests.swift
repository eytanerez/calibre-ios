import Foundation
import XCTest
@testable import CalibreKit

/// `{ok, data}` success wrapper, mirroring what APIClient unwraps.
struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
}

func fixtureData(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        XCTFail("Missing fixture \(name).json", file: file, line: line)
        throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
}

/// The exact decoder the client uses, pointed at a fake origin so
/// absolutization is observable.
func apiDecoder(origin: String = "https://api.test") -> JSONDecoder {
    APIClient.makeDecoder(origin: URL(string: origin)!)
}

/// Decodes every recorded fixture into its model and spot-checks identity
/// fields, decimal prices and image URLs against the real captures.
final class FixtureDecodingTests: XCTestCase {

    // MARK: listings-page (full view)

    func testListingsPageFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<PageResponse<Listing>>.self,
            from: fixtureData("listings-page")
        )
        XCTAssertTrue(envelope.ok)

        let page = envelope.data
        XCTAssertEqual(page.results.count, 4)
        XCTAssertEqual(page.pagination.page, 1)
        XCTAssertEqual(page.pagination.pageSize, 4)
        XCTAssertEqual(page.pagination.total, 2522)

        let first = try XCTUnwrap(page.results.first)
        XCTAssertEqual(first.id, "49e52179-1035-46f9-abe0-443d915d8c3b")
        XCTAssertEqual(first.listingNumber, 3099)
        XCTAssertEqual(first.title, "Tudor Black Bay Pro M79470-0001")
        XCTAssertEqual(first.brand, "Tudor")
        XCTAssertEqual(first.model, "Black Bay Pro")
        XCTAssertEqual(first.referenceNumber, "M79470-0001")
        XCTAssertEqual(first.price.value, Decimal(string: "4400.00"))
        XCTAssertEqual(first.currency, "USD")
        XCTAssertEqual(first.status, .active)
        XCTAssertEqual(first.condition?.overall, "Like New")
        XCTAssertEqual(first.condition?.caseCondition, "Like New")
        XCTAssertEqual(first.boxPapers, false)
        XCTAssertEqual(first.productionYear, 2024)
        XCTAssertNotNil(first.description)
        XCTAssertNotNil(first.createdAt)
        XCTAssertEqual(first.metrics?.views, 0)

        // Seller + reputation.
        let seller = try XCTUnwrap(first.seller)
        XCTAssertEqual(seller.username, "johon")
        XCTAssertEqual(seller.reputation?.salesCount, 4)
        XCTAssertEqual(seller.reputation?.averageRating, 5.0)

        // Internal media URLs are rewritten to the configured API origin so the
        // simulator/device never tries to reach the web frontend's localhost.
        XCTAssertEqual(first.images.count, 6)
        XCTAssertEqual(
            first.images.first?.url?.absoluteString,
            "https://api.test/media/listing_images/49e52179-1035-46f9-abe0-443d915d8c3b/80464fd84ef543fbb7a460d973637daa.jpg"
        )
    }

    // MARK: listings-card (card view)

    func testListingsCardFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<PageResponse<Listing>>.self,
            from: fixtureData("listings-card")
        )
        XCTAssertEqual(envelope.data.results.count, 4)
        for listing in envelope.data.results {
            XCTAssertFalse(listing.id.isEmpty)
            XCTAssertFalse(listing.title.isEmpty)
            XCTAssertGreaterThan(listing.price.value, 0)
            XCTAssertEqual(listing.images.count, 1, "card view carries exactly the primary image")
            XCTAssertNil(listing.description, "card view nulls out description")
        }
        let grandSeiko = try XCTUnwrap(envelope.data.results.first { $0.brand == "Grand Seiko" })
        XCTAssertEqual(grandSeiko.price.value, Decimal(string: "5728.00"))
    }

    // MARK: listing-detail

    func testListingDetailFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(Envelope<Listing>.self, from: fixtureData("listing-detail"))
        let listing = envelope.data
        XCTAssertEqual(listing.id, "49e52179-1035-46f9-abe0-443d915d8c3b")
        XCTAssertEqual(listing.sellerId, "0063c484-4f59-4239-8865-903447b34b4e")
        XCTAssertEqual(listing.price.value, Decimal(string: "4400.00"))
        XCTAssertEqual(listing.images.count, 6)
        XCTAssertEqual(listing.status, .active)
        XCTAssertEqual(listing.reviewEvents?.count, 0)
        XCTAssertNil(listing.estimatedShipping)
    }

    // MARK: listings-metadata

    func testListingsMetadataFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<MarketMetadata>.self,
            from: fixtureData("listings-metadata")
        )
        let metadata = envelope.data
        XCTAssertEqual(metadata.price.min.value, 0)
        XCTAssertEqual(metadata.price.max.value, Decimal(2_423_001))
        XCTAssertEqual(metadata.counts.liveTotal, 2522)
        XCTAssertEqual(metadata.options.brands.count, 26)
        XCTAssertEqual(metadata.options.brands.first, "A. Lange & Söhne")
        XCTAssertEqual(metadata.options.references.count, 2521)
        XCTAssertEqual(metadata.options.byBrand.count, 26)

        // Cascading facet groups: brand → models → references.
        let lange = try XCTUnwrap(metadata.options.byBrand.first)
        XCTAssertEqual(lange.brand, "A. Lange & Söhne")
        let firstModel = try XCTUnwrap(lange.models.first)
        XCTAssertEqual(firstModel.model, "1815 Chronograph")
        XCTAssertEqual(firstModel.references, ["410.025"])
        XCTAssertEqual(firstModel.liveTotal, 1)

        XCTAssertEqual(metadata.stats?.averagePrice?.value, Decimal(string: "21024.54"))
        XCTAssertNotNil(metadata.stats?.latestListingUpdatedAt)
    }

    // MARK: listings-home

    func testListingsHomeFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(Envelope<HomeFeed>.self, from: fixtureData("listings-home"))
        let home = envelope.data
        XCTAssertEqual(home.popular.count, 12)
        XCTAssertEqual(home.trending.count, 12)
        XCTAssertEqual(home.recommended.count, 0)
        XCTAssertEqual(home.recentlyViewed.count, 0)
        XCTAssertEqual(home.metadata.counts.liveTotal, 2522)
        for listing in home.popular + home.trending {
            XCTAssertFalse(listing.id.isEmpty)
            XCTAssertGreaterThan(listing.price.value, 0)
            XCTAssertFalse(listing.images.isEmpty)
            XCTAssertNotNil(listing.images.first?.url)
        }
    }

    // MARK: support-thread (guest capture: `data: null`)

    func testSupportThreadNullFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<SupportConversation?>.self,
            from: fixtureData("support-thread")
        )
        XCTAssertTrue(envelope.ok)
        XCTAssertNil(envelope.data)
    }

    // MARK: Synthetic wire samples for FIXTURE-PENDING models
    //
    // These bodies are hand-built from the backend serializers (offers.py,
    // orders.py, payouts.py, stripe.py) because authenticated captures were
    // blocked by the mid-migration backend. Replace with recorded fixtures
    // once ./Scripts/record-fixtures.sh succeeds again.

    func testOfferSyntheticSampleDecodes() throws {
        let json = """
        {
          "id": "0f0e0d0c-0b0a-4988-8776-655443322110",
          "listing_id": "49e52179-1035-46f9-abe0-443d915d8c3b",
          "buyer_id": "b1",
          "seller_id": "s1",
          "order_id": null,
          "amount": "4100.00",
          "currency": "USD",
          "status": "countered",
          "buyer_message": "Would you take 4100?",
          "seller_response": "Meet me at 4300.",
          "negotiation_history": [
            {"by": "buyer", "amount": "4100.00", "message": "Would you take 4100?", "at": "2026-07-06T10:00:00+00:00"},
            {"by": "seller", "amount": "4300.00", "message": "Meet me at 4300.", "at": "2026-07-06T11:30:00+00:00"}
          ],
          "awaiting": "buyer",
          "expires_at": "2026-07-07T10:00:00+00:00",
          "buyer_payment_due_at": null,
          "buyer_penalty_consent_at": "2026-07-06T10:00:00+00:00",
          "accepted_at": null,
          "paid_at": null,
          "hold": {
            "amount": "250.00",
            "currency": "USD",
            "status": "requires_capture",
            "payment_intent_id": "pi_123",
            "capture_before": "2026-07-12T10:00:00+00:00",
            "authorized_at": "2026-07-06T10:00:05+00:00",
            "released_at": null,
            "captured_at": null,
            "client_secret": null
          },
          "buyer": {"id": "b1", "username": "buyer_person"},
          "listing": {"id": "49e52179-1035-46f9-abe0-443d915d8c3b", "listing_number": 3099, "title": "Tudor Black Bay Pro", "status": "active", "price": "4400.00", "currency": "USD"},
          "perspective": "sent",
          "created_at": "2026-07-06T10:00:00+00:00",
          "updated_at": "2026-07-06T11:30:00+00:00"
        }
        """
        let offer = try apiDecoder().decode(Offer.self, from: Data(json.utf8))
        XCTAssertEqual(offer.status, .countered)
        XCTAssertEqual(offer.awaiting, "buyer")
        XCTAssertEqual(offer.amount.value, Decimal(string: "4100.00"))
        XCTAssertEqual(offer.negotiationHistory.count, 2)
        XCTAssertEqual(offer.negotiationHistory[1].by, "seller")
        XCTAssertEqual(offer.negotiationHistory[1].amount.value, Decimal(string: "4300.00"))
        XCTAssertEqual(offer.hold?.amount.value, Decimal(250))
        XCTAssertEqual(offer.hold?.status, "requires_capture")
        XCTAssertNotNil(offer.expiresAt)
        XCTAssertEqual(offer.listing?.listingNumber, 3099)
    }

    func testOfferUnknownStatusFallsBack() throws {
        let json = """
        {"id": "x", "listing_id": "l", "buyer_id": "b", "seller_id": "s", "order_id": null,
         "amount": "1.00", "currency": "USD", "status": "brand_new_server_status",
         "negotiation_history": [], "awaiting": null}
        """
        let offer = try apiDecoder().decode(Offer.self, from: Data(json.utf8))
        XCTAssertEqual(offer.status, .unknown, "new server statuses must never crash decoding")
    }

    func testOrderSyntheticSampleDecodes() throws {
        let json = """
        {
          "id": "7e2e0000-0000-4000-8000-00000000e2e1",
          "buyer_id": "b1",
          "listing_id": "49e52179-1035-46f9-abe0-443d915d8c3b",
          "listing": {
            "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "listing_number": 3099,
            "title": "Tudor Black Bay Pro", "price": "4400.00", "currency": "USD",
            "status": "sold", "production_year": 2024,
            "image": "/media/listing_images/x/front.jpg",
            "seller": {"id": "s1", "username": "johon"}
          },
          "status": "to_auth",
          "subtotal": "4400.00",
          "fees_total": "132.00",
          "seller_fee_percent_applied": "8.00",
          "seller_fee_amount": "352.00",
          "fee_adjustments": [],
          "tax_total": "0.00",
          "shipping_base_total": "60.00",
          "shipping_upcharge_percent": "20.00",
          "shipping_upcharge_total": "12.00",
          "shipping_quote_provider": "flat_rate",
          "shipping_total": "72.00",
          "grand_total": "4604.00",
          "currency": "USD",
          "payout_status": "pending",
          "payout_released_at": null,
          "checkout_payment_method": "card",
          "payment_due_at": null,
          "seller_action_state": null,
          "fulfillment_deadline_at": null,
          "seller_label_paid_at": "2026-07-07T00:00:00+00:00",
          "seller_label_created_at": "2026-07-07T00:05:00+00:00",
          "seller_label_price_total": "24.10",
          "seller_label_package": {},
          "to_auth_shipment": {
            "id": "sh1", "shipment_type": "to_auth", "carrier": "FedEx", "provider": "ifs",
            "provider_shipment_id": "PS1", "tracking_number": "TRACK123",
            "label_url": "https://labels.example/label.pdf", "reference": "CAL-3099",
            "reference_show_on_label": true, "shipped_at": "2026-07-07T12:00:00+00:00",
            "delivered_at": null, "created_at": "2026-07-07T00:05:00+00:00"
          },
          "to_buyer_shipment": null,
          "latest_shipment": null,
          "auth_result": {
            "id": "ar1", "intake_id": "in1", "outcome": "pass", "reasons": [],
            "notes": null, "aftermarket_flag": false,
            "created_at": "2026-07-08T00:00:00+00:00", "updated_at": "2026-07-08T00:00:00+00:00"
          },
          "shipping_address": {
            "full_name": "Test Buyer", "phone": "5551234", "line1": "1 Infinite Loop",
            "line2": null, "city": "Cupertino", "region": "CA", "postal_code": "95014",
            "country": "US", "source_address_id": "addr1"
          },
          "auth_center_address": {
            "full_name": "Authentication Center", "company_name": "Authentication Center",
            "line1": "7602 Carla Rd", "line2": "", "city": "Baltimore", "region": "MD",
            "postal_code": "21208", "country": "US", "phone": "", "email": ""
          },
          "shipping_package_limits": {"max_length_in": 108.0, "max_girth_plus_length_in": 165.0},
          "created_at": "2026-07-06T20:00:00+00:00",
          "updated_at": "2026-07-08T00:00:00+00:00"
        }
        """
        let order = try apiDecoder().decode(Order.self, from: Data(json.utf8))
        XCTAssertEqual(order.status, .toAuth)
        XCTAssertEqual(order.subtotal.value, Decimal(string: "4400.00"))
        XCTAssertEqual(order.grandTotal.value, Decimal(string: "4604.00"))
        XCTAssertEqual(order.sellerFeePercentApplied?.value, Decimal(string: "8.00"))
        XCTAssertEqual(order.checkoutPaymentMethod, .card)
        XCTAssertEqual(order.toAuthShipment?.shipmentType, .toAuth)
        XCTAssertEqual(order.toAuthShipment?.trackingNumber, "TRACK123")
        XCTAssertEqual(order.authResult?.outcome, "pass")
        XCTAssertEqual(order.shippingAddress?.city, "Cupertino")
        // Relative media path in the embedded listing absolutizes against the origin.
        XCTAssertEqual(
            order.listing?.image?.url?.absoluteString,
            "https://api.test/media/listing_images/x/front.jpg"
        )
    }

    func testOrderStatusCoversAllStates() throws {
        let wire = [
            "awaiting_wire", "purchased", "to_auth", "auth_pass", "auth_fail",
            "to_buyer", "delivered", "cancelled", "refunded",
        ]
        let expected: [OrderStatus] = [
            .awaitingWire, .purchased, .toAuth, .authPass, .authFail,
            .toBuyer, .delivered, .cancelled, .refunded,
        ]
        for (raw, status) in zip(wire, expected) {
            let decoded = try apiDecoder().decode(OrderStatus.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(decoded, status)
        }
        let unknown = try apiDecoder().decode(OrderStatus.self, from: Data("\"escrow_hold\"".utf8))
        XCTAssertEqual(unknown, .unknown)
    }

    func testOfferStatusCoversAllStates() throws {
        let wire = [
            "hold_pending", "hold_failed", "pending_seller", "countered",
            "accepted_pending_payment", "paid", "declined", "withdrawn",
            "expired", "penalty_captured",
        ]
        let expected: [OfferStatus] = [
            .holdPending, .holdFailed, .pendingSeller, .countered,
            .acceptedPendingPayment, .paid, .declined, .withdrawn,
            .expired, .penaltyCaptured,
        ]
        for (raw, status) in zip(wire, expected) {
            let decoded = try apiDecoder().decode(OfferStatus.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(decoded, status)
        }
    }

    func testProfileAndDashboardSyntheticSamplesDecode() throws {
        let profileJSON = """
        {
          "id": "u1", "email": "buyer@example.com", "username": "buyer_person",
          "first_name": "Test", "last_name": "Buyer", "phone": "+15551234567",
          "created_at": "2026-01-01T00:00:00+00:00", "updated_at": "2026-07-01T00:00:00+00:00",
          "seller_profile": {
            "status": "approved", "is_verified_dealer": true, "dealer_active_until": null,
            "unlock": {
              "status": "approved", "is_active": true, "active_until": null,
              "live_listing_count": 12, "threshold": 10, "remaining_to_unlock": 0,
              "next_month_unlocked": true, "current_fee_percent": "5.00",
              "member_fee_percent": "8", "dealer_fee_percent": "5",
              "current_month_label": "July", "next_month_label": "August"
            }
          },
          "stats": {"orders": 3, "listings": 14, "live_listings": 12, "cart": 1, "watchlist": 6, "addresses": 2}
        }
        """
        let profile = try apiDecoder().decode(Profile.self, from: Data(profileJSON.utf8))
        XCTAssertEqual(profile.username, "buyer_person")
        XCTAssertEqual(profile.stats.watchlist, 6)
        XCTAssertEqual(profile.sellerProfile?.unlock?.currentFeePercent.value, Decimal(5))
        XCTAssertEqual(profile.sellerProfile?.unlock?.memberFeePercent.value, Decimal(8))

        let readinessJSON = """
        {
          "connect": {
            "account_id": "acct_1", "onboarding_complete": true, "details_submitted": true,
            "charges_enabled": true, "payouts_enabled": true,
            "last_checked_at": "2026-07-10T00:00:00+00:00",
            "requirements_currently_due": [], "requirements_eventually_due": ["individual.id_number"]
          },
          "can_list": true
        }
        """
        let readiness = try apiDecoder().decode(SellerReadiness.self, from: Data(readinessJSON.utf8))
        XCTAssertTrue(readiness.canList)
        XCTAssertEqual(readiness.connect.requirementsEventuallyDue, ["individual.id_number"])
    }

    func testCartWatchlistAddressSyntheticSamplesDecode() throws {
        let cartJSON = """
        [{
          "id": "c1", "user_id": "u1", "listing_id": "l1", "note": null,
          "created_at": "2026-07-01T00:00:00+00:00", "updated_at": "2026-07-01T00:00:00+00:00",
          "listing": {
            "id": "l1", "listing_number": 3099, "title": "Tudor Black Bay Pro",
            "price": "4400.00", "currency": "USD", "status": "active", "production_year": 2024,
            "image": "/media/listing_images/l1/front.jpg", "seller": {"id": "s1", "username": "johon"}
          }
        }]
        """
        let cart = try apiDecoder().decode([CartItem].self, from: Data(cartJSON.utf8))
        XCTAssertEqual(cart.first?.listing?.price.value, Decimal(string: "4400.00"))
        XCTAssertEqual(
            cart.first?.listing?.image?.url?.absoluteString,
            "https://api.test/media/listing_images/l1/front.jpg"
        )

        let addressJSON = """
        {
          "id": "a1", "user_id": "u1", "label": "Home", "first_name": "Test",
          "last_name": "Buyer", "full_name": "Test Buyer", "phone": "5551234",
          "line1": "1 Infinite Loop", "line2": null, "city": "Cupertino", "region": "CA",
          "postal_code": "95014", "country": "US",
          "is_default_shipping": true, "is_default_billing": false,
          "created_at": "2026-07-01T00:00:00+00:00", "updated_at": "2026-07-01T00:00:00+00:00"
        }
        """
        let address = try apiDecoder().decode(Address.self, from: Data(addressJSON.utf8))
        XCTAssertEqual(address.postalCode, "95014")
        XCTAssertTrue(address.isDefaultShipping)
    }
}
