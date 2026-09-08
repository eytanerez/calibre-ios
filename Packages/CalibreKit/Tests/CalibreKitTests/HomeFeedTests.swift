import Foundation
import XCTest
@testable import CalibreKit

/// `GET /home/feed` — the server-composed feed, recorded from the running API
/// (`home-feed-guest.json`).
///
/// The thing under test is that this client *renders what it was given*: the
/// server's order, the server's sentences, the server's omissions. Anything
/// here that passes by re-deriving an answer locally would be the second
/// ranker this whole contract exists to delete.
final class HomeFeedTests: XCTestCase {

    private func recordedFeed() throws -> ComposedHomeFeed {
        try apiDecoder().decode(
            Envelope<ComposedHomeFeed>.self,
            from: fixtureData("home-feed-guest")
        ).data
    }

    /// The order the fixture itself carries, read straight out of the JSON so
    /// the expectation cannot drift away from the recording.
    private func recordedModuleTypes() throws -> [String] {
        let raw = try JSONSerialization.jsonObject(with: fixtureData("home-feed-guest"))
        let data = (raw as? [String: Any])?["data"] as? [String: Any]
        let modules = data?["modules"] as? [[String: Any]] ?? []
        return modules.compactMap { $0["type"] as? String }
    }

    func testTheFeedIsRenderedInTheOrderTheServerGaveIt() throws {
        let recorded = try recordedModuleTypes()
        XCTAssertFalse(recorded.isEmpty, "The recording has no modules; every assertion below would be vacuous.")

        let feed = try recordedFeed()

        XCTAssertEqual(feed.modules.map(\.type), recorded)
        XCTAssertEqual(feed.renderableModules.map(\.type), recorded)
        XCTAssertEqual(feed.modules.last?.type, "end_of_feed", "The feed has to end explicitly.")
    }

    func testTheEnvelopeSaysWhoItIsForAndWhetherItIsWhole() throws {
        let feed = try recordedFeed()

        XCTAssertEqual(feed.feedVersion, 1)
        XCTAssertEqual(feed.audience, "guest")
        XCTAssertFalse(feed.degraded)
        XCTAssertFalse(feed.refreshed)
        // A module that had nothing true to say is simply absent. `omitted` is
        // for a builder that *failed*, and confusing the two turns an honest
        // empty state into a fault report.
        XCTAssertEqual(feed.omitted, [])
        XCTAssertFalse(feed.modules.contains { $0.type == "your_collection" })
        XCTAssertFalse(feed.modules.contains { $0.type == "saved_search_matches" })
        XCTAssertTrue(feed.validUntil > feed.generatedAt)
    }

    func testAListingModuleCarriesItsCardsAndOnlyTheReasonsTheServerSent() throws {
        let feed = try recordedFeed()
        let shopWindow = try XCTUnwrap(feed.modules.first { $0.type == "worth_a_look" })

        XCTAssertFalse(shopWindow.cards.isEmpty)
        XCTAssertEqual(shopWindow.action?.route, "buy")
        // The old shelf's "View all" always asked for popular results while the
        // shelf claimed to be personal. The action now comes from the server
        // and points at the same inventory the module was drawn from.
        XCTAssertEqual(shopWindow.action?.label, "View all inventory")

        for card in shopWindow.cards {
            XCTAssertEqual(card.id, card.listing.id)
            // A guest has no affinity, so the ranker cannot justify a reason
            // and does not invent one. Null is the honest answer and the
            // client has nothing to print.
            XCTAssertNil(card.reason)
        }
    }

    func testAReasonIsPrintedVerbatimAndNeverComposedFromItsCode() throws {
        // A reason code this build has never heard of still carries a sentence,
        // and the sentence is what goes on the card. That is the whole reason
        // the server sends both.
        let json = """
        {"id": "l1", "listing": \(Self.listingJSON), "signal": null,
         "reason": {"code": "some_new_code", "text": "Because of a thing this build has never heard of",
                    "evidence": [{"type": "listing", "id": "l9"}]}}
        """
        let card = try apiDecoder().decode(HomeFeedCard.self, from: Data(json.utf8))

        XCTAssertEqual(card.reason?.text, "Because of a thing this build has never heard of")
        XCTAssertEqual(card.reason?.code, "some_new_code")
        XCTAssertEqual(card.reason?.evidence.first?.id, "l9")
    }

    func testAModuleTypeThisBuildHasNeverHeardOfIsSkippedAndTheRestStillRender() throws {
        // The additive contract, and the only reason an installed app keeps
        // working after the server learns a new module: an unknown `type` is
        // skipped, the feed is not abandoned at it, and nothing is guessed at.
        let json = """
        {"feed_version": 1, "feed_day": "2026-09-07", "generated_at": "2026-09-07T01:00:00Z",
         "valid_until": "2026-09-07T01:05:00Z", "audience": "guest", "refreshed": false,
         "degraded": false, "omitted": [],
         "modules": [
           {"type": "worth_a_look", "title": "Worth a look", "subtitle": null,
            "action": {"label": "View all inventory", "route": "buy"}, "source_records": [],
            "cards": [{"id": "l1", "listing": \(Self.listingJSON), "reason": null, "signal": null}]},
           {"type": "auction_countdown", "title": "Ending soon", "subtitle": null,
            "action": {"label": "See the room", "route": "auctions"}, "source_records": [],
            "lots": [{"id": "a1", "closes_at": "2026-09-08T01:00:00Z"}]},
           {"type": "end_of_feed", "title": "That's everything for you today.", "subtitle": null,
            "action": {"label": "Browse all inventory", "route": "buy"}, "source_records": [],
            "state": "complete"}
         ]}
        """
        let feed = try apiDecoder().decode(ComposedHomeFeed.self, from: Data(json.utf8))

        XCTAssertEqual(feed.modules.count, 3)
        XCTAssertEqual(feed.renderableModules.map(\.type), ["worth_a_look", "end_of_feed"])
        XCTAssertTrue(try XCTUnwrap(feed.modules.first { $0.type == "auction_countdown" }).isUnrecognized)
        XCTAssertEqual(feed.renderableModules.last?.type, "end_of_feed")
    }

    func testAModuleIsAskedForByNameAndAnUnknownTypeIsNeverReturned() throws {
        // Home places the feed's modules between shelves of its own, so it asks
        // for each one by name rather than walking the array. A type this build
        // has never heard of must not come back from that lookup — it would be
        // drawn as whichever composition asked for it.
        let feed = try apiDecoder().decode(ComposedHomeFeed.self, from: Data("""
        {"feed_version": 1, "feed_day": "2026-09-07", "generated_at": "2026-09-07T01:00:00Z",
         "valid_until": "2026-09-07T01:05:00Z", "audience": "guest", "refreshed": false,
         "degraded": false, "omitted": [],
         "modules": [
           {"type": "worth_a_look", "title": "Worth a look", "subtitle": null,
            "action": {"label": "View all inventory", "route": "buy"}, "source_records": [],
            "cards": [{"id": "l1", "listing": \(Self.listingJSON), "reason": null, "signal": null}]},
           {"type": "auction_countdown", "title": "Ending soon", "subtitle": null,
            "action": null, "source_records": [],
            "lots": [{"id": "a1", "closes_at": "2026-09-08T01:00:00Z"}]}
         ]}
        """.utf8))

        XCTAssertEqual(feed.module(ofType: "worth_a_look")?.cards.count, 1)
        XCTAssertNil(feed.module(ofType: "auction_countdown"))
        // Sent by neither this response nor any other: absent, not empty.
        XCTAssertNil(feed.module(ofType: "your_collection"))
    }

    func testTheGreetingShelfIsTheServersModuleUnderThisScreensHeading() throws {
        let feed = try recordedFeed()
        let served = try XCTUnwrap(feed.module(ofType: "worth_a_look"))
        let greeted = served.retitled("Hi Eytan, here are some watches for you")

        XCTAssertEqual(greeted.title, "Hi Eytan, here are some watches for you")
        // Everything else is the server's and has to survive the swap: the
        // heading is the only part of this module the screen writes.
        XCTAssertEqual(greeted.type, served.type)
        XCTAssertEqual(greeted.subtitle, served.subtitle)
        XCTAssertEqual(greeted.action?.route, served.action?.route)
        XCTAssertEqual(greeted.action?.label, served.action?.label)
        XCTAssertEqual(greeted.cards.map(\.id), served.cards.map(\.id))
        XCTAssertEqual(greeted.cards.map { $0.reason?.text }, served.cards.map { $0.reason?.text })
        XCTAssertFalse(greeted.cards.isEmpty, "An empty card list would make the comparison vacuous.")
    }

    func testTheGreetingNameFollowsTheAddressBooksOwnOrder() throws {
        // Billing first, then shipping, then whatever is on file — the same
        // order the server resolves its own greeting in, so the two can never
        // call the same member two different things.
        let book = try Self.addresses("""
        [{"id": "a1", "first_name": "Shipping", "line1": "1 A St", "city": "Boca Raton",
          "postal_code": "33432", "country": "US", "is_default_shipping": true,
          "is_default_billing": false},
         {"id": "a2", "first_name": "Billing", "line1": "2 B St", "city": "Boca Raton",
          "postal_code": "33432", "country": "US", "is_default_shipping": false,
          "is_default_billing": true}]
        """)
        XCTAssertEqual(HomeGreeting.firstName(from: book), "Billing")

        let shippingOnly = try Self.addresses("""
        [{"id": "a1", "first_name": "Shipping", "line1": "1 A St", "city": "Boca Raton",
          "postal_code": "33432", "country": "US", "is_default_shipping": true,
          "is_default_billing": false}]
        """)
        XCTAssertEqual(HomeGreeting.firstName(from: shippingOnly), "Shipping")

        // A one-field address book still knows the name.
        let fullNameOnly = try Self.addresses("""
        [{"id": "a1", "full_name": "Eytan Erez", "line1": "1 A St", "city": "Boca Raton",
          "postal_code": "33432", "country": "US", "is_default_shipping": false,
          "is_default_billing": false}]
        """)
        XCTAssertEqual(HomeGreeting.firstName(from: fullNameOnly), "Eytan")

        // A guest, or a member who has never checked out. The shelf still has a
        // heading, and it does not have a hole in it.
        XCTAssertEqual(HomeGreeting.firstName(from: []), HomeGreeting.fallbackName)
        XCTAssertEqual(
            HomeGreeting.watchesForYouTitle(addresses: []),
            "Hi there, here are some watches for you"
        )
        XCTAssertEqual(
            HomeGreeting.watchesForYouTitle(addresses: fullNameOnly),
            "Hi Eytan, here are some watches for you"
        )
    }

    private static func addresses(_ json: String) throws -> [Address] {
        try apiDecoder().decode([Address].self, from: Data(json.utf8))
    }

    func testVotingPatchesThePollModuleAndTouchesNothingElse() throws {
        let feed = try recordedFeed()
        let before = try XCTUnwrap(feed.modules.first { $0.type == "todays_poll" })
        guard case .poll(let prompt) = before.body else {
            return XCTFail("The recorded feed's poll module carries no question.")
        }
        XCTAssertNil(prompt.results, "A question nobody has answered reveals nothing yet.")

        let voted = try apiDecoder().decode(CommunityPrompt.self, from: Data("""
        {"id": "\(prompt.id)", "question": "\(prompt.question)", "kind": "watch",
         "options": [{"key": "royal-oak", "label": "Royal Oak"}],
         "asked_on": "2026-09-07", "closed": false, "my_vote": "royal-oak",
         "results": {"total_votes": 1, "options": [
            {"key": "royal-oak", "label": "Royal Oak", "votes": 1, "percent": 100},
            {"key": "nautilus", "label": "Nautilus", "votes": 0, "percent": 0}]}}
        """.utf8))

        let patched = feed.replacingPoll(voted)
        let after = try XCTUnwrap(patched.modules.first { $0.type == "todays_poll" })
        guard case .poll(let updated) = after.body else {
            return XCTFail("The patched module stopped being a poll.")
        }

        XCTAssertEqual(updated.myVote, "royal-oak")
        XCTAssertEqual(updated.results?.totalVotes, 1)
        // Zero is a real count and has to survive the round trip — an option
        // nobody picked is not an option with no answer.
        XCTAssertEqual(updated.results?.options.last?.votes, 0)
        // Everything else is untouched, which is what makes patching in place
        // safe: no other module is recomputed to redraw one bar chart.
        XCTAssertEqual(patched.modules.map(\.type), feed.modules.map(\.type))
        XCTAssertEqual(
            patched.modules.first { $0.type == "worth_a_look" }?.cards.map(\.id),
            feed.modules.first { $0.type == "worth_a_look" }?.cards.map(\.id)
        )
    }

    func testTheEndOfFeedStateIsTheServersAndTheDegradedOneOffersNoBrowseAction() throws {
        let feed = try recordedFeed()
        let end = try XCTUnwrap(feed.modules.last)
        guard case .endOfFeed(let state) = end.body else {
            return XCTFail("The last module is not the terminator.")
        }
        XCTAssertEqual(state, "impersonal")
        XCTAssertFalse(end.title.isEmpty)

        let degraded = try apiDecoder().decode(HomeFeedModule.self, from: Data("""
        {"type": "end_of_feed", "title": "Some of your feed couldn't load.", "subtitle": null,
         "action": null, "source_records": [], "state": "degraded"}
        """.utf8))
        guard case .endOfFeed(let degradedState) = degraded.body else {
            return XCTFail("Decoded the terminator as something else.")
        }
        XCTAssertEqual(degradedState, "degraded")
        XCTAssertNil(degraded.action)
    }

    func testTheNextStepAndCollectionBodiesDecodeTheShapeTheServerDocuments() throws {
        let step = try apiDecoder().decode(HomeFeedModule.self, from: Data("""
        {"type": "your_next_step", "title": "Ship order #1041 to authentication",
         "subtitle": "Give us the parcel's size and weight and we'll buy the label.",
         "action": {"label": "Open the order", "route": "order/6b2f"},
         "source_records": [{"type": "order", "id": "6b2f"}],
         "step": {"code": "seller_ship_to_auth", "due_at": "2026-09-08T17:00:00Z",
                  "reference_label": "#1041"}}
        """.utf8))
        guard case .nextStep(let body) = step.body else {
            return XCTFail("your_next_step decoded as something else.")
        }
        XCTAssertEqual(body.code, "seller_ship_to_auth")
        XCTAssertEqual(body.referenceLabel, "#1041")
        XCTAssertNotNil(body.dueAt)

        let collection = try apiDecoder().decode(HomeFeedModule.self, from: Data("""
        {"type": "your_collection", "title": "Your collection", "subtitle": null,
         "action": {"label": "Open your collection", "route": "vault"},
         "source_records": [{"type": "vault_watch", "id": "77bd"}],
         "collection": {"watch_count": 4, "authenticated_count": 2, "valued_count": 0,
           "estimated_total": null,
           "watches": [{"id": "77bd", "brand": "Tudor", "model": "Black Bay Pro",
             "reference": "M79470-0001", "photo_url": null, "passport_code": "CAL-7Q2M",
             "authenticated": true, "estimated_value": null}]}}
        """.utf8))
        guard case .collection(let body) = collection.body else {
            return XCTFail("your_collection decoded as something else.")
        }
        XCTAssertEqual(body.watchCount, 4)
        // Nothing carries a stated figure, so there is no total to print and
        // the module shows the count alone.
        XCTAssertEqual(body.valuedCount, 0)
        XCTAssertNil(body.estimatedTotal)
        XCTAssertEqual(body.watches.first?.displayTitle, "Tudor Black Bay Pro")
    }

    func testTheRoutesThisBuildCanPlaceAndTheOnesItRefusesTo() {
        XCTAssertEqual(HomeFeedRoute("buy"), .buy)
        XCTAssertEqual(HomeFeedRoute("buy?sort=newest"), .buyNewest)
        XCTAssertEqual(HomeFeedRoute("alerts"), .alerts)
        XCTAssertEqual(HomeFeedRoute("support"), .support)
        XCTAssertEqual(HomeFeedRoute("vault"), .vault)
        XCTAssertEqual(HomeFeedRoute("community"), .community)
        XCTAssertEqual(HomeFeedRoute("listing/abc"), .listing("abc"))
        XCTAssertEqual(HomeFeedRoute("offer/abc"), .offer("abc"))
        XCTAssertEqual(HomeFeedRoute("order/abc"), .order("abc"))
        XCTAssertEqual(HomeFeedRoute("journal/some-slug"), .journalArticle("some-slug"))
        XCTAssertEqual(HomeFeedRoute("bites/some-slug"), .bite("some-slug"))
        XCTAssertEqual(HomeFeedRoute("seller/lt1209"), .seller("lt1209"))

        // The return case is a card on the order's own screen, so the order is
        // where this route actually resolves.
        XCTAssertEqual(HomeFeedRoute("order/abc/return"), .order("abc"))

        // The seller's own listing editor is not a screen this app has, and it
        // must not fall through to that seller's public storefront.
        XCTAssertNil(HomeFeedRoute("seller/listings/abc"))
        // A route from a newer server costs one missing CTA, never a wrong
        // destination.
        XCTAssertNil(HomeFeedRoute("auctions/lot/9"))
        XCTAssertNil(HomeFeedRoute("something-new"))
        XCTAssertNil(HomeFeedRoute("listing/"))
        XCTAssertNil(HomeFeedRoute(""))
    }

    func testTheBiteModuleCarriesItsSlotAndAnArchiveBiteKeepsItsOwnDate() throws {
        // Fixed dates, not `Date.now`: the assertion is that an archive-slot
        // Bite is never re-dated to look like today's, and a test computing
        // today's date could not tell the two apart. The slot is also a wire
        // value — one named on the server that this build has never heard of
        // must not fail the module.
        let module = try apiDecoder().decode(HomeFeedModule.self, from: Data("""
        {"type": "todays_bite", "title": "Today's bite", "subtitle": null,
         "action": {"label": "Read it", "route": "bites/papers-prove-less-than-you-think"},
         "source_records": [{"type": "bite", "id": "papers-prove-less-than-you-think"}],
         "slot": "some_new_slot",
         "bite": {"id": "papers-prove-less-than-you-think",
           "title": "A warranty card proves a sale happened.", "topic": "provenance",
           "body": "Box and papers reliably raise what a watch sells for.",
           "author": "Calibre Desk", "date": "June 18, 2026", "datePublishedISO": "2026-06-18",
           "isArchive": true, "archived": false, "image": null, "imageAlt": null,
           "sources": [{"href": "https://buycalibre.com/journal", "label": "The Calibre Journal"}],
           "article": null, "next": null, "correctedOn": null, "correctionNote": null}}
        """.utf8))

        guard case .bite(let slot, let bite) = module.body else {
            return XCTFail("todays_bite decoded as something else.")
        }
        XCTAssertEqual(slot, "some_new_slot")
        XCTAssertTrue(bite.isArchive)
        XCTAssertEqual(bite.datePublishedISO, "2026-06-18")
        XCTAssertEqual(bite.date, "June 18, 2026")
        XCTAssertEqual(module.action?.route, "bites/papers-prove-less-than-you-think")
    }

    func testASignalToneThisBuildHasNeverHeardOfStillDecodes() throws {
        let json = """
        {"id": "l1", "listing": \(Self.listingJSON), "reason": null,
         "signal": {"code": "auction_closing", "label": "Closing soon", "tone": "urgent"}}
        """
        let card = try apiDecoder().decode(HomeFeedCard.self, from: Data(json.utf8))

        XCTAssertEqual(card.signal?.tone, "urgent")
        XCTAssertEqual(card.signal?.label, "Closing soon")
    }

    // MARK: - Fill-ins

    func testAFillInPrintsNoReasonWhateverItArrivedWith() throws {
        // Flagged, and with a reason attached anyway: the flag wins. A fill-in
        // is by definition a card nobody justified, so the sentence is not
        // printed even though the server sent one.
        let flagged = try apiDecoder().decode(HomeFeedCard.self, from: Data("""
        {"id": "l1", "listing": \(Self.listingJSON), "signal": null, "is_fill": true,
         "reason": {"code": "brand_affinity", "text": "You keep coming back to Tudor", "evidence": []}}
        """.utf8))
        XCTAssertTrue(flagged.isFill)
        XCTAssertNotNil(flagged.reason, "The reason has to survive decoding for the suppression to mean anything.")
        XCTAssertNil(flagged.reasonLine)

        // Unflagged and reason-less: treated as a fill-in on the reason alone.
        let unflagged = try apiDecoder().decode(HomeFeedCard.self, from: Data("""
        {"id": "l1", "listing": \(Self.listingJSON), "signal": null, "is_fill": false, "reason": null}
        """.utf8))
        XCTAssertFalse(unflagged.isFill)
        XCTAssertNil(unflagged.reasonLine)

        // Ranked: the sentence prints, verbatim.
        let ranked = try apiDecoder().decode(HomeFeedCard.self, from: Data("""
        {"id": "l1", "listing": \(Self.listingJSON), "signal": null, "is_fill": false,
         "reason": {"code": "brand_affinity", "text": "You keep coming back to Tudor", "evidence": []}}
        """.utf8))
        XCTAssertFalse(ranked.isFill)
        XCTAssertEqual(ranked.reasonLine, "You keep coming back to Tudor")
    }

    func testAServerFromBeforeTheFillFlagStillDecodesAndItsCardsAreRanked() throws {
        // The recording predates `is_fill`. Its cards carry no flag at all,
        // and every one of them has to decode as a ranked card rather than
        // failing the module — the flag is read when present, never required.
        let feed = try recordedFeed()
        let cards = try XCTUnwrap(feed.module(ofType: "worth_a_look")).cards
        XCTAssertFalse(cards.isEmpty, "An empty shelf would make the check below vacuous.")
        for card in cards {
            XCTAssertFalse(card.isFill)
        }

        let raw = try JSONSerialization.jsonObject(with: fixtureData("home-feed-guest"))
        let data = (raw as? [String: Any])?["data"] as? [String: Any]
        let modules = data?["modules"] as? [[String: Any]] ?? []
        let shelf = modules.first { $0["type"] as? String == "worth_a_look" }
        let recordedCards = shelf?["cards"] as? [[String: Any]] ?? []
        XCTAssertEqual(recordedCards.count, cards.count)
        XCTAssertTrue(
            recordedCards.allSatisfy { $0["is_fill"] == nil },
            "The recording now carries is_fill; this test's premise is gone and the tolerance check above is no longer exercising anything."
        )
    }

    // MARK: - The running order

    private static let everySection: Set<HomeSection> = [
        .nextStep, .watchesForYou, .recentlyViewed, .brands, .popular, .freshArrivals,
        .savedSearches, .bite, .poll, .collection, .endOfFeed,
    ]

    func testTheMemberPageRunsTheSitesOrderAndTheGuestPageIsTheSameSkeletonWithLess() {
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .member, feed: .loaded, present: Self.everySection),
            [
                .nextStep, .watchesForYou, .bite, .recentlyViewed, .brands, .popular, .freshArrivals,
                .savedSearches, .poll, .collection, .endOfFeed,
            ]
        )

        // The guest opens with the newest shelf where the member's ranked one
        // sits, and gets none of what only a member has — even when the server
        // sent it. The guest feed carries a poll and a terminator; the guest
        // page draws neither, and the ranked module is not drawn for a guest
        // under a greeting that has nobody to greet.
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .guest, feed: .loaded, present: Self.everySection),
            [.freshArrivals, .bite, .brands, .popular]
        )
    }

    /// The Bite sits directly under the first row of watches and above
    /// Recently viewed — the same slot relative to the first shelf on both
    /// pages, whichever shelf that is.
    func testTheBiteSitsDirectlyUnderTheFirstShelfAndAboveRecentlyViewed() throws {
        let member = HomeRunningOrder.sections(audience: .member, feed: .loaded, present: Self.everySection)
        let shelf = try XCTUnwrap(member.firstIndex(of: .watchesForYou))
        let recent = try XCTUnwrap(member.firstIndex(of: .recentlyViewed))
        XCTAssertEqual(member.firstIndex(of: .bite), shelf + 1)
        XCTAssertEqual(recent, shelf + 2)

        let guest = HomeRunningOrder.sections(audience: .guest, feed: .loaded, present: Self.everySection)
        let newest = try XCTUnwrap(guest.firstIndex(of: .freshArrivals))
        XCTAssertEqual(guest.firstIndex(of: .bite), newest + 1)

        // The slot is relative to the shelf, not to the page: with the shelf
        // still loading, or failed, the Bite follows whatever stands in for it
        // and still comes before Recently viewed.
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .member, feed: .loading, present: [.bite, .recentlyViewed, .brands]),
            [.feedLoading, .bite, .recentlyViewed, .brands]
        )
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .guest, feed: .failed, present: [.bite, .brands]),
            [.feedUnavailable, .bite, .brands]
        )
    }

    func testASectionWithNothingToShowIsAbsentRatherThanAnEmptyFrame() {
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .member, feed: .loaded, present: [.bite, .brands, .popular]),
            [.bite, .brands, .popular]
        )
        XCTAssertEqual(HomeRunningOrder.sections(audience: .guest, feed: .loaded, present: []), [])
        XCTAssertEqual(HomeRunningOrder.sections(audience: .member, feed: .loaded, present: []), [])
    }

    func testTheSkeletonAndTheRetryTakeTheFirstShelfsSlotAndThePageGoesOnBelowEither() {
        // A load in flight is the skeleton in the ranked shelf's slot, and the
        // page goes on below it: the shelves that run their own queries draw
        // around a shelf that is still loading, as they do on the site.
        XCTAssertEqual(
            HomeRunningOrder.sections(
                audience: .member, feed: .loading, present: [.recentlyViewed, .brands, .popular, .freshArrivals]
            ),
            [.feedLoading, .recentlyViewed, .brands, .popular, .freshArrivals]
        )
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .guest, feed: .loading, present: [.freshArrivals, .brands]),
            [.feedLoading, .freshArrivals, .brands]
        )
        // The slot is the ranked shelf's — below the member's next-step band,
        // first on the guest page.
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .member, feed: .loading, present: [.nextStep, .brands]),
            [.nextStep, .feedLoading, .brands]
        )
        // With nothing else on hand yet, the skeleton stands alone: the slot
        // is filled, and the rest is absent rather than an empty frame.
        XCTAssertEqual(HomeRunningOrder.sections(audience: .member, feed: .loading, present: []), [.feedLoading])
        XCTAssertEqual(HomeRunningOrder.sections(audience: .guest, feed: .loading, present: []), [.feedLoading])

        // A failed request takes the same slot, and the page goes on below it
        // the same way.
        XCTAssertEqual(
            HomeRunningOrder.sections(
                audience: .member, feed: .failed, present: [.recentlyViewed, .brands, .popular, .freshArrivals]
            ),
            [.feedUnavailable, .recentlyViewed, .brands, .popular, .freshArrivals]
        )
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .guest, feed: .failed, present: [.freshArrivals, .brands]),
            [.feedUnavailable, .freshArrivals, .brands]
        )
        // Both are decided by the feed's state alone: naming either as present
        // does not draw it over a feed that loaded, and neither is drawn in
        // the other's state — the slot has one occupant.
        XCTAssertEqual(
            HomeRunningOrder.sections(
                audience: .member, feed: .loaded, present: [.feedLoading, .feedUnavailable, .brands]
            ),
            [.brands]
        )
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .guest, feed: .loading, present: [.feedUnavailable]),
            [.feedLoading]
        )
        XCTAssertEqual(
            HomeRunningOrder.sections(audience: .guest, feed: .failed, present: [.feedLoading]),
            [.feedUnavailable]
        )
    }

    /// The card-view listing shape, exactly as `_serialize_listing_card` sends
    /// it. Trimmed to the keys the decoder requires.
    private static let listingJSON = """
    {"id": "l1", "listing_number": 1, "seller_id": "s1", "seller": null, "variant_id": null,
     "title": "Tudor Black Bay Pro M79470-0001", "brand": "Tudor", "model": "Black Bay Pro",
     "reference_number": "M79470-0001", "description": null, "price": "4400.00",
     "currency": "USD", "condition": {"overall": "Like New"}, "box_papers": false,
     "production_year": 2024, "status": "active", "review_status": "active",
     "seller_status": "live", "review_events": [], "images": [], "estimated_shipping": null,
     "metrics": {"views": 3, "watchers": 1}, "created_at": "2026-09-04T21:12:09Z",
     "updated_at": "2026-09-06T00:57:53Z"}
    """
}
