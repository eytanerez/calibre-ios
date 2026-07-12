import Foundation
import Observation
import SwiftUI

/// The five root tabs.
enum AppTab: Hashable {
    case home, discover, sell, activity, you
}

/// Everything the app can navigate to from anywhere — pushes, push
/// notifications, and calibre:// / universal links all funnel through here.
enum Route: Hashable {
    case listing(String)
    case seller(String)
    case brand(String)
    case order(String)
    case offer(String)
    case journalArticle(String)
    case supportChat
    case alerts
    case checkout(String, offerID: String?)
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
    var discoverPath: [Route] = []
    var sellPath: [Route] = []
    var activityPath: [Route] = []
    /// Type-erased: the You tab pushes both `Route` (support, from deep links)
    /// and `ProfileDestination` (profile/addresses/…), so a homogeneous
    /// `[Route]` would silently drop the profile pushes and desync the stack.
    var youPath = NavigationPath()

    /// Set when a calibre://auth/reset?token= link arrives; the root view
    /// presents the reset-password screen.
    var passwordResetToken: String?

    /// The checkout cover currently presented, if any.
    var checkoutRequest: CheckoutRequest?

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
        let tab = homeTab(for: route)
        selectedTab = tab
        switch tab {
        case .home: homePath.append(route)
        case .discover: discoverPath.append(route)
        case .sell: sellPath.append(route)
        case .activity: activityPath.append(route)
        case .you: youPath.append(route)  // NavigationPath.append accepts any Hashable
        }
    }

    /// Which tab a route naturally lives in.
    private func homeTab(for route: Route) -> AppTab {
        switch route {
        case .listing, .seller, .brand, .journalArticle, .checkout:
            .home
        case .order, .offer, .alerts:
            .activity
        case .supportChat:
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
            guard let id = segments.first else { return false }
            open(.journalArticle(id))
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
            guard segments.count > 1 else { return false }
            open(.journalArticle(segments[1]))
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
