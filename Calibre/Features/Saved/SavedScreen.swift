import CalibreDesign
import CalibreKit
import SwiftUI

/// Saved — two tabs, one list at a time (item 1.10): **Watches** and
/// **Searches**, each carrying its own count.
///
/// The two halves are different kinds of thing. A saved watch is a specific
/// object you are deciding about; a saved search is a standing instruction to
/// the marketplace. They were never both on this screen before — the searches
/// half existed only as a create action inside the filter sheet and the search
/// screen's empty state, with no surface anywhere in the app that listed what
/// had been saved. So a member could ask us to watch for a Datejust and then
/// never see, run, or cancel that request again.
///
/// Price-drop badges were spec'd "if detectable": the watchlist payload
/// carries only the listing's current price — no saved-at price — so drops
/// aren't detectable from the API today. Skipped and noted.
struct SavedScreen: View {

    /// Which half is showing. Only one list is on screen at a time — the two
    /// stacked, as the web page had them, made a short saved-search list a
    /// footnote under a tall grid of watches.
    enum Tab: Hashable {
        case watches
        case searches
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    /// This screen pushes on its own stack rather than through
    /// `@Environment(\.browsePush)`.
    ///
    /// `browseStackNode()` injects `browsePush` into a screen's **descendants**
    /// — the modifier sits below `body`, so a view cannot read the value its
    /// own modifier supplies. Inside the browse track that is invisible,
    /// because the parent browse screen already put a working push in the
    /// environment. Saved is also reachable straight from the Me tab
    /// (`YouScreen`), whose stack is not a browse stack, and there
    /// `browsePush` resolves to its default — `{ _ in }`. Tapping a saved
    /// watch from Me therefore did nothing at all, silently, and the saved
    /// searches added here would have inherited the same dead tap.
    @State private var pushed: BrowseDestination?

    @State private var tab: Tab = .watches
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isEditing = false
    @State private var searchesLoaded = false
    @Namespace private var zoomNamespace
    /// Guards `load()`'s commit: a pull to refresh landing while the initial
    /// `.task` load (or a "Try again" retry) is still in flight must not let
    /// the slower call win.
    @State private var loadGeneration = 0

    private var items: [WatchlistItem] { services.commerce.watchlist }
    private var searches: [SavedSearchSummary] { services.serverAlerts.savedSearches }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "heart",
                    title: "Keep your shortlist here",
                    message: "Sign in and the watches and searches you save will wait for you on any device.",
                    actionTitle: "Sign in"
                ) {
                    services.auth.require("Sign in to see your saved watches") {}
                }
            } else {
                VStack(spacing: 0) {
                    SegmentedTabs(
                        selection: $tab,
                        items: [
                            (.watches, "Watches (\(items.count))"),
                            (.searches, "Searches (\(searches.count))"),
                        ]
                    )
                    .padding(.horizontal, Space.margin)

                    switch tab {
                    case .watches: watchesPane
                    case .searches: searchesPane
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calibrePageBackground()
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushed) { destination in
            BrowseDestinationView(destination: destination)
        }
        .toolbar {
            // Edit belongs to the watch grid — the search rows carry their own
            // Remove, and an Edit button that did nothing on one of two tabs
            // would be worse than no Edit button at all.
            if tab == .watches, !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(Motion.easeMedium) {
                            isEditing.toggle()
                        }
                    }
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.primary)
                }
            }
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
        // Leaving the watch grid ends Edit mode; coming back to a screen still
        // in Edit with a minus button on every card is a state nobody asked
        // for and cannot see the cause of.
        .onChange(of: tab) { _, newValue in
            if newValue != .watches, isEditing {
                withAnimation(Motion.easeMedium) { isEditing = false }
            }
        }
    }

    // MARK: - Watches

    @ViewBuilder
    private var watchesPane: some View {
        if isLoading, items.isEmpty {
            skeleton
        } else if items.isEmpty, loadFailed {
            EmptyState(
                icon: "wifi.slash",
                title: "Couldn't load your saved watches",
                message: "Check your connection and try again.",
                actionTitle: "Try again"
            ) {
                Task { await load() }
            }
        } else if items.isEmpty {
            EmptyState(
                icon: "heart",
                title: "Nothing saved yet",
                message: "Watches you save appear here so you can compare and act when the moment is right.",
                aside: "The one you keep going back to counts."
            )
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: calibreGridColumns(typeSize, spacing: Space.l),
                alignment: .leading,
                spacing: Space.xl
            ) {
                ForEach(items) { item in
                    savedCell(item)
                }
            }
            .padding(Space.margin)
        }
    }

    /// Same `ListingCard` every other grid in the app uses — the unavailable
    /// badge is the one addition, laid over the image corner. The zoom
    /// transition and Share action mirror `ListingGridCard` so a saved watch
    /// opens and behaves the same as it does from Home or Browse.
    private func savedCell(_ item: WatchlistItem) -> some View {
        let sourceID = "saved-\(item.id)"
        return Button {
            guard !isEditing else { return }
            pushed = .listing(item.listingId, zoom: ListingZoomSource(id: sourceID, namespace: zoomNamespace))
        } label: {
            ZStack(alignment: .topTrailing) {
                ListingCard(model: cardModel(for: item)) { url in
                    ListingImageWell(url: url)
                }
                .overlay(alignment: .topLeading) {
                    // Over the bottom-left corner of the **photograph**, not
                    // of the card.
                    //
                    // It used to hang off the card's own bottom edge, which
                    // was the price row's line — and once §4 gave the card a
                    // Ref. line and a dealer chip, "No longer listed" landed
                    // squarely on top of "$5,150". A sold watch's price and
                    // the fact that it is sold are the two things this cell
                    // exists to say, and they were overprinting each other.
                    //
                    // The clear square reproduces the photo's footprint —
                    // `ListingCard` gives the image `aspectRatio(1, .fit)`, so
                    // a square pinned to the card's top-leading corner is
                    // exactly where the photo is, at any card width.
                    if let badge = item.listing?.unavailableBadge {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .bottomLeading) {
                                // `StatusBadge` fills its capsule with its own
                                // tint at 12% — legible on the page ground it
                                // was drawn for, and very nearly invisible on
                                // a photograph. The frosted plate is the one
                                // `ConditionPill` and `WatcherPill` already
                                // use for exactly this, so the three marks
                                // that ride on a photo read the same way.
                                StatusBadge(badge.text, tone: badge.tone)
                                    .background(
                                        Color.calibre.background.opacity(0.95),
                                        in: Capsule()
                                    )
                                    .padding(Space.s)
                            }
                            .allowsHitTesting(false)
                    }
                }

                if isEditing {
                    Button {
                        Task { await remove(item) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.calibre.destructive)
                            .background(Color.calibre.background, in: Circle())
                            .frame(width: Space.touchTarget, height: Space.touchTarget, alignment: .topTrailing)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(Space.xs)
                    .transition(.opacity)
                    .accessibilityLabel("Remove \(item.listing?.title ?? "watch") from Saved")
                }
            }
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: sourceID, in: zoomNamespace)
        .contextMenu {
            Button(role: .destructive) {
                Task { await remove(item) }
            } label: {
                Label("Remove from Saved", systemImage: "heart.slash")
            }
            ShareLink(item: item.webURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityLabel(cardLabel(for: item))
    }

    /// Everything the cell actually shows, in the order it shows it. This
    /// `Button` collapses the card into a single element, so whatever is left
    /// out of this string is simply not there for a screen reader — the
    /// condition pill, the dealer mark, and above all the Sold / Reserved
    /// badge, which is the difference between a watch you can buy and one you
    /// cannot.
    private func cardLabel(for item: WatchlistItem) -> String {
        let model = cardModel(for: item)
        return [
            model.brand,
            model.title,
            model.priceText,
            model.condition,
            model.isVerifiedDealer ? "Verified dealer" : nil,
            item.listing?.unavailableBadge?.text,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    /// The watchlist payload only ever omits `listing` for a row whose watch
    /// was deleted outright — vanishingly rare, so a plain placeholder card
    /// is fine.
    private func cardModel(for item: WatchlistItem) -> ListingCardModel {
        // The catalog's brand list, when it is warm, is what lets a
        // multi-word brand ("A. Lange & Sohne") come off a composed title in
        // one piece rather than as "A.".
        item.listing?.cardModel(knownBrands: services.catalog.metadata?.options.brands ?? []) ?? ListingCardModel(
            id: item.listingId,
            brand: " ",
            title: "Listing",
            priceText: "—"
        )
    }

    private var skeleton: some View {
        ScrollView {
            LazyVGrid(
                columns: calibreGridColumns(typeSize, spacing: Space.l),
                spacing: Space.xl
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    ListingCardSkeleton()
                }
            }
            .padding(Space.margin)
        }
        .disabled(true)
    }

    // MARK: - Searches

    @ViewBuilder
    private var searchesPane: some View {
        if !searchesLoaded, searches.isEmpty {
            ScrollView {
                VStack(spacing: Space.s) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                            .fill(Color.calibre.card)
                            .frame(height: 64)
                            .shimmer()
                    }
                }
                .padding(Space.margin)
            }
            .disabled(true)
        } else if searches.isEmpty {
            EmptyState(
                icon: "bell.badge",
                title: "No saved searches",
                message: "Save a search and we'll watch the market for you — you'll hear from us the moment something matches.",
                aside: "Set it once; we'll do the looking."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: Space.s) {
                    ForEach(searches) { search in
                        savedSearchRow(search)
                    }
                }
                .padding(Space.margin)
            }
        }
    }

    /// One standing instruction. Tapping it runs the query it stands for —
    /// which is the whole reason `filters` is now decoded off the payload.
    private func savedSearchRow(_ search: SavedSearchSummary) -> some View {
        Button {
            pushed = .results(BrowseFilters(savedSearch: search.filters), title: search.name)
        } label: {
            HStack(spacing: Space.m) {
                IconTile(systemName: "bell.badge")

                VStack(alignment: .leading, spacing: 2) {
                    // A saved search's name is a name (§0.6) — it wraps rather
                    // than clipping, so "Tudor Black Bay Pro under $4,500"
                    // does not become "Tudor Black Bay Pro und…".
                    Text(search.name)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(for: search))
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.calibre.placeholder)
            }
            .padding(Space.l)
            .frame(minHeight: Space.touchTarget)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(role: .destructive) {
                Task { await removeSearch(search) }
            } label: {
                Label("Stop watching for this", systemImage: "bell.slash")
            }
        }
        .accessibilityLabel("\(search.name). \(subtitle(for: search))")
        .accessibilityHint("Runs this search")
        .accessibilityAction(named: "Stop watching for this") {
            Task { await removeSearch(search) }
        }
    }

    /// What this search has done for you lately. `last_matched_at` starts at
    /// the moment the search was created — the backend sets it so nothing
    /// already listed is retro-notified — so an untriggered search and a
    /// brand-new one carry the same timestamp and the honest line is about
    /// when it started, not about a match that never happened.
    private func subtitle(for search: SavedSearchSummary) -> String {
        let facets = search.filters.count
        let facetText = facets == 1 ? "1 filter" : "\(facets) filters"
        guard let created = Self.date(from: search.createdAt) else {
            return "Watching the market · \(facetText)"
        }
        return "Watching since \(created.formatted(date: .abbreviated, time: .omitted)) · \(facetText)"
    }

    private static func date(from iso: String?) -> Date? {
        guard let iso else { return nil }
        // The API emits fractional-second timestamps; accept plain ones too.
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? Date(iso, strategy: fractional)) ?? (try? Date(iso, strategy: .iso8601))
    }

    private func removeSearch(_ search: SavedSearchSummary) async {
        do {
            try await services.serverAlerts.deleteSavedSearch(id: search.id)
            Haptics.shared.play(.save)
            toasts.show(title: "We'll stop watching for that one")
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't remove that search", message: error.browseMessage, tone: .error)
        }
    }

    // MARK: - Loading

    /// Both halves load together, whichever tab is showing: the tab labels
    /// carry counts, so a count that only became true after you tapped the tab
    /// would be a wrong number on screen rather than a missing one.
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        guard session.isAuthenticated else {
            isLoading = false
            return
        }
        isLoading = true
        // CommerceStore itself guards `watchlist` against a stale
        // response landing after a session reset; this generation check
        // additionally protects this screen's own loading/error state
        // against two overlapping `load()` calls (retry vs. refresh).
        async let watchlist: Void = loadWatchlist()
        async let alerts: Void = loadSearches()
        // The brand list is what lets a composed watchlist title be split
        // into brand / model / reference; usually warm, never blocking.
        async let metadata: Void = { _ = try? await services.catalog.loadMetadata() }()
        _ = await (watchlist, alerts, metadata)
        guard generation == loadGeneration, !Task.isCancelled else { return }
        isLoading = false
    }

    private func loadWatchlist() async {
        let generation = loadGeneration
        do {
            _ = try await services.commerce.loadWatchlist()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            loadFailed = false
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            loadFailed = true
        }
    }

    /// A failed search load leaves `searchesLoaded` true on purpose: the pane
    /// then shows the empty state rather than shimmering forever, and pull to
    /// refresh is right there.
    private func loadSearches() async {
        _ = try? await services.serverAlerts.loadSavedSearches()
        guard !Task.isCancelled else { return }
        searchesLoaded = true
    }

    private func remove(_ item: WatchlistItem) async {
        do {
            try await services.commerce.toggleWatch(listingID: item.listingId)
            Haptics.shared.play(.save)
            toasts.show(title: "Removed from Saved")
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't remove it", message: error.browseMessage, tone: .error)
        }
    }
}
