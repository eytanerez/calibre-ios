import Foundation
import Observation

/// The member's Collection. Calibre purchases land here automatically on
/// delivery; manual adds cover watches bought elsewhere.
@MainActor
@Observable
public final class VaultStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var watches: [VaultWatch] = []

    public init(client: APIClient) {
        self.client = client
    }

    @discardableResult
    public func load() async throws -> [VaultWatch] {
        struct Response: Decodable { let results: [VaultWatch] }
        let response: Response = try await client.send(Endpoint(path: "/vault"))
        watches = response.results
        return response.results
    }

    /// `nickname` is what the owner calls the watch rather than what it is —
    /// optional, and skipped far more often than it is filled in. It becomes
    /// the vault's primary line where it exists, so the reference stays
    /// underneath rather than being replaced by it.
    @discardableResult
    public func add(
        brand: String,
        model: String? = nil,
        reference: String? = nil,
        productionYear: Int? = nil,
        acquiredPrice: String? = nil,
        nickname: String? = nil
    ) async throws -> VaultWatch {
        struct Payload: Encodable {
            let brand: String
            let model: String?
            let reference: String?
            let productionYear: Int?
            let acquiredPrice: String?
            let nickname: String?
        }
        let created: VaultWatch = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/vault",
                payload: Payload(
                    brand: brand,
                    model: model,
                    reference: reference,
                    productionYear: productionYear,
                    acquiredPrice: acquiredPrice,
                    nickname: nickname
                )
            )
        )
        watches.insert(created, at: 0)
        return created
    }

    /// The owner's own watches at this reference that are free to be listed —
    /// what the sell flow asks "is this that watch?" about.
    ///
    /// The server scopes this to the caller's collection and drops anything
    /// another of their listings already claims, so an empty list is the
    /// normal "nothing to ask about" answer. A blank reference is one too: the
    /// sell form asks before it knows.
    ///
    /// Never cached into `watches` — this is a question about one reference,
    /// not the collection, and the payload deliberately carries less than a
    /// collection row does.
    public func matches(reference: String) async throws -> [VaultMatch] {
        struct Response: Decodable { let results: [VaultMatch] }
        let response: Response = try await client.send(
            Endpoint(path: "/vault/matches", query: [URLQueryItem(name: "reference", value: reference)])
        )
        return response.results
    }

    /// The public Passport for one watch. Anonymized on the server and
    /// readable without a session — this is the record an owner sends to a
    /// buyer, and the buyer has no account yet.
    public func passport(code: String) async throws -> WatchPassport {
        try await client.send(Endpoint(path: "/passports/\(code)", requiresAuth: false))
    }

    public func remove(id: String) async throws {
        struct Response: Decodable { let deleted: Bool }
        let _: Response = try await client.send(Endpoint(method: .delete, path: "/vault/\(id)"))
        watches.removeAll { $0.id == id }
    }

    /// The detail route's payload: the watch, its service history, the
    /// catalog row behind it, and whether a suggestion is already in review.
    /// Deliberately not cached in `watches` — the list rows carry none of it.
    public func detail(id: String) async throws -> VaultWatchDetail {
        try await client.send(Endpoint(path: "/vault/\(id)"))
    }

    /// "We don't have this watch yet" — the owner's account of their own
    /// watch, sent for review. A blank brand or reference falls back to the
    /// watch's own on the server, so an owner who only wants to add specs
    /// doesn't have to retype what they already told us.
    ///
    /// Refusals come back as `APIError.server` carrying the server's own
    /// sentence (already told us / already in the catalog / a diameter is
    /// between 10 and 100 millimetres) — show that, don't write a second one.
    @discardableResult
    public func submitReferenceSuggestion(
        id: String,
        brand: String?,
        model: String?,
        reference: String?,
        productionYear: Int?,
        notes: String?,
        specs: WatchReferenceSpecsDraft
    ) async throws -> ReferenceSuggestion {
        // Bare spec keys at the top level, alongside the identity fields —
        // the shape the server's shared spec parser reads.
        struct Payload: Encodable {
            let brand: String?
            let model: String?
            let reference: String?
            let productionYear: Int?
            let notes: String?
            let material: String?
            let bezel: String?
            let glass: String?
            let back: String?
            let shape: String?
            let diameterMm: String?
            let finish: String?
            let dial: String?
            let indexes: String?
            let hands: String?
        }
        func filled(_ value: String) -> String? {
            InputValidation.isNonBlank(value) ? InputValidation.trimmed(value) : nil
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/vault/\(id)/reference-suggestion",
                payload: Payload(
                    brand: brand.flatMap(filled),
                    model: model.flatMap(filled),
                    reference: reference.flatMap(filled),
                    productionYear: productionYear,
                    notes: notes.flatMap(filled),
                    material: filled(specs.material),
                    bezel: filled(specs.bezel),
                    glass: filled(specs.glass),
                    back: filled(specs.back),
                    shape: filled(specs.shape),
                    diameterMm: filled(specs.diameterMm),
                    finish: filled(specs.finish),
                    dial: filled(specs.dial),
                    indexes: filled(specs.indexes),
                    hands: filled(specs.hands)
                )
            )
        )
    }

    public func reset() {
        watches = []
    }

    /// Sum of cached estimates, for the header tile.
    public var estimatedTotal: Double {
        watches.reduce(0) { total, watch in
            total + (Double(watch.estimatedValue ?? "") ?? 0)
        }
    }
}
