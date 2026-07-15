import CalibreDesign
import CalibreKit
import NukeUI
import SwiftUI

/// The seller's shop — tab root once `can_list` is true. Header, dealer
/// progress, the prioritized action queue, buyer requests, inventory,
/// recent sales and received offers.
struct SellerDashboardScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(SellSession.self) private var sell
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    enum InventoryTab: String, CaseIterable {
        case all = "All"
        case needsAction = "Needs action"
        case live = "Live"
        case draft = "Draft"
        case pending = "Pending"
        case sold = "Sold"
        case archived = "Archived"
    }

    @State private var loading = true
    @State private var loadError: String?
    @State private var loadGeneration = 0
    /// Flips true the first time a load actually surfaces `dashboard`
    /// content; stays true afterward so a later refresh/retry updates
    /// content in place rather than hiding it behind the skeleton again.
    @State private var hasRevealedContent = false
    @State private var requests: [WatchRequest] = []
    @State private var inventoryTab: InventoryTab = .all
    @State private var wizardContext: WizardContext?
    @State private var saleDetailOrderID: String?
    @State private var showBulkImports = false
    @State private var showOpenRequests = false
    @State private var confirmSubmit: Listing?
    @State private var confirmArchive: Listing?
    @State private var confirmDelete: Listing?
    @State private var showAllInventory = false
    @State private var tutorial = TutorialController(
        id: "sell.dashboard",
        steps: [
            TutorialStep(
                id: "menu",
                anchor: "sell.menu",
                title: "Bulk import lives here",
                message: "Listing many watches at once? This ⋯ menu opens your bulk-import status, where CSV drafts you started on the web get finished.",
                advance: .tapToContinue,
                hint: .tap,
                cutout: .circle
            ),
            TutorialStep(
                id: "shop",
                title: "Running your shop",
                message: "Swipe any inventory row left for its quick actions — Edit, Submit for review, or Archive. And the queue up top always surfaces whatever needs you next: an offer to answer, a sale to ship, a draft to finish.",
                advance: .tapToContinue
            ),
        ]
    )

    var body: some View {
        List {
            header

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
            } else {
                if let dealer = dashboard?.dealer {
                    dealerCard(dealer).sellRow()
                }
                if let queue = dashboard?.actionQueue, !queue.isEmpty {
                    actionQueueHeader.sellRow(bottom: Space.s)
                    ForEach(Array(queue.prefix(6).enumerated()), id: \.element.stableID) { index, action in
                        actionRow(action)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .strokeBorder(Color.calibre.border, lineWidth: 1)
                            )
                            .sellRow(bottom: index == min(queue.count, 6) - 1 ? Space.xl : Space.s)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                actionRowSwipeActions(action)
                            }
                    }
                }
                if !requests.isEmpty {
                    buyerRequests.sellRow()
                }
                inventorySection
                recentSales.sellRow()
                if let offers = dashboard?.offers, !offers.isEmpty {
                    offersSection(offers).sellRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.calibre.background.ignoresSafeArea())
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
            tutorial.startIfNeeded()
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
        .sheet(isPresented: $showOpenRequests) {
            OpenBuyerRequestsScreen(requests: requests) { request in
                openWizard(.new(prefill: request))
            }
        }
        .confirmationDialog(
            "Submit for review?",
            isPresented: submitBinding,
            titleVisibility: .visible,
            presenting: confirmSubmit
        ) { listing in
            Button("Submit") {
                Task { await submitDraft(listing) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Our team reviews every listing before it goes live. All six photos need to be uploaded first.")
        }
        .confirmationDialog(
            "Archive this listing?",
            isPresented: archiveBinding,
            titleVisibility: .visible,
            presenting: confirmArchive
        ) { listing in
            Button("Archive", role: .destructive) {
                Task { await archive(listing) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It leaves the market right away. You can restore and resubmit it any time.")
        }
        .confirmationDialog(
            "Delete this draft?",
            isPresented: deleteBinding,
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { listing in
            Button("Delete draft", role: .destructive) {
                Task { await deleteDraft(listing) }
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

    private var archiveBinding: Binding<Bool> {
        Binding(get: { confirmArchive != nil }, set: { if !$0 { confirmArchive = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
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
        _ = await (dashboardTask, listingsTask, requestsTask, salesTask)
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

    private func loadRequests(generation: Int) async {
        let result = (try? await services.seller.openDealerRequests()) ?? requests
        guard generation == loadGeneration else { return }
        requests = result
    }

    private func loadSales() async {
        _ = try? await sell.ops.loadSales(pageSize: 30)
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

            Button {
                openWizard(.new(prefill: nil))
            } label: {
                Label("List a watch", systemImage: "plus")
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
        }
        .sellRow(top: Space.l)
    }

    // MARK: - Dealer progress

    private func dealerCard(_ dealer: DealerUnlock) -> some View {
        let keepNow = Decimal(
            dealer.isActive ? MarketplaceFees.dealerKeepPercent : MarketplaceFees.privateSellerKeepPercent
        )
        let keepDealer = Decimal(MarketplaceFees.dealerKeepPercent)
        return SellCard {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow("Dealer progress")
                    Spacer()
                    if dealer.isActive {
                        StatusBadge("Dealer", tone: .success)
                    }
                }

                if dealer.isActive {
                    Text(activeDealerLine(dealer))
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("You keep \(percentText(keepDealer))% on every sale at the dealer rate.")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(dealer.liveListingCount) of \(dealer.threshold)")
                            .font(CalibreType.price)
                            .foregroundStyle(Color.calibre.foreground)
                        Text("live listings")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    // Thin dealer-unlock bar.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.calibre.border)
                            Capsule()
                                .fill(Color.calibre.primary)
                                .frame(width: max(
                                    proxy.size.width * CGFloat(dealer.liveListingCount) / CGFloat(max(dealer.threshold, 1)),
                                    dealer.liveListingCount > 0 ? 6 : 0
                                ))
                        }
                    }
                    .frame(height: 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(dealer.liveListingCount) of \(dealer.threshold) live listings toward dealer status")

                    Text("You keep \(percentText(keepNow))% today — dealers keep \(percentText(keepDealer))%.")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)

                    if dealer.nextMonthUnlocked, let nextMonth = dealer.nextMonthLabel {
                        Text("Dealer rate unlocked for \(nextMonth).")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.success)
                    }
                }
            }
            .padding(Space.l)
        }
    }

    private func activeDealerLine(_ dealer: DealerUnlock) -> String {
        if let until = dealer.activeUntil {
            return "Dealer active through \(until.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Dealer rate active"
    }

    private func percentText(_ value: Decimal) -> String {
        var raw = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    // MARK: - Action queue

    /// Each queued action is its own `List` row (rather than one merged card
    /// of stacked rows) so a draft entry here can carry the same native
    /// swipe-to-delete as an inventory row — the only way a seller who never
    /// scrolls to Inventory can still delete a draft.
    private var actionQueueHeader: some View {
        SellSectionHeader("Waiting on you")
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
    /// dialog, and `deleteDraft(_:)` call as an inventory row — no
    /// duplicated deletion path.
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
                router.open(.offer(offerID))
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

    // MARK: - Buyer requests

    /// A single summary row rather than the requests themselves — the shop's
    /// front page stays scannable; the full list lives one tap away.
    private var buyerRequests: some View {
        Button {
            showOpenRequests = true
        } label: {
            HStack(spacing: Space.m) {
                IconTile(systemName: "sparkle.magnifyingglass")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Buyers are looking for \(requests.count) watch\(requests.count == 1 ? "" : "es")")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("List against an open request")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .padding(Space.l)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Shows every open buyer request")
    }

    // MARK: - Inventory

    private var filteredListings: [Listing] {
        switch inventoryTab {
        case .all: listings
        case .needsAction: listings.filter(SellerStatusDisplay.needsAction)
        case .live: listings.filter { $0.status == .active || $0.status == .reserved }
        case .draft: listings.filter { $0.status == .draft }
        case .pending: listings.filter { $0.status == .pendingReview }
        case .sold: listings.filter { $0.status == .sold }
        case .archived: listings.filter { $0.status == .archived || $0.status == .rejected }
        }
    }

    /// Only the first few rows show until the seller taps "Show all" — a busy
    /// shop otherwise buries recent sales and offers under a long inventory.
    private static let inventoryPreviewCount = 5

    private var visibleListings: [Listing] {
        if showAllInventory { return filteredListings }
        return Array(filteredListings.prefix(Self.inventoryPreviewCount))
    }

    @ViewBuilder
    private var inventorySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Inventory")
            // A trailing fade + chevron makes it obvious the filter bar scrolls
            // to more tabs than fit the screen.
            ScrollView(.horizontal, showsIndicators: false) {
                SegmentedTabs(
                    selection: $inventoryTab,
                    items: InventoryTab.allCases.map { ($0, $0.rawValue) }
                )
                .frame(width: 660)
                .padding(.trailing, Space.xl)
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.calibre.background.opacity(0), Color.calibre.background],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .padding(.trailing, 2)
                        .background(Color.calibre.background)
                }
                .allowsHitTesting(false)
            }
            .onChange(of: inventoryTab) { showAllInventory = false }
        }
        .sellRow(bottom: Space.s)

        if filteredListings.isEmpty {
            emptyInventory.sellRow()
        } else {
            ForEach(visibleListings) { listing in
                inventoryRow(listing)
                    .sellRow(bottom: Space.m)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        swipeButtons(listing)
                    }
            }
            if filteredListings.count > Self.inventoryPreviewCount {
                inventoryToggle.sellRow(bottom: Space.m)
            }
        }
    }

    private var inventoryToggle: some View {
        Button {
            withAnimation(Motion.easeMedium) { showAllInventory.toggle() }
        } label: {
            HStack(spacing: Space.s) {
                Text(showAllInventory
                    ? "Show less"
                    : "Show all \(filteredListings.count)")
                    .font(CalibreType.bodyMedium)
                Image(systemName: showAllInventory ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.calibre.primary)
            .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var emptyInventory: some View {
        Group {
            if listings.isEmpty {
                EmptyState(
                    icon: "camera",
                    title: "Your shop is ready for its first watch",
                    message: "Six photos, one calm flow — most sellers list in under five minutes.",
                    actionTitle: "List a watch",
                    action: { openWizard(.new(prefill: nil)) }
                )
            } else {
                Text(emptyTabMessage)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Space.xl)
            }
        }
    }

    private var emptyTabMessage: String {
        switch inventoryTab {
        case .needsAction: "Nothing needs your attention right now."
        case .live: "No live listings at the moment."
        case .draft: "No drafts — everything you started is out the door."
        case .pending: "Nothing waiting on review."
        case .sold: "No sales yet — they'll appear here."
        case .archived: "Nothing archived."
        case .all: "No listings here yet."
        }
    }

    private func inventoryRow(_ listing: Listing) -> some View {
        let badge = SellerStatusDisplay.badge(for: listing)
        let rejectionNote = rejectionReason(listing)
        return Button {
            openListing(listing)
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.m) {
                    SellThumb(url: listing.images.first?.url)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(listing.title)
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .lineLimit(1)
                        StatusBadge(badge.text, tone: badge.tone)
                        HStack(spacing: Space.s) {
                            Text("#\(listing.listingNumber) · \(PriceFormatter.format(listing.price.value))")
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                            if let metrics = listing.metrics, metrics.views + metrics.watchers > 0 {
                                Label("\(metrics.views)", systemImage: "eye")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                                Label("\(metrics.watchers)", systemImage: "heart")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let rejectionNote {
                    CalloutBand(icon: "exclamationmark.bubble", message: rejectionNote)
                }
            }
            .padding(Space.m)
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// The moderator's words, shown on rejected rows.
    private func rejectionReason(_ listing: Listing) -> String? {
        guard listing.status == .rejected else { return nil }
        let note = listing.reviewEvents?
            .first { $0.toStatus == "rejected" && !($0.notes ?? "").isEmpty }?
            .notes
        return note ?? "Our review team asked for changes. Edit and resubmit when ready."
    }

    @ViewBuilder
    private func swipeButtons(_ listing: Listing) -> some View {
        Button {
            openWizard(listing.status == .draft ? .finishDraft(listing) : .edit(listing))
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }
        .tint(Color.calibre.primary)

        if listing.status == .draft {
            Button {
                confirmSubmit = listing
            } label: {
                Label("Submit", systemImage: "paperplane")
            }
            .tint(Color.calibre.success)

            Button(role: .destructive) {
                confirmDelete = listing
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color.calibre.destructive)
        }

        if listing.status != .archived && listing.status != .sold {
            Button {
                confirmArchive = listing
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(Color.calibre.mutedForeground)
        }
    }

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
                router.open(.listing(listing.id))
            }
        default:
            router.open(.listing(listing.id))
        }
    }

    private func submitDraft(_ listing: Listing) async {
        do {
            _ = try await services.seller.submitForReview(listingID: listing.id)
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

    private func archive(_ listing: Listing) async {
        do {
            _ = try await services.seller.updateListing(id: listing.id, ListingDraftPayload(status: .archived))
            toasts.show(title: "Archived", message: "\(listing.title) left the market.")
            await load()
        } catch {
            toasts.show(title: "Couldn't archive", message: sellErrorMessage(error), tone: .error)
        }
    }

    private func deleteDraft(_ listing: Listing) async {
        do {
            try await services.seller.deleteListing(id: listing.id)
            // Clear any saved local snapshot so it doesn't try to resume a
            // draft that no longer exists on the server.
            DraftStore.clear(listingID: listing.id)
            Haptics.shared.play(.press)
            toasts.show(title: "Draft deleted", message: "\(listing.title) is gone.")
            await load()
        } catch {
            toasts.show(title: "Couldn't delete", message: sellErrorMessage(error), tone: .error)
        }
    }

    // MARK: - Recent sales

    private var recentSales: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Recent sales")
            if sell.ops.sales.isEmpty {
                Text("When a watch sells, everything you need to ship it lands here.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
            } else {
                SellCard {
                    VStack(spacing: 0) {
                        ForEach(Array(sell.ops.sales.prefix(5).enumerated()), id: \.element.id) { index, order in
                            saleRow(order)
                            if index < min(sell.ops.sales.count, 5) - 1 {
                                Rectangle().fill(Color.calibre.border).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func saleRow(_ order: Order) -> some View {
        let badge = SellerStatusDisplay.badge(forOrder: order.status)
        let needsLabel = order.sellerActionState == "sold_awaiting_label_creation"
        return Button {
            saleDetailOrderID = order.id
        } label: {
            HStack(spacing: Space.m) {
                SellThumb(url: order.listing?.image?.url, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.listing?.title ?? "Sold watch")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    StatusBadge(badge.text, tone: badge.tone)
                }
                Spacer(minLength: Space.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PriceFormatter.format(order.subtotal.value))
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)
                    Text(needsLabel ? "Get label" : "View sale")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Offers

    private func offersSection(_ offers: [Offer]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Offers on your watches") {
                Text("Respond in Offers")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            SellCard {
                VStack(spacing: 0) {
                    ForEach(Array(offers.prefix(4).enumerated()), id: \.element.id) { index, offer in
                        offerRow(offer)
                        if index < min(offers.count, 4) - 1 {
                            Rectangle().fill(Color.calibre.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func offerRow(_ offer: Offer) -> some View {
        Button {
            // The Offers track owns response UI — link, don't rebuild.
            router.open(.offer(offer.id))
        } label: {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.listing?.title ?? "Your listing")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    Text(offerStatusLine(offer))
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                Spacer(minLength: Space.s)
                Text(PriceFormatter.format(offer.amount.value))
                    .font(CalibreType.priceSmall)
                    .foregroundStyle(Color.calibre.foreground)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func offerStatusLine(_ offer: Offer) -> String {
        switch offer.status {
        case .pendingSeller: "Waiting for your response"
        case .countered: "You countered — waiting on the buyer"
        case .acceptedPendingPayment: "Accepted — awaiting payment"
        case .paid: "Paid"
        default: offer.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Wizard

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

// MARK: - List row plumbing

private extension View {
    /// Plain-list row chrome: no separators, quiet background, brand margins.
    func sellRow(top: CGFloat = 0, bottom: CGFloat = Space.xl) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: Space.margin, bottom: bottom, trailing: Space.margin))
    }
}
