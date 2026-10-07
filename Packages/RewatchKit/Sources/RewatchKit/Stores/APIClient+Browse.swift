import Foundation

// Browse-track additions: typed wrappers for endpoints the stores don't
// cover yet. New file per the no-collision rules — existing kit files are
// read-only to feature tracks.
extension APIClient {
    /// `GET /account/profile` — the signed-in user's full profile. The home
    /// greeting wants a first name; `CurrentUser` only carries a username.
    public func accountProfile() async throws -> Profile {
        try await send(Endpoint(path: "/account/profile"))
    }

    /// `GET /listings/{id}/offers` — the caller's offers on one listing.
    /// Drives the PDP's "Offer pending — view" state.
    public func offers(onListing listingID: String) async throws -> [Offer] {
        try await send(Endpoint(path: "/listings/\(listingID)/offers"))
    }
}
