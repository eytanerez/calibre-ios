import Foundation
import XCTest
@testable import CalibreKit

/// The two halves of "is this the watch you already own?": the question the
/// sell flow asks the vault, and the seller's answer riding back on the
/// listing. Both are wire-level claims — a mistyped route or a dropped key
/// fails silently in the app (no prompt, or a link that never lands), so they
/// are checked against bytes rather than against the models.
///
/// The two fixtures are recordings of the real backend's own output against
/// the dev database, not payloads written by hand:
/// `vault-matches.json` is `VaultReferenceMatchView.get`'s envelope, and
/// `listing-vault-linked.json` is `_serialize_listing`'s seller-view payload
/// for a listing carrying a vault link.
final class VaultLinkTests: XCTestCase {
    // MARK: The question

    func testVaultMatchesFixtureDecodes() throws {
        struct Results: Decodable { let results: [VaultMatch] }
        let envelope = try apiDecoder().decode(Envelope<Results>.self, from: fixtureData("vault-matches"))
        XCTAssertTrue(envelope.ok)

        let match = try XCTUnwrap(envelope.data.results.first)
        XCTAssertEqual(envelope.data.results.count, 1)
        XCTAssertEqual(match.vaultWatchId, "943e858d-334e-555e-985c-13026a9a96f4")
        XCTAssertEqual(match.id, match.vaultWatchId, "the id a list is keyed on is the watch's own")
        XCTAssertEqual(match.brand, "Rolex")
        XCTAssertEqual(match.model, "Datejust 41")
        XCTAssertEqual(match.reference, "126300")
        XCTAssertEqual(match.acquiredDate, "2026-08-13")
        XCTAssertEqual(match.passportCode, "do3bgntrgzgphfml")
        XCTAssertEqual(match.displayTitle, "Rolex Datejust 41")
    }

    /// A watch the catalog only half-knows is still one the owner can
    /// recognise — the prompt falls back to the reference rather than to a
    /// blank line or an invented name.
    func testMatchWithoutBrandOrModelIsNamedByItsReference() throws {
        let payload = Data("""
        {"ok": true, "data": {"results": [
          {"vault_watch_id": "0f2c1f2e-0000-0000-0000-00000000abcd",
           "brand": null, "model": null, "reference": "126610LN",
           "acquired_date": null, "passport_code": null}
        ]}}
        """.utf8)
        struct Results: Decodable { let results: [VaultMatch] }
        let match = try XCTUnwrap(
            apiDecoder().decode(Envelope<Results>.self, from: payload).data.results.first
        )
        XCTAssertEqual(match.displayTitle, "126610LN")
        XCTAssertNil(match.acquiredDate, "an unknown acquisition day stays unknown")
    }

    @MainActor
    func testMatchLookupAsksTheVaultRouteForExactlyTheReferenceTyped() async throws {
        let seen = SeenRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Data("{\"ok\": true, \"data\": {\"results\": []}}".utf8))
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        // The seller's own typing, spaces and casing included: normalising it
        // is the server's job, and a client that "helpfully" cleaned it up
        // first would be a second, quietly different matcher.
        let matches = try await vault.matches(reference: " 126610 ln ")

        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(seen.method, "GET")
        XCTAssertEqual(seen.path, "/vault/matches")
        XCTAssertEqual(seen.queryItems["reference"], " 126610 ln ")
        XCTAssertEqual(seen.queryItems.count, 1, "there is no second parameter that could widen the scope")
    }

    /// The lookup is a question about the caller's own property, so it must
    /// never be attempted without a session attached.
    @MainActor
    func testMatchLookupIsAnAuthenticatedRequest() async throws {
        let seen = SeenRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Data("{\"ok\": true, \"data\": {\"results\": []}}".utf8))
        }
        let auth = StaticHeaderAuthStub(name: "Authorization", value: "Bearer token-1")
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: auth))

        _ = try await vault.matches(reference: "126610LN")

        XCTAssertEqual(seen.header("Authorization"), "Bearer token-1")
    }

    // MARK: The answer

    @MainActor
    func testCreateListingSendsTheSellersYesAsVaultWatchId() async throws {
        let seen = SeenRequest()
        let linkedListing = try fixtureData("listing-vault-linked")
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (201, linkedListing)
        }
        let seller = SellerStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        let created = try await seller.createListing(
            ListingDraftPayload(
                title: "Rolex Datejust 41 126300",
                vaultWatchId: "943e858d-334e-555e-985c-13026a9a96f4",
                status: .draft
            )
        )

        XCTAssertEqual(seen.method, "POST")
        XCTAssertEqual(seen.path, "/account/listings")
        XCTAssertEqual(seen.jsonBody["vault_watch_id"] as? String, "943e858d-334e-555e-985c-13026a9a96f4")
        // And the server's echo is what the wizard reads back to know the
        // question has already been answered for this listing.
        XCTAssertEqual(created.vaultWatchId, "943e858d-334e-555e-985c-13026a9a96f4")
    }

    /// A decline is the absence of the field, not a null: the server treats
    /// "not sent" as "nothing to write", and a payload that sent null on every
    /// save would be clearing a link the seller never made.
    @MainActor
    func testListingPayloadWithoutAnAnswerOmitsTheKeyEntirely() async throws {
        let seen = SeenRequest()
        let linkedListing = try fixtureData("listing-vault-linked")
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, linkedListing)
        }
        let seller = SellerStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        _ = try await seller.updateListing(
            id: "03034396-7c16-5739-8746-ec6c735060f9",
            ListingDraftPayload(title: "Rolex Datejust 41 126300", brand: "Rolex")
        )

        XCTAssertEqual(seen.method, "PATCH")
        XCTAssertEqual(seen.jsonBody["brand"] as? String, "Rolex")
        XCTAssertFalse(
            seen.jsonBody.keys.contains("vault_watch_id"),
            "a wizard that never got an answer must not write one"
        )
    }

    func testTheLinkComesBackOnTheSellersPayloadAndNotTheBuyersOne() throws {
        let sellersOwn = try apiDecoder().decode(
            Envelope<Listing>.self,
            from: fixtureData("listing-vault-linked")
        ).data
        XCTAssertEqual(sellersOwn.vaultWatchId, "943e858d-334e-555e-985c-13026a9a96f4")
        XCTAssertNotNil(sellersOwn.sellerSku, "the vault link rides the same seller-only flag as the SKU")

        // A recorded buyer-facing capture: the key is absent, and absent must
        // decode as "no link" rather than failing the whole payload.
        let buyerFacing = try apiDecoder().decode(
            Envelope<Listing>.self,
            from: fixtureData("listing-detail")
        ).data
        XCTAssertNil(buyerFacing.vaultWatchId)
        XCTAssertNil(buyerFacing.sellerSku)
    }
}

// MARK: - Test doubles

/// The one request the mock saw, readable from the test's actor. The handler
/// runs on URLSession's thread, so every field is lock-guarded.
private final class SeenRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var body: Data?

    func record(_ request: URLRequest) {
        // `httpBody` is nil by the time a request reaches a URLProtocol —
        // URLSession hands the body over as a stream — so it is drained here,
        // while the handler still has it.
        let drained = request.httpBody ?? request.httpBodyStream.map(drainHTTPBodyStream)
        lock.withLock {
            self.request = request
            self.body = drained
        }
    }

    var method: String? { lock.withLock { request?.httpMethod } }
    var path: String? { lock.withLock { request?.url?.path } }

    func header(_ name: String) -> String? {
        lock.withLock { request?.value(forHTTPHeaderField: name) }
    }

    /// Query parameters as the client actually sent them, percent-decoding
    /// undone by `URLComponents`.
    var queryItems: [String: String] {
        let url = lock.withLock { request?.url }
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        return (components.queryItems ?? []).reduce(into: [:]) { items, item in
            items[item.name] = item.value
        }
    }

    /// The request body as the JSON object the server would parse. Empty when
    /// there was no body, which reads the same as "no keys were sent" —
    /// deliberately, since every assertion here is about a specific key.
    var jsonBody: [String: Any] {
        let data = lock.withLock { body }
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }
}

/// An auth provider that only ever supplies a header — enough to prove a
/// request was made as the signed-in member.
private struct StaticHeaderAuthStub: AuthProviding {
    let name: String
    let value: String

    func authHeader() async -> (name: String, value: String)? { (name, value) }
    func refreshAfterUnauthorized() async -> Bool { false }
}
