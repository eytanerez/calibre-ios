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
    @State private var swapCandidate: CartItem?
    @Namespace private var similarNamespace

    var body: some View {
        Group {
            if let listing {
                content(listing)
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
        .background(Color.calibre.background)
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
        .sheet(isPresented: $showMakeOfferStub) {
            MakeOfferStub()
        }
        .confirmationDialog(
            "Your bag holds one watch at a time.",
            isPresented: swapDialogPresented,
            titleVisibility: .visible,
            presenting: swapCandidate
        ) { existing in
            Button("Move \(existing.listing?.title ?? "the current watch") to Saved") {
                Task { await performSwap(existing) }
            }
            Button("Keep my bag as it is", role: .cancel) {}
        } message: { existing in
            Text("We'll tuck \(existing.listing?.title ?? "your current watch") into Saved and put this one in your bag.")
        }
    }

    // MARK: - Content

    private func content(_ listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ListingGallery(
                    images: listing.images.map(\.url),
                    condition: listing.condition?.overall
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
                Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                    .font(CalibreType.priceLarge)
                    .foregroundStyle(Color.calibre.foreground)
                if let badge = availabilityBadge(listing) {
                    StatusBadge(badge.text, tone: badge.tone)
                }
            }

            Text("Taxes and shipping calculated at checkout.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    private func actionStack(_ listing: Listing) -> some View {
        VStack(spacing: Space.m) {
            Button("Buy Now") {
                Haptics.shared.play(.press)
                buyNow()
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(!isAvailable(listing))

            if let openOffer {
                Button("Offer pending — view") {
                    services.router.open(.offer(openOffer.id))
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
            } else {
                Button("Make Offer") {
                    makeOffer()
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
                .disabled(!isAvailable(listing))
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

                Button {
                    addToBag()
                } label: {
                    Label("Add to Bag", systemImage: "bag")
                }
                .buttonStyle(.calibre(.ghost, fullWidth: true))
                .disabled(!isAvailable(listing))
            }
        }
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

    private var swapDialogPresented: Binding<Bool> {
        Binding(
            get: { swapCandidate != nil },
            set: { if !$0 { swapCandidate = nil } }
        )
    }

    // MARK: - Loading

    private func load() async {
        let catalog = services.catalog
        do {
            let loaded = try await catalog.listing(id: listingID)
            listing = loaded
            services.signals.recordViewed(listingID)
            failed = false

            async let similarLoad: [Listing] = (try? catalog.similarListings(to: loaded, limit: 8)) ?? []
            if session.isAuthenticated {
                await refreshOpenOffer()
            }
            similar = await similarLoad
        } catch {
            if listing == nil {
                failed = true
            } else {
                toasts.show(title: "Couldn't refresh this listing", message: error.browseMessage, tone: .error)
            }
        }
    }

    private func refreshOpenOffer() async {
        let waitingStatuses: Set<OfferStatus> = [
            .holdPending, .pendingSeller, .countered, .acceptedPendingPayment,
        ]
        let offers = (try? await services.client.offers(onListing: listingID)) ?? []
        openOffer = offers.first { waitingStatuses.contains($0.status) }
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

    private func toggleSave() {
        let commerce = services.commerce
        let toasts = toasts
        let listingID = listingID
        session.require("Sign in to save this watch") {
            let wasSaved = commerce.isWatching(listingID: listingID)
            do {
                try await commerce.toggleWatch(listingID: listingID)
                Haptics.shared.play(.save)
                if wasSaved {
                    toasts.show(title: "Removed from Saved")
                } else {
                    toasts.show(title: "Saved", message: "We'll keep an eye on this one for you.", tone: .success)
                }
            } catch {
                Haptics.shared.play(.error)
                toasts.show(title: "Couldn't update Saved", message: error.browseMessage, tone: .error)
            }
        }
    }

    private func addToBag() {
        let commerce = services.commerce
        let toasts = toasts
        let listingID = listingID
        let candidate = $swapCandidate
        session.require("Sign in to add this watch to your bag") {
            do {
                let cart = try await commerce.loadCart()
                if cart.contains(where: { $0.listingId == listingID }) {
                    toasts.show(title: "Already in your bag")
                    return
                }
                if let existing = cart.first {
                    candidate.wrappedValue = existing
                    return
                }
                try await commerce.addToCart(listingID: listingID)
                Haptics.shared.play(.save)
                toasts.show(title: "In your bag", message: "Ready when you are.", tone: .success)
            } catch {
                Haptics.shared.play(.error)
                toasts.show(title: "Couldn't add to your bag", message: error.browseMessage, tone: .error)
            }
        }
    }

    /// The one-watch bag swap: previous watch moves to Saved, this one takes
    /// its place.
    private func performSwap(_ existing: CartItem) async {
        let commerce = services.commerce
        do {
            if !commerce.isWatching(listingID: existing.listingId) {
                try await commerce.toggleWatch(listingID: existing.listingId)
            }
            try await commerce.removeCartItem(id: existing.id)
            try await commerce.addToCart(listingID: listingID)
            Haptics.shared.play(.save)
            toasts.show(
                title: "In your bag",
                message: "We moved \(existing.listing?.title ?? "your other watch") to Saved.",
                tone: .success
            )
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't swap your bag", message: error.browseMessage, tone: .error)
        }
    }
}
