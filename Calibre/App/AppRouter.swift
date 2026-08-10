import CalibreKit
import Foundation
import Observation
import SwiftUI

/// The five root tabs.
enum AppTab: Hashable {
    case home, community, sell, collection, you
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
    case supportChat
    case alerts
    case checkout(String, offerID: String?)
    /// A past poll's own page, carried by value — there's no fetch-by-id yet.
    case poll(CommunityPrompt)
}

/// A checkout the app is presenting as a full-screen cover. Checkout owns its
/// own navigation stack, so it rides above the tabs rather than pushing.
struct CheckoutRequest: Identifiable, Hashable {
    let listingID: String
    let offerID: String?
    var id: String { "\(listingID)|\(offerID ?? "")" }
}

/// Owns tab selection and one navigation path per tab. `open(_:)` selects the
/// tab a route belongs to and pushes it; `handle(url:)` decodes deep links.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    var homePath: [Route] = []
    var communityPath: [Route] = []
    var sellPath: [Route] = []
    var collectionPath: [Route] = []
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

    /// Send the seller to a fresh listing prefilled from one of their watches.
    func startListing(prefill: ListingPrefill) {
        pendingListingPrefill = prefill
        selectedTab = .sell
    }

    /// Presents checkout for a listing (optionally an accepted offer) as a
    /// full-screen cover above the tab shell.
    func presentCheckout(listingID: String, offerID: String? = nil) {
        checkoutRequest = CheckoutRequest(listingID: listingID, offerID: offerID)
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
        selectedTab = tab
        switch tab {
        case .home: homePath.append(route)
        case .community: communityPath.append(route)
        case .sell: sellPath.append(route)
        case .collection: collectionPath.append(route)
        case .you: youPath.append(route)  // NavigationPath.append accepts any Hashable
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
        case .listing, .seller, .brand, .checkout:
            .home
        case .journal, .journalArticle, .poll:
            .community
        case .order, .offer, .alerts, .supportChat:
            .you
        }
    }

    /// Handles calibre:// scheme links and https://buycalibre.com universal
    /// links. Returns true when the URL was recognized.
    @discardableResult
    func handle(url: URL) -> Bool {
        if url.scheme?.lowercased() == "calibre" {
            return handleCalibreScheme(url)
        }
        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
           let host = url.host()?.lowercased(),
           host == "buycalibre.com" || host == "www.buycalibre.com" {
            return handleUniversalLink(url)
        }
        return false
    }

    /// calibre://listing/<id>, calibre://order/<id>, calibre://offer/<id>,
    /// calibre://support, calibre://alerts, calibre://auth/reset?token=…
    /// (Google's calibre://auth?code= callback is consumed by the web-auth
    /// session, never here.)
    private func handleCalibreScheme(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let segments = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "listing":
            guard let id = segments.first else { return false }
            open(.listing(id))
        case "seller":
            guard let id = segments.first else { return false }
            open(.seller(id))
        case "brand":
            guard let id = segments.first else { return false }
            open(.brand(id))
        case "order":
            guard let id = segments.first else { return false }
            open(.order(id))
        case "offer":
            guard let id = segments.first else { return false }
            open(.offer(id))
        case "journal":
            if let id = segments.first {
                open(.journalArticle(id))
            } else {
                open(.journal)
            }
        case "support":
            open(.supportChat)
        case "alerts":
            open(.alerts)
        case "auth":
            guard segments.first == "reset",
                  let token = queryValue("token", in: url), !token.isEmpty else { return false }
            passwordResetToken = token
        default:
            return false
        }
        return true
    }

    /// https://buycalibre.com/listing/:id and friends — the web app's paths.
    private func handleUniversalLink(_ url: URL) -> Bool {
        let segments = url.pathComponents.filter { $0 != "/" }
        guard let first = segments.first?.lowercased() else { return false }

        switch first {
        case "listing", "listings":
            guard segments.count > 1 else { return false }
            open(.listing(segments[1]))
        case "seller", "sellers":
            guard segments.count > 1 else { return false }
            open(.seller(segments[1]))
        case "brand", "brands":
            guard segments.count > 1 else { return false }
            open(.brand(segments[1]))
        case "order", "orders":
            guard segments.count > 1 else { return false }
            open(.order(segments[1]))
        case "offer", "offers":
            guard segments.count > 1 else { return false }
            open(.offer(segments[1]))
        case "journal":
            if segments.count > 1 {
                open(.journalArticle(segments[1]))
            } else {
                open(.journal)
            }
        case "support":
            open(.supportChat)
        case "auth":
            guard segments.count > 1, segments[1].lowercased() == "reset-password",
                  let token = queryValue("token", in: url), !token.isEmpty else { return false }
            passwordResetToken = token
        default:
            return false
        }
        return true
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
