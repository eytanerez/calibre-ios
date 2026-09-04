import CalibreDesign
import CalibreKit
import SwiftUI

/// The product detail page — gallery, buy box, authentication callout,
/// specs, condition grading, seller, and similar watches. Guests can read
/// everything; save/bag/buy/offer gate through the auth session.
struct ListingDetailScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.browsePush) private var push

    let listingID: String

    @State private var listing: Listing?
    @State private var similar: [Listing] = []
    @State private var openOffer: Offer?
    @State private var failed = false
    @State private var lightbox: LightboxContext?
    @State private var showAuthenticationInfo = false
    @State private var showMakeOfferStub = false
    /// Display pricing — the read-only quote behind the all-in toggle. Built
    /// fresh per listing so the toggle always starts off.
    @State private var pricing: ListingPricingModel?
    @State private var showAddressBook = false
    @Namespace private var similarNamespace
    /// Guards `load()`'s commit: `.task(id:)` cancels the in-flight load when
    /// `listingID` changes, but a manual "Try again" tap can still overlap
    /// with it — this keeps the slower of the two from winning.
    @State private var loadGeneration = 0
    /// The listing `watch_viewed` has already been sent for. Scoped to this
    /// screen instance, so it survives every re-render and a "Try again"
    /// reload, and keyed by id so a push to a different listing on the same
    /// instance still counts as a view.
    @State private var viewedListingID: String?
    /// Set when the detail endpoint refused this listing rather than failing
    /// to arrive. Item 18.6: `ListingDetailView` 404s a sold watch to everyone
    /// but its seller (`_can_view_non_active_listing` /
    /// `listing_claimable_by_buyer` in the backend), and the screen used to
    /// answer that 404 with "Check your connection and try again" over a
    /// "Try again" button that could never work. A watch that has sold is not
    /// a network problem and must not be dressed as one.
    @State private var gone: GoneReason?

    /// Why a listing is not here. Both arms are honest endings, not retries.
    enum GoneReason {
        case sold
        case withdrawn
    }

    var body: some View {
        Group {
            if let listing {
                content(listing)
            } else if let gone {
                goneState(gone)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                EmptyState(
                    icon: "clock.badge.questionmark",
                    title: "This watch is out of reach",
                    message: "We couldn't load this listing. Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    failed = false
                    Task { await load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                skeleton
            }
        }
        .calibrePageBackground()
        .accessibilityIdentifier("listing-detail-screen")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
        .toolbar {
            if let listing {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(items: [listing.webURL, shareImageURL]) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .accessibilityLabel("Share this watch")
                }
            }
        }
        .task(id: listingID) {
            await load()
        }
        .fullScreenCover(item: $lightbox) { context in
            GalleryLightbox(images: listing?.images.map(\.url) ?? [], startPage: context.page)
        }
        .sheet(isPresented: $showAuthenticationInfo) {
            AuthenticationInfoSheet()
        }
        // The all-in toggle asks for an address rather than disappearing, so
        // it needs somewhere to send the buyer — and it re-prices itself the
        // moment they come back with one.
        .sheet(isPresented: $showAddressBook, onDismiss: {
            guard let pricing else { return }
            Task { await pricing.load(isAuthenticated: session.isAuthenticated) }
        }) {
            NavigationStack {
                AddressesScreen()
            }
        }
        .sheet(isPresented: $showMakeOfferStub) { makeOfferSheet }
    }

    private var makeOfferSheet: some View {
        MakeOfferSheet(listingID: listingID)
    }

    // MARK: - Content

    private func content(_ listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                // The marks travel on this payload already; asking for them
                // separately would give the gallery a source that can
                // disagree with the photos it is drawing over.
                ListingGallery(
                    images: listing.images.map(\.url),
                    condition: listing.condition?.overall,
                    annotations: listing.annotations
                ) { page in
                    lightbox = LightboxContext(page: page)
                }

                VStack(alignment: .leading, spacing: Space.xl) {
                    buyBox(listing)
                    actionStack(listing)

                    CalloutBand(
                        icon: "checkmark.shield",
                        title: "Authenticated by Calibre",
                        message: "Inspected at our authentication center before it ships."
                    ) {
                        showAuthenticationInfo = true
                    }

                    QuickSpecRow(listing: listing)
                    specSection(listing)
                    conditionSection(listing)
                    sellerSection(listing)
                }
                .padding(.horizontal, Space.margin)

                if !similar.isEmpty {
                    ListingLaneRow(
                        title: "Similar watches",
                        listings: similar,
                        laneKey: "similar",
                        zoomNamespace: similarNamespace
                    )
                }

                notesSection(listing)
                    .padding(.horizontal, Space.margin)
            }
            .padding(.bottom, Space.xxl * 2)
        }
    }

    private func buyBox(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(eyebrowText(listing))

            Text(listing.model ?? listing.title)
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)

            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                // Logged-out visitors only ever see the seller's listed
                // price; the model keeps it that way until there is a quote.
                Text(pricing?.headlinePrice(for: listing)
                    ?? PriceFormatter.format(listing.price.value, currency: listing.currency))
                    .font(CalibreType.priceLarge)
                    .foregroundStyle(Color.calibre.foreground)
                if let badge = availabilityBadge(listing) {
                    StatusBadge(badge.text, tone: badge.tone)
                }
            }

            Text(pricing?.headlineCaption ?? "Taxes and shipping calculated at checkout.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if let pricing {
                ListingPriceControls(model: pricing) {
                    showAddressBook = true
                }
                .padding(.top, Space.xs)
            }

            returnTerms(listing)
        }
    }

    /// The seller's return terms, where the buyer is deciding — they have to
    /// be visible before purchase, not discovered at checkout.
    @ViewBuilder
    private func returnTerms(_ listing: Listing) -> some View {
        if let terms = listing.returns {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    // Item 1.22: the window, not the fact of a window.
                    Text(terms.summary ?? "Sold without returns")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.foreground)
                } icon: {
                    Image(systemName: terms.accepted ? "arrow.uturn.backward" : "xmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                if terms.accepted, let costLine = returnCostLine {
                    Text(costLine)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Space.xs)
            .accessibilityElement(children: .combine)
        }
    }

    /// What a return costs, from the marketplace config. Without it the terms
    /// still stand — they just arrive without figures rather than with
    /// remembered ones.
    private var returnCostLine: String? {
        guard let fee = services.config.config?.returnFee,
              let percent = fee.percent, let minimum = fee.minimum else { return nil }
        let percentText = CheckoutCopy.percentText(percent.value)
        let minimumText = PriceFormatter.format(minimum.value)
        return "A return costs \(percentText) of the watch price with a \(minimumText) minimum, the label is deducted from your refund, and the card fee is not refunded."
    }

    private func actionStack(_ listing: Listing) -> some View {
        VStack(spacing: Space.m) {
            // The reason comes before the disabled controls, not after them.
            // Whichever of the two applies, the buyer reads why the buttons
            // below are grey before they try one.
            ownListingBand(listing)
            unavailableBand(listing)

            Button("Buy Now") {
                Haptics.shared.play(.press)
                buyNow()
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .unavailable(!canTransact(listing))

            if let openOffer {
                Button("Offer pending — view") {
                    services.router.push(.offer(openOffer.id))
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
            } else {
                Button("Make Offer") {
                    makeOffer()
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
                .unavailable(!canTransact(listing))
            }

            HStack(spacing: Space.m) {
                Button {
                    toggleSave()
                } label: {
                    Label(
                        isSaved ? "Saved" : "Save",
                        systemImage: isSaved ? "heart.fill" : "heart"
                    )
                }
                .buttonStyle(.calibre(.ghost, fullWidth: true))
                // Save is wider than buy — the server keeps saving open on a
                // reserved watch whose hold can lapse
                // (`_SAVABLE_LISTING_STATUSES`) — so it is gated on ownership
                // and on the watch still being on the market, not on
                // `canTransact`.
                .unavailable(isOwnListing(listing) || !isSavable(listing))

                Button {
                    addToBag()
                } label: {
                    Label("Add to Bag", systemImage: "bag")
                }
                .buttonStyle(.calibre(.ghost, fullWidth: true))
                .unavailable(!canTransact(listing))
            }
        }
        // Four disabled buttons with no explanation is the thing item 1.6
        // names. The band above says it on screen; this says it to VoiceOver,
        // which does not read a `CalloutBand` that sits outside the button.
        .accessibilityHint(actionsHint(listing) ?? "")
    }

    /// The one sentence that explains a greyed action stack, or nil when
    /// nothing is greyed.
    private func actionsHint(_ listing: Listing) -> String? {
        if isOwnListing(listing) {
            return "This is your own listing, so you can't buy, bag or save it."
        }
        switch listing.status {
        case .active: return nil
        case .sold: return "This watch has sold."
        case .reserved: return "Another buyer is holding this watch."
        default: return "This watch is no longer for sale."
        }
    }

    /// Item 18.6 on a page that *did* load — the seller's own view of a watch
    /// they sold, and the reserved case, where the buy box would otherwise
    /// read like an ordinary listing with a small badge beside the price.
    @ViewBuilder
    private func unavailableBand(_ listing: Listing) -> some View {
        if !isOwnListing(listing), listing.status != .active {
            CalloutBand(
                icon: listing.status == .sold ? "checkmark.seal" : "clock.badge.xmark",
                title: listing.status == .sold ? "Sold" : (listing.status == .reserved ? "On hold" : "No longer listed"),
                message: listing.status == .sold
                    ? "This watch found an owner. It stays here for reference only."
                    : (listing.status == .reserved
                        ? "Another buyer is checking out. If the hold lapses it comes back."
                        : "The seller took this watch off the market.")
            )
        }
    }

    /// Still savable: on the market now, or held by somebody whose hold can
    /// lapse. Mirrors `_SAVABLE_LISTING_STATUSES` on the server.
    private func isSavable(_ listing: Listing) -> Bool {
        listing.status == .active || listing.status == .reserved
    }

    private func specSection(_ listing: Listing) -> some View {
        let parsed = ParsedDescription(listing.description)
        var rows: [(label: String, value: String)] = []
        if let brand = listing.brand { rows.append(("Brand", brand)) }
        if let model = listing.model { rows.append(("Model", model)) }
        if let reference = listing.referenceNumber { rows.append(("Reference", reference)) }
        if let year = listing.productionYear { rows.append(("Year", String(year))) }
        if let boxPapers = listing.boxPapers {
            rows.append(("Box & papers", boxPapers ? "Full set" : "Watch only"))
        }
        rows.append(contentsOf: parsed.specs)

        return VStack(alignment: .leading, spacing: Space.m) {
            Text("The details")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            SpecList(rows)
        }
    }

    @ViewBuilder
    private func conditionSection(_ listing: Listing) -> some View {
        if let condition = listing.condition {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Condition grading")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                ConditionGradingCard(condition: condition)
            }
        }
    }

    @ViewBuilder
    private func sellerSection(_ listing: Listing) -> some View {
        if let seller = listing.seller {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("The seller")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                SellerCard(seller: seller) {
                    push(.seller(seller.username))
                }
                if !isOwnListing(listing) {
                    Button {
                        Haptics.shared.play(.press)
                        messageSeller(listing)
                    } label: {
                        Label("Message Seller", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.calibre(.ghost, fullWidth: true))
                }
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ listing: Listing) -> some View {
        let notes = ParsedDescription(listing.description).notes
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("From the seller")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Text(notes)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .lineSpacing(6)
            }
        }
    }

    private var skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Rectangle()
                    .aspectRatio(1, contentMode: .fit)
                    .shimmer()
                VStack(alignment: .leading, spacing: Space.m) {
                    Rectangle().frame(width: 120, height: 12).shimmer()
                    Rectangle().frame(width: 220, height: 26).shimmer()
                    Rectangle().frame(width: 110, height: 26).shimmer()
                    Rectangle().frame(maxWidth: .infinity).frame(height: 48).shimmer()
                        .padding(.top, Space.m)
                    Rectangle().frame(maxWidth: .infinity).frame(height: 48).shimmer()
                }
                .padding(.horizontal, Space.margin)
            }
        }
        .disabled(true)
    }

    /// Item 18.6, made honest. A sold watch is gone for good, so the offer is
    /// a way onward rather than a retry: the market, and the search that finds
    /// the next one like it.
    private func goneState(_ reason: GoneReason) -> some View {
        EmptyState(
            icon: reason == .sold ? "checkmark.seal" : "clock.badge.xmark",
            title: reason == .sold ? "This one sold" : "This listing is closed",
            message: reason == .sold
                ? "It found an owner. The market moves — there may well be another like it."
                : "The seller took this watch off the market.",
            aside: "Nothing here to wait for.",
            actionTitle: "Find another"
        ) {
            push(.search)
        }
    }

    /// Item 1.6 — you cannot buy your own listing, and the app says so rather
    /// than presenting four dead buttons and no reason. A greyed control with
    /// no explanation reads as a bug; the seller's own watch is not a bug.
    ///
    /// The buttons below are disabled *as well* because the server refuses
    /// this on every path — checkout, offers, bag and save all answer
    /// `own_listing` — and a disabled control that agrees with the server is
    /// the honest one. The refusal is still handled in the action handlers,
    /// because a listing can change hands under an open screen.
    @ViewBuilder
    private func ownListingBand(_ listing: Listing) -> some View {
        if isOwnListing(listing) {
            CalloutBand(
                icon: "person.crop.circle.badge.checkmark",
                title: "This is your listing",
                message: "You can't buy, bag, or save your own watch. Manage it from Sell."
            )
        }
    }

    // MARK: - Derived

    private func eyebrowText(_ listing: Listing) -> String {
        var parts: [String] = []
        if let brand = listing.brand { parts.append(brand) }
        if let reference = listing.referenceNumber { parts.append("Ref. \(reference)") }
        return parts.isEmpty ? "Listing №\(listing.listingNumber)" : parts.joined(separator: " · ")
    }

    private func isAvailable(_ listing: Listing) -> Bool {
        listing.status == .active
    }

    /// Whether the signed-in member is this listing's seller.
    ///
    /// Matched on `sellerId` against `session.user?.id` — the same comparison
    /// `_seller_is_viewer` makes on the server
    /// (Backend/app/api/views/account.py). A guest is never the seller, so
    /// this is false while signed out and the guest still gets the ordinary
    /// sign-in gate.
    private func isOwnListing(_ listing: Listing) -> Bool {
        guard let userID = session.user?.id else { return false }
        return listing.sellerId == userID
    }

    /// Can this member act on this watch at all — buy it, bag it, offer on
    /// it? Their own listing is excluded here rather than at each of the four
    /// buttons, so a fifth button cannot be added without the rule.
    private func canTransact(_ listing: Listing) -> Bool {
        isAvailable(listing) && !isOwnListing(listing)
    }

    private func availabilityBadge(_ listing: Listing) -> (text: String, tone: StatusBadge.Tone)? {
        switch listing.status {
        case .active: nil
        case .sold: ("Sold", .neutral)
        case .reserved: ("Reserved", .warning)
        default: ("No longer listed", .neutral)
        }
    }

    private var isSaved: Bool {
        services.commerce.isWatching(listingID: listingID)
    }

    private var shareImageURL: URL {
        services.client.baseURL.appending(path: "/listings/\(listingID)/share-image.jpg")
    }

    // MARK: - Loading

    /// The similar-watches lane and the open-offer state used to arrive
    /// after `listing` was already on screen, so "Similar watches" would pop
    /// in beneath already-read content and shift the notes section down.
    /// Both now resolve concurrently before the page reveals anything.
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let catalog = services.catalog
        do {
            let loaded = try await catalog.listing(id: listingID)

            async let similarLoad: [Listing] = (try? catalog.similarListings(to: loaded, limit: 8)) ?? []
            async let offerLoad: Offer? = session.isAuthenticated ? loadOpenOffer() : nil
            let (resolvedSimilar, resolvedOffer) = await (similarLoad, offerLoad)

            guard generation == loadGeneration else { return }
            gone = nil
            listing = loaded
            similar = resolvedSimilar
            openOffer = resolvedOffer

            // A fresh model per listing, so the all-in toggle always starts
            // off — never inherited from the last watch the buyer looked at.
            let model = ListingPricingModel(
                listingID: listingID,
                catalog: catalog,
                commerce: services.commerce
            )
            pricing = model
            Task { await model.load(isAuthenticated: session.isAuthenticated) }
            services.signals.recordViewed(listingID)
            if viewedListingID != listingID {
                viewedListingID = listingID
                Analytics.watchViewed(.init(loaded))
            }
            failed = false
        } catch {
            guard generation == loadGeneration, !(error is CancellationError) else { return }
            // A 404 here is the server saying this watch is no longer
            // readable, which after a purchase is exactly what it says
            // (`_can_view_non_active_listing`). It is a different fact from
            // "the request did not arrive" and gets a different screen.
            if (error as? APIError)?.httpStatus == 404 {
                gone = .sold
                listing = nil
                failed = false
            } else if listing == nil {
                failed = true
            } else {
                toasts.show(title: "Couldn't refresh this listing", message: error.browseMessage, tone: .error)
            }
        }
    }

    private func loadOpenOffer() async -> Offer? {
        let waitingStatuses: Set<OfferStatus> = [
            .holdPending, .pendingSeller, .countered, .acceptedPendingPayment,
        ]
        let offers = (try? await services.client.offers(onListing: listingID)) ?? []
        return offers.first { waitingStatuses.contains($0.status) }
    }

    // MARK: - Actions

    private func buyNow() {
        let router = services.router
        let listingID = listingID
        session.require("Sign in to buy this watch") {
            router.open(.checkout(listingID, offerID: nil))
        }
    }

    private func makeOffer() {
        let stubPresented = $showMakeOfferStub
        session.requireThenPresent("Sign in to make an offer") {
            stubPresented.wrappedValue = true
        }
    }

    /// Opens (or resumes) the buyer's thread with this listing's seller and
    /// pushes onto whichever stack the PDP is already on — same in-context
    /// navigation `push(.seller(...))` above uses, so Back returns here
    /// rather than jumping to a different tab.
    private func messageSeller(_ listing: Listing) {
        let router = services.router
        let toasts = toasts
        let messaging = services.messaging
        let listingID = listingID
        let sellerID = listing.sellerId
        let listingTitle = listing.title
        let listingReference = listing.referenceNumber
        session.require("Sign in to message the seller") {
            do {
                let thread = try await messaging.openThread(
                    listingID: listingID,
                    sellerID: sellerID,
                    listingTitle: listingTitle,
                    listingReference: listingReference
                )
                router.push(.messageThread(thread.id))
            } catch {
                Haptics.shared.play(.error)
                toasts.show(
                    title: "Couldn't start this conversation",
                    message: error.browseMessage,
                    tone: .error
                )
            }
        }
    }

    /// Listing-shaped analytics properties, degrading to the id alone while
    /// the listing is still loading.
    private var analyticsListing: Analytics.ListingInfo {
        listing.map(Analytics.ListingInfo.init) ?? .init(id: listingID)
    }

    private func toggleSave() {
        let commerce = services.commerce
        let toasts = toasts
        let listingID = listingID
        let analyticsListing = analyticsListing
        session.require("Sign in to save this watch") {
            let wasSaved = commerce.isWatching(listingID: listingID)
            do {
                try await commerce.toggleWatch(listingID: listingID)
                Haptics.shared.play(.save)
                if wasSaved {
                    toasts.show(title: "Removed from Saved")
                } else {
                    // Save direction only — the toggle is optimistic, so the
                    // pre-call snapshot above is the reliable discriminator.
                    Analytics.watchLiked(analyticsListing)
                    toasts.show(title: "Saved", message: "We'll keep an eye on this one for you.", tone: .success)
                }
            } catch {
                Haptics.shared.play(.error)
                if let refusal = Self.refusalToast(error, verb: "save") {
                    toasts.show(title: refusal.title, message: refusal.message, tone: .error)
                } else {
                    toasts.show(title: "Couldn't update Saved", message: error.browseMessage, tone: .error)
                }
            }
        }
    }

    /// The two refusals every buyer action can come back with, said in words
    /// rather than as the server's code.
    ///
    /// Item 1.6 asks that the app not merely disable these — the disabled
    /// button is what the buyer sees before they act, and this is what they
    /// see if the world changed while the screen was open: a listing bought by
    /// someone else, or a screen left open across a sign-in that made them the
    /// seller. Falling through to the generic "couldn't do that" would tell a
    /// seller their network was flaky.
    static func refusalToast(_ error: Error, verb: String) -> (title: String, message: String)? {
        switch (error as? APIError)?.serverCode {
        case ListingRefusal.ownListing:
            return ("This is your own listing", "You can't \(verb) a watch you're selling. Manage it from Sell.")
        case ListingRefusal.unavailable:
            return ("This watch is gone", "It sold or was withdrawn while this page was open.")
        default:
            return nil
        }
    }

    /// Adds this watch to the bag. The bag holds as many as the buyer wants —
    /// the checkout that follows covers whichever of them they pick — so
    /// nothing has to be displaced to make room.
    private func addToBag() {
        let commerce = services.commerce
        let toasts = toasts
        let listingID = listingID
        let analyticsListing = analyticsListing
        session.require("Sign in to add this watch to your bag") {
            do {
                let cart = try await commerce.loadCart()
                if cart.contains(where: { $0.listingId == listingID }) {
                    toasts.show(title: "Already in your bag")
                    return
                }
                try await commerce.addToCart(listingID: listingID)
                Analytics.watchAddedToCart(analyticsListing)
                Haptics.shared.play(.save)
                toasts.show(
                    title: "In your bag",
                    message: cart.isEmpty
                        ? "Ready when you are."
                        : "That's \(cart.count + 1) in your bag — buy them together or one at a time.",
                    tone: .success
                )
            } catch {
                Haptics.shared.play(.error)
                if let refusal = Self.refusalToast(error, verb: "bag") {
                    toasts.show(title: refusal.title, message: refusal.message, tone: .error)
                    // The server has just told us something this screen's copy
                    // of the listing does not know. Re-read it so the buttons
                    // agree with the answer.
                    await load()
                } else {
                    toasts.show(title: "Couldn't add to your bag", message: error.browseMessage, tone: .error)
                }
            }
        }
    }
}

/// Greying out, which the button style does not do for itself.
///
/// `CalibreButtonStyle.makeBody` reads `configuration.isPressed` and nothing
/// else — there is no `\.isEnabled` branch anywhere in it — so `.disabled(true)`
/// on a Calibre button produces a control that is pixel-identical to a live one
/// and simply ignores taps. Item 1.6 asks for these to be **greyed out** and to
/// say why, and an inert button that still looks tappable is the worse half of
/// both: the buyer taps it, nothing happens, and they conclude the app is
/// broken rather than that the rule exists.
///
/// Desaturating rather than only fading is deliberate: at 0.55 opacity alone
/// the copper primary is still plainly the strong action on the screen. Taking
/// the hue out is what makes it read as out of play.
private extension View {
    func unavailable(_ isUnavailable: Bool) -> some View {
        disabled(isUnavailable)
            .saturation(isUnavailable ? 0 : 1)
            .opacity(isUnavailable ? 0.55 : 1)
    }
}
