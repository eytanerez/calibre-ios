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
          "seller_fee_percent_applied": "6.00",
          "seller_fee_amount": "264.00",
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
        XCTAssertEqual(order.sellerFeePercentApplied?.value, Decimal(string: "6.00"))
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
        // `dealer_application` is top level and replaced the old nested
        // `unlock` block; `seller_profile` is down to status + the badge flag.
        let profileJSON = """
        {
          "id": "u1", "email": "buyer@example.com", "username": "buyer_person",
          "first_name": "Test", "last_name": "Buyer", "phone": "+15551234567",
          "created_at": "2026-01-01T00:00:00+00:00", "updated_at": "2026-07-01T00:00:00+00:00",
          "seller_profile": {"status": "approved", "is_verified_dealer": true},
          "dealer_application": {
            "status": "verified", "company_name": "Meridian Watch Co.", "country": "US",
            "applied_at": "2026-06-02T14:10:00+00:00", "verified_at": "2026-06-03T09:41:00+00:00",
            "revoked_reason": null, "member_fee_percent": "6.00", "dealer_fee_percent": "4.00"
          },
          "stats": {"orders": 3, "listings": 14, "live_listings": 12, "cart": 1, "watchlist": 6, "addresses": 2}
        }
        """
        let profile = try apiDecoder().decode(Profile.self, from: Data(profileJSON.utf8))
        XCTAssertEqual(profile.username, "buyer_person")
        XCTAssertEqual(profile.stats.watchlist, 6)
        XCTAssertEqual(profile.sellerProfile?.isVerifiedDealer, true)
        XCTAssertEqual(profile.dealerApplication?.status, .verified)
        XCTAssertEqual(profile.dealerApplication?.memberFeePercent?.value, Decimal(string: "6.00"))
        XCTAssertEqual(profile.dealerApplication?.dealerFeePercent?.value, Decimal(string: "4.00"))
        XCTAssertEqual(profile.dealerApplication?.companyName, "Meridian Watch Co.")

        let readinessJSON = """
        {
          "connect": {
            "account_id": "acct_1", "onboarding_complete": true, "details_submitted": true,
            "charges_enabled": true, "payouts_enabled": true,
            "last_checked_at": "2026-07-10T00:00:00+00:00",
            "requirements_currently_due": [], "requirements_eventually_due": ["individual.id_number"],
            "status": "complete", "status_basis": "live",
            "missing_items": [], "review_items": [],
            "upcoming_items": [{"key": "ssn", "label": "Social Security number — entered directly with Stripe"}],
            "disabled_reason": null
          },
          "can_list": true
        }
        """
        let readiness = try apiDecoder().decode(SellerReadiness.self, from: Data(readinessJSON.utf8))
        XCTAssertTrue(readiness.canList)
        XCTAssertEqual(readiness.connect.requirementsEventuallyDue, ["individual.id_number"])
        // The raw key and its humanized twin travel together — the raw list is
        // Stripe's spelling, the items are the seller's.
        XCTAssertEqual(readiness.connect.upcomingItems.map(\.key), ["ssn"])
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

    // MARK: - Recorded payloads for the marketplace overhaul
    //
    // Every fixture below is written to the v1 contract. The assertions are
    // deliberately about the numbers the client is forbidden from computing:
    // if one of these stops decoding, a screen would otherwise quietly fall
    // back to a hardcoded figure, which is the exact failure we're guarding.

    func testAccountProfileFixtureCarriesDealerApplication() throws {
        let envelope = try apiDecoder().decode(Envelope<Profile>.self, from: fixtureData("account-profile"))
        let profile = envelope.data
        XCTAssertEqual(profile.username, "iosbuyer")
        let application = try XCTUnwrap(profile.dealerApplication)
        XCTAssertEqual(application.status, .verified)
        XCTAssertEqual(application.memberFeePercent?.value, Decimal(string: "6.00"))
        XCTAssertEqual(application.dealerFeePercent?.value, Decimal(string: "4.00"))
        XCTAssertEqual(profile.sellerProfile?.isVerifiedDealer, true)
    }

    func testAccountDashboardFixtureCarriesDealerApplication() throws {
        let envelope = try apiDecoder().decode(
            Envelope<SellerDashboard>.self,
            from: fixtureData("account-dashboard")
        )
        let dashboard = envelope.data
        // Spelled out: through an optional chain, a bare `.none` binds to
        // `Optional.none` and silently asserts nil instead of the case.
        XCTAssertEqual(dashboard.dealerApplication?.status, DealerApplicationStatus.none)
        XCTAssertEqual(dashboard.dealerApplication?.hasApplied, false)
        XCTAssertEqual(dashboard.dealerApplication?.dealerFeePercent?.value, Decimal(string: "4.00"))
        XCTAssertEqual(dashboard.metrics.activeListings, 0)
        XCTAssertEqual(dashboard.whatToList.count, 5)
    }

    func testDealerApplicationResultFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<DealerApplicationResult>.self,
            from: fixtureData("dealer-application")
        )
        XCTAssertEqual(envelope.data.application.status, .pending)
        XCTAssertEqual(envelope.data.application.companyName, "Meridian Watch Co.")
        XCTAssertNotNil(envelope.data.application.appliedAt)
        XCTAssertEqual(envelope.data.stripe?.clientSecret, "accs_secret_1MxDealerOnboardingSession")
    }

    // MARK: Dealer watch requests

    /// `/dealer/watch-requests` is a flat `{results, page, page_size, total}`
    /// page — not the `{results, pagination}` envelope browse uses.
    func testDealerWatchRequestPageFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<DealerWatchRequestPage>.self,
            from: fixtureData("dealer-watch-requests")
        )
        let page = envelope.data
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.pageSize, 25)
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.results.count, 2)

        let matched = try XCTUnwrap(page.results.first)
        XCTAssertEqual(matched.requesterUsername, "harrison.k")
        XCTAssertEqual(matched.status, .open)
        XCTAssertEqual(matched.maxBudget?.value, Decimal(string: "14500.00"))
        XCTAssertEqual(matched.watchReferenceId, "b21e5c88-30b5-4d64-9a3a-1f7e2c9d5a44")
        XCTAssertEqual(matched.watchReference?.reference, "126610LN")
        XCTAssertEqual(matched.watchReference?.model, "Submariner Date")
        XCTAssertTrue(matched.isCatalogMatched)
        XCTAssertEqual(matched.liveMatchCount, 3)
        XCTAssertNotNil(matched.createdAt)

        // Free text that never resolved: no catalog row, and therefore no
        // live-match count to speak of.
        let unmatched = page.results[1]
        XCTAssertNil(unmatched.watchReferenceId)
        XCTAssertNil(unmatched.watchReference)
        XCTAssertFalse(unmatched.isCatalogMatched)
        XCTAssertEqual(unmatched.liveMatchCount, 0)
        XCTAssertNil(unmatched.maxBudget)
    }

    /// `/account/watch-requests` still answers a bare array without the
    /// dealer-only columns; the same model has to survive both.
    func testAccountWatchRequestDecodesWithoutDealerFields() throws {
        let json = """
        {
          "id": "6f0a9e21-0a4b-4a3f-9b53-3f0f3a6a1c11",
          "requester_id": "1c3d7a52-77aa-4c0e-9e07-2a1b6f9d4e02",
          "brand": "Tudor",
          "model": "Black Bay 58",
          "reference": "79030N",
          "watch_reference_id": null,
          "watch_reference": null,
          "production_year": null,
          "max_budget": "3200.00",
          "currency": "USD",
          "notes": null,
          "status": "open",
          "fulfilled_listing_id": null,
          "created_at": "2026-08-12T11:02:00+00:00",
          "updated_at": "2026-08-12T11:02:00+00:00"
        }
        """
        let request = try apiDecoder().decode(WatchRequest.self, from: Data(json.utf8))
        XCTAssertNil(request.requesterUsername)
        XCTAssertNil(request.matchingLiveListings)
        XCTAssertEqual(request.liveMatchCount, 0)
        XCTAssertFalse(request.isCatalogMatched)
    }

    func testDealerApplicationUnknownStatusFallsBack() throws {
        let json = #"{"status": "under_manual_review"}"#
        let application = try apiDecoder().decode(DealerApplication.self, from: Data(json.utf8))
        XCTAssertEqual(application.status, .unknown, "a new server status must never crash decoding")
        XCTAssertNil(application.dealerFeePercent)
    }

    // MARK: Publish preview

    func testPublishPreviewFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<ListingPublishPreview>.self,
            from: fixtureData("publish-preview")
        )
        let preview = envelope.data
        XCTAssertEqual(preview.price.value, Decimal(string: "4400.00"))
        XCTAssertEqual(preview.commission.percent.value, Decimal(string: "6.00"))
        XCTAssertEqual(preview.commission.amount.value, Decimal(string: "264.00"))
        XCTAssertEqual(preview.commission.minimum.value, Decimal(string: "250.00"))
        XCTAssertFalse(preview.commission.minimumApplied)
        XCTAssertEqual(preview.netProceeds.value, Decimal(string: "4064.00"))
        XCTAssertEqual(preview.buyerDisplay.standard.price.value, Decimal(string: "4400.00"))
        XCTAssertEqual(preview.shippingEstimate?.amount.value, Decimal(string: "72.00"))
        XCTAssertEqual(preview.returns?.accepted, true)
        XCTAssertEqual(preview.returns?.windowHours, 48)

        let discount = try XCTUnwrap(preview.buyerDisplay.discountStates)
        XCTAssertEqual(discount.states, ["CT", "MA"])
        XCTAssertEqual(discount.wirePrice.value, Decimal(string: "4400.00"))
        XCTAssertGreaterThan(discount.price.value, discount.wirePrice.value,
                             "in the discount presentation the listed price is the card price")
    }

    func testPublishPreviewAppliesTheCommissionMinimum() throws {
        let envelope = try apiDecoder().decode(
            Envelope<ListingPublishPreview>.self,
            from: fixtureData("publish-preview-minimum")
        )
        let preview = envelope.data
        XCTAssertTrue(preview.commission.minimumApplied)
        XCTAssertEqual(preview.commission.amount.value, preview.commission.minimum.value)
        // The server already applied the floor — the client must never redo it.
        XCTAssertEqual(preview.netProceeds.value, Decimal(string: "1678.00"))
        XCTAssertEqual(preview.returns?.accepted, false)
        XCTAssertNil(preview.returns?.windowHours)
    }

    // MARK: Checkout breakdown v2

    func testCheckoutCreateIntentCardFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<NativeCheckoutIntent>.self,
            from: fixtureData("checkout-create-intent-card")
        )
        let intent = envelope.data
        XCTAssertEqual(intent.paymentIntent.id, "pi_3PxCalibre001")
        XCTAssertEqual(intent.publishableKey, "pk_test_calibre")

        let breakdown = try XCTUnwrap(intent.breakdown, "a single-watch checkout keeps the legacy breakdown")
        XCTAssertEqual(breakdown.pricingMode, .surcharge)
        XCTAssertFalse(breakdown.isDiscountPresentation)
        XCTAssertFalse(breakdown.acceptsDebit, "surcharge states take credit only")
        XCTAssertEqual(breakdown.cardFee?.percent?.value, Decimal(string: "2.90"))
        XCTAssertEqual(breakdown.cardFee?.fixed?.value, Decimal(string: "0.30"))
        XCTAssertEqual(breakdown.cardFee?.amount.value, Decimal(string: "129.99"))
        XCTAssertEqual(breakdown.totals?.card?.value, Decimal(string: "4601.99"))
        XCTAssertEqual(breakdown.totals?.wire?.value, Decimal(string: "4472.00"))
        XCTAssertEqual(breakdown.display?.price.value, Decimal(string: "4400.00"))
        XCTAssertNil(breakdown.display?.wirePrice)
        XCTAssertEqual(breakdown.paymentDisclosures?.cardFeeNonrefundable, true)
        XCTAssertEqual(breakdown.returns?.windowHours, 48)
        XCTAssertEqual(breakdown.returnFee?.percent?.value, Decimal(string: "7.00"))
        XCTAssertEqual(breakdown.returnFee?.minimum?.value, Decimal(string: "250.00"))
        // Legacy keys still land, so nothing that reads them regresses.
        XCTAssertEqual(breakdown.cardConvenienceFee?.value, Decimal(string: "129.99"))
        XCTAssertEqual(breakdown.taxCalculatedUpfront, true)

        // A single-watch checkout also answers with the group shape, so one
        // renderer covers both kinds of purchase.
        let group = try XCTUnwrap(intent.breakdownGroup)
        XCTAssertEqual(group.items.count, 1)
        XCTAssertEqual(group.combined?.itemCount, 1)
        XCTAssertEqual(group.checkoutGroupId, "8d2a5f13-64c7-42be-9a01-b7e5c3d09f26")
        // The combined column of a set of one is the same money the legacy
        // breakdown states — and it carries that one watch's return terms.
        let combined = try XCTUnwrap(group.combinedBreakdown)
        XCTAssertEqual(combined.grandTotal.value, breakdown.grandTotal.value)
        XCTAssertEqual(combined.cardFee?.amount.value, breakdown.cardFee?.amount.value)
        XCTAssertEqual(combined.returns?.windowHours, 48)
        XCTAssertEqual(combined.paymentDisclosures?.cardFeeNonrefundable, true)
    }

    // MARK: Multi-item checkout

    func testCheckoutPaymentIntentGroupFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<NativeCheckoutIntent>.self,
            from: fixtureData("checkout-payment-intent-group")
        )
        let intent = envelope.data
        XCTAssertEqual(intent.paymentIntent.id, "pi_3PxCalibreGroup01")
        XCTAssertNil(intent.breakdown, "a set carries breakdown_group only")

        let group = try XCTUnwrap(intent.breakdownGroup)
        XCTAssertEqual(group.checkoutGroupId, "3f8b6c1e-9a24-4d77-b0f5-2c9d81a4e6b3")
        XCTAssertEqual(
            group.items.map(\.listingId),
            ["49e52179-1035-46f9-abe0-443d915d8c3b", "7c1f2b90-33ad-4a52-9c61-5b0a2f4d81e7"]
        )

        let combined = try XCTUnwrap(group.combined)
        XCTAssertEqual(combined.itemCount, 2)
        XCTAssertEqual(combined.subtotal.value, Decimal(string: "12000.00"))
        XCTAssertEqual(combined.shipping.value, Decimal(string: "156.00"))
        XCTAssertEqual(combined.tax?.value, Decimal(string: "110.00"))
        XCTAssertEqual(combined.cardFee?.amount.value, Decimal(string: "362.94"))
        XCTAssertEqual(combined.cardFee?.percent?.value, Decimal(string: "2.90"))
        XCTAssertEqual(combined.cardFee?.fixed?.value, Decimal(string: "0.30"))
        XCTAssertEqual(combined.grandTotal.value, Decimal(string: "12628.94"))
        XCTAssertEqual(combined.totals?.card?.value, Decimal(string: "12628.94"))
        XCTAssertEqual(combined.totals?.wire?.value, Decimal(string: "12262.85"))

        // The server allocates; the client only checks that what it was handed
        // is internally consistent. Each item's own share of the single card
        // fee sums to the fee charged once, and the per-order grand totals —
        // which are exactly what `purchase_completed.value` reports — sum to
        // what the buyer pays.
        let feeShares = group.items.compactMap { $0.fees?.value }
        XCTAssertEqual(feeShares.count, 2)
        XCTAssertEqual(feeShares.reduce(Decimal(0), +), Decimal(string: "362.94"))
        XCTAssertEqual(
            group.items.map(\.grandTotal.value).reduce(Decimal(0), +),
            Decimal(string: "12628.94")
        )
        XCTAssertEqual(
            group.items.map(\.subtotal.value).reduce(Decimal(0), +),
            combined.subtotal.value
        )
        XCTAssertEqual(
            group.items.compactMap { $0.tax?.value }.reduce(Decimal(0), +),
            Decimal(string: "110.00")
        )

        // Return terms are the seller's, so two watches in one purchase can
        // answer differently.
        XCTAssertEqual(group.items.first?.returns?.accepted, true)
        XCTAssertEqual(group.items.first?.returns?.windowHours, 48)
        XCTAssertEqual(group.items.last?.returns?.accepted, false)
        XCTAssertNil(group.items.last?.returns?.windowHours)

        // The combined column renders through the same breakdown shape every
        // piece of checkout copy already reads — with no return terms, because
        // the two watches don't share any.
        let payable = try XCTUnwrap(intent.payableBreakdown)
        XCTAssertEqual(payable.grandTotal.value, Decimal(string: "12628.94"))
        XCTAssertEqual(payable.subtotal.value, Decimal(string: "12000.00"))
        XCTAssertEqual(payable.currency, "USD")
        XCTAssertEqual(payable.pricingMode, .surcharge)
        XCTAssertFalse(payable.isDiscountPresentation)
        XCTAssertEqual(payable.paymentDisclosures?.cardFeeNonrefundable, true)
        XCTAssertNil(payable.returns)
        XCTAssertNil(payable.returnFee)
    }

    func testListingQuoteDiscountModeFixtureDecodes() throws {
        let envelope = try apiDecoder().decode(
            Envelope<CheckoutBreakdown>.self,
            from: fixtureData("listing-quote-discount")
        )
        let breakdown = envelope.data
        XCTAssertTrue(breakdown.isDiscountPresentation)
        XCTAssertTrue(breakdown.acceptsDebit, "debit is accepted where the discount presentation applies")
        XCTAssertEqual(breakdown.acceptedCardFunding, ["credit", "debit"])
        // The listed price shown IS the card price; wire reveals the lower one.
        XCTAssertEqual(breakdown.display?.price.value, Decimal(string: "4529.99"))
        XCTAssertEqual(breakdown.display?.wirePrice?.value, Decimal(string: "4400.00"))
        // Same money either way — only the presentation differs.
        XCTAssertEqual(breakdown.totals?.card?.value, Decimal(string: "4601.99"))

        // This capture predates the tax-source keys, and a payload without
        // them has to keep decoding — an absent key is not an outage.
        XCTAssertNil(breakdown.taxSource)
        XCTAssertNil(breakdown.taxUnavailableWarning)
        XCTAssertNil(breakdown.taxStubWarning)
        XCTAssertFalse(breakdown.isTaxUnavailable)
    }

    /// The tax provider is unreachable. The quote endpoints no longer answer
    /// 503: every other line is priced, `tax` is a placeholder zero, and the
    /// three keys say so. The zero is the trap — read on its own it means "no
    /// tax is owed", so the source is what a screen has to branch on.
    func testListingQuoteTaxUnavailableFixtureDecodes() throws {
        let breakdown = try apiDecoder().decode(
            Envelope<CheckoutBreakdown>.self,
            from: fixtureData("listing-quote-tax-unavailable")
        ).data

        XCTAssertEqual(breakdown.taxSource, "unavailable")
        XCTAssertTrue(breakdown.isTaxUnavailable)
        XCTAssertEqual(breakdown.tax?.value, Decimal(string: "0.00"))
        XCTAssertNil(breakdown.taxStubWarning)
        XCTAssertEqual(
            breakdown.taxUnavailableWarning,
            "Sales tax could not be calculated just now, so it is not included here. "
                + "The full total, tax included, is shown again at checkout before you pay."
        )

        // Everything the server *could* price still arrived, which is the
        // whole point of the 200: the panel has lines to show.
        XCTAssertEqual(breakdown.subtotal.value, Decimal(string: "4400.00"))
        XCTAssertEqual(breakdown.shipping.value, Decimal(string: "72.00"))
        XCTAssertEqual(breakdown.cardFee?.amount.value, Decimal(string: "129.99"))
        XCTAssertEqual(breakdown.grandTotal.value, Decimal(string: "4601.99"))
    }

    func testPaymentMethodValidationFixturesDecode() throws {
        let accepted = try apiDecoder().decode(
            Envelope<PaymentMethodValidation>.self,
            from: fixtureData("validate-payment-method-accepted")
        ).data
        XCTAssertTrue(accepted.accepted)
        XCTAssertEqual(accepted.funding, "credit")
        XCTAssertNil(accepted.reason)

        let refused = try apiDecoder().decode(
            Envelope<PaymentMethodValidation>.self,
            from: fixtureData("validate-payment-method-refused")
        ).data
        XCTAssertFalse(refused.accepted)
        XCTAssertEqual(refused.funding, "prepaid")
        XCTAssertEqual(refused.reason, "prepaid_not_accepted")
    }

    func testCheckoutConfirmationFixtureDecodes() throws {
        let confirmation = try apiDecoder().decode(
            Envelope<CheckoutConfirmation>.self,
            from: fixtureData("checkout-confirm")
        ).data
        XCTAssertTrue(confirmation.requiresAction)
        XCTAssertEqual(confirmation.status, "requires_action")
        XCTAssertEqual(confirmation.clientSecret, "pi_3PxCalibre001_secret_abc")
    }

    // MARK: Returns

    func testReturnQuoteFixtureDecodes() throws {
        let quote = try apiDecoder().decode(
            Envelope<ReturnQuote>.self,
            from: fixtureData("return-quote")
        ).data
        XCTAssertEqual(quote.watchPrice.value, Decimal(string: "10000.00"))
        XCTAssertEqual(quote.taxRefund?.value, Decimal(string: "625.00"))
        XCTAssertEqual(quote.returnFee.percent.value, Decimal(string: "7.00"))
        XCTAssertEqual(quote.returnFee.minimum.value, Decimal(string: "250.00"))
        XCTAssertEqual(quote.returnFee.amount.value, Decimal(string: "700.00"))
        XCTAssertEqual(quote.outboundLabelDeduction?.value, Decimal(string: "150.00"))
        // Calibre's own return label is deducted from the refund too, and the
        // client renders the server's figure rather than inferring one.
        XCTAssertEqual(quote.returnLabelDeduction?.value, Decimal(string: "35.00"))
        XCTAssertEqual(quote.processingWithholdingBasis, "card_fee_never_refunded")
        XCTAssertEqual(quote.refundTotal.value, Decimal(string: "9445.95"))
        XCTAssertEqual(quote.window?.open, true)
        XCTAssertNil(quote.existingReturn)
    }

    func testReturnQuoteWithoutALabelDeductionLeavesTheRowOut() throws {
        // Older payloads carry no `return_label_deduction`; the field stays
        // nil so the screen omits the line rather than inventing a figure.
        let json = """
        {
          "watch_price": "10000.00",
          "return_fee": { "percent": "7.00", "minimum": "250.00", "amount": "700.00" },
          "refund_total": "9300.00",
          "currency": "USD"
        }
        """
        let quote = try apiDecoder().decode(ReturnQuote.self, from: Data(json.utf8))
        XCTAssertNil(quote.returnLabelDeduction)
    }

    func testReturnQuoteWireBuyerWithholdsAnEquivalent() throws {
        let quote = try apiDecoder().decode(
            Envelope<ReturnQuote>.self,
            from: fixtureData("return-quote-wire")
        ).data
        // A wire buyer had no card fee, so an equivalent is withheld instead.
        XCTAssertEqual(quote.processingWithholdingBasis, "card_fee_equivalent")
        // 7% of $2,000 is $140, so the $250 minimum is what applies.
        XCTAssertEqual(quote.returnFee.amount.value, quote.returnFee.minimum.value)
    }

    func testOrderWithOpenReturnFixtureDecodes() throws {
        let order = try apiDecoder().decode(
            Envelope<Order>.self,
            from: fixtureData("order-return")
        ).data
        XCTAssertEqual(order.status, .delivered)
        XCTAssertEqual(order.listing?.seller?.isVerifiedDealer, true)

        let terms = try XCTUnwrap(order.returns)
        XCTAssertTrue(terms.accepted)
        XCTAssertEqual(terms.windowHours, 48)
        XCTAssertNotNil(terms.windowEndsAt)

        let summary = try XCTUnwrap(order.returnSummary)
        XCTAssertEqual(summary.state, "requested")
        XCTAssertTrue(summary.awaitingShipment)
        XCTAssertFalse(summary.isInTransit)
        XCTAssertNil(summary.relistDecision)
        XCTAssertEqual(summary.refundTotal?.value, Decimal(string: "9445.95"))
        // The frozen return carries the label's cost, so the summary can show
        // the same deduction the quote promised.
        XCTAssertEqual(summary.returnLabelDeduction?.value, Decimal(string: "35.00"))
        XCTAssertEqual(summary.label?.trackingNumber, "794612345098")
        XCTAssertNotNil(summary.shipDeadlineAt)

        let payout = try XCTUnwrap(order.payoutBlock)
        XCTAssertEqual(payout.trigger, "return_window_close")
        // "You receive" is the server's figure. 6% of $10,000 is $600, and the
        // payout block states the $9,400 itself rather than leaving the client
        // to subtract one from the other.
        XCTAssertEqual(payout.amount?.value, Decimal(string: "9400.00"))
        XCTAssertEqual(payout.firstPayoutHold, true)
        XCTAssertNotNil(payout.expectedArrivalAt)
        XCTAssertNil(payout.releasedAt)
        XCTAssertEqual(payout.statusLabel, "Scheduled — releases when the return window closes")
        // Nothing seller-facing may leak the processor's vocabulary.
        let label = payout.statusLabel ?? ""
        for banned in ["Stripe", "balance", "connected account"] {
            XCTAssertFalse(label.localizedCaseInsensitiveContains(banned), "payout label leaked \"\(banned)\"")
        }

        let expected = try XCTUnwrap(order.expected)
        XCTAssertNotNil(expected.authenticationVerdictBy)
        XCTAssertNotNil(expected.deliveredBy)
        XCTAssertNotNil(expected.returnWindowEndsAt)
        XCTAssertEqual(expected.payout?.trigger, "return_window_close")
    }

    func testReturnStartResultReadsLabelAndDeadlineAsSiblings() throws {
        // `label` and `ship_deadline_at` arrive beside the return record,
        // not inside it.
        let json = """
        {
          "id": "ret_1", "order_id": "o1", "status": "requested",
          "requested_at": "2026-08-14T10:20:00+00:00",
          "ship_deadline_at": "2026-08-18T10:20:00+00:00",
          "label": {
            "shipment_id": "sh_9", "carrier": "FedEx", "tracking_number": "794612345098",
            "label_url": "/media/labels/return-794612345098.pdf"
          }
        }
        """
        let result = try apiDecoder().decode(ReturnStartResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.return.status, "requested")
        XCTAssertEqual(result.label?.trackingNumber, "794612345098")
        XCTAssertNotNil(result.shipDeadlineAt)
        XCTAssertEqual(
            result.label?.labelUrl?.url?.absoluteString,
            "https://api.test/media/labels/return-794612345098.pdf"
        )
    }

    // MARK: Offers — forfeiture

    func testOfferForfeitFixtureDecodes() throws {
        let offer = try apiDecoder().decode(
            Envelope<Offer>.self,
            from: fixtureData("offer-forfeit")
        ).data
        XCTAssertEqual(offer.status, .penaltyCaptured)
        XCTAssertNotNil(offer.paymentFailedAt)
        XCTAssertNotNil(offer.resolveBy)
        // The hold amount is the only source of the figure clients may show.
        XCTAssertEqual(offer.hold?.amount.value, Decimal(string: "250.00"))
        // The seller's net is the server's to compute, never the client's.
        XCTAssertEqual(offer.forfeit?.sellerAmount?.value, Decimal(string: "242.50"))
        XCTAssertNotNil(offer.forfeit?.forfeitedAt)
    }

    // MARK: Seller card, config, deletion

    func testSellerCardFixtureDecodes() throws {
        let card = try apiDecoder().decode(
            Envelope<SellerCardState>.self,
            from: fixtureData("seller-card")
        ).data
        XCTAssertTrue(card.present)
        XCTAssertEqual(card.funding, "credit")
        XCTAssertEqual(card.displayName, "Visa •••• 4242")
        XCTAssertEqual(card.expiryLabel, "09/26")
        XCTAssertTrue(card.needsAttention, "an expiring card is surfaced before it lapses")
    }

    func testMarketplaceConfigFixtureDecodes() throws {
        let config = try apiDecoder().decode(
            Envelope<MarketplaceConfig>.self,
            from: fixtureData("marketplace-config")
        ).data
        XCTAssertEqual(config.sellerFeePercentMember?.value, Decimal(string: "6.00"))
        XCTAssertEqual(config.sellerFeePercentDealer?.value, Decimal(string: "4.00"))
        XCTAssertEqual(config.sellerFeeMinimum?.value, Decimal(string: "250.00"))
        XCTAssertEqual(config.cardFee?.percent?.value, Decimal(string: "2.90"))
        XCTAssertEqual(config.cardFee?.fixed?.value, Decimal(string: "0.30"))
        XCTAssertEqual(config.offerHoldAmount?.value, Decimal(string: "250.00"))
        XCTAssertEqual(config.offerTtlHours, 24)
        XCTAssertEqual(config.offerPaymentGraceHours, 12)
        XCTAssertEqual(config.offerPaymentDeadlineHours, 24)
        XCTAssertEqual(config.returnWindows, [24, 48, 72])
        XCTAssertEqual(config.wireReservationText, "24–48 hours")
        XCTAssertEqual(config.discountStatesText, "CT and MA")
    }

    func testMarketplaceConfigAcceptsAScalarReservationWindow() throws {
        let json = #"{"wire_reservation_hours": 24, "discount_presentation_states": ["CT"]}"#
        let config = try apiDecoder().decode(MarketplaceConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.wireReservationHours, [24])
        XCTAssertEqual(config.wireReservationText, "24 hours")
        XCTAssertEqual(config.discountStatesText, "CT")
        XCTAssertNil(config.offerHoldAmount, "a missing figure stays nil so the UI omits the number")
    }

    func testAccountDeletionStateFixtureListsObligations() throws {
        let state = try apiDecoder().decode(
            Envelope<AccountDeletionState>.self,
            from: fixtureData("account-delete-request")
        ).data
        XCTAssertTrue(state.requested)
        XCTAssertFalse(state.canDelete)
        XCTAssertEqual(state.obligations.count, 3)
        XCTAssertEqual(state.obligations.first?.kind, "live_order")
        XCTAssertEqual(state.obligations.first?.reference, "CAL-3099")
        XCTAssertNil(state.scheduledDate, "nothing is scheduled while obligations remain")
    }

    // MARK: Support

    func testSupportThreadCarriesAssignedContact() throws {
        let thread = try apiDecoder().decode(
            Envelope<SupportConversation?>.self,
            from: fixtureData("support-thread-assigned")
        ).data
        let conversation = try XCTUnwrap(thread)
        XCTAssertEqual(conversation.status, .waitingOnCalibre)
        XCTAssertEqual(conversation.assignedContact?.displayName, "Amelia Hart")
        XCTAssertEqual(conversation.messages.count, 1)
    }

    func testSupportConversationStatusCoversTheNewStates() throws {
        let wire = ["open", "waiting_on_calibre", "waiting_on_customer", "closed"]
        let expected: [SupportConversationStatus] = [.open, .waitingOnCalibre, .waitingOnCustomer, .closed]
        for (raw, status) in zip(wire, expected) {
            let decoded = try apiDecoder().decode(
                SupportConversationStatus.self,
                from: Data("\"\(raw)\"".utf8)
            )
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: Listings — returns terms + dealer badge

    func testListingDetailCarriesReturnTermsAndDealerFlag() throws {
        let listing = try apiDecoder().decode(
            Envelope<Listing>.self,
            from: fixtureData("listing-detail")
        ).data
        XCTAssertEqual(listing.returns?.accepted, true)
        XCTAssertEqual(listing.returns?.windowHours, 48)
        XCTAssertEqual(listing.seller?.isVerifiedDealer, true)
        XCTAssertEqual(listing.countryOfOrigin, "CH")
        XCTAssertEqual(listing.htsCode, "9101.21.50")
    }

    func testListingsPageCarriesBothReturnStances() throws {
        let page = try apiDecoder().decode(
            Envelope<PageResponse<Listing>>.self,
            from: fixtureData("listings-page")
        ).data
        XCTAssertTrue(page.results.contains { $0.returns?.accepted == true })
        XCTAssertTrue(page.results.contains { $0.returns?.accepted == false })
        // A listing that doesn't accept returns carries no window.
        for listing in page.results where listing.returns?.accepted == false {
            XCTAssertNil(listing.returns?.windowHours)
        }
    }

    // MARK: Journal content

    func testJournalFeedFixtureDecodesWithoutBodies() throws {
        // The feed wraps its rows in `results`; the article endpoint answers
        // with the article itself. Decoding the feed as a bare array is the
        // shape mismatch this pins.
        let rows = try apiDecoder().decode(
            Envelope<JournalFeedPageProbe>.self,
            from: fixtureData("content-journal")
        ).data.results
        XCTAssertEqual(rows.count, 4)
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(first.id, "rolex-2026-releases")
        XCTAssertEqual(first.category, "Market")
        XCTAssertEqual(first.image, "rolex-2026-market.jpg")
        XCTAssertEqual(first.datePublishedISO, "2026-06-18T00:00:00Z")
        XCTAssertFalse(first.takeaways.isEmpty)
        // The feed omits bodies — they must default rather than fail.
        for row in rows {
            XCTAssertTrue(row.sections.isEmpty)
            XCTAssertTrue(row.sources.isEmpty)
            XCTAssertFalse(row.hasBody)
            XCTAssertFalse(row.title.isEmpty)
        }
    }

    func testJournalArticleFixtureDecodesWithBody() throws {
        let article = try apiDecoder().decode(
            Envelope<JournalArticle>.self,
            from: fixtureData("content-journal-article")
        ).data
        XCTAssertEqual(article.id, "rolex-2026-releases")
        XCTAssertTrue(article.hasBody)
        XCTAssertEqual(article.sections.count, 5)
        XCTAssertEqual(article.sources.count, 4)
        XCTAssertFalse(article.sections[0].heading.isEmpty)
        XCTAssertFalse(article.sections[0].paragraphs.isEmpty)
    }

    // MARK: market reference prices

    func testMarketReferencePricesFixtureDecodes() throws {
        let payload = try apiDecoder().decode(
            Envelope<MarketReferencePriceList>.self,
            from: fixtureData("market-reference-prices")
        ).data
        XCTAssertEqual(payload.asOf, "2026-08-23T14:05:20.235013Z")

        let priced = try XCTUnwrap(payload.references.first { $0.slug == "audemars-piguet-26574st-oo-1220st-02" })
        XCTAssertEqual(priced.brand, "Audemars Piguet")
        XCTAssertEqual(priced.reference, "26574ST.OO.1220ST.02")
        XCTAssertEqual(priced.price.value, Decimal(string: "23506.35"))
        XCTAssertEqual(priced.currency, "USD")
        // History is change-points, oldest first, always landing on today's
        // price — the chart depends on both ends of that promise.
        let history = priced.history
        XCTAssertEqual(history.first?.date, "2026-02-24")
        XCTAssertEqual(history.last?.date, "2026-08-23")
        XCTAssertEqual(history.last?.price.value, priced.price.value)
    }

    func testReferencePriceSpecsReadInSheetOrder() throws {
        let payload = try apiDecoder().decode(
            Envelope<MarketReferencePriceList>.self,
            from: fixtureData("market-reference-prices")
        ).data
        let priced = try XCTUnwrap(payload.references.first { $0.slug == "audemars-piguet-26574st-oo-1220st-02" })
        XCTAssertEqual(priced.specs.diameterMm, 41)
        XCTAssertEqual(priced.specs.dial, "Blue Grande Tapisserie")
        XCTAssertEqual(
            priced.specs.rows.map(\.label),
            ["Material", "Bezel", "Glass", "Back", "Shape", "Diameter", "Finish", "Dial", "Indexes", "Hands"]
        )
        // Millimetres render as one word, never a bare number.
        XCTAssertEqual(priced.specs.rows.first { $0.label == "Diameter" }?.value, "41mm")
    }

    func testUnfilledSpecsProduceNoRowsAtAll() throws {
        let payload = try apiDecoder().decode(
            Envelope<MarketReferencePriceList>.self,
            from: fixtureData("market-reference-prices")
        ).data
        // Most published references carry no specs yet. An empty sheet must
        // come back empty rather than as a column of dashes.
        let bare = try XCTUnwrap(payload.references.first { $0.slug == "a-lange-s-hne-191-032" })
        XCTAssertTrue(bare.specs.isEmpty)
        XCTAssertTrue(bare.specs.rows.isEmpty)
        XCTAssertNil(bare.specs.diameterMm)
    }

    func testMarketReferencePriceFixtureDecodes() throws {
        let price = try apiDecoder().decode(
            Envelope<MarketReferencePrice>.self,
            from: fixtureData("market-reference-price")
        ).data
        XCTAssertEqual(price.slug, "audemars-piguet-26574st-oo-1220st-02")
        XCTAssertEqual(price.model, "Royal Oak Perpetual Calendar")
        XCTAssertEqual(price.setAt, "2026-08-20T13:00:00Z")
        XCTAssertEqual(price.specs.material, "Stainless steel")
        XCTAssertEqual(price.history.last?.price.value, price.price.value)
    }

    // MARK: vault detail

    func testVaultWatchDetailSyntheticSampleDecodes() throws {
        let json = """
        {
          "id": "3f1c9d20-1111-4a1e-9f0c-2c9c0c0c0c0c",
          "source": "calibre_order",
          "authenticated": true,
          "order_id": "o1",
          "listing_id": "l1",
          "passport_code": "CAL-7F3A2B",
          "brand": "Audemars Piguet",
          "model": "Royal Oak Perpetual Calendar",
          "reference": "26574ST.OO.1220ST.02",
          "production_year": 2021,
          "nickname": null,
          "notes": "Bought at the boutique.",
          "photo_url": null,
          "acquired_price": "23000.00",
          "acquired_date": "2024-05-02",
          "estimated_value": "23506.35",
          "estimated_at": "2026-08-23T14:05:20Z",
          "created_at": "2024-05-02T10:00:00Z",
          "service_records": [
            {
              "id": "s1",
              "vault_watch_id": "3f1c9d20-1111-4a1e-9f0c-2c9c0c0c0c0c",
              "serviced_at": "2025-06-01",
              "provider": "AP Service",
              "details": "Full service.",
              "cost": "900.00",
              "created_at": "2025-06-02T09:00:00Z"
            }
          ],
          "reference_row": {
            "id": "70af3897-793a-40e6-99e9-0a3bed919425",
            "slug": "audemars-piguet-26574st-oo-1220st-02",
            "brand": "Audemars Piguet",
            "model": "Royal Oak Perpetual Calendar",
            "reference": "26574ST.OO.1220ST.02",
            "specs": {
              "material": "Stainless steel", "bezel": null, "glass": null, "back": null,
              "shape": null, "diameter_mm": 41, "finish": null, "dial": null,
              "indexes": null, "hands": null
            },
            "in_catalog": true
          },
          "pending_suggestion": false
        }
        """
        let detail = try apiDecoder().decode(VaultWatchDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.id, detail.watch.id)
        XCTAssertTrue(detail.watch.authenticated)
        XCTAssertEqual(detail.watch.passportCode, "CAL-7F3A2B")
        XCTAssertEqual(detail.serviceRecords.first?.provider, "AP Service")
        XCTAssertEqual(detail.referenceRow?.slug, "audemars-piguet-26574st-oo-1220st-02")
        XCTAssertEqual(detail.referenceRow?.inCatalog, true)
        XCTAssertEqual(detail.referenceRow?.specs.rows.map(\.label), ["Material", "Diameter"])
        XCTAssertFalse(detail.pendingSuggestion)
    }

    func testVaultWatchDetailWithoutACatalogRowDecodes() throws {
        let json = """
        {
          "id": "aa11", "source": "manual", "authenticated": false, "order_id": null,
          "listing_id": null, "passport_code": null, "brand": "Seiko", "model": null,
          "reference": "SBGA211", "production_year": null, "nickname": "Snowflake",
          "notes": null, "photo_url": null, "acquired_price": null, "acquired_date": null,
          "estimated_value": null, "estimated_at": null, "created_at": null,
          "service_records": [], "reference_row": null, "pending_suggestion": true
        }
        """
        let detail = try apiDecoder().decode(VaultWatchDetail.self, from: Data(json.utf8))
        XCTAssertNil(detail.referenceRow)
        XCTAssertTrue(detail.pendingSuggestion)
        XCTAssertTrue(detail.serviceRecords.isEmpty)
        XCTAssertEqual(detail.watch.displayTitle, "Snowflake")
    }

    func testAuthenticatedComesFromTheServerNotFromSource() throws {
        // The badge is the server's word. A client that re-derived it from
        // `source` would light this row up, and this test is what stops that
        // from being reintroduced quietly.
        let json = """
        {"id": "bb22", "source": "calibre_order", "authenticated": false, "order_id": "o9",
         "listing_id": null, "passport_code": null, "brand": "Rolex", "model": null,
         "reference": null, "production_year": null, "nickname": null, "notes": null,
         "photo_url": null, "acquired_price": null, "acquired_date": null,
         "estimated_value": null, "estimated_at": null, "created_at": null}
        """
        let watch = try apiDecoder().decode(VaultWatch.self, from: Data(json.utf8))
        XCTAssertFalse(watch.authenticated)
    }

    func testReferenceSuggestionResultDecodes() throws {
        let json = """
        {
          "id": "sug-1", "brand": "Seiko", "model": "Grand Seiko Snowflake",
          "reference": "SBGA211", "production_year": 2019, "notes": "Titanium case.",
          "specs": {
            "material": "Titanium", "bezel": null, "glass": "Sapphire", "back": null,
            "shape": "Round", "diameter_mm": 41, "finish": "Zaratsu", "dial": "Snowflake white",
            "indexes": "Applied", "hands": "Polished"
          },
          "submitted_at": "2026-08-25T09:00:00Z", "resolved_at": null
        }
        """
        let suggestion = try apiDecoder().decode(ReferenceSuggestion.self, from: Data(json.utf8))
        XCTAssertEqual(suggestion.reference, "SBGA211")
        XCTAssertEqual(suggestion.specs.diameterMm, 41)
        XCTAssertNil(suggestion.resolvedAt)
        XCTAssertEqual(suggestion.specs.rows.first?.value, "Titanium")
    }

    func testJournalArticleRoundTripsThroughTheOfflineCache() throws {
        // ContentStore persists articles with a plain JSONEncoder, so the
        // camelCase keys have to survive a re-decode without the API's
        // snake_case strategy.
        let article = try apiDecoder().decode(
            Envelope<JournalArticle>.self,
            from: fixtureData("content-journal-article")
        ).data
        let encoded = try JSONEncoder().encode(article)
        let restored = try JSONDecoder().decode(JournalArticle.self, from: encoded)
        XCTAssertEqual(restored, article)
    }
}

/// Mirrors `ContentStore`'s private feed wrapper, so the fixture that pins the
/// wire's shape and the code that reads it can never drift apart silently.
private struct JournalFeedPageProbe: Decodable {
    let results: [JournalArticle]
}
