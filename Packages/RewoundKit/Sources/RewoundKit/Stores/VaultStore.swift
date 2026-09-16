import Foundation
import Observation

/// One field of a PATCH: set to something, or emptied.
///
/// A nil `VaultFieldEdit?` is the third case and the default one — the key is
/// never written, and the server leaves the column alone.
public enum VaultFieldEdit: Encodable, Equatable, Sendable {
    case set(String)
    case clear

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .set(let value): try container.encode(value)
        case .clear: try container.encodeNil()
        }
    }

    /// What a text box holds, as an edit: typing something sets it, clearing
    /// it out empties it. Whitespace alone is an empty box.
    public static func text(_ raw: String) -> VaultFieldEdit {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .clear : .set(trimmed)
    }
}

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

    /// An edit to one watch the caller owns — `PATCH /vault/{id}`.
    ///
    /// The server reads an ABSENT key as "leave this alone" and a null as
    /// "clear it", and Swift's synthesised encoding writes a nil optional as an
    /// absent key. So a field that has to be cleared cannot be expressed as
    /// `nil`, and `VaultFieldEdit` is what draws the two apart: `nil` means the
    /// caller is not touching the field, `.clear` means they are emptying it.
    ///
    /// Identity fields are deliberately not here. Editing one makes the server
    /// discard the stored estimate and re-match the catalog row, which is a
    /// different act from renaming a watch or writing a note about it.
    ///
    /// `photo_url` is deliberately not here either, and its absence is load
    /// bearing. The column still exists and the server still accepts a write
    /// to it, but this app no longer has a link form to write one from
    /// (contracts §9d) — and a PATCH that named the column while meaning
    /// nothing by it would wipe the seller's photograph of a watch that
    /// arrived from a Calibre order, leaving the card with no cover at all the
    /// moment the owner deletes their own uploads. Never sending the key is
    /// what keeps that from being one careless argument away.
    @discardableResult
    public func update(
        id: String,
        notes: VaultFieldEdit? = nil,
        nickname: VaultFieldEdit? = nil
    ) async throws -> VaultWatch {
        struct Payload: Encodable {
            let notes: VaultFieldEdit?
            let nickname: VaultFieldEdit?
        }
        let updated: VaultWatch = try await client.send(
            try Endpoint.json(
                method: .patch,
                path: "/vault/\(id)",
                payload: Payload(notes: notes, nickname: nickname)
            )
        )
        if let index = watches.firstIndex(where: { $0.id == id }) {
            watches[index] = updated
        }
        return updated
    }

    // MARK: - The owner's own photographs

    /// The gallery as the server holds it — `GET /vault/{id}/photos`.
    ///
    /// Every verb below answers with the same shape and every one of them
    /// folds the answer back into the cached row, so the collection card
    /// behind the sheet redraws on the cover the write just settled instead of
    /// waiting for the next full load.
    @discardableResult
    public func photos(id: String) async throws -> VaultGallery {
        let gallery: VaultGallery = try await client.send(Endpoint(path: "/vault/\(id)/photos"))
        apply(gallery, to: id)
        return gallery
    }

    /// Adds one photograph. It lands last; the cover is whatever sorts first,
    /// so the first one uploaded to an empty gallery becomes the cover by
    /// arriving rather than by being named one.
    ///
    /// One file per request, because that is the shape of the route: a
    /// multi-file upload that fails partway is a state nobody can read.
    /// Refusals come back as `APIError.server` carrying the server's own
    /// sentence and a `details.code` — show the sentence, and switch on the
    /// code only where the app has something better to do than say it.
    @discardableResult
    public func addPhoto(
        id: String,
        data: Data,
        filename: String,
        contentType: String
    ) async throws -> VaultGalleryAddition {
        var form = MultipartForm()
        form.addFile("file", filename: filename, contentType: contentType, data: data)
        let added: VaultGalleryAddition = try await client.send(
            Endpoint(method: .post, path: "/vault/\(id)/photos", body: .multipart(form))
        )
        apply(added.gallery, to: id)
        return added
    }

    /// Removes one photograph for good — `DELETE`. There is no tombstone and
    /// no undo: contracts §9d, and the sheet asks first for that reason.
    @discardableResult
    public func deletePhoto(id: String, photoID: String) async throws -> VaultGallery {
        let gallery: VaultGallery = try await client.send(
            Endpoint(method: .delete, path: "/vault/\(id)/photos/\(photoID)")
        )
        apply(gallery, to: id)
        return gallery
    }

    /// Moves one photograph to a position, zero-based — the drag, and the only
    /// way to change the cover. There is deliberately no "make this the cover"
    /// verb: the cover is position zero, so making one the cover is moving it
    /// there.
    ///
    /// A position past the end is clamped by the server rather than refused,
    /// which is what a drag onto the end of a gallery another device just
    /// shortened means.
    @discardableResult
    public func movePhoto(id: String, photoID: String, to position: Int) async throws -> VaultGallery {
        struct Payload: Encodable { let position: Int }
        let gallery: VaultGallery = try await client.send(
            try Endpoint.json(
                method: .patch,
                path: "/vault/\(id)/photos/\(photoID)",
                payload: Payload(position: position)
            )
        )
        apply(gallery, to: id)
        return gallery
    }

    private func apply(_ gallery: VaultGallery, to id: String) {
        guard let index = watches.firstIndex(where: { $0.id == id }) else { return }
        watches[index] = watches[index].applying(gallery)
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

    // There is deliberately no total here.
    //
    // What was here summed `estimatedValue` with a `?? 0`, which cannot tell a
    // watch Calibre has refused to value from a watch it valued at nothing —
    // so a collection of five unvalued watches added up to $0 and a collection
    // where one refusal sat among four figures quietly under-reported itself.
    // `VaultEstimate` is the whole answer and only its `ok` state carries a
    // figure; no consumer surface prints one, and a column of numbers Calibre
    // withholds in most cases would add up to the one figure on the screen
    // that could not be true.
}
