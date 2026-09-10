import CalibreKit
import Foundation
import Observation
import SwiftUI

/// The five root tabs.
enum AppTab: Hashable {
    case home, community, sell, collection, you

    /// The tab's own name, as the tab bar prints it. Used by the back button
    /// a cross-tab jump leaves behind, so it names the place the reader
    /// actually came from.
    var title: String {
        switch self {
        case .home: "Home"
        case .community: "Community"
        case .sell: "Sell"
        case .collection: "Vault"
        case .you: "Me"
        }
    }
}

/// Everything the app can navigate to from anywhere — pushes, push
/// notifications, and calibre:// / universal links all funnel through here.
enum Route: Hashable {
    case listing(String)
    case seller(String)
    case brand(String)
    case order(String)
    case offer(String)
    case journal
    case journalArticle(String)
    /// The list of the customer's own support conversations. Support opens
    /// here, not on a thread — there is more than one now.
    case supportChat
    /// One support conversation, by id. A reply push names its own thread.
    case supportThread(String)
    case messages
    /// One buyer↔seller conversation, by its calibre-messaging thread id.
    case messageThread(String)
    case alerts
    case checkout(String, offerID: String?)
    /// A past poll's own page, carried by value — there's no fetch-by-id yet.
    case poll(CommunityPrompt)
    /// One watch in the member's vault. The id, not the model: the detail
    /// route refetches, and a route that carried a stale copy of the watch
    /// would keep showing it after an edit.
    case vaultWatch(String)
    /// A watch's public Passport, by its printed code. Anonymized and
    /// readable without a session — it is the page an owner sends to a buyer.
    case passport(String)
    /// The authentication report for an order or a vault watch. A page, not a
    /// sheet: the envelope sequence opens onto the document itself, and a
    /// sheet is a surface above the one the film is playing on.
    case authenticationReport(AuthenticationReportTarget)
}

/// A checkout the app is presenting as a full-screen cover. Checkout owns its
/// own navigation stack, so it rides above the tabs rather than pushing.
///
/// A checkout covers a *set* of watches — one payment, one order each. Buying
/// a single watch is a set of one, so the PDP, an accepted offer and a bag of
/// five all present through the same request.
struct CheckoutRequest: Identifiable, Hashable {
    let listingIDs: [String]
    let offerID: String?

    init(listingIDs: [String], offerID: String? = nil) {
        self.listingIDs = listingIDs
        self.offerID = offerID
    }

    init(listingID: String, offerID: String? = nil) {
        self.init(listingIDs: [listingID], offerID: offerID)
    }

    var id: String { "\(listingIDs.joined(separator: ","))|\(offerID ?? "")" }
}

/// Owns tab selection and one navigation path per tab. `open(_:)` selects the
/// tab a route belongs to and pushes it; `handle(url:)` decodes deep links.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    /// Where a cross-tab jump came from, so Back can return across it.
    ///
    /// Some destinations are a tab and not a screen — the feed's "go to the
    /// Vault" card, the Vault's "list this watch" — and those cannot be an
    /// ordinary push: the Vault's whole stack sits under a biometric gate that
    /// only the tab raises, and the listing wizard needs the Sell tab's own
    /// session. Moving the reader's position into another tab's stack would
    /// leave both behind. So the jump stays a jump and the origin is kept
    /// here; the destination's root draws a way back while it is set, and
    /// returning is the reverse selection with the origin's stack untouched.
    private(set) var tabOrigin: AppTab?

    /// The tab bar's own selection. Choosing a tab by hand ends any jump: the
    /// reader has just said where they are, and a back button still pointing
    /// at a card they left two taps ago would be a lie.
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { tab in
                self.tabOrigin = nil
                self.selectedTab = tab
            }
        )
    }

    /// Sends the reader to a whole tab, rememberable. Selecting the tab they
    /// are already on is not a jump and leaves any earlier origin alone.
    func jump(to tab: AppTab) {
        guard tab != selectedTab else { return }
        tabOrigin = selectedTab
        selectedTab = tab
    }

    /// The destination root's back button.
    func returnFromJump() {
        guard let origin = tabOrigin else { return }
        tabOrigin = nil
        selectedTab = origin
    }

    var homePath: [Route] = []
    var communityPath: [Route] = []
    var sellPath: [Route] = []
    /// Type-erased, like the Me tab below and for the same kind of reason: the
    /// Vault pushes `Route` (a Passport, a listing) and `VaultWatchLink` (one
    /// watch, which carries the photograph's frame into the screen it opens),
    /// and a homogeneous `[Route]` can hold only one of the two.
    ///
    /// It is also what keeps a watch open. A watch that Calibre authenticated
    /// plays a film on arrival; the moment host used to re-parent the whole app
    /// to do that, every `NavigationStack` in it was rebuilt, and a push that
    /// was not IN the path is state a rebuild does not carry — the detail
    /// screen appeared and was thrown straight back to the list. The host is
    /// fixed; a path element would have survived it either way.
    var collectionPath = NavigationPath()
    /// Type-erased: the Me tab pushes both `Route` (orders/offers/alerts and
    /// support, from deep links) and `ProfileDestination` (profile/addresses/…),
    /// so a homogeneous `[Route]` would silently drop the profile pushes and
    /// desync the stack.
    var youPath = NavigationPath()

    /// The swipe deck, presented full-screen from the Home header.
    var deckPresented = false {
        didSet {
            if !deckPresented { deckPath = [] }
        }
    }
    /// The deck cover's own navigation stack (listing detail from a card).
    var deckPath: [Route] = []

    /// Set when a calibre://auth/reset?token= link arrives; the root view
    /// presents the reset-password screen.
    var passwordResetToken: String?

    /// The checkout cover currently presented, if any.
    var checkoutRequest: CheckoutRequest?

    /// A listing the Vault asked us to start. The wizard needs the Sell tab's
    /// `SellSession`, so the Vault parks the prefill here and switches tabs;
    /// the seller dashboard picks it up and opens the wizard — which also
    /// means the seller gate still applies to people who can't list yet.
    var pendingListingPrefill: ListingPrefill?

    /// A moderation notification can name a listing that is deliberately not
    /// public (draft, rejected, or taken down). The Sell dashboard owns the
    /// authenticated listing collection and editor, so the router parks the
    /// id here while it switches tabs and the dashboard consumes it after its
    /// listings load.
    var pendingSellerListingID: String?

    /// Send the seller to a fresh listing prefilled from one of their watches.
    func startListing(prefill: ListingPrefill) {
        pendingListingPrefill = prefill
        jump(to: .sell)
    }

    /// Opens one of the member's own listings in the seller editor.
    func openSellerListing(id: String) {
        deckPresented = false
        tabOrigin = nil
        pendingSellerListingID = id
        selectedTab = .sell
    }

    /// Presents checkout for a listing (optionally an accepted offer) as a
    /// full-screen cover above the tab shell.
    func presentCheckout(listingID: String, offerID: String? = nil) {
        checkoutRequest = CheckoutRequest(listingID: listingID, offerID: offerID)
    }

    /// Presents checkout for a set of watches — the bag's selected rows. An
    /// empty set is not a checkout, so it presents nothing.
    func presentCheckout(listingIDs: [String]) {
        guard !listingIDs.isEmpty else { return }
        checkoutRequest = CheckoutRequest(listingIDs: listingIDs)
    }

    /// Selects the tab that owns `route` and pushes it there. `.checkout` is
    /// special — it presents as a cover rather than a stack push.
    func open(_ route: Route) {
        if case let .checkout(listingID, offerID) = route {
            presentCheckout(listingID: listingID, offerID: offerID)
            return
        }
        // A route arriving from a push or deep link should land on a visible
        // stack — dismiss the deck cover if it's up.
        deckPresented = false
        let tab = homeTab(for: route)
        // A push notification or a link is not a place inside the app, so
        // there is nothing behind it to offer a way back to.
        tabOrigin = nil
        selectedTab = tab
        switch tab {
        case .home: homePath.append(route)
        case .community: communityPath.append(route)
        case .sell: sellPath.append(route)
        case .collection: collectionPath.append(route)
        case .you: youPath.append(route)
        }
    }

    /// In-app navigation: push onto the stack the user is *already* looking
    /// at, so Back returns them where they came from. A listing opened from
    /// the Sell tab stays in Sell. Deep links and notifications use `open(_:)`
    /// instead, which jumps to the route's canonical tab.
    func push(_ route: Route) {
        if case let .checkout(listingID, offerID) = route {
            presentCheckout(listingID: listingID, offerID: offerID)
            return
        }
        // The swipe deck is a cover with its own stack — stay inside it.
        if deckPresented {
            deckPath.append(route)
            return
        }
        switch selectedTab {
        case .home: homePath.append(route)
        case .community: communityPath.append(route)
        case .sell: sellPath.append(route)
        case .collection: collectionPath.append(route)
        case .you: youPath.append(route)
        }
    }

    /// Which tab a route naturally lives in.
    private func homeTab(for route: Route) -> AppTab {
        switch route {
        // The public Passport is not a vault record and must not land in the
        // Vault tab, even though it is a document about a watch. That tab's
        // entire navigation stack sits under `vaultGate` — the biometric lock
        // is above the stack on purpose, so no pushed route can escape it —
        // and the lock is on by default after every trip to the background. A
        // passport routed there therefore asks a signed-in member for Face ID
        // before it will show them a booklet that needs no account at all,
        // usually somebody else's. Android routes it outside its own gate for
        // the same reason (`navigation/MainTabShell.kt`).
        case .passport:
            .home
        case .listing, .seller, .brand, .checkout:
            .home
        case .journal, .journalArticle, .poll:
            .community
        case .order, .offer, .alerts, .supportChat, .supportThread, .messages, .messageThread,
             .authenticationReport:
            .you
        case .vaultWatch:
            .collection
        }
    }

    /// What a recognized link names. Decoding is separate from navigating so
    /// that a caller who is already standing somewhere — a link tapped inside a
    /// support conversation, say — can push the destination above itself
    /// instead of jumping to the route's canonical tab and losing the page the
    /// reader was on.
    enum LinkTarget {
        case route(Route)
        case passwordReset(String)
    }

    /// Decodes calibre:// scheme links and https://buycalibre.com universal
    /// links without navigating. Nil when the URL is not one of ours.
    func target(for url: URL) -> LinkTarget? {
        if url.scheme?.lowercased() == "calibre" {
            return calibreSchemeTarget(url)
        }
        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
           let host = url.host()?.lowercased(),
           host == "buycalibre.com" || host == "www.buycalibre.com" {
            return universalLinkTarget(url)
        }
        return nil
    }

    /// Handles calibre:// scheme links and https://buycalibre.com universal
    /// links. Returns true when the URL was recognized.
    @discardableResult
    func handle(url: URL) -> Bool {
        switch target(for: url) {
        case .route(let route):
            open(route)
            return true
        case .passwordReset(let token):
            passwordResetToken = token
            return true
        case nil:
            return false
        }
    }

    /// calibre://listing/<id>, calibre://order/<id>, calibre://offer/<id>,
    /// calibre://support, calibre://alerts, calibre://auth/reset?token=…
    /// (Google's calibre://auth?code= callback is consumed by the web-auth
    /// session, never here.)
    private func calibreSchemeTarget(_ url: URL) -> LinkTarget? {
        guard let host = url.host()?.lowercased() else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "listing":
            guard let id = segments.first else { return nil }
            return .route(.listing(id))
        case "seller":
            guard let id = segments.first else { return nil }
            return .route(.seller(id))
        case "brand":
            guard let id = segments.first else { return nil }
            return .route(.brand(id))
        case "order":
            guard let id = segments.first else { return nil }
            return .route(.order(id))
        case "offer":
            guard let id = segments.first else { return nil }
            return .route(.offer(id))
        case "journal":
            if let id = segments.first {
                return .route(.journalArticle(id))
            }
            return .route(.journal)
        case "passport":
            guard let code = segments.first else { return nil }
            return .route(.passport(code))
        // `support` and `support/<thread id>` are both live: the customer
        // push now names its conversation, and a build that only understood
        // the bare word would have dropped the id in silence.
        case "support":
            if let id = segments.first, !id.isEmpty {
                return .route(.supportThread(id))
            }
            if let thread = queryValue("thread", in: url), !thread.isEmpty {
                return .route(.supportThread(thread))
            }
            return .route(.supportChat)
        case "alerts":
            return .route(.alerts)
        case "auth":
            guard segments.first == "reset",
                  let token = queryValue("token", in: url), !token.isEmpty else { return nil }
            return .passwordReset(token)
        default:
            return nil
        }
    }

    /// https://buycalibre.com/listing/:id and friends — the web app's paths.
    private func universalLinkTarget(_ url: URL) -> LinkTarget? {
        let segments = url.pathComponents.filter { $0 != "/" }
        guard let first = segments.first?.lowercased() else { return nil }

        switch first {
        case "listing", "listings":
            guard segments.count > 1 else { return nil }
            return .route(.listing(segments[1]))
        case "seller", "sellers":
            guard segments.count > 1 else { return nil }
            return .route(.seller(segments[1]))
        case "brand", "brands":
            guard segments.count > 1 else { return nil }
            return .route(.brand(segments[1]))
        case "order", "orders":
            guard segments.count > 1 else { return nil }
            return .route(.order(segments[1]))
        case "offer", "offers":
            guard segments.count > 1 else { return nil }
            return .route(.offer(segments[1]))
        case "journal":
            if segments.count > 1 {
                return .route(.journalArticle(segments[1]))
            }
            return .route(.journal)
        // The link an owner sends a buyer. It now opens the booklet in the
        // app rather than bouncing the reader out to Safari.
        case "passport", "passports":
            guard segments.count > 1 else { return nil }
            return .route(.passport(segments[1]))
        // The reply email's CTA for a signed-in customer is
        // `/support?thread=<id>`; the bare path is still the list.
        case "support":
            if segments.count > 1, !segments[1].isEmpty {
                return .route(.supportThread(segments[1]))
            }
            if let thread = queryValue("thread", in: url), !thread.isEmpty {
                return .route(.supportThread(thread))
            }
            return .route(.supportChat)
        case "auth":
            guard segments.count > 1, segments[1].lowercased() == "reset-password",
                  let token = queryValue("token", in: url), !token.isEmpty else { return nil }
            return .passwordReset(token)
        default:
            return nil
        }
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
