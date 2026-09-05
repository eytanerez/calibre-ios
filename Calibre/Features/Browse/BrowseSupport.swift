import CalibreDesign
import CalibreKit
import Nuke
import NukeUI
import SwiftUI

// MARK: - Local navigation
//
// The shared NavigationStacks bind typed `[Route]` paths owned by AppRouter
// (Calibre/App is read-only to this track), so the browse screens navigate
// among themselves with `navigationDestination(item:)` pushes. The
// orchestrator wires the shared Route cases to these screens after P3 lands.

/// Everything the browse track can push. Kept separate from the shared
/// `Route` enum on purpose — see the note above.
enum BrowseDestination: Hashable {
    case search
    case results(BrowseFilters, title: String)
    case brands
    case brand(String)
    case listing(String, zoom: ListingZoomSource?)
    case seller(String)
    case saved
    case recentlyViewed
    case journalIndex
    case journalArticle(String)
}

/// Where a listing-card zoom transition starts: the card's
/// `matchedTransitionSource` id and the namespace it registered in.
struct ListingZoomSource: Hashable {
    let id: String
    let namespace: Namespace.ID
}

extension EnvironmentValues {
    /// Pushes a browse destination onto the current navigation stack. Every
    /// browse screen overrides this with its own `browseStackNode()`, so the
    /// nearest screen owns the push.
    @Entry var browsePush: (BrowseDestination) -> Void = { _ in }
}

/// Attach to the root of every browse screen: hosts the item-based push and
/// hands descendants a `browsePush` that lands on this screen's stack level.
private struct BrowseStackNode: ViewModifier {
    @State private var pushed: BrowseDestination?

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $pushed) { destination in
                BrowseDestinationView(destination: destination)
            }
            .environment(\.browsePush) { pushed = $0 }
    }
}

extension View {
    func browseStackNode() -> some View {
        modifier(BrowseStackNode())
    }
}

/// Resolves a `BrowseDestination` to its screen. Each destination re-attaches
/// its own stack node so chained pushes keep working.
struct BrowseDestinationView: View {
    let destination: BrowseDestination

    var body: some View {
        Group {
            switch destination {
            case .search:
                SearchScreen()
            case .results(let filters, let title):
                ResultsScreen(filters: filters, title: title)
            case .brands:
                AllBrandsScreen()
            case .brand(let brand):
                BrandScreen(brand: brand)
            case .listing(let id, let zoom):
                if let zoom {
                    ListingDetailScreen(listingID: id)
                        .navigationTransition(.zoom(sourceID: zoom.id, in: zoom.namespace))
                } else {
                    ListingDetailScreen(listingID: id)
                }
            case .seller(let username):
                SellerStorefrontScreen(username: username)
            case .saved:
                SavedScreen()
            case .recentlyViewed:
                RecentlyViewedScreen()
            case .journalIndex:
                JournalScreen()
            case .journalArticle(let id):
                JournalArticleScreen(articleID: id)
            }
        }
        .browseStackNode()
    }
}

// MARK: - Filters

/// Everything the results grid can filter and sort by. Hashable so it can
/// ride inside `BrowseDestination` and be diffed for the live-count debounce.
struct BrowseFilters: Hashable {
    var search: String?
    var seller: String?
    var brand: String?
    var model: String?
    var reference: String?
    var condition: String?
    var year: Int?
    var priceMin: Decimal?
    var priceMax: Decimal?
    var boxPapers: Bool?
    var material: String?
    var color: String?
    var caseSize: String?
    var movement: String?
    var bracelet: String?
    var thickness: String?
    var lugWidth: String?
    var waterResistance: String?
    var caliber: String?
    /// Item 1.21 — the seller's return window. `nil` means the buyer has not
    /// asked; `.all` means "any seller who takes returns".
    var returnWindow: ReturnWindowFilter?
    var sort: ListingQuery.Sort?

    /// Facets counted on the Filter button badge. Search, seller and sort
    /// aren't facets; a locked brand is excluded via `countingBrand`.
    func activeCount(countingBrand: Bool = true) -> Int {
        var count = 0
        if countingBrand, brand != nil { count += 1 }
        if model != nil { count += 1 }
        if reference != nil { count += 1 }
        if condition != nil { count += 1 }
        if year != nil { count += 1 }
        if priceMin != nil || priceMax != nil { count += 1 }
        if boxPapers == true { count += 1 }
        for value in [material, color, caseSize, movement, bracelet, thickness, lugWidth, waterResistance, caliber] where value != nil {
            count += 1
        }
        if let returnWindow, returnWindow != .any { count += 1 }
        return count
    }

    func query(page: Int = 1, pageSize: Int = 24, includeTotal: Bool = true) -> ListingQuery {
        ListingQuery(
            search: search,
            seller: seller,
            brand: brand,
            model: model,
            reference: reference,
            priceMin: priceMin,
            priceMax: priceMax,
            condition: condition,
            boxPapers: boxPapers,
            year: year,
            material: material,
            color: color,
            caseSize: caseSize,
            movement: movement,
            bracelet: bracelet,
            thickness: thickness,
            lugWidth: lugWidth,
            waterResistance: waterResistance,
            caliber: caliber,
            returnWindow: returnWindow,
            sort: sort,
            page: page,
            pageSize: pageSize,
            view: .card,
            includeTotal: includeTotal
        )
    }

    /// Everything cleared except search/seller/brand context and sort.
    func cleared(keepBrand: Bool) -> BrowseFilters {
        var cleared = BrowseFilters(search: search, seller: seller, sort: sort)
        if keepBrand { cleared.brand = brand }
        return cleared
    }
}

// A second initializer written inside the struct would suppress the
// memberwise one that 30-odd call sites use, so it lives out here.
extension BrowseFilters {
    /// Rebuilds the filters a saved search stands for.
    ///
    /// The keys are the server's own (`SAVED_SEARCH_FILTER_KEYS` in
    /// Backend/app/api/views/alerts.py), which is also what `saveSearch` in
    /// `FilterSheet` writes — so a search saved from the filter sheet re-runs
    /// as exactly the query that saved it. Anything unrecognised is dropped
    /// rather than guessed at: a saved search that runs the wrong query is
    /// worse than one facet fewer.
    init(savedSearch filters: [String: String]) {
        self.init()
        search = filters["search"]
        brand = filters["brand"]
        model = filters["model"]
        reference = filters["reference"]
        condition = filters["condition"]
        year = filters["year"].flatMap(Int.init)
        priceMin = filters["price_min"].flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        priceMax = filters["price_max"].flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        boxPapers = filters["box_papers"] == "true" ? true : nil
    }

}

// MARK: - Card mapping

extension Listing {
    /// The grid/lane card projection. The model line carries the title slot —
    /// brand and year already live in the eyebrow.
    var cardModel: ListingCardModel {
        ListingCardModel(
            id: id,
            brand: brand ?? "Watch",
            year: productionYear.map(String.init),
            title: model ?? title,
            reference: referenceNumber,
            priceText: PriceFormatter.format(price.value, currency: currency),
            condition: condition?.overall,
            watcherCount: metrics?.watchers,
            imageURL: images.first?.url,
            isVerifiedDealer: seller?.isVerifiedDealer ?? false
        )
    }

    /// The listing's page on the web marketplace — used for sharing.
    var webURL: URL {
        URL(string: "https://buycalibre.com/listing/\(id)")!
    }
}

extension WatchlistItem {
    /// The listing's page on the web marketplace — used for sharing a saved
    /// watch, same as a full `Listing`'s `webURL`.
    var webURL: URL {
        URL(string: "https://buycalibre.com/listing/\(listingId)")!
    }
}

extension ListingSummary {
    /// Cards for cart/watchlist rows.
    ///
    /// `_serialize_listing_summary` (Backend/app/api/views/account.py) sends
    /// only a composed `title` — no brand, model or reference — so this
    /// projection has to take the card's three identity slots out of one
    /// string. What it used to do instead was put the **production year** in
    /// the brand slot and the whole title in the model slot, which §4 makes
    /// visibly wrong twice over: a year sits where a brand goes, the year
    /// column is empty beside it, and the model line — one line, shrinking to
    /// 0.8 and then clipping — turned "Cartier Santos Chronograph WSSA0017"
    /// into "Cartier Santos Chronograph…". §0.6 does not allow that ellipsis.
    ///
    /// Splitting the brand off the front fixes both: the brand row gets a
    /// brand and the year, and the model line is short enough to survive.
    /// `knownBrands` is the catalog's own brand list when the caller has it
    /// (multi-word brands like "A. Lange & Sohne" only split correctly
    /// against a list); without it the first word is used, which is right for
    /// every single-word brand and no worse than today for the rest.
    func cardModel(knownBrands: [String] = []) -> ListingCardModel {
        let parts = Self.split(title: title, knownBrands: knownBrands)
        return ListingCardModel(
            id: id,
            brand: parts.brand,
            year: productionYear.map(String.init),
            title: parts.model,
            reference: parts.reference,
            priceText: PriceFormatter.format(price.value, currency: currency),
            imageURL: image?.url,
            isVerifiedDealer: seller?.isVerifiedDealer ?? false
        )
    }

    var cardModel: ListingCardModel { cardModel(knownBrands: []) }

    /// Pulls a brand off the front of a composed title, and a reference off
    /// the back when the last word can only be one.
    ///
    /// The reference test is deliberately strict — five characters or more,
    /// at least two digits, and no lowercase — because getting it wrong costs
    /// part of a model name, while declining costs only a longer line.
    /// "300M" (four characters) and "40" stay in the model where they belong;
    /// "WSSA0017", "126622" and "SRPB43" move to the Ref. line.
    static func split(title: String, knownBrands: [String]) -> (brand: String, model: String, reference: String?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Longest match wins: "A. Lange & Sohne" must beat "A." if both were
        // ever in the list.
        let matchedBrand = knownBrands
            .filter { !$0.isEmpty && trimmed.lowercased().hasPrefix($0.lowercased() + " ") }
            .max(by: { $0.count < $1.count })

        var remainder: String
        var brand: String
        if let matchedBrand {
            brand = matchedBrand
            remainder = String(trimmed.dropFirst(matchedBrand.count))
                .trimmingCharacters(in: .whitespaces)
        } else {
            var words = trimmed.split(separator: " ").map(String.init)
            // A one-word title is the whole name; splitting it would leave the
            // model line empty.
            guard words.count >= 2 else {
                return (trimmed.isEmpty ? "Watch" : trimmed, trimmed, nil)
            }
            brand = words.removeFirst()
            remainder = words.joined(separator: " ")
        }

        var words = remainder.split(separator: " ").map(String.init)
        var reference: String?
        if words.count >= 2, let last = words.last, Self.looksLikeReference(last) {
            reference = last
            words.removeLast()
        }
        let model = words.joined(separator: " ")
        return (brand, model.isEmpty ? remainder : model, reference)
    }

    private static func looksLikeReference(_ word: String) -> Bool {
        guard word.count >= 5 else { return false }
        guard !word.contains(where: \.isLowercase) else { return false }
        return word.filter(\.isNumber).count >= 2
    }

    var isAvailable: Bool { status == .active }

    /// "Sold" / "Reserved" badge for saved and bagged watches that got away.
    var unavailableBadge: (text: String, tone: StatusBadge.Tone)? {
        switch status {
        case .sold: ("Sold", .neutral)
        case .reserved: ("Reserved", .warning)
        case .active: nil
        default: ("No longer listed", .neutral)
        }
    }
}

// MARK: - Images

/// The one way browse loads listing imagery: NukeUI with downsampling sized
/// to the container, resting on a stable warm secondary well. Loading, missing,
/// and failed images keep the exact same proposed frame as the final image so
/// cards and rows never jump when decoding finishes.
struct ListingImageWell: View {
    let url: URL?
    var targetWidth: CGFloat = 400

    var body: some View {
        ZStack {
            Color.calibre.secondary.opacity(0.5)

            if let request {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else if state.error != nil {
                        fallbackGlyph
                    } else {
                        Rectangle().shimmer()
                    }
                }
            } else {
                fallbackGlyph
            }
        }
        .clipped()
        // Smart Invert turns every photograph into a negative; the watch is
        // the product, so the well opts its imagery out the way Photos does.
        .accessibilityIgnoresInvertColors()
    }

    private var request: ImageRequest? {
        url.map {
            ImageRequest(url: $0, processors: [.resize(width: targetWidth, upscale: false)])
        }
    }

    private var fallbackGlyph: some View {
        Image(systemName: "clock")
            .font(.system(size: min(40, max(18, targetWidth * 0.1)), weight: .light))
            .foregroundStyle(Color.calibre.placeholder)
            .accessibilityHidden(true)
    }
}

// MARK: - Grid card

/// A tappable listing card: pushes the PDP with a zoom transition, offers
/// Save / Share on long-press. Used by every lane and grid in the track.
struct ListingGridCard: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.browsePush) private var push

    let listing: Listing
    let laneKey: String
    let zoomNamespace: Namespace.ID

    private var sourceID: String { "\(laneKey)-\(listing.id)" }

    var body: some View {
        Button {
            push(.listing(listing.id, zoom: ListingZoomSource(id: sourceID, namespace: zoomNamespace)))
        } label: {
            ListingCard(model: listing.cardModel) { url in
                ListingImageWell(url: url)
            }
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: sourceID, in: zoomNamespace)
        .contextMenu {
            Button {
                toggleSaved()
            } label: {
                if services.commerce.isWatching(listingID: listing.id) {
                    Label("Remove from Saved", systemImage: "heart.slash")
                } else {
                    Label("Save", systemImage: "heart")
                }
            }
            ShareLink(item: listing.webURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityLabel("\(listing.cardModel.brand) \(listing.cardModel.title), \(listing.cardModel.priceText)")
    }

    private func toggleSaved() {
        let id = listing.id
        let commerce = services.commerce
        let toasts = toasts
        let analyticsListing = Analytics.ListingInfo(listing)
        services.auth.require("Sign in to save this watch") {
            let wasWatching = commerce.isWatching(listingID: id)
            do {
                try await commerce.toggleWatch(listingID: id)
                Haptics.shared.play(.save)
                if wasWatching {
                    toasts.show(title: "Removed from Saved")
                } else {
                    Analytics.watchLiked(analyticsListing)
                    toasts.show(title: "Saved", message: "We'll keep an eye on this one for you.", tone: .success)
                }
            } catch {
                Haptics.shared.play(.error)
                toasts.show(title: "Couldn't update Saved", message: error.browseMessage, tone: .error)
            }
        }
    }
}

/// A horizontally scrolling lane of listing cards under a serif header.
/// Shared by the home rows and the PDP's "Similar watches". Passing
/// `onViewAll` appends a trailing card, in the same footprint as every other
/// card in the lane, that opens the shelf's full browse destination.
struct ListingLaneRow: View {
    let title: String
    let listings: [Listing]
    let laneKey: String
    let zoomNamespace: Namespace.ID
    var onViewAll: (() -> Void)?

    /// Some listings have a reference number and some don't, so cards in the
    /// same lane aren't naturally the same height — measured (not
    /// hardcoded) so it scales with Dynamic Type and stays correct if the
    /// card's content ever changes shape.
    @State private var cardHeight: CGFloat?

    /// The width scales too. It used to be a frozen 168pt, which is what put
    /// "R  2002" where "ROLEX 2002" belongs at accessibility text sizes and
    /// pushed the condition pill out over the photograph. Capped by
    /// `calibreLaneCardWidth` so the card never outgrows the phone.
    @ScaledMetric(relativeTo: .body) private var scaledCardWidth: CGFloat = 168
    private var cardWidth: CGFloat { calibreLaneCardWidth(scaledCardWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
                .padding(.horizontal, Space.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.l) {
                    ForEach(listings) { listing in
                        ListingGridCard(listing: listing, laneKey: laneKey, zoomNamespace: zoomNamespace)
                            .frame(width: cardWidth)
                            .measureLaneCardHeight()
                            .frame(height: cardHeight, alignment: .top)
                    }
                    if let onViewAll {
                        ListingLaneViewAllCard(title: title, action: onViewAll)
                            .frame(width: cardWidth)
                            .measureLaneCardHeight()
                            .frame(height: cardHeight, alignment: .top)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, 2)
            }
        }
        .onPreferenceChange(LaneCardHeightKey.self) { cardHeight = $0 }
    }
}

/// Reports the max natural (unconstrained) height across every card in a
/// `ListingLaneRow`, so every card — including the trailing "view all" card
/// — can be pinned to the same total footprint regardless of which optional
/// lines any individual card happens to show.
private struct LaneCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Reads this view's natural height via a background `GeometryReader`
    /// (measured before any later `.frame(height:)` is applied, so it isn't
    /// self-referential) and reports it up to `ListingLaneRow`.
    func measureLaneCardHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: LaneCardHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

/// The lane's own trailing "view all" card. Mirrors `ListingCard`'s image
/// square + eyebrow/title/price-row layout; `ListingLaneRow` measures every
/// card's natural height (this one included) and pins them all to the
/// tallest, so it's never shorter or taller than what its actual content
/// happens to need — no hardcoded/reserved lines here.
struct ListingLaneViewAllCard: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.calibre.secondary.opacity(0.5))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Color.calibre.border, lineWidth: 1)
                    )
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.calibre.primary)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(title)
                    Text("See the full shelf")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline) {
                        Text("View all")
                            .font(CalibreType.price)
                            .foregroundStyle(Color.calibre.primary)
                        Spacer()
                    }
                    .padding(.top, 1)
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("View all \(title)")
        .accessibilityHint("Shows the full list")
    }
}

/// Skeleton twin of `ListingLaneRow` for cold loads.
struct ListingLaneSkeleton: View {
    /// Matches the real lane's card width so the skeleton doesn't jump.
    @ScaledMetric(relativeTo: .body) private var scaledCardWidth: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Rectangle()
                .frame(width: 140, height: 20)
                .shimmer()
                .padding(.horizontal, Space.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.l) {
                    ForEach(0..<4, id: \.self) { _ in
                        ListingCardSkeleton().frame(width: calibreLaneCardWidth(scaledCardWidth))
                    }
                }
                .padding(.horizontal, Space.margin)
            }
            .disabled(true)
        }
    }
}

// MARK: - Search field

/// Visual twin of the design system's `SearchField` that additionally
/// autofocuses and reports submits — the kit component keeps its focus state
/// private, and CalibreDesign is read-only to feature tracks. Tokens only.
struct BrowseSearchField: View {
    @Binding var text: String
    var placeholder = "Search watches"
    var autofocus = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Color.calibre.placeholder)
            )
            .font(CalibreType.body)
            .foregroundStyle(Color.calibre.foreground)
            .tint(Color.calibre.primary)
            .focused($focused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.calibre.placeholder)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(minHeight: Space.touchTarget)
        .background(
            Color.calibre.secondary,
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(focused ? Color.calibre.borderBright : Color.calibre.border, lineWidth: 1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                .strokeBorder(Color.calibre.primary.opacity(0.11), lineWidth: 3)
                .padding(-3)
                .opacity(focused ? 1 : 0)
        }
        .animation(Motion.easeFast, value: focused)
        .animation(Motion.easeFast, value: text.isEmpty)
        .task {
            guard autofocus else { return }
            // Let the push animation land before raising the keyboard.
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }
}

// MARK: - Recent searches

/// Tiny on-device store for the search screen's recent queries. Lives in the
/// feature layer: extensions can't add stored state to `LocalSignals`, and
/// the kit files are read-only to this track.
@MainActor
@Observable
final class RecentSearchesStore {
    private(set) var entries: [String] = []

    @ObservationIgnored private let key = "browse.recentSearches"
    @ObservationIgnored private let cap = 8

    init() {
        entries = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        entries.insert(text, at: 0)
        if entries.count > cap {
            entries.removeLast(entries.count - cap)
        }
        UserDefaults.standard.set(entries, forKey: key)
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Gated presentation

extension AuthSession {
    /// `require()`, but when the gate had to be raised, the replayed action
    /// waits for the auth sheet to slide away before presenting UI of its
    /// own — presenting during the dismissal animation gets swallowed.
    func requireThenPresent(_ reason: String, action: @escaping @MainActor @Sendable () async -> Void) {
        if isAuthenticated {
            Task { await action() }
        } else {
            require(reason) {
                try? await Task.sleep(for: .milliseconds(700))
                await action()
            }
        }
    }
}

// MARK: - Errors

extension Error {
    /// The message to show for a browse/commerce failure — the backend's own
    /// words when it spoke, a gentle fallback otherwise.
    var browseMessage: String {
        (self as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
