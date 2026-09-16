import Foundation
import Observation

/// The Bites reader's two reads: one Bite by slug, and the archive.
///
/// There is no read of `GET /content/bites/today` here, and that is
/// deliberate: today's Bite arrives inside the Home feed's own `todays_bite`
/// module, already chosen and already carrying its slot. A second fetch of the
/// same answer could disagree with the one the reader is looking at.
///
/// Separate from `ContentStore` on purpose. The Journal is tens of articles and
/// caches as one whole collection; Bites accrue one a day, so the two cannot
/// share a cache shape — and nothing about the Journal changes because Bites
/// exist.
@MainActor
@Observable
public final class BitesStore {
    @ObservationIgnored private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// One published Bite. A Bite with no publication is a 404 — the same way
    /// a Journal draft is — and that surfaces as an ordinary server error.
    public func bite(slug: String) async throws -> Bite {
        try await client.send(Endpoint(path: "/content/bites/\(slug)", requiresAuth: false))
    }

    /// The archive, newest first. `before` pages backwards on the editorial
    /// date rather than on an offset, so a Bite published mid-read cannot
    /// shift the page under the reader.
    public func archive(before: String? = nil) async throws -> BiteArchivePage {
        try await client.send(
            Endpoint(
                path: "/content/bites",
                query: before.map { [URLQueryItem(name: "before", value: $0)] } ?? [],
                requiresAuth: false
            )
        )
    }
}
