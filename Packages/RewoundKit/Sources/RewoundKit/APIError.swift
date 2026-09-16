import Foundation

/// Every failure surface of the Calibre API, normalized. Server errors carry
/// the backend's human-readable message — show it; don't invent copy.
public enum APIError: Error, LocalizedError, Sendable {
    /// Backend returned `{ok: false}` — message is the server's plain-English error.
    case server(message: String, code: String?, status: Int, details: [String: String]?)
    /// 401 that survived a token refresh — session is gone.
    case sessionExpired
    /// 429 — surface a gentle "try again shortly".
    case rateLimited(retryAfter: TimeInterval?)
    case network(underlying: Error)
    case decoding(underlying: Error, path: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .server(let message, _, _, _): message
        case .sessionExpired: "Your session has expired. Please sign in again."
        case .rateLimited: "Too many requests — please try again in a moment."
        case .network: "Couldn't reach Calibre. Check your connection and try again."
        case .decoding: "Something went wrong reading the response."
        case .invalidResponse: "Something went wrong. Please try again."
        }
    }

    /// Machine-readable error code from the backend when present
    /// (e.g. "ssn_required", "seller_onboarding_blocked", "stripe_checkout_required").
    public var serverCode: String? {
        if case .server(_, let code, _, _) = self { return code }
        return nil
    }

    /// The HTTP status behind a server refusal, when there was one. A screen
    /// that needs to tell "this is gone" apart from "the network is down"
    /// cannot do it from the message — the messages read the same to a
    /// `catch`, and one of them has a "Try again" that can never work.
    public var httpStatus: Int? {
        if case .server(_, _, let status, _) = self { return status }
        return nil
    }
}

/// The refusal codes every buyer-action surface has to be able to tell apart.
/// They are the server's own strings — `OWN_LISTING_CODE` and
/// `UNAVAILABLE_LISTING_CODE` in Backend/app/api/views/account.py, and the same
/// `own_listing` the checkout gate and `POST /listings/<id>/offers` send.
public enum ListingRefusal {
    /// You are the seller. Item 1.6.
    public static let ownListing = "own_listing"
    /// Sold, archived, or held by somebody else. Item 18.6.
    public static let unavailable = "listing_unavailable"
}
