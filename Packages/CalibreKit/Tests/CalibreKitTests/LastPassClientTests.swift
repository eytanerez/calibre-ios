import Foundation
import XCTest
@testable import CalibreKit

/// The client half of four backend features: notifications that are cleared
/// rather than read, support conversations that are plural, the "this one
/// sold" notice, and the thread list's preview and unread count.
final class LastPassClientTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let suite = "calibre.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - Notifications are cleared, not read

    /// The badge counts what is left in the inbox, not what is unread. This
    /// payload is a member who has read everything and cleared nothing: every
    /// row carries a `read_at`, and the badge is still three.
    @MainActor
    func testTheBadgeCountsWhatIsLeftRatherThanWhatIsUnread() async throws {
        let body = envelope("""
        {"results": [
           {"id": "n1", "category": "order_updates", "title": "Shipped", "body": "On its way",
            "route": "order/o1", "read_at": "2026-09-08T10:00:00Z", "cleared_at": null,
            "created_at": "2026-09-08T09:00:00Z"},
           {"id": "n2", "category": "offer_updates", "title": "Countered", "body": "They replied",
            "route": "offer/of1", "read_at": "2026-09-08T10:00:00Z", "cleared_at": null,
            "created_at": "2026-09-08T09:00:00Z"},
           {"id": "n3", "category": "watchlist_alerts", "title": "Price drop", "body": "Lower now",
            "route": "listing/l1", "read_at": "2026-09-08T10:00:00Z", "cleared_at": null,
            "created_at": "2026-09-08T09:00:00Z"}
         ],
         "page": 1, "page_size": 50, "total": 3,
         "remaining_count": 3, "unread_count": 3}
        """)
        MockURLProtocol.setHandler { _ in (200, body) }

        let store = ServerAlertsStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        _ = try await store.load()

        XCTAssertEqual(store.remainingCount, 3)
        XCTAssertTrue(store.notifications.allSatisfy { $0.readAt != nil })
    }

    /// Clearing one row is a DELETE on that row, and the row leaves the inbox
    /// and the badge without waiting for a refetch.
    @MainActor
    func testClearingOneNotificationDeletesItAndDropsItFromTheInbox() async throws {
        let seen = SeenCall()
        let listBody = envelope("""
        {"results": [
           {"id": "n1", "category": "order_updates", "title": "Shipped", "body": "On its way",
            "route": "order/o1", "read_at": null, "cleared_at": null,
            "created_at": "2026-09-08T09:00:00Z"},
           {"id": "n2", "category": "offer_updates", "title": "Countered", "body": "They replied",
            "route": "offer/of1", "read_at": null, "cleared_at": null,
            "created_at": "2026-09-08T09:00:00Z"}
         ],
         "page": 1, "page_size": 50, "total": 2,
         "remaining_count": 2, "unread_count": 2}
        """)
        let clearedBody = envelope("""
        {"id": "n1", "category": "order_updates", "title": "Shipped", "body": "On its way",
         "route": "order/o1", "read_at": null, "cleared_at": "2026-09-08T11:00:00Z",
         "created_at": "2026-09-08T09:00:00Z"}
        """)
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return request.httpMethod == "DELETE" ? (200, clearedBody) : (200, listBody)
        }

        let store = ServerAlertsStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        _ = try await store.load()
        let cleared = try await store.clear(id: "n1")

        XCTAssertEqual(seen.method, "DELETE")
        XCTAssertEqual(seen.path, "/account/notifications/n1")
        XCTAssertNotNil(cleared.clearedAt)
        XCTAssertEqual(store.notifications.map(\.id), ["n2"])
        XCTAssertEqual(store.remainingCount, 1)
    }

    /// Clear all is a DELETE on the collection, and it empties both the list
    /// and the badge.
    @MainActor
    func testClearAllEmptiesTheInbox() async throws {
        let seen = SeenCall()
        let listBody = envelope("""
        {"results": [
           {"id": "n1", "category": "order_updates", "title": "Shipped", "body": "On its way",
            "route": "order/o1", "read_at": null, "cleared_at": null,
            "created_at": "2026-09-08T09:00:00Z"}
         ],
         "page": 1, "page_size": 50, "total": 1,
         "remaining_count": 1, "unread_count": 1}
        """)
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return request.httpMethod == "DELETE"
                ? (200, envelope("{\"cleared\": 1, \"remaining_count\": 0}"))
                : (200, listBody)
        }

        let store = ServerAlertsStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        _ = try await store.load()
        let swept = try await store.clearAll()

        XCTAssertEqual(seen.method, "DELETE")
        XCTAssertEqual(seen.path, "/account/notifications")
        XCTAssertEqual(swept, 1)
        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertEqual(store.remainingCount, 0)
    }

    /// A server one deploy behind sends only the old key. The badge reads the
    /// value that is there rather than throwing the whole inbox away over a
    /// missing integer.
    func testAListWithOnlyTheOldCountKeyStillDecodes() throws {
        let data = Data("""
        {"results": [], "page": 1, "page_size": 50, "total": 0, "unread_count": 4}
        """.utf8)
        let list = try APIClient.makeDecoder(origin: nil).decode(ServerNotificationList.self, from: data)
        XCTAssertEqual(list.remainingCount, 4)
    }

    // MARK: - Support has separate conversations

    /// A guest asks for their list with every token this device holds, one
    /// repeated `token` parameter each — the server answers with exactly the
    /// threads those tokens name and nothing else.
    @MainActor
    func testAGuestListsThreadsWithEveryTokenItHolds() async throws {
        let seen = SeenCall()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            // The two sends are how the device comes to hold two tokens; the
            // list is what the test is actually about.
            if request.url?.path == "/support/messages" {
                let token = request.httpBodyStream
                    .map { drainHTTPBodyStream($0) }
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["new_thread"] != nil
                    ? "token-two" : "token-one"
                return (201, envelope("""
                {"thread": {"id": "c1", "status": "waiting_on_calibre", "title": "September 8, 2026",
                            "resolved": false, "resumable": true,
                            "created_at": "2026-09-08T09:00:00Z", "last_message_at": "2026-09-08T10:00:00Z",
                            "messages": [], "assigned_contact": null},
                 "guest_token": "\(token)"}
                """))
            }
            return (200, envelope("""
            {"results": [
               {"id": "c2", "status": "waiting_on_calibre", "title": "September 8, 2026",
                "resolved": false, "resumable": true, "origin": "customer",
                "created_at": "2026-09-08T09:00:00Z", "last_message_at": "2026-09-08T10:00:00Z",
                "snippet": "Is the bracelet original?", "assigned_contact": null,
                "guest_token": "token-two"},
               {"id": "c1", "status": "closed", "title": "March 2, 2026",
                "resolved": true, "resumable": false, "origin": "calibre",
                "created_at": "2026-03-02T09:00:00Z", "last_message_at": "2026-03-02T10:00:00Z",
                "snippet": "All sorted, thank you.", "assigned_contact": {"key": "ez", "display_name": "Eytan"},
                "guest_token": "token-one"}
             ]}
            """))
        }

        let defaults = scratchDefaults()
        let store = SupportStore(client: APIClient(configuration: mockConfiguration(), auth: nil), defaults: defaults)
        // Two conversations means two tokens, which is what a guest who used
        // New chat ends up holding.
        _ = try await store.send("first", authenticated: false, guestEmail: "a@b.test")
        _ = try await store.send("second", authenticated: false, newThread: true)

        let threads = try await store.listThreads(authenticated: false)

        XCTAssertEqual(seen.path, "/support/threads")
        XCTAssertEqual(seen.queryValues(named: "token"), store.guestTokens)
        XCTAssertEqual(threads.map(\.id), ["c2", "c1"])
        XCTAssertEqual(threads[0].title, "September 8, 2026")
        XCTAssertTrue(threads[0].resumable)
        XCTAssertTrue(threads[1].resolved)
        XCTAssertFalse(threads[1].resumable)
        XCTAssertEqual(threads[1].origin, .calibre)
    }

    /// New chat is a flag on the send, and the token it mints is kept
    /// *alongside* the ones already held — a guest's older conversations do
    /// not stop being theirs because they started another.
    @MainActor
    func testStartingANewChatSendsTheFlagAndKeepsTheOlderToken() async throws {
        let seen = SeenCall()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            let token = seen.callCount == 1 ? "token-one" : "token-two"
            return (201, envelope("""
            {"thread": {"id": "c\(seen.callCount)", "status": "waiting_on_calibre",
                        "title": "September 8, 2026", "resolved": false, "resumable": true,
                        "created_at": "2026-09-08T09:00:00Z", "last_message_at": "2026-09-08T10:00:00Z",
                        "messages": [], "assigned_contact": null},
             "guest_token": "\(token)"}
            """))
        }

        let defaults = scratchDefaults()
        let store = SupportStore(client: APIClient(configuration: mockConfiguration(), auth: nil), defaults: defaults)
        _ = try await store.send("first", authenticated: false, guestEmail: "a@b.test")
        _ = try await store.send("second", authenticated: false, newThread: true)

        XCTAssertEqual(seen.bodyValue(forKey: "new_thread") as? Bool, true)
        XCTAssertEqual(store.guestTokens, ["token-one", "token-two"])
    }

    /// Naming the thread is how a reply lands in the conversation the customer
    /// is reading, including a closed one.
    @MainActor
    func testReplyingNamesTheThreadItIsWrittenIn() async throws {
        let seen = SeenCall()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (201, envelope("""
            {"thread": {"id": "c1", "status": "closed", "title": "March 2, 2026",
                        "resolved": true, "resumable": false,
                        "created_at": "2026-03-02T09:00:00Z", "last_message_at": "2026-03-02T10:00:00Z",
                        "messages": [], "assigned_contact": null},
             "guest_token": null}
            """))
        }

        let store = SupportStore(
            client: APIClient(configuration: mockConfiguration(), auth: nil),
            defaults: scratchDefaults()
        )
        let thread = try await store.send("one more thing", authenticated: true, threadID: "c1")

        XCTAssertEqual(seen.bodyValue(forKey: "thread_id") as? String, "c1")
        XCTAssertNil(seen.bodyValue(forKey: "new_thread"))
        XCTAssertTrue(thread.resolved)
        XCTAssertFalse(thread.resumable)
    }

    /// The 24-hour resume window is the server's, in one place. The client
    /// reads the answer off the payload — including for a thread whose last
    /// message is minutes old, which a client-side window would have called
    /// resumable and the server did not.
    func testResumabilityIsReadFromThePayloadAndNotFromTheTimestamp() throws {
        let stamp = ISO8601DateFormatter().string(from: .now)
        let data = Data("""
        {"id": "c1", "status": "open", "title": "September 8, 2026",
         "resolved": false, "resumable": false,
         "created_at": "\(stamp)", "last_message_at": "\(stamp)",
         "messages": [], "assigned_contact": null}
        """.utf8)
        let thread = try APIClient.makeDecoder(origin: nil).decode(SupportConversation.self, from: data)

        XCTAssertFalse(thread.resumable)
        XCTAssertEqual(thread.title(), "September 8, 2026")
    }

    // MARK: - The sold notice

    /// The read is a read. It fetches the pending notices and sends no
    /// acknowledgement of its own — the tabs that call it refresh whenever
    /// they appear, and one that acknowledged would spend the notice while
    /// the phone was in a pocket.
    @MainActor
    func testReadingTheSoldNoticesAcknowledgesNothing() async throws {
        let seen = SeenCall()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, envelope("""
            {"notices": [
               {"id": "no1", "listing_id": "l1", "listing_number": 4242, "reason": "sold",
                "source": "both", "title": "Omega Speedmaster Professional",
                "image": "https://cdn.calibre.test/l1.jpg", "price": "6250.00",
                "currency": "USD", "created_at": "2026-09-08T12:00:00Z"}
             ],
             "has_more": false}
            """))
        }

        let store = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        let notices = try await store.loadListingNotices()

        XCTAssertEqual(seen.method, "GET")
        XCTAssertEqual(seen.path, "/listing-notices")
        XCTAssertEqual(seen.callCount, 1)
        XCTAssertEqual(notices.map(\.id), ["no1"])
        XCTAssertEqual(notices[0].source, .both)
        XCTAssertEqual(notices[0].priceValue, Decimal(string: "6250.00"))
        XCTAssertEqual(store.listingNotices.count, 1)
    }

    /// The burn is explicit, names the rows it is burning, and takes them out
    /// of the pending list.
    @MainActor
    func testAcknowledgingBurnsExactlyTheNoticesItNames() async throws {
        let seen = SeenCall()
        let listBody = envelope("""
        {"notices": [
           {"id": "no1", "listing_id": "l1", "reason": "sold", "source": "cart",
            "title": "Omega Speedmaster", "image": null, "price": "6250.00",
            "currency": "USD", "created_at": "2026-09-08T12:00:00Z"},
           {"id": "no2", "listing_id": "l2", "reason": "sold", "source": "saved",
            "title": "Tudor Black Bay", "image": null, "price": "3100.00",
            "currency": "USD", "created_at": "2026-09-08T12:00:00Z"}
         ],
         "has_more": false}
        """)
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return request.httpMethod == "POST"
                ? (200, envelope("{\"acknowledged\": 1}"))
                : (200, listBody)
        }

        let store = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        _ = try await store.loadListingNotices()
        let burned = try await store.acknowledgeListingNotices(ids: ["no1"])

        XCTAssertEqual(seen.method, "POST")
        XCTAssertEqual(seen.path, "/listing-notices/seen")
        XCTAssertEqual(seen.bodyValue(forKey: "ids") as? [String], ["no1"])
        XCTAssertEqual(burned, 1)
        XCTAssertEqual(store.listingNotices.map(\.id), ["no2"])
    }

    /// Acknowledging nothing asks the server nothing. An empty list is not a
    /// request worth making, and the endpoint refuses a malformed one.
    @MainActor
    func testAcknowledgingAnEmptyListMakesNoRequest() async throws {
        let seen = SeenCall()
        MockURLProtocol.setHandler { request in
            seen.record(request)
            return (200, envelope("{\"acknowledged\": 0}"))
        }

        let store = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        let burned = try await store.acknowledgeListingNotices(ids: [])

        XCTAssertEqual(burned, 0)
        XCTAssertEqual(seen.callCount, 0)
    }

    /// The decoding trap this app has hit before: a date-only stamp is not
    /// ISO-8601 date-time, the shared strategy returns nothing for it, and a
    /// synthesized initializer would throw and take the whole banner — the one
    /// notice this member ever gets about this watch — down with it. The stamp
    /// is the only thing allowed to be lost.
    func testANoticeWithADateOnlyStampStillDecodes() throws {
        let data = Data("""
        {"id": "no1", "listing_id": "l1", "reason": "sold", "source": "saved",
         "title": "Omega Speedmaster", "image": null, "price": "6250.00",
         "currency": "USD", "created_at": "2026-09-08"}
        """.utf8)
        let notice = try APIClient.makeDecoder(origin: nil).decode(ListingGoneNotice.self, from: data)

        XCTAssertEqual(notice.id, "no1")
        XCTAssertEqual(notice.title, "Omega Speedmaster")
        XCTAssertNil(notice.createdAt)
    }

    /// A `source` this build has never heard of is a row it can still show.
    func testANoticeWithAnUnknownSourceStillDecodes() throws {
        let data = Data("""
        {"id": "no1", "listing_id": "l1", "reason": "withdrawn", "source": "offer",
         "title": null, "image": null, "price": null, "currency": "USD",
         "created_at": "2026-09-08T12:00:00Z"}
        """.utf8)
        let notice = try APIClient.makeDecoder(origin: nil).decode(ListingGoneNotice.self, from: data)

        XCTAssertEqual(notice.source, .unknown)
        XCTAssertEqual(notice.reason, "withdrawn")
        XCTAssertNil(notice.priceValue)
    }

    // MARK: - The messaging thread list

    /// The row carries the last delivered line, the stamp that belongs to it,
    /// and the caller's own unread count.
    @MainActor
    func testAThreadRowCarriesItsPreviewAndUnreadCount() async throws {
        MockURLProtocol.setHandler { _ in
            (200, Data("""
            [{"id": "t1", "listing_id": "l1", "buyer_id": "b1", "seller_id": "s1",
              "listing_title": "Submariner 126610LN", "listing_reference": "CAL-1001",
              "state": "open", "last_message_at": "2026-09-08T11:50:00Z",
              "created_at": "2026-09-08T09:00:00Z",
              "last_message_preview": "Box and papers are both with it.",
              "last_message_preview_at": "2026-09-08T11:50:00Z",
              "unread_count": 2}]
            """.utf8))
        }
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://mock.calibre-messaging.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
        let store = MessagingStore(client: MessagingClient(configuration: configuration, auth: nil))
        let threads = try await store.listThreads()

        XCTAssertEqual(threads[0].lastMessagePreview, "Box and papers are both with it.")
        XCTAssertNotNil(threads[0].lastMessagePreviewAt)
        XCTAssertEqual(threads[0].unreadCount, 2)
        XCTAssertEqual(threads[0].markedRead().unreadCount, 0)
    }

    /// A thread with nothing delivered in it yet is a real state, not a
    /// broken row: nulls on both preview keys, and no unread.
    func testAThreadWithNothingDeliveredDecodesWithNoPreview() throws {
        let data = Data("""
        {"id": "t1", "listing_id": "l1", "buyer_id": "b1", "seller_id": "s1",
         "listing_title": null, "listing_reference": null, "state": "open",
         "last_message_at": null, "created_at": "2026-09-08T09:00:00Z",
         "last_message_preview": null, "last_message_preview_at": null,
         "unread_count": 0}
        """.utf8)
        let thread = try APIClient.makeDecoder(origin: nil).decode(MessageThread.self, from: data)

        XCTAssertNil(thread.lastMessagePreview)
        XCTAssertNil(thread.lastMessagePreviewAt)
        XCTAssertEqual(thread.unreadCount, 0)
    }

    /// A messaging service one deploy behind sends none of the three new
    /// keys. The inbox still opens.
    func testAThreadFromAServiceWithoutTheNewKeysStillDecodes() throws {
        let data = Data("""
        {"id": "t1", "listing_id": "l1", "buyer_id": "b1", "seller_id": "s1",
         "listing_title": "Submariner", "listing_reference": null, "state": "open",
         "last_message_at": "2026-09-08T11:50:00Z", "created_at": "2026-09-08T09:00:00Z"}
        """.utf8)
        let thread = try APIClient.makeDecoder(origin: nil).decode(MessageThread.self, from: data)

        XCTAssertNil(thread.lastMessagePreview)
        XCTAssertEqual(thread.unreadCount, 0)
    }
}

/// The house `{ok, data}` wrapper every Backend response arrives in. A free
/// function rather than a method, so a `@Sendable` mock handler can call it
/// without capturing the test case.
private func envelope(_ json: String) -> Data {
    Data("{\"ok\": true, \"data\": \(json)}".utf8)
}

/// What the mock saw. The handler runs on URLSession's thread, so everything
/// here is lock-guarded rather than merely `nonisolated(unsafe)`.
private final class SeenCall: @unchecked Sendable {
    private let lock = NSLock()
    private var _method: String?
    private var _url: URL?
    private var _body: [String: Any] = [:]
    private var _count = 0

    var method: String? { lock.withLock { _method } }
    var path: String? { lock.withLock { _url?.path } }
    var callCount: Int { lock.withLock { _count } }

    func record(_ request: URLRequest) {
        let body = request.httpBodyStream.map { drainHTTPBodyStream($0) } ?? request.httpBody
        let parsed = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        lock.withLock {
            _method = request.httpMethod
            _url = request.url
            _count += 1
            if let parsed { _body = parsed }
        }
    }

    func bodyValue(forKey key: String) -> Any? {
        lock.withLock { _body[key] }
    }

    /// Every value of one repeated query parameter, in the order it was sent.
    func queryValues(named name: String) -> [String] {
        let url = lock.withLock { _url }
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return []
        }
        return (components.queryItems ?? [])
            .filter { $0.name == name }
            .compactMap(\.value)
    }
}
