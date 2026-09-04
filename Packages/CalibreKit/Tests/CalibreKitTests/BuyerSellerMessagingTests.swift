import Foundation
import XCTest
@testable import CalibreKit

/// Buyer↔seller messaging (`MessagingClient`, `MessagingStore`, and the wire
/// models) — not `MessagingTests.swift`, which covers push-tap reporting and
/// the support-chat guest token.
///
/// The one thing worth a dedicated suite: calibre-messaging is not Backend.
/// It answers plain JSON, never Backend's `{ok, data}` envelope, and refuses
/// with FastAPI's `{"detail": ...}` rather than `{"error": ...}`. A
/// `MessagingClient` built like `APIClient` would fail to decode every
/// response, success or failure — these tests exist to catch that
/// regression, not to re-prove `APIClient`'s own envelope handling.
final class BuyerSellerMessagingTests: XCTestCase {
    private func mockConfiguration() -> APIConfiguration {
        APIConfiguration(
            baseURL: URL(string: "https://mock.calibre-messaging.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
    }

    // MARK: - Plain-JSON decoding (no {ok, data} envelope)

    func testListThreadsDecodesThePlainJSONArrayCalibreMessagingActuallySends() async throws {
        MockURLProtocol.setHandler { _ in
            (200, Data("""
            [{"id": "t1", "listing_id": "l1", "buyer_id": "b1", "seller_id": "s1",
              "listing_title": "Rolex Submariner", "listing_reference": "126610LN",
              "state": "open", "last_message_at": "2026-01-01T00:00:00Z",
              "created_at": "2026-01-01T00:00:00Z"}]
            """.utf8))
        }
        let client = MessagingClient(configuration: mockConfiguration(), auth: nil)
        let store = MessagingStore(client: client)
        let threads = try await store.listThreads()

        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].id, "t1")
        XCTAssertEqual(threads[0].listingTitle, "Rolex Submariner")
        XCTAssertEqual(threads[0].state, .open)
    }

    /// The send response — `{message, action, notice}` — decodes directly,
    /// with no `data` key to unwrap. This is the shape a fresh send renders
    /// its bubble from.
    func testSendDecodesTheHeldResponseDirectly() async throws {
        MockURLProtocol.setHandler { _ in
            (201, Data("""
            {"message": {"id": "m1", "thread_id": "t1", "sender_id": "b1",
                         "body": "Call me at 415-555-0134", "guard_action": "hold",
                         "delivered_at": null, "created_at": "2026-01-01T00:00:00Z"},
             "action": "hold",
             "notice": "This message flagged something in our system and is under review. It hasn't been delivered yet."}
            """.utf8))
        }
        let client = MessagingClient(configuration: mockConfiguration(), auth: nil)
        let store = MessagingStore(client: client)
        let result = try await store.send(threadID: "t1", body: "Call me at 415-555-0134")

        XCTAssertEqual(result.action, .hold)
        XCTAssertEqual(result.message.deliveryState, .held)
        XCTAssertEqual(result.notice, MessagingCopy.heldNotice)
    }

    /// `delivered_at`, not `guard_action`, is what `deliveryState` keys off —
    /// the model's own doc comment says why: it is the field the server
    /// treats as authoritative, never null once delivered.
    func testDeliveryStateReadsDeliveredAtNotGuardAction() throws {
        let decoder = APIClient.makeDecoder(origin: nil)
        let delivered = try decoder.decode(ThreadMessage.self, from: Data("""
        {"id": "m1", "thread_id": "t1", "sender_id": "b1", "body": "Hi",
         "guard_action": "allow", "delivered_at": "2026-01-01T00:00:00Z",
         "created_at": "2026-01-01T00:00:00Z"}
        """.utf8))
        let held = try decoder.decode(ThreadMessage.self, from: Data("""
        {"id": "m2", "thread_id": "t1", "sender_id": "b1", "body": "Text me",
         "guard_action": "hold", "delivered_at": null,
         "created_at": "2026-01-01T00:00:00Z"}
        """.utf8))

        XCTAssertEqual(delivered.deliveryState, .delivered)
        XCTAssertEqual(held.deliveryState, .held)
    }

    // MARK: - Refusals: FastAPI's {"detail": ...}, never Backend's {"error": ...}

    func testAStringDetailRefusalSurfacesAsAReadableServerError() async throws {
        MockURLProtocol.setHandler { _ in
            (404, Data(#"{"detail": "Thread not found"}"#.utf8))
        }
        let client = MessagingClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: MessageThread = try await client.send(Endpoint(path: "/threads/missing"))
            XCTFail("Expected a server error")
        } catch APIError.server(let message, _, let status, _) {
            XCTAssertEqual(message, "Thread not found")
            XCTAssertEqual(status, 404)
        }
    }

    /// A 422 validation refusal carries `detail` as an array of error
    /// objects, not a string — the other shape FastAPI's default handler
    /// produces, and the one a naive `{"detail": String}` decode would choke
    /// on silently (via `try?`) rather than surface.
    func testAValidationDetailArrayStillSurfacesAMessage() async throws {
        MockURLProtocol.setHandler { _ in
            (422, Data(#"{"detail": [{"loc": ["body", "body"], "msg": "Field required", "type": "missing"}]}"#.utf8))
        }
        let client = MessagingClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: MessageThread = try await client.send(Endpoint(path: "/threads/x"))
            XCTFail("Expected a server error")
        } catch APIError.server(let message, _, _, _) {
            XCTAssertEqual(message, "Field required")
        }
    }

    // MARK: - No body

    /// `POST /threads/{id}/read` answers a bare 204 — the same empty-body
    /// shortcut `APIClient` takes for a caller that asked for nothing back.
    func testMarkReadAcceptsAnEmpty204() async throws {
        let seen = SeenPath()
        MockURLProtocol.setHandler { request in
            seen.record(request.url?.path)
            return (204, Data())
        }
        let client = MessagingClient(configuration: mockConfiguration(), auth: nil)
        let store = MessagingStore(client: client)
        try await store.markRead(threadID: "t1")

        XCTAssertEqual(seen.path, "/threads/t1/read")
    }
}

/// The one request path the mock saw, readable from the test's actor — the
/// handler runs on URLSession's own thread.
private final class SeenPath: @unchecked Sendable {
    private let lock = NSLock()
    private var _path: String?
    var path: String? { lock.withLock { _path } }
    func record(_ path: String?) { lock.withLock { _path = path } }
}
