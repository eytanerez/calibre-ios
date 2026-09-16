import Foundation
import XCTest
@testable import RewoundKit

/// The owner's own photographs of a watch in their Vault: what the four verbs
/// put on the wire, what comes back, which picture leads, and — the one that
/// is silent when it is wrong — which addresses the app's bearer token is
/// allowed to travel to.
final class VaultGalleryTests: XCTestCase {

    // MARK: - What the four verbs put on the wire

    @MainActor
    func testListingTheGalleryAsksTheWatchsOwnCollection() async throws {
        let seen = SeenPhotoRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Self.twoPhotographs)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        let gallery = try await vault.photos(id: "v1")

        XCTAssertEqual(seen.method, "GET")
        XCTAssertEqual(seen.path, "/vault/v1/photos")
        XCTAssertEqual(gallery.results.map(\.id), ["p1", "p2"])
        XCTAssertEqual(gallery.results.map(\.position), [0, 1])
    }

    /// The route reads exactly one part, named `file`, and nothing else. A
    /// second part naming a slot or a position would be silently ignored by
    /// the server, so a client that sent one would be arranging a gallery it
    /// only believed it had arranged.
    @MainActor
    func testAddingAPhotographSendsOneFilePartAndNothingElse() async throws {
        let seen = SeenPhotoRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (201, Self.additionOfOne)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        let added = try await vault.addPhoto(
            id: "v1",
            data: Data("not really a jpeg".utf8),
            filename: "photo.heic",
            contentType: "image/heic"
        )

        XCTAssertEqual(seen.method, "POST")
        XCTAssertEqual(seen.path, "/vault/v1/photos")
        XCTAssertTrue(seen.contentType?.hasPrefix("multipart/form-data; boundary=") ?? false)
        XCTAssertEqual(seen.partNames, ["file"])
        XCTAssertTrue(seen.body.contains("filename=\"photo.heic\""))
        // Explicit, because an iOS HEIC part sent as application/octet-stream
        // is refused by the shared upload rules.
        XCTAssertTrue(seen.body.contains("Content-Type: image/heic"))
        XCTAssertEqual(added.photo.id, "p1")
    }

    @MainActor
    func testDeletingNamesThePhotographAndSendsNoBody() async throws {
        let seen = SeenPhotoRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Self.emptyGallery)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        let gallery = try await vault.deletePhoto(id: "v1", photoID: "p2")

        XCTAssertEqual(seen.method, "DELETE")
        XCTAssertEqual(seen.path, "/vault/v1/photos/p2")
        XCTAssertEqual(seen.body, "")
        XCTAssertTrue(gallery.results.isEmpty)
    }

    /// A move is a position, zero-based, and it is the only way to change the
    /// cover — there is no "make this the cover" verb to send instead.
    @MainActor
    func testMovingSendsTheZeroBasedPosition() async throws {
        let seen = SeenPhotoRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Self.twoPhotographs)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        _ = try await vault.movePhoto(id: "v1", photoID: "p2", to: 0)

        XCTAssertEqual(seen.method, "PATCH")
        XCTAssertEqual(seen.path, "/vault/v1/photos/p2")
        XCTAssertEqual(seen.json["position"] as? Int, 0)
    }

    // MARK: - What the answer does to the row behind the sheet

    /// All four verbs answer with the gallery AND the cover precisely so the
    /// card behind the sheet does not have to re-fetch the watch to find out
    /// that the picture on it has changed.
    @MainActor
    func testAGalleryVerbRedrawsTheCachedWatch() async throws {
        MockURLProtocol.setHandler { request in
            request.url?.path.hasSuffix("/photos") == true
                ? (200, Self.twoPhotographs)
                : (200, Self.listWithOneLinkedWatch)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        try await vault.load()
        XCTAssertEqual(
            vault.watches.first?.coverUrl?.url?.absoluteString,
            "https://seller.example/tudor.jpg",
            "until the owner has photographed it, the link the watch arrived with is the cover"
        )
        XCTAssertTrue(vault.watches.first?.gallery.isEmpty ?? false)

        _ = try await vault.photos(id: "v1")

        XCTAssertEqual(vault.watches.count, 1, "a gallery read is not an insert")
        XCTAssertEqual(vault.watches.first?.gallery.map(\.id), ["p1", "p2"])
        XCTAssertEqual(
            vault.watches.first?.coverUrl?.url?.absoluteString,
            "https://mock.rewound.test/secure-media/vault_photos/v1/one.jpg"
        )
        XCTAssertEqual(
            vault.watches.first?.photoUrl,
            "https://seller.example/tudor.jpg",
            "the link column is not destroyed and not migrated \u{2014} it is still on the row"
        )
    }

    /// A payload served by a deployment that predates the gallery carries no
    /// key at all, and absent is not the same claim as empty.
    func testAWatchWithNoGalleryKeyIsNotAWatchWithNoPhotographs() throws {
        let row = try apiDecoder(origin: "https://mock.rewound.test")
            .decode(VaultWatch.self, from: Self.rowWithoutAGalleryKey)
        XCTAssertNil(row.photos)
        XCTAssertTrue(row.gallery.isEmpty, "a grid has nothing to lay out either way")
    }

    // MARK: - Which address may carry the credential

    /// An object under the permission-checked prefix is fetched with the
    /// member's session; everything else is fetched without it. Getting this
    /// backwards is silent in both directions: the owner's photograph never
    /// appears, or the app's bearer token goes somewhere it was not needed.
    func testOnlyThePermissionCheckedPrefixIsPrivate() {
        let origin = URL(string: "https://mock.rewound.test")!
        XCTAssertEqual(
            VaultCoverSource.resolve(
                URL(string: "https://mock.rewound.test/secure-media/vault_photos/v1/one.jpg"),
                apiOrigin: origin
            ),
            .privateMedia(URL(string: "https://mock.rewound.test/secure-media/vault_photos/v1/one.jpg")!)
        )
        // Rewound's own host, but public media — a seeded demo watch, a
        // listing's own photographs. Nothing guards these, so nothing sends a
        // credential to them and they go through the ordinary image pipeline.
        XCTAssertEqual(
            VaultCoverSource.resolve(
                URL(string: "https://mock.rewound.test/media/demo-watches/tudor.jpg"),
                apiOrigin: origin
            ),
            .link(URL(string: "https://mock.rewound.test/media/demo-watches/tudor.jpg")!)
        )
        XCTAssertEqual(
            VaultCoverSource.resolve(URL(string: "https://seller.example/tudor.jpg"), apiOrigin: origin),
            .link(URL(string: "https://seller.example/tudor.jpg")!)
        )
        // A different port on the same host is a different origin, so the
        // prefix alone does not make it Rewound's.
        XCTAssertEqual(
            VaultCoverSource.resolve(
                URL(string: "https://mock.rewound.test:8443/secure-media/vault_photos/v1/one.jpg"),
                apiOrigin: origin
            ),
            .link(URL(string: "https://mock.rewound.test:8443/secure-media/vault_photos/v1/one.jpg")!)
        )
        // Neither of these is a photograph the app will load.
        XCTAssertNil(VaultCoverSource.resolve(URL(string: "http://seller.example/tudor.jpg"), apiOrigin: origin))
        XCTAssertNil(VaultCoverSource.resolve(URL(string: "mine.jpg"), apiOrigin: origin))
        XCTAssertNil(VaultCoverSource.resolve(nil, apiOrigin: origin))
    }

    /// The dev box is plain http, and its `/media/` covers are on the very
    /// origin the app already talks to. Requiring https of them would have
    /// resolved every seeded watch to nothing and drawn a placeholder over a
    /// picture that loads perfectly.
    func testRewoundsOwnPublicMediaLoadsOverTheOriginsOwnScheme() {
        let origin = URL(string: "http://localhost:8010")!
        XCTAssertEqual(
            VaultCoverSource.resolve(
                URL(string: "http://localhost:8010/media/demo-watches/grand-seiko.jpg"),
                apiOrigin: origin
            ),
            .link(URL(string: "http://localhost:8010/media/demo-watches/grand-seiko.jpg")!)
        )
        XCTAssertEqual(
            VaultCoverSource.resolve(
                URL(string: "http://localhost:8010/secure-media/vault_photos/v1/one.jpg"),
                apiOrigin: origin
            ),
            .privateMedia(URL(string: "http://localhost:8010/secure-media/vault_photos/v1/one.jpg")!)
        )
    }

    /// The refusal is enforced again at the moment a request would actually be
    /// built, because that is the only place it can be: a URL that reached the
    /// loader by any other route still does not get the token.
    func testTheLoaderRefusesToCarryTheTokenOffRewound() async {
        let attempted = Attempted()
        MockURLProtocol.setHandler { request in
            attempted.record(request)
            return (200, Data("bytes".utf8))
        }
        let loader = PrivateMediaLoader(configuration: mockConfiguration(), auth: SingleFlightAuthStub())

        do {
            _ = try await loader.data(for: URL(string: "https://seller.example/tudor.jpg")!)
            XCTFail("an off-origin address must not be fetched with the member's credential")
        } catch {
            XCTAssertEqual(attempted.count, 0, "and it must not be fetched at all")
        }
    }

    func testTheLoaderCarriesTheTokenToRewoundsOwnOrigin() async throws {
        let attempted = Attempted()
        MockURLProtocol.setHandler { request in
            attempted.record(request)
            return (200, Data("bytes".utf8))
        }
        let loader = PrivateMediaLoader(configuration: mockConfiguration(), auth: SingleFlightAuthStub())

        let bytes = try await loader.data(
            for: URL(string: "https://mock.rewound.test/secure-media/vault_photos/v1/one.jpg")!
        )

        XCTAssertEqual(bytes, Data("bytes".utf8))
        XCTAssertEqual(attempted.authorization, "Bearer stale")
    }

    /// The same contract `APIClient` honors. Without it a gallery empties
    /// itself the first morning after an access token ages out, and the owner
    /// is shown a watch with no picture on it rather than a signed-in app.
    func testAnExpiredTokenRefreshesOnceAndTheFetchIsRetried() async throws {
        let attempted = Attempted()
        MockURLProtocol.setHandler { request in
            attempted.record(request)
            let header = request.value(forHTTPHeaderField: "Authorization")
            return header == "Bearer fresh" ? (200, Data("bytes".utf8)) : (401, Data())
        }
        let auth = SingleFlightAuthStub()
        let loader = PrivateMediaLoader(configuration: mockConfiguration(), auth: auth)

        let bytes = try await loader.data(
            for: URL(string: "https://mock.rewound.test/secure-media/vault_photos/v1/one.jpg")!
        )

        XCTAssertEqual(bytes, Data("bytes".utf8))
        XCTAssertEqual(attempted.count, 2)
        let refreshes = await auth.state.refreshCount
        XCTAssertEqual(refreshes, 1)
    }

    /// A 404 is the answer for a photograph that is not the caller's, and it
    /// is not retried as if it were an expired session.
    func testAPhotographThatIsNotYoursIsNotRetried() async {
        let attempted = Attempted()
        MockURLProtocol.setHandler { request in
            attempted.record(request)
            return (404, Data())
        }
        let loader = PrivateMediaLoader(configuration: mockConfiguration(), auth: SingleFlightAuthStub())

        do {
            _ = try await loader.data(
                for: URL(string: "https://mock.rewound.test/secure-media/vault_photos/v1/one.jpg")!
            )
            XCTFail("a 404 is a refusal, not a picture")
        } catch {
            XCTAssertEqual((error as? APIError)?.httpStatus, 404)
            XCTAssertEqual(attempted.count, 1)
        }
    }

    /// The same photograph drawn in two places is one fetch, and a session
    /// that ends takes the bytes with it.
    func testBytesAreHeldForTheSessionAndDroppedWithIt() async throws {
        let attempted = Attempted()
        MockURLProtocol.setHandler { request in
            attempted.record(request)
            return (200, Data("bytes".utf8))
        }
        let loader = PrivateMediaLoader(configuration: mockConfiguration(), auth: SingleFlightAuthStub())
        let url = URL(string: "https://mock.rewound.test/secure-media/vault_photos/v1/one.jpg")!

        _ = try await loader.data(for: url)
        _ = try await loader.data(for: url)
        XCTAssertEqual(attempted.count, 1)

        await loader.clear()
        _ = try await loader.data(for: url)
        XCTAssertEqual(attempted.count, 2, "nothing of the last account's is still held")
    }

    // MARK: - Payloads

    /// Two photographs, in gallery order, with the cover the first of them.
    private static let twoPhotographs = Data("""
    {"ok": true, "data": {
      "results": [
        {"id": "p1", "url": "/secure-media/vault_photos/v1/one.jpg",
         "content_type": "image/jpeg", "size_bytes": 12, "width": 1200, "height": 800,
         "position": 0, "created_at": null},
        {"id": "p2", "url": "/secure-media/vault_photos/v1/two.jpg",
         "content_type": "image/jpeg", "size_bytes": 12, "width": 1200, "height": 800,
         "position": 1, "created_at": null}
      ],
      "cover_url": "/secure-media/vault_photos/v1/one.jpg"}}
    """.utf8)

    private static let additionOfOne = Data("""
    {"ok": true, "data": {
      "results": [
        {"id": "p1", "url": "/secure-media/vault_photos/v1/one.jpg",
         "content_type": "image/jpeg", "size_bytes": 12, "width": 1200, "height": 800,
         "position": 0, "created_at": null}
      ],
      "cover_url": "/secure-media/vault_photos/v1/one.jpg",
      "photo": {"id": "p1", "url": "/secure-media/vault_photos/v1/one.jpg",
        "content_type": "image/jpeg", "size_bytes": 12, "width": 1200, "height": 800,
        "position": 0, "created_at": null}}}
    """.utf8)

    /// The last photograph gone, and the link the watch arrived with taking
    /// the cover back.
    private static let emptyGallery = Data("""
    {"ok": true, "data": {"results": [], "cover_url": "https://seller.example/tudor.jpg"}}
    """.utf8)

    /// A watch that came from a Rewound order: the seller's photograph is on
    /// the row as a link, and the owner has not photographed it themselves.
    private static let listWithOneLinkedWatch = Data("""
    {"ok": true, "data": {"results": [
      {"id": "v1", "source": "rewound_order", "authenticated": true,
       "order_id": null, "listing_id": null, "passport_code": null,
       "brand": "Tudor", "model": "Black Bay", "reference": "79030N",
       "production_year": null, "nickname": null, "notes": null,
       "photo_url": "https://seller.example/tudor.jpg",
       "cover_url": "https://seller.example/tudor.jpg", "photos": [],
       "acquired_price": null, "acquired_date": null,
       "estimated_value": null, "estimated_at": null, "created_at": null}]}}
    """.utf8)

    private static let rowWithoutAGalleryKey = Data("""
    {"id": "v1", "source": "manual", "authenticated": false, "order_id": null,
     "listing_id": null, "passport_code": null, "brand": "Tudor", "model": "Black Bay",
     "reference": "79030N", "production_year": null, "nickname": null, "notes": null,
     "photo_url": null, "acquired_price": null, "acquired_date": null,
     "estimated_value": null, "estimated_at": null, "created_at": null}
    """.utf8)
}

/// The one request the mock saw, readable from the test's actor.
private final class SeenPhotoRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var payload: Data?

    func record(_ request: URLRequest) {
        let drained = request.httpBody ?? request.httpBodyStream.map(drainHTTPBodyStream)
        lock.withLock {
            self.request = request
            self.payload = drained
        }
    }

    var method: String? { lock.withLock { request?.httpMethod } }
    var path: String? { lock.withLock { request?.url?.path } }
    var contentType: String? {
        lock.withLock { request?.value(forHTTPHeaderField: "Content-Type") }
    }

    var body: String {
        let data = lock.withLock { payload }
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var json: [String: Any] {
        let data = lock.withLock { payload }
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    /// Every `name="…"` in a multipart body, in the order the parts were
    /// written. What this is really asking is whether anything besides the
    /// file went along.
    var partNames: [String] {
        body.split(separator: "\r\n").compactMap { line in
            guard line.hasPrefix("Content-Disposition: form-data;"),
                  let range = line.range(of: "name=\"") else { return nil }
            let rest = line[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
    }
}

/// What the loader actually put on the network.
private final class Attempted: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    var count: Int { lock.withLock { requests.count } }
    var authorization: String? {
        lock.withLock { requests.last?.value(forHTTPHeaderField: "Authorization") }
    }
}
