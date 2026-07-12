# P3 — Browse track

First read Docs/specs/shared-rules.md. Your simulator: **iPhone 17 Pro**. Derived data: /tmp/dd-p3. Screenshots: scratchpad/p3/.

You own: Calibre/Features/Home/, Browse/, ListingDetail/, Journal/, Cart/, Saved/, SellerStorefront/ (create dirs as needed). Replace P2's placeholder roots for Home in place.

Kit surface: CatalogStore (browse/metadata/home/detail/storefront/similar), CommerceStore (cart, watchlist, addresses), LocalSignals (recently viewed), AuthSession.require. Fixtures show exact shapes (Tests/Fixtures/*.json).

## Screens

1. **HomeScreen** (tab root) — the listings-first home the user demanded (never a pitch):
   - Header row: serif "Calibre" wordmark small + bag (cart) button with count badge → CartSheet; search field (tap → SearchScreen push).
   - Signed-in greeting line when authed ("Good evening, {firstName}." — time-aware, quiet).
   - Content rows, each horizontally scrolling ListingCards (LazyImage): "For you" (home feed recommended lane; fall back to popular for guests), "Fresh arrivals" (fresh lane), "Popular right now" (popular), "Recently viewed" (LocalSignals ids → fetch, only when non-empty). Brand chip rail (ChipRail from metadata top brands) → BrandScreen. One quiet Journal teaser card (latest article, editorial styling) → JournalArticleScreen.
   - Staggered fade-up on first load; ListingCardSkeleton rows while loading; pull-to-refresh.
2. **SearchScreen** — SearchField autofocus, debounced 200ms: facet suggestion rows (brand/model/reference matches from metadata) + listing suggestions (thumbnail, title, price); recent searches (LocalSignals-style small store you may add to kit as extension); submit → ResultsScreen.
3. **ResultsScreen / BrowseGrid** — 2-col LazyVGrid of ListingCards, infinite scroll (page on approach), toolbar: result count line ("214 watches"), Filter button (badge = active count) → FilterSheet, Sort menu (Newest / Price low→high / Price high→low / Most popular). Cell context menu (long-press): Save / Share. Swipe... grids don't swipe; save via context menu + PDP.
4. **FilterSheet** (SheetScaffold, large detent) — cascading Brand→Model→Reference pickers (metadata by_brand), Condition segmented, Year field, PriceRangeSlider (bounds from metadata), Box & papers toggle, the 8 secondary facets (Material, Dial color, Case size, Movement, Bracelet, Thickness, Lug width, Water resistance, Caliber) as compact selects, live count CTA "Show N watches" (debounced count query with include_total), "Clear all".
5. **BrandScreen** — brand hero (serif brand name, count), locked-brand grid + same filter/sort minus brand, "Explore other brands" chip rail.
6. **ListingDetailScreen (PDP)** — the hero screen, arrive via `.navigationTransition(.zoom)` from any ListingCard (matchedTransitionSource on cards):
   - Gallery pager (TabView page style): full-bleed square images, pinch → full-screen lightbox (fullScreenCover, zoomable ScrollView, drag-down dismiss), image counter dots, condition pill overlay.
   - Buy box: Eyebrow "{Brand} · Ref. {ref}", serif title, priceLarge, "Taxes and shipping calculated at checkout" caption; authenticated CalloutBand ("Inspected at our authentication center before it ships") → AuthenticationInfoSheet (static editorial content); spec quick-row (Condition / Year / Box & papers).
   - Action stack: Buy Now (primary, route .checkout(listingID, offerID: nil)), Make Offer (secondary, route .makeOffer(listingID)) or "Offer pending — view" when an open offer exists (GET /listings/{id}/offers when authed), Save toggle + Add to Bag (ghost row) with one-watch swap confirmation dialog when bag occupied (moves previous watch to Saved, toast).
   - Below: SpecList (brand/model/reference/year/box&papers + parsed description label:value lines), Condition grading SpecList (crystal/bezel/bracelet/clasp/caseback/overall as StatusBadges), seller card (AvatarInitial, username, sales count, StarRating avg + count → SellerStorefrontScreen), "Similar watches" row (similar query), seller notes paragraph.
   - ShareLink (uses {base}/listings/{id}/share-image.jpg URL + web listing URL). Record LocalSignals viewed. Guest: all read; actions gate via require().
7. **SellerStorefrontScreen** — header (avatar, @username, member-since, sales count, rating), reviews list (paginated, StarRating + comment + relative date), inventory grid of active listings.
8. **CartSheet** (from bag icon; also full CartScreen route if cleaner) — the single cart item card (image/title/price, Checkout primary, Save for later, Remove w/ confirm), one-watch explainer caption, Saved-for-later section below (Move to bag w/ swap dialog, View, Remove), unavailable states (Sold/Reserved badges, disabled checkout).
9. **SavedScreen** (You-tab route or Home entry; wire internally from your own screens) — grid of watchlist items; swipe-to-remove on rows... use grid cells with context menu Remove + an Edit mode; price-drop StatusBadge when listing price < saved-at price if detectable (skip if not in API — note it).
10. **JournalScreen + JournalArticleScreen** — index of bundled articles (Calibre/Resources/Journal/articles.json + images/): editorial cards (image, category eyebrow, serif title, excerpt, read time). Reader: large serif title, hero image, takeaways as a quiet accent card, sections with serif h2s, sources as links, generous line-height, no chrome. Load via a small JournalStore you create IN YOUR feature dir (Bundle decode).

## Notes
- Buy Now / Make Offer: those flows are another track's — your buttons must route via AppRouter routes (.checkout, .makeOffer(listingID)) if present in Route enum; if a case is missing, call a stub `router.open(...)` equivalent and note it for the orchestrator. NEVER build checkout/offer UI yourself.
- Metadata + home feed have 5-min disk cache — instant warm loads; still show skeletons on cold.
- Cart/watchlist need auth: gate with require("Sign in to save this watch" / "…to add to your bag").
- Verify: guest browse E2E (home rows real data, search, filters actually filter — check count changes, brand page, PDP gallery + lightbox, journal reader), signed-in save/bag flows incl. swap dialog, light+dark screenshots of: home, results grid, filter sheet, PDP top, PDP specs, lightbox, cart with item, journal reader.
