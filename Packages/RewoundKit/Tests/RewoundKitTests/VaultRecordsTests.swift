import Foundation
import XCTest
@testable import RewoundKit

/// The vault's two quiet contracts: what Rewound will say about a watch's
/// worth, and what the owner's own edits put on the wire.
///
/// Both are places where a wrong answer is silent. An estimate state folded
/// into a neighbouring one puts a sentence about evidence under somebody's
/// watch that Rewound never said; a PATCH that writes an absent key where it
/// meant a null leaves a note on a row the owner just cleared, and one that
/// names a key it means nothing by wipes a column nobody asked it to touch.
final class VaultRecordsTests: XCTestCase {

    // MARK: - What Rewound will say about a figure

    private func watch(estimate: String?) throws -> VaultWatch {
        let block = estimate.map { ", \"estimate\": \($0)" } ?? ""
        let json = """
        {"id": "v1", "source": "manual", "authenticated": false, "order_id": null,
         "listing_id": null, "passport_code": null, "brand": "Tudor", "model": "Black Bay",
         "reference": "79030N", "production_year": null, "nickname": null, "notes": null,
         "photo_url": null, "acquired_price": null, "acquired_date": null,
         "estimated_value": null, "estimated_at": null, "created_at": null\(block)}
        """
        return try apiDecoder().decode(VaultWatch.self, from: Data(json.utf8))
    }

    private func estimate(_ state: String, value: String = "null") -> String {
        """
        {"state": "\(state)", "value": \(value), "as_of": null, "scope": null,
         "basis": null, "sample_size": null, "window_days": null}
        """
    }

    /// A row built to vary the three fields the stamp could be mis-keyed to:
    /// the server's own flag, the `source` it is computed from, and whether a
    /// Passport exists.
    private func stampable(
        id: String = "v1",
        authenticated: Bool,
        source: String = "rewound_order",
        passportCode: String? = nil
    ) throws -> VaultWatch {
        let code = passportCode.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"id": "\(id)", "source": "\(source)", "authenticated": \(authenticated),
         "order_id": null, "listing_id": null, "passport_code": \(code),
         "brand": "Tudor", "model": "Black Bay", "reference": "79030N",
         "production_year": null, "nickname": null, "notes": null,
         "photo_url": null, "acquired_price": null, "acquired_date": null,
         "estimated_value": null, "estimated_at": null, "created_at": null}
        """
        return try apiDecoder().decode(VaultWatch.self, from: Data(json.utf8))
    }

    // MARK: - The stamp on the vault detail

    /// The mark asserts that Rewound stands behind this watch, so it is gated
    /// on the server's own answer to that and on nothing that merely tends to
    /// travel with it.
    func testTheStampFollowsTheServersFlag() throws {
        XCTAssertNotNil(try stampable(authenticated: true).authenticationMarkKey)
        XCTAssertNil(
            try stampable(authenticated: false, source: "manual").authenticationMarkKey,
            "a watch somebody typed in is a watch nobody at Rewound has held"
        )
    }

    /// The two near-misses, written out because either would pass a reading of
    /// the screen and stamp the wrong watch.
    ///
    /// `source` is what the server computes the flag FROM, not the flag: a
    /// second copy of that rule here is how the badge comes to mean one thing
    /// on the web and another on the phone. And a Passport is a document that
    /// may or may not have been minted — a delivered order without one is a
    /// gap in our records, not a watch nobody checked — so gating on the code
    /// would quietly withdraw a true claim.
    func testTheStampIsNotKeyedToSourceOrToAPassport() throws {
        XCTAssertNil(
            try stampable(authenticated: false, source: "rewound_order").authenticationMarkKey,
            "the flag is the server's, never re-derived from `source` here"
        )
        XCTAssertNil(
            try stampable(authenticated: false, source: "manual", passportCode: "CAL-1").authenticationMarkKey,
            "a passport code is not a verdict"
        )
        XCTAssertNotNil(
            try stampable(authenticated: true, passportCode: nil).authenticationMarkKey,
            "a missing passport row does not withdraw a claim the server made"
        )
    }

    /// The key names the fact, not the surface — so a watch already stamped in
    /// this session stands still when the screen is opened a second time, and
    /// two watches never share one announcement.
    func testTheStampKeyIsPerWatchAndStable() throws {
        let first = try XCTUnwrap(try stampable(id: "v1", authenticated: true).authenticationMarkKey)
        let again = try XCTUnwrap(try stampable(id: "v1", authenticated: true).authenticationMarkKey)
        let other = try XCTUnwrap(try stampable(id: "v2", authenticated: true).authenticationMarkKey)

        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, other)
    }

    /// The two refusals are different findings and must never collapse into
    /// one line: not knowing WHICH watch this is, and having looked at the
    /// right watch and found too little. The second one means the reference
    /// is understood.
    ///
    /// `insufficient_evidence` is asserted whole rather than by a phrase in
    /// it. The wording is settled and shared with the web
    /// (`frontend/src/lib/vaultApi.ts`), so drift is the failure this is
    /// watching for — and a substring check would pass through a rewrite that
    /// kept three words and changed what the sentence says.
    func testTheTwoRefusalsSayDifferentThings() throws {
        let unidentified = try XCTUnwrap(watch(estimate: estimate("unidentified")).estimate?.note)
        let insufficient = try XCTUnwrap(watch(estimate: estimate("insufficient_evidence")).estimate?.note)

        XCTAssertNotEqual(unidentified, insufficient)
        XCTAssertTrue(unidentified.contains("could not tell which watch this is"))
        XCTAssertEqual(insufficient, "We know this reference, but too few have sold to show a price yet.")
    }

    /// The concession is the difference. `insufficient_evidence` grants the
    /// reference before it withholds the figure; `unidentified` cannot, and
    /// must not read as though it does.
    func testOnlyTheUnderTradedRefusalGrantsTheReference() throws {
        let unidentified = try XCTUnwrap(watch(estimate: estimate("unidentified")).estimate?.note)
        let insufficient = try XCTUnwrap(watch(estimate: estimate("insufficient_evidence")).estimate?.note)

        XCTAssertTrue(insufficient.lowercased().contains("know this reference"))
        XCTAssertFalse(unidentified.lowercased().contains("know this reference"))
    }

    /// A figure is never printed, so the states that have one have no absence
    /// to explain — and a state nobody has looked up has nothing to explain
    /// either.
    func testTheStatesThatCarryAFigureSayNothing() throws {
        XCTAssertNil(try watch(estimate: estimate("ok", value: "\"9500.00\"")).estimate?.note)
        XCTAssertNil(try watch(estimate: estimate("stale")).estimate?.note)
        XCTAssertNil(try watch(estimate: estimate("not_estimated")).estimate?.note)
    }

    /// A state this build has never heard of must arrive as itself rather than
    /// throwing the collection away or being read as one of the five — and it
    /// says nothing, because this build cannot know what it would be saying.
    func testAnUnrecognisedStateDecodesAndStaysQuiet() throws {
        let row = try watch(estimate: estimate("under_review"))
        XCTAssertEqual(row.estimate?.state, "under_review")
        XCTAssertNil(row.estimate?.kind)
        XCTAssertNil(row.estimate?.note)
    }

    /// A payload served by a deployment that predates the estimate block
    /// carries no key at all. Inventing a state for it would put a sentence
    /// about evidence under a watch nobody looked up.
    func testAWatchWithNoEstimateBlockSaysNothing() throws {
        let row = try watch(estimate: nil)
        XCTAssertNil(row.estimate)
        XCTAssertNil(row.estimate?.note)
    }

    /// `ok` is the only state that carries a figure. This is the property that
    /// stopped `estimatedTotal` being rewritable: a refusal has no number, so
    /// nothing can sum one as a zero.
    func testOnlyOkCarriesAFigure() throws {
        XCTAssertEqual(try watch(estimate: estimate("ok", value: "\"9500.00\"")).estimate?.value, "9500.00")
        XCTAssertNil(try watch(estimate: estimate("insufficient_evidence")).estimate?.value)
        XCTAssertNil(try watch(estimate: estimate("unidentified")).estimate?.value)
        XCTAssertNil(try watch(estimate: estimate("stale")).estimate?.value)
    }

    // MARK: - What an edit puts on the wire

    @MainActor
    func testClearingAFieldWritesANullAndLeavesTheOthersAlone() async throws {
        let seen = SeenVaultRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Self.updatedRow)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        _ = try await vault.update(id: "v1", notes: .clear)

        XCTAssertEqual(seen.method, "PATCH")
        XCTAssertEqual(seen.path, "/vault/v1")
        // The server reads an absent key as "leave it alone", so a removal has
        // to arrive as a null that was actually written.
        XCTAssertTrue(seen.body.contains("notes"))
        XCTAssertTrue(seen.json["notes"] is NSNull)
        XCTAssertFalse(seen.json.keys.contains("nickname"), "a field nobody touched is not sent")
    }

    /// The one key an edit from this app must never carry.
    ///
    /// `photo_url` is a live column the server still accepts a write to, and a
    /// watch that arrived from a Rewound order keeps the seller's photograph
    /// in it. The link form is gone, so nothing here means anything by that
    /// column — and a PATCH that named it while meaning nothing would wipe the
    /// seller's picture, leaving the card with no cover at all the moment the
    /// owner deletes their own uploads. It cannot be sent by accident because
    /// there is no argument for it; this is what says so out loud.
    @MainActor
    func testAnEditNeverNamesThePhotoLinkColumn() async throws {
        let seen = SeenVaultRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Self.updatedRow)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        _ = try await vault.update(id: "v1", notes: .clear, nickname: .clear)

        XCTAssertFalse(seen.body.contains("photo_url"))
        XCTAssertFalse(seen.json.keys.contains("photo_url"))
    }

    @MainActor
    func testSettingAFieldTrimsItAndSendsIt() async throws {
        let seen = SeenVaultRequest()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, Self.updatedRow)
        }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))

        _ = try await vault.update(id: "v1", notes: .text("  Bought at the boutique.  "))

        XCTAssertEqual(seen.json["notes"] as? String, "Bought at the boutique.")
        XCTAssertFalse(seen.json.keys.contains("photo_url"))
    }

    /// An emptied box is a removal, not a save of nothing.
    func testAnEmptyBoxIsAClear() {
        XCTAssertEqual(VaultFieldEdit.text("   \n "), .clear)
        XCTAssertEqual(VaultFieldEdit.text("a note"), .set("a note"))
    }

    @MainActor
    func testTheSavedRowReplacesTheCachedOne() async throws {
        MockURLProtocol.setHandler { _ in (200, Self.updatedRow) }
        let vault = VaultStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        try await vault.load()
        XCTAssertNil(vault.watches.first?.nickname)

        _ = try await vault.update(id: "v1", nickname: .set("The daily"))

        XCTAssertEqual(vault.watches.count, 1, "an edit is not an insert")
        XCTAssertEqual(vault.watches.first?.nickname, "The daily")
    }

    /// The list handler answers both calls in the test above: the first is a
    /// GET whose envelope carries a `results` array, the second a PATCH whose
    /// envelope carries the row. `MockURLProtocol` hands back the same bytes
    /// for both, so the payload has to satisfy either shape — it carries
    /// `results` alongside the row's own keys.
    private static let updatedRow = Data("""
    {"ok": true, "data": {
      "results": [{"id": "v1", "source": "manual", "authenticated": false,
        "order_id": null, "listing_id": null, "passport_code": null,
        "brand": "Tudor", "model": "Black Bay", "reference": "79030N",
        "production_year": null, "nickname": null, "notes": null,
        "photo_url": null, "acquired_price": null, "acquired_date": null,
        "estimated_value": null, "estimated_at": null, "created_at": null}],
      "id": "v1", "source": "manual", "authenticated": false,
      "order_id": null, "listing_id": null, "passport_code": null,
      "brand": "Tudor", "model": "Black Bay", "reference": "79030N",
      "production_year": null, "nickname": "The daily", "notes": null,
      "photo_url": "https://photos.example/mine.jpg",
      "acquired_price": null, "acquired_date": null,
      "estimated_value": null, "estimated_at": null, "created_at": null}}
    """.utf8)
}

/// The one request the mock saw, readable from the test's actor.
private final class SeenVaultRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var payload: Data?

    func record(_ request: URLRequest) {
        // `httpBody` is nil by the time a request reaches a URLProtocol —
        // URLSession hands the body over as a stream — so it is drained here,
        // while the handler still has it.
        let drained = request.httpBody ?? request.httpBodyStream.map(drainHTTPBodyStream)
        lock.withLock {
            self.request = request
            self.payload = drained
        }
    }

    var method: String? { lock.withLock { request?.httpMethod } }
    var path: String? { lock.withLock { request?.url?.path } }

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
}
