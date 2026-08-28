import CalibreKit
import Foundation
import PostHog

/// The app's one analytics seam. Screens call the typed methods here and never
/// touch `PostHogSDK` directly, so the schema in
/// `Backend/docs/analytics-events.md` has exactly one place it can drift from.
///
/// Three rules the schema imposes and this type enforces centrally:
///
/// * Every capture carries `event_id` (a fresh lowercase UUID v4, so a future
///   server-side send of the same action can deduplicate against the client
///   send) and `platform: "ios"`.
/// * Names and property keys are snake_case verbatim. They are written as
///   string literals in one place — `Event` and the `send` calls below — and
///   nowhere else in the app.
/// * A property whose value the client genuinely does not have is **omitted**,
///   never invented. `properties(for:)` drops nil rather than substituting.
/// * `environment` rides on every event as a super property registered at
///   start-up, not as an argument threaded through each call — see
///   `environment` below.
///
/// Emission must never break the product: an empty `CALIBRE_POSTHOG_KEY`
/// disables the whole thing (the SDK is never even configured) and every entry
/// point is a silent no-op when disabled.
@MainActor
enum Analytics {

    // MARK: - Vocabulary

    /// `signup_completed.method`.
    enum SignupMethod: String {
        case email, apple, google
    }

    /// `listing_submitted.source`.
    enum ListingSource: String {
        case manual
        case bulkImport = "bulk_import"
    }

    /// `checkout_started.payment_method` / `purchase_completed.payment_method`.
    enum PaymentMethod: String {
        case card, wire
    }

    /// `checkout_started.pricing_mode` — which side of the card/wire spread the
    /// displayed breakdown is quoting.
    enum PricingMode: String {
        case surcharge, discount
    }

    /// The `environment` super property (contracts §12.1a). Exactly these
    /// three spellings on every platform — never `prod`, `dev` or `local` —
    /// because one PostHog project holds all of it and a fourth spelling is a
    /// year of production data quietly split in two.
    enum Environment: String {
        case production, staging, development
    }

    /// Resolved from the **build configuration**, which is the only thing that
    /// knows what this binary is. Explicitly not the APNs sandbox/production
    /// flag: that is push routing, and a TestFlight build is neither of those
    /// while still being a production build of the app.
    ///
    /// There is no staging configuration in this project yet. `STAGING` is the
    /// compilation condition a staging scheme would set, named here so the
    /// answer is already correct on the day one is added, rather than
    /// defaulting a staging build into production's funnels.
    static var environment: Environment {
        #if DEBUG
        return .development
        #elseif STAGING
        return .staging
        #else
        return .production
        #endif
    }

    /// The listing-shaped property group (`listing_id`, `brand`, `reference`,
    /// `price_band`) that most events carry. `brand` and `reference` are
    /// optional because several payloads (cart rows, watchlist rows, order
    /// rows) only ever carry a `ListingSummary`, which has no brand or
    /// reference field — those events go out without them, per the schema.
    struct ListingInfo {
        var id: String
        var brand: String?
        var reference: String?
        /// Listed price in USD. An accepted offer passes the agreed amount.
        var price: Decimal?

        init(id: String, brand: String? = nil, reference: String? = nil, price: Decimal? = nil) {
            self.id = id
            self.brand = brand
            self.reference = reference
            self.price = price
        }

        /// Full listing — every listing-shaped property is available.
        init(_ listing: Listing) {
            self.init(
                id: listing.id,
                brand: listing.brand,
                reference: listing.referenceNumber,
                price: listing.price.value
            )
        }

        /// Compact listing as embedded in cart / watchlist / order payloads.
        /// `ListingSummary` carries no brand or reference, so those are absent.
        init(_ summary: ListingSummary) {
            self.init(id: summary.id, price: summary.price.value)
        }

        /// Same listing, repriced — used when an accepted offer's agreed amount
        /// should drive `price_band` instead of the listed price.
        func priced(at amount: Decimal?) -> ListingInfo {
            var copy = self
            if let amount { copy.price = amount }
            return copy
        }
    }

    /// Band by listed price in USD. Edges are identical on every platform and
    /// are compared with `<` on the upper edge.
    static func priceBand(_ amount: Decimal) -> String {
        if amount < 5_000 { return "under_5k" }
        if amount < 10_000 { return "5k_10k" }
        if amount < 25_000 { return "10k_25k" }
        if amount < 50_000 { return "25k_50k" }
        return "50k_plus"
    }

    // MARK: - Lifecycle

    /// Configures the SDK once at launch. With an empty `CALIBRE_POSTHOG_KEY`
    /// this returns without calling `setup`, leaving analytics fully off — no
    /// network, no storage, no swizzling.
    static func start() {
        guard !isStarted else { return }
        isStarted = true

        guard let token = infoValue("CalibrePostHogKey"), !token.isEmpty else { return }
        let host = infoValue("CalibrePostHogHost") ?? defaultHost

        let configuration = PostHogConfig(projectToken: token, host: host)
        // Only the schema's events may be emitted. PostHog's automatic capture
        // would add screen views, lifecycle events and UI interactions on top
        // of them, so it is all switched off deliberately.
        configuration.captureScreenViews = false
        configuration.captureApplicationLifecycleEvents = false
        configuration.captureElementInteractions = false
        configuration.sessionReplay = false

        PostHogSDK.shared.setup(configuration)

        // Registered once, here, before anything can capture — a super
        // property rather than an argument on every `send`. Passed per call it
        // would eventually ship on an event that forgot it, and it would never
        // reach `$identify` or any event PostHog raises on its own behalf.
        PostHogSDK.shared.register(["environment": environment.rawValue])

        isEnabled = true
    }

    /// Called whenever the observed auth session's user id changes, including
    /// the launch-time restore. Idempotent: re-notifying with the same id does
    /// nothing, so the call site can wire it to an `onChange(initial: true)`
    /// without risking a `reset()` that would break anonymous-to-identified
    /// aliasing on a cold launch.
    static func sessionChanged(to userID: String?) {
        guard userID != identifiedUserID else { return }
        if let userID {
            identifiedUserID = userID
            guard isEnabled else { return }
            PostHogSDK.shared.identify(userID)
        } else {
            identifiedUserID = nil
            guard isEnabled else { return }
            PostHogSDK.shared.reset()
            // reset() deletes registered properties with the stored identity,
            // so the environment has to be re-registered or every event until
            // the next cold launch ships without it.
            PostHogSDK.shared.register(["environment": environment.rawValue])
        }
    }

    // MARK: - Events

    static func signupCompleted(method: SignupMethod) {
        send(.signupCompleted, ["method": method.rawValue])
    }

    static func sellerStarted() {
        // "First Connect-onboarding session is opened" — guarded here rather
        // than at the call sites so every entry into onboarding is covered by
        // one latch.
        guard !hasStartedSelling else { return }
        hasStartedSelling = true
        send(.sellerStarted, ["side": "seller"])
    }

    static func listingSubmitted(_ listing: ListingInfo, source: ListingSource) {
        send(.listingSubmitted, properties(for: listing, adding: [
            "side": "seller",
            "source": source.rawValue,
        ]))
    }

    static func offerStarted(_ listing: ListingInfo) {
        send(.offerStarted, properties(for: listing, adding: ["side": "buyer"]))
    }

    /// Fires **once per listing**. A checkout covering three watches calls
    /// this three times, and each call is its own event with its own
    /// `event_id` — a shared id would deduplicate two of them away.
    ///
    /// `pricingMode` is optional because the server's breakdown can carry a
    /// mode this build does not know. The schema's rule for that is to send
    /// the event without the property rather than invent a value; the same
    /// rule governs `checkoutGroupID`, which is additive and simply absent on
    /// a checkout the client has no group id for.
    static func checkoutStarted(
        _ listing: ListingInfo,
        paymentMethod: PaymentMethod,
        pricingMode: PricingMode?,
        fromOffer: Bool,
        checkoutGroupID: String? = nil
    ) {
        var extras: [String: Any] = [
            "payment_method": paymentMethod.rawValue,
            "from_offer": fromOffer,
            "side": "buyer",
        ]
        if let pricingMode { extras["pricing_mode"] = pricingMode.rawValue }
        addCheckoutGroup(checkoutGroupID, to: &extras)
        send(.checkoutStarted, properties(for: listing, adding: extras))
    }

    /// Fires **once per order**. `value` is that order's own grand total —
    /// its share of the purchase, exactly as the API reports it on the order,
    /// including its allocated share of the single card fee. It is never the
    /// combined total: summing `value` across a `checkout_group_id` is what
    /// the buyer paid, and that only holds if each event carries its share.
    static func purchaseCompleted(
        orderID: String,
        listing: ListingInfo,
        paymentMethod: PaymentMethod,
        value: Decimal,
        checkoutGroupID: String? = nil
    ) {
        var extras: [String: Any] = [
            "order_id": orderID,
            "payment_method": paymentMethod.rawValue,
            // The only raw amount in the schema; everything else uses a band.
            "value": NSDecimalNumber(decimal: value).doubleValue,
            "currency": "USD",
            "side": "buyer",
        ]
        addCheckoutGroup(checkoutGroupID, to: &extras)
        send(.purchaseCompleted, properties(for: listing, adding: extras))
    }

    /// The additive `checkout_group_id`, written only when we actually have
    /// one. An order placed before multi-item checkout existed has no group,
    /// and an event without the property is the schema's answer to that.
    private static func addCheckoutGroup(_ id: String?, to properties: inout [String: Any]) {
        guard let id, !id.isEmpty else { return }
        properties["checkout_group_id"] = id
    }

    static func watchViewed(_ listing: ListingInfo) {
        send(.watchViewed, properties(for: listing))
    }

    static func searchPerformed(query: String, resultsCount: Int, filtersActive: Bool) {
        send(.searchPerformed, [
            "query": query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "results_count": resultsCount,
            "zero_results": resultsCount == 0,
            "filters_active": filtersActive,
        ])
    }

    static func savedSearchCreated(query: String, hasFilters: Bool) {
        send(.savedSearchCreated, [
            "query": query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "has_filters": hasFilters,
        ])
    }

    static func watchRequestSubmitted(
        brand: String,
        reference: String?,
        watchReferenceID: String?,
        hasBudget: Bool
    ) {
        var properties: [String: Any] = [
            "brand": brand,
            "has_budget": hasBudget,
            "side": "buyer",
        ]
        // Absent, not empty, when the request names no reference / matched no
        // catalogue entry.
        if let reference, !reference.isEmpty { properties["reference"] = reference }
        if let watchReferenceID, !watchReferenceID.isEmpty {
            properties["watch_reference_id"] = watchReferenceID
        }
        send(.watchRequestSubmitted, properties)
    }

    static func watchAddedToCart(_ listing: ListingInfo) {
        send(.watchAddedToCart, properties(for: listing, adding: ["side": "buyer"]))
    }

    static func watchLiked(_ listing: ListingInfo) {
        send(.watchLiked, properties(for: listing))
    }

    static func reviewLeft(orderID: String, listingID: String, rating: Int) {
        send(.reviewLeft, [
            "order_id": orderID,
            "listing_id": listingID,
            "rating": rating,
        ])
    }

    /// The user tapped a push. `notification_id` is what joins this to the
    /// `push_delivered` the backend emitted for the same row, so the pair
    /// answers which categories are worth sending at all.
    ///
    /// Of the four messaging events the clients only ever emit this one — the
    /// other three are the backend's, which is where delivery and bounces are
    /// actually observed.
    static func pushOpened(notificationID: String, category: String, route: String?) {
        var properties: [String: Any] = [
            "notification_id": notificationID,
            "category": category,
        ]
        // Absent, not empty, on a push that carried no route.
        if let route, !route.isEmpty { properties["route"] = route }
        send(.pushOpened, properties)
    }

    // MARK: - Listing provenance

    /// Remembers that these drafts arrived from a bulk CSV/XLSX import.
    ///
    /// A listing carries no import provenance on the wire, and the import
    /// completion queue never submits anything itself — it only fills drafts
    /// in, and the seller submits them later from the shop, through the same
    /// control a wizard draft uses. Recording the queue's ids is what lets
    /// that one submit path report a truthful `source` instead of calling
    /// everything "manual". A CSV cannot carry photos, so every imported
    /// draft passes through the queue and gets recorded here.
    static func noteBulkImportedDrafts(_ listingIDs: some Sequence<String>) {
        var known = Set(UserDefaults.standard.stringArray(forKey: bulkImportedKey) ?? [])
        known.formUnion(listingIDs)
        // Bounded so the ledger can't grow without limit on a heavy importer.
        let trimmed = known.count > bulkImportedLimit
            ? Array(known.suffix(bulkImportedLimit))
            : Array(known)
        UserDefaults.standard.set(trimmed, forKey: bulkImportedKey)
    }

    /// `"bulk_import"` for a draft seen in an import completion queue on this
    /// device, `"manual"` otherwise.
    static func listingSource(for listingID: String) -> ListingSource {
        let known = UserDefaults.standard.stringArray(forKey: bulkImportedKey) ?? []
        return known.contains(listingID) ? .bulkImport : .manual
    }

    // MARK: - Emission

    /// The schema's event names, verbatim. Nothing outside this enum may name
    /// an event. `listing_approved` is intentionally missing, as are
    /// `push_delivered`, `email_delivered` and `email_bounced`: those are
    /// emitted by the backend only, which is the side that can see them.
    private enum Event: String {
        case signupCompleted = "signup_completed"
        case sellerStarted = "seller_started"
        case listingSubmitted = "listing_submitted"
        case offerStarted = "offer_started"
        case checkoutStarted = "checkout_started"
        case purchaseCompleted = "purchase_completed"
        case watchViewed = "watch_viewed"
        case searchPerformed = "search_performed"
        case savedSearchCreated = "saved_search_created"
        case watchRequestSubmitted = "watch_request_submitted"
        case watchAddedToCart = "watch_added_to_cart"
        case watchLiked = "watch_liked"
        case reviewLeft = "review_left"
        case pushOpened = "push_opened"
    }

    /// Adds the common properties and hands the event to the SDK. Capture is
    /// enqueued and flushed on PostHog's own background queue, so this returns
    /// immediately and never blocks the frame that triggered it.
    private static func send(_ event: Event, _ properties: [String: Any] = [:]) {
        guard isEnabled else { return }
        var payload = properties
        payload["event_id"] = UUID().uuidString.lowercased()
        payload["platform"] = "ios"
        PostHogSDK.shared.capture(event.rawValue, properties: payload)
    }

    /// Expands the listing-shaped property group, dropping anything the client
    /// does not actually have.
    private static func properties(
        for listing: ListingInfo,
        adding extras: [String: Any] = [:]
    ) -> [String: Any] {
        var properties = extras
        properties["listing_id"] = listing.id
        if let brand = listing.brand, !brand.isEmpty { properties["brand"] = brand }
        if let reference = listing.reference, !reference.isEmpty {
            properties["reference"] = reference
        }
        if let price = listing.price { properties["price_band"] = priceBand(price) }
        return properties
    }

    // MARK: - Configuration

    private static let defaultHost = "https://us.i.posthog.com"
    private static let sellerStartedKey = "analytics.sellerStarted.v1"
    private static let bulkImportedKey = "analytics.bulkImportedDrafts.v1"
    private static let bulkImportedLimit = 2_000

    private static var isStarted = false
    /// False until `start()` finds a non-empty key and configures the SDK.
    /// Every entry point above checks it, so a keyless build never reaches
    /// PostHog at all.
    private static var isEnabled = false
    private static var identifiedUserID: String?

    private static var hasStartedSelling: Bool {
        get { UserDefaults.standard.bool(forKey: sellerStartedKey) }
        set { UserDefaults.standard.set(newValue, forKey: sellerStartedKey) }
    }

    /// Trimmed Info.plist string, or nil when missing/blank. An unsubstituted
    /// `$(...)` placeholder counts as blank so a misconfigured build disables
    /// analytics instead of shipping a garbage token.
    private static func infoValue(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
