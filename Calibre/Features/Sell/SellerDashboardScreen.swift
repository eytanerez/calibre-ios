import CalibreDesign
import CalibreKit
import SwiftUI

/// The seller's shop — tab root once `can_list` is true.
///
/// Four tabs, in the order of the seller's day: what am I selling, who wants
/// it, how is it going, who am I. This screen owns the loads, the state the
/// tabs share and every verb they can reach for; each tab owns its own
/// reading of it.
///
/// Two things deliberately sit *above* the tabs rather than inside one: the
/// card-on-file banner, and the queue of what needs the seller next. Both are
/// true whichever tab is open, and an offer that needs answering must not be
/// something you only find by picking the right room.
struct SellerDashboardScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(SellSession.self) private var sell
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    /// The tab survives a reload and a back-navigation: a seller who opens an
    /// offer and comes back lands on Offers, not on Listings.
    @AppStorage("sellerShopTab") private var tab: SellerTab = .listings
    @State private var listingFilter: SellerListingFilter = .all

    @State private var loading = true
    @State private var loadError: String?
    @State private var loadGeneration = 0
    /// Flips true the first time a load actually surfaces `dashboard`
    /// content; stays true afterward so a later refresh/retry updates
    /// content in place rather than hiding it behind the skeleton again.
    @State private var hasRevealedContent = false
    @State private var requests: [WatchRequest] = []
    @State private var wizardContext: WizardContext?
    @State private var saleDetailOrderID: String?
    @State private var showBulkImports = false
    /// The import whose drafts the seller is finishing right now.
    @State private var continueImportJob: ImportJobRef?
    /// Imports that still have drafts waiting, newest first.
    @State private var unfinishedImports: [UnfinishedImport] = []
    @State private var showOpenRequests = false
    @State private var confirmSubmit: Listing?
    @State private var confirmDelete: Listing?
    @State private var showDealerApplication = false
    @State private var showSellerCard = false
    @State private var showAllQueue = false
    /// The card a counterfeit or misrepresentation charge would land on.
    /// Nil until the first load answers; a banner appears only when the
    /// server says it needs attention.
    @State private var sellerCard: SellerCardState?

    /// How much of the queue stands above the tabs before it is folded. The
    /// tab bar has to stay in reach on the first screen — a queue that pushed
    /// it below the fold would put the whole shop behind a scroll.
    private static let queuePreviewCount = 3

    /// Bulk import is dealer-only, so the lesson that points at it is too.
    /// Two controllers over the same ledger id: whichever one matches the
    /// seller's status is the one that starts, and completing either retires
    /// the lesson for good.
    private static let bulkImportStep = TutorialStep(
        id: "menu",
        anchor: "sell.menu",
        title: "Bulk import lives here",
        message: "Listing many watches at once? This ⋯ menu opens your bulk-import status, where CSV drafts you started on the web get finished.",
        advance: .tapToContinue,
        hint: .tap,
        cutout: .circle
    )

    private static let shopStep = TutorialStep(
        id: "shop",
        title: "Running your shop",
        message: "Your shop is four tabs: what you're selling, who wants it, how it's going, and how buyers see you. Swipe any listing left — or press and hold it — for Edit, Submit and Delete. And whatever needs you next stays above the tabs, whichever one you're in.",
        advance: .tapToContinue
    )

    @State private var tutorial = TutorialController(
        id: "sell.dashboard",
        steps: [shopStep]
    )

    /// Dealer status brings exactly three things, and bulk import is one of
    /// them — the menu entry, the lesson about it, and the screen behind it
    /// all follow this.
    private var isVerifiedDealer: Bool {
        dashboard?.dealerApplication?.isVerified == true
    }

    var body: some View {
        List {
            header

            if let sellerCard, sellerCard.needsAttention {
                sellerCardBanner(sellerCard).sellRow()
            }

            if let loadError, !hasRevealedContent {
                EmptyState(
                    icon: "wifi.slash",
                    title: "Your shop didn't load",
                    message: loadError,
                    actionTitle: "Try again",
                    action: { Task { await load() } }
                )
                .sellRow()
            } else if loading, !hasRevealedContent {
                loadingRows
            } else if let dashboard {
                actionQueue(dashboard.actionQueue)

                Section {
                    tabContent(dashboard)
                } header: {
                    tabBar
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .calibrePageBackground()
        .tutorialOverlay(tutorial)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable {
            await load()
        }
        .task {
            // Always run the generation-safe aggregate load, even if
            // `services.seller.dashboard` is already populated from an
            // earlier view instance (e.g. re-pushed after onboarding) — this
            // screen's own `requests`/`hasRevealedContent`/`loading` are
            // fresh `@State` on every new instance regardless, so skipping
            // `load()` here left them stuck at their initial values and the
            // skeleton never resolved.
            await load()
            // The bulk-import lesson only exists for the sellers who have the
            // menu entry it points at, which the load above has now answered.
            tutorial.adopt(steps: isVerifiedDealer ? [Self.bulkImportStep, Self.shopStep] : [Self.shopStep])
            tutorial.startIfNeeded()
            consumePendingPrefill()
        }
        // The Vault parks a prefill on the router and switches to this tab.
        .onChange(of: router.pendingListingPrefill) { _, _ in
            consumePendingPrefill()
        }
        .fullScreenCover(item: $wizardContext) { context in
            ListingWizardScreen(context: context) {
                Task { await load() }
            }
        }
        .fullScreenCover(item: saleDetailItem) { item in
            SaleDetailScreen(orderID: item.id)
        }
        .sheet(isPresented: $showBulkImports) {
            BulkImportStatusScreen()
        }
        // Straight into the work, without a stop at the job list: this is the
        // entry point for the phone, and the phone is where the camera is.
        .sheet(item: $continueImportJob) { job in
            NavigationStack {
                DraftFinishingQueueScreen(jobID: job.id)
            }
        }
        // Applying is a real path from the Storefront tab: two fields here,
        // then the embedded verification step that collects the EIN.
        .sheet(isPresented: $showDealerApplication) {
            DealerApplicationScreen(application: dashboard?.dealerApplication) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showSellerCard) {
            SellerCardScreen { saved in
                sellerCard = saved
            }
        }
        .sheet(isPresented: $showOpenRequests) {
            OpenBuyerRequestsScreen(requests: requests) { request in
                openWizard(.new(prefill: ListingPrefill(request: request)))
            }
        }
        .alert(
            "Submit for review?",
            isPresented: submitBinding,
            presenting: confirmSubmit
        ) { listing in
            Button("Submit") {
                Task { await submitDraft(listing) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Our team reviews every listing before it goes live. All six photos need to be uploaded first.")
        }
        .alert(
            confirmDelete?.status == .draft ? "Delete this draft?" : "Delete this listing?",
            isPresented: deleteBinding,
            presenting: confirmDelete
        ) { listing in
            Button("Delete", role: .destructive) {
                Task { await deleteListing(listing) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { listing in
            Text("\"\(listing.title)\" and its photos are removed for good. This can't be undone.")
        }
    }

    private var dashboard: SellerDashboard? {
        services.seller.dashboard
    }

    private var listings: [Listing] {
        services.seller.myListings
    }

    private func listing(for id: String) -> Listing? {
        listings.first { $0.id == id }
    }

    /// listingID → the most relevant order, for sold-row taps.
    private var orderByListing: [String: Order] {
        var map: [String: Order] = [:]
        for order in sell.ops.sales.reversed() {
            map[order.listingId] = order
        }
        return map
    }

    private var saleDetailItem: Binding<SaleDetailItem?> {
        Binding(
            get: { saleDetailOrderID.map(SaleDetailItem.init) },
            set: { saleDetailOrderID = $0?.id }
        )
    }

    private var submitBinding: Binding<Bool> {
        Binding(get: { confirmSubmit != nil }, set: { if !$0 { confirmSubmit = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
    }

    // MARK: - The tabs

    /// Pinned by the plain list style, so switching rooms is one tap from
    /// anywhere in a long inventory.
    private var tabBar: some View {
        SellerTabBar(selection: $tab, badges: tabBadges)
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s)
            .background(Color.calibre.background)
            .listRowInsets(EdgeInsets())
    }

    /// A count only where work is actually waiting — `SellerTabBadge` has no
    /// zero-valued form, so a tab either promises something or says nothing.
    ///
    /// The Listings count is the same predicate its "Needs action" filter
    /// uses, so tapping the badge lands on exactly that many rows.
    private var tabBadges: [SellerTab: SellerTabBadge] {
        var badges: [SellerTab: SellerTabBadge] = [:]
        let needsAction = listings.filter(SellerStatusDisplay.needsAction).count
        if let badge = SellerTabBadge(
            count: needsAction,
            spoken: { $0 == 1 ? "1 needs your attention" : "\($0) need your attention" }
        ) {
            badges[.listings] = badge
        }
        if let dashboard, let badge = SellerTabBadge(
            count: dashboard.metrics.offersWaiting,
            spoken: { $0 == 1 ? "1 waiting on you" : "\($0) waiting on you" }
        ) {
            badges[.offers] = badge
        }
        return badges
    }

    @ViewBuilder
    private func tabContent(_ dashboard: SellerDashboard) -> some View {
        switch tab {
        case .listings:
            SellerListingsTab(
                listings: listings,
                unfinishedImports: unfinishedImports,
                filter: $listingFilter,
                actions: shopActions
            )
        case .offers:
            SellerOffersTab(
                offers: dashboard.offers,
                listings: listings,
                actions: shopActions
            )
        case .performance:
            SellerPerformanceTab(
                metrics: dashboard.metrics,
                whatToList: dashboard.whatToList,
                sales: sell.ops.sales,
                requests: requests,
                actions: shopActions
            )
        case .storefront:
            SellerStorefrontTab(
                username: session.user?.username ?? "",
                application: dashboard.dealerApplication,
                actions: shopActions
            )
        }
    }

    /// The shop's verbs, defined once and handed to every tab.
    private var shopActions: SellerShopActions {
        SellerShopActions(
            listWatch: { openWizard(.new(prefill: $0)) },
            openWizard: { openWizard($0) },
            openListing: { openListing($0) },
            confirmSubmit: { confirmSubmit = $0 },
            confirmDelete: { confirmDelete = $0 },
            openSale: { saleDetailOrderID = $0 },
            openOffer: { router.push(.offer($0)) },
            openCardOnFile: { showSellerCard = true },
            continueImport: { continueImportJob = $0 },
            openBuyerRequests: { showOpenRequests = true },
            openStorefrontPage: {
                if let username = session.user?.username, !username.isEmpty {
                    router.push(.seller(username))
                }
            },
            openDealerApplication: { showDealerApplication = true },
            showListings: { filter in
                listingFilter = filter
                withAnimation(Motion.easeMedium) { tab = .listings }
            },
            reload: { await load() }
        )
    }

    // MARK: - Loading

    /// Runs every section's fetch concurrently and reveals the dashboard once
    /// they've all settled — dealer/queue/requests/inventory/sales used to
    /// pop in independently as each raced ahead of the others. `loadGeneration`
    /// guards every write this function (and its children) make to view
    /// state: a `load()` superseded by a newer one (double-tapped "Try
    /// again", a refresh landing mid-retry) can still finish, but its result
    /// is dropped instead of clobbering the newer call's state.
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        loadError = nil
        async let dashboardTask: Void = loadDashboard(generation: generation)
        async let listingsTask: Void = loadListings()
        async let requestsTask: Void = loadRequests(generation: generation)
        async let salesTask: Void = loadSales()
        async let cardTask: Void = loadSellerCard(generation: generation)
        async let importsTask: Void = loadUnfinishedImports(generation: generation)
        _ = await (dashboardTask, listingsTask, requestsTask, salesTask, cardTask, importsTask)
        guard generation == loadGeneration else { return }
        loading = false
        // Only the first load to actually surface content flips this — once
        // true, the skeleton/error gate steps aside for good and a later
        // refresh or retry updates the same visible content in place instead
        // of hiding it behind a skeleton again.
        if dashboard != nil {
            hasRevealedContent = true
        }
    }

    private func loadDashboard(generation: Int) async {
        do {
            _ = try await services.seller.loadDashboard()
        } catch {
            guard generation == loadGeneration else { return }
            loadError = sellErrorMessage(error)
        }
    }

    private func loadListings() async {
        _ = try? await services.seller.loadMyListings()
    }

    /// Verified dealers only. A non-dealer's 403 is swallowed here on purpose:
    /// the summary row simply never appears, and the shop still opens.
    private func loadRequests(generation: Int) async {
        let result = (try? await services.seller.openDealerRequests())?.results ?? requests
        guard generation == loadGeneration else { return }
        requests = result
    }

    private func loadSales() async {
        _ = try? await sell.ops.loadSales(pageSize: 30)
    }

    /// The imports that left drafts behind.
    ///
    /// Both figures are the server's, counted across the job's rows in one
    /// query: "finished" means the row's listing has left `draft`. A job whose
    /// payload does not state them drops out of the section rather than
    /// appearing with a ratio worked out here — `created + updated` counts
    /// rows an import wrote, not listings a seller finished, and it says
    /// nothing at all about the ones it skipped.
    ///
    /// One request for the whole section. The completion queue is still
    /// fetched, but by the finishing flow, for the drafts themselves.
    ///
    /// Bulk import is dealer-only, so a non-dealer's 403 simply leaves the
    /// section absent.
    private func loadUnfinishedImports(generation: Int) async {
        guard let jobs = try? await services.seller.importJobs() else { return }
        let found = jobs
            .filter { $0.status == .completed || $0.status == .completedWithErrors }
            .compactMap(UnfinishedImport.init)
            .prefix(Self.importLookback)
        guard generation == loadGeneration else { return }
        unfinishedImports = Array(found)
    }

    /// How many recent imports are worth asking about.
    private static let importLookback = 3

    /// The card a counterfeit or misrepresentation charge would land on. The
    /// banner only appears when the server says the card needs attention, so
    /// a failure here simply leaves the dashboard as it was.
    private func loadSellerCard(generation: Int) async {
        guard let card = try? await services.seller.sellerCard() else { return }
        guard generation == loadGeneration else { return }
        sellerCard = card
    }

    private var loadingRows: some View {
        Group {
            Rectangle().frame(maxWidth: .infinity).frame(height: 96).shimmer().sellRow()
            Rectangle().frame(maxWidth: .infinity).frame(height: 140).shimmer().sellRow()
            ForEach(0..<3, id: \.self) { _ in
                SellRowSkeleton().sellRow()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(session.user?.username ?? "Your")'s shop")
                    .font(CalibreType.title)
                    .foregroundStyle(Color.calibre.foreground)
                Spacer()
                // Bulk import is dealer-only, so the entry to it isn't
                // offered to a seller who would only be refused behind it.
                if isVerifiedDealer {
                    Menu {
                        Button {
                            showBulkImports = true
                        } label: {
                            Label("Bulk import status", systemImage: "tray.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color.calibre.foreground)
                            .frame(width: Space.touchTarget, height: Space.touchTarget, alignment: .trailing)
                    }
                    .accessibilityLabel("More options")
                    .tutorialAnchor("sell.menu")
                }
            }

            Button {
                openWizard(.new(prefill: nil))
            } label: {
                Label("List a watch", systemImage: "plus")
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
        }
        .sellRow(top: Space.l, bottom: Space.l)
    }

    // MARK: - Card on file

    /// Quiet, and only when the server says so: no card, one that stopped
    /// working, or one about to lapse. An expiring card is surfaced before it
    /// lapses rather than after.
    private func sellerCardBanner(_ card: SellerCardState) -> some View {
        CalloutBand(
            icon: "creditcard",
            title: sellerCardBannerTitle(card),
            message: sellerCardBannerMessage(card),
            action: { showSellerCard = true }
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your card on file")
    }

    private func sellerCardBannerTitle(_ card: SellerCardState) -> String {
        if !card.present { return "Add a card on file" }
        if card.valid == false { return "Your card on file needs replacing" }
        return "Your card on file expires soon"
    }

    private func sellerCardBannerMessage(_ card: SellerCardState) -> String {
        if !card.present {
            return "Selling on Calibre needs a credit card on file. It takes a minute, and nothing is charged to it now."
        }
        if card.valid == false {
            return "\(card.displayName) isn't working any more. Replace it so nothing interrupts a sale."
        }
        if let expiry = card.expiryLabel {
            return "\(card.displayName) expires \(expiry). Replace it before it lapses."
        }
        return "\(card.displayName) is close to expiring. Replace it before it lapses."
    }

    // MARK: - What needs you next

    /// Above the tabs, because it is the one thing that should reach the
    /// seller whichever tab they are on.
    ///
    /// Each queued action is its own `List` row (rather than one merged card
    /// of stacked rows) so a draft entry here can carry the same native
    /// swipe-to-delete as an inventory row — the only way a seller who never
    /// opens Listings can still delete a draft.
    @ViewBuilder
    private func actionQueue(_ queue: [DashboardAction]) -> some View {
        if !queue.isEmpty {
            let shown = showAllQueue ? queue : Array(queue.prefix(Self.queuePreviewCount))
            SellSectionHeader("Waiting on you").sellRow(bottom: Space.s)
            ForEach(Array(shown.enumerated()), id: \.element.stableID) { index, action in
                actionRow(action)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                            .strokeBorder(Color.calibre.border, lineWidth: 1)
                    )
                    .sellRow(bottom: index == shown.count - 1 ? Space.l : Space.s)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        actionRowSwipeActions(action)
                    }
            }
            if queue.count > Self.queuePreviewCount {
                queueToggle(queue.count).sellRow(bottom: Space.l)
            }
        }
    }

    private func queueToggle(_ total: Int) -> some View {
        Button {
            withAnimation(Motion.easeMedium) { showAllQueue.toggle() }
        } label: {
            HStack(spacing: Space.s) {
                Text(showAllQueue ? "Show less" : "Show all \(total)")
                    .font(CalibreType.label)
                Image(systemName: showAllQueue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.calibre.primary)
            .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func actionRow(_ action: DashboardAction) -> some View {
        Button {
            route(action)
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: actionIcon(action.kind))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.calibre.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.calibre.accent.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(actionTitle(action))
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    Text(actionSubtitle(action))
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .lineLimit(2)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .background(Color.calibre.card)
    }

    /// A draft queue row can be deleted with the same swipe, confirmation
    /// dialog, and deletion call as an inventory row — no duplicated
    /// deletion path.
    @ViewBuilder
    private func actionRowSwipeActions(_ action: DashboardAction) -> some View {
        if action.kind == "draft", let listingId = action.listingId, let draft = listing(for: listingId) {
            Button(role: .destructive) {
                confirmDelete = draft
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color.calibre.destructive)
        }
    }

    /// Drafts are named by their listing title — a seller can hold several at
    /// once, so a generic "Finish your draft" wouldn't tell them apart.
    private func actionTitle(_ action: DashboardAction) -> String {
        if action.kind == "draft", let id = action.listingId, let draft = listing(for: id) {
            let name = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Untitled draft" : name
        }
        return action.title
    }

    private func actionSubtitle(_ action: DashboardAction) -> String {
        if action.kind == "draft" {
            return "Draft — finish and submit"
        }
        return action.description
    }

    private func actionIcon(_ kind: String) -> String {
        switch kind {
        case "offer": "arrow.left.arrow.right"
        case "fulfillment": "shippingbox"
        case "draft": "square.and.pencil"
        case "rejected": "exclamationmark.triangle"
        default: "bell"
        }
    }

    private func route(_ action: DashboardAction) {
        switch action.kind {
        case "offer":
            if let offerID = action.offerId {
                router.push(.offer(offerID))
            }
        case "fulfillment":
            if let orderID = action.orderId {
                saleDetailOrderID = orderID
            }
        case "draft":
            if let listingID = action.listingId, let draft = listing(for: listingID) {
                openWizard(.finishDraft(draft))
            }
        case "rejected":
            if let listingID = action.listingId, let rejected = listing(for: listingID) {
                openWizard(.edit(rejected))
            }
        default:
            break
        }
    }

    // MARK: - Listing actions

    private func openListing(_ listing: Listing) {
        switch listing.status {
        case .draft:
            openWizard(.finishDraft(listing))
        case .rejected:
            openWizard(.edit(listing))
        case .sold:
            if let order = orderByListing[listing.id] {
                saleDetailOrderID = order.id
            } else {
                router.push(.listing(listing.id))
            }
        default:
            router.push(.listing(listing.id))
        }
    }

    private func submitDraft(_ listing: Listing) async {
        do {
            let submitted = try await services.seller.submitForReview(listingID: listing.id)
            // The shop is where bulk-imported drafts are actually submitted —
            // the import completion queue only fills them in — so the source
            // comes from the import ledger rather than being assumed manual.
            Analytics.listingSubmitted(
                .init(submitted),
                source: Analytics.listingSource(for: submitted.id)
            )
            Haptics.shared.play(.success)
            toasts.show(
                title: "In review",
                message: "We'll let you know the moment it's live.",
                tone: .success
            )
            await load()
        } catch {
            toasts.show(title: "Couldn't submit", message: sellErrorMessage(error), tone: .error)
        }
    }

    private func deleteListing(_ listing: Listing) async {
        do {
            try await services.seller.deleteListing(id: listing.id)
            // Clear any saved local snapshot so it doesn't try to resume a
            // draft that no longer exists on the server.
            DraftStore.clear(listingID: listing.id)
            Haptics.shared.play(.press)
            toasts.show(
                title: listing.status == .draft ? "Draft deleted" : "Listing deleted",
                message: "\(listing.title) is gone."
            )
            await load()
        } catch {
            toasts.show(title: "Couldn't delete", message: sellErrorMessage(error), tone: .error)
        }
    }

    // MARK: - Wizard

    private func consumePendingPrefill() {
        guard let prefill = router.pendingListingPrefill else { return }
        router.pendingListingPrefill = nil
        openWizard(.new(prefill: prefill))
    }

    private func openWizard(_ kind: WizardContext.Kind) {
        wizardContext = WizardContext(kind: kind)
    }
}

/// Identity wrapper for the sale-detail cover.
private struct SaleDetailItem: Identifiable {
    let id: String
}

private extension DashboardAction {
    /// `DashboardAction` has no single id field, but `kind` plus whichever
    /// entity id it actually carries is stable across queue re-fetches —
    /// unlike the array offset `ForEach` used to key on, which reassigns a
    /// row's identity (and therefore its swipe/animation state) whenever the
    /// queue's order or count changes between loads.
    var stableID: String {
        kind + "-" + (listingId ?? orderId ?? offerId ?? href ?? title)
    }
}

/// One import that still has drafts waiting, and how far through it the
/// seller is.
///
/// Both figures are served, and the initializer fails when either is missing
/// or there is nothing left to finish — so this type cannot exist holding a
/// number nobody counted.
struct UnfinishedImport: Identifiable {
    let job: ListingImportJob
    let remaining: Int
    let total: Int
    let finished: Int

    init?(job: ListingImportJob) {
        guard let total = job.draftsTotal,
              let remaining = job.draftsRemaining,
              let finished = job.draftsFinished,
              total > 0,
              remaining > 0 else { return nil }
        self.job = job
        self.total = total
        self.remaining = remaining
        self.finished = finished
    }

    var id: String { job.id }

    var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, max(0, CGFloat(finished) / CGFloat(total)))
    }

    var remainderLine: String {
        remaining == 1 ? "1 still a draft" : "\(remaining) still drafts"
    }
}
