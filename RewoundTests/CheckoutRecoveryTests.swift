import RewoundKit
import Foundation
import XCTest
@testable import Rewound

/// "Go on without it" — the button a buyer gets when the server refuses to
/// reserve one watch of several.
///
/// Two things have to be true of it at once, and they pull against each other:
///
/// * it must move no money. `method` is `.wire` by default, so resuming on
///   what is *selected* would place a $250 authorization on the card of
///   somebody who never asked to pay by wire;
/// * it must leave the buyer with a price. The button's own words are "we'll
///   price your purchase again without it", and the review step has no pricing
///   trigger of its own — arriving unpriced it draws a skeleton with no total,
///   no pay button and no retry, and the only way out is closing checkout.
///
/// A version that resumed only what was already in flight satisfied the first
/// and broke the second: the recovery is only reachable from a pricing
/// failure, and at that moment there is no card intent and no wire checkout by
/// construction, so neither branch fired and the purchase was left unpriced.
@MainActor
final class CheckoutRecoveryTests: XCTestCase {
    private let firstWatch = "49e52179-1035-46f9-abe0-443d915d8c3b"
    private let secondWatch = "7c1f2b90-33ad-4a52-9c61-5b0a2f4d81e7"

    override func tearDown() {
        CheckoutMockURLProtocol.reset()
        super.tearDown()
    }

    private func model(listingIDs: [String]) -> CheckoutModel {
        let client = APIClient(configuration: CheckoutMockURLProtocol.configuration(), auth: nil)
        let model = CheckoutModel(
            listingIDs: listingIDs,
            offerID: nil,
            catalog: CatalogStore(client: client),
            commerce: CommerceStore(client: client),
            client: client
        )
        // The shipping step's answer, which pricing needs and nothing else
        // here depends on.
        model.selectedAddressID = "addr-1"
        return model
    }

    /// `{"ok": false, …}` with the code the checkout API refuses a taken watch
    /// with, naming the watch.
    private func reserved(_ listingID: String) -> Data {
        Data("""
        {"ok": false, "error": "Someone else is checking out with this watch right now.",
         "details": {"code": "listing_reserved", "listing_id": "\(listingID)"}}
        """.utf8)
    }

    /// A priced set: one payment intent, one line per watch, one combined
    /// column. Only the keys the model reads are asserted on below.
    private func priced(_ listingIDs: [String]) -> Data {
        let items = listingIDs.map { id in
            """
            {"listing_id": "\(id)", "subtotal": "4400.00", "shipping": "72.00",
             "grand_total": "4645.52", "currency": "USD"}
            """
        }
        return Data("""
        {"ok": true, "data": {
          "payment_intent": {"id": "pi_test", "client_secret": "pi_test_secret"},
          "publishable_key": "pk_test_rewound",
          "customer_id": "cus_test",
          "breakdown_group": {
            "items": [\(items.joined(separator: ","))],
            "combined": {"subtotal": "4400.00", "shipping": "72.00", "grand_total": "4645.52",
                         "currency": "USD", "item_count": \(listingIDs.count)}
          }
        }}
        """.utf8)
    }

    /// The whole walk: the method step's automatic price is refused, the buyer
    /// drops the watch, and the rest of the purchase comes back priced.
    func testGoingOnWithoutTheTakenWatchPricesTheRest() async {
        let model = model(listingIDs: [firstWatch, secondWatch])
        let taken = firstWatch
        let refusal = reserved(taken)
        let priced = priced([secondWatch])
        CheckoutMockURLProtocol.setHandler { request in
            guard request.url?.path == "/checkout/payment-intent" else { return (404, Data()) }
            // The first ask is refused; the ask after the watch was dropped is
            // the re-price the button promises.
            return CheckoutMockURLProtocol.seen(path: "/checkout/payment-intent") == 1
                ? (409, refusal)
                : (200, priced)
        }

        await model.prepareCardIntent()
        XCTAssertEqual(model.reservedWatch?.listingID, taken)
        XCTAssertNotNil(model.pricingProblem)
        XCTAssertTrue(model.canContinueWithoutReservedWatch)

        await model.continueWithoutReservedWatch()

        XCTAssertEqual(model.listingIDs, [secondWatch], "the taken watch stayed in the purchase")
        XCTAssertNil(model.pricingProblem)
        XCTAssertNotNil(
            model.breakdown,
            "the recovery left the buyer with no price — the review step draws a skeleton with no way forward"
        )
        XCTAssertEqual(model.droppedWatch?.listingID, taken, "the buyer was never told what was dropped")
    }

    /// The half that must not regress: recovering from a watch going out of
    /// stock never opens a wire, whatever `method` happens to be selected.
    func testTheRecoveryOpensNoWire() async {
        let model = model(listingIDs: [firstWatch, secondWatch])
        XCTAssertEqual(model.method, .wire, "wire is the default selection this guards against")
        let taken = firstWatch
        let refusal = reserved(taken)
        let priced = priced([secondWatch])
        CheckoutMockURLProtocol.setHandler { request in
            guard request.url?.path == "/checkout/payment-intent" else { return (404, Data()) }
            return CheckoutMockURLProtocol.seen(path: "/checkout/payment-intent") == 1
                ? (409, refusal)
                : (200, priced)
        }

        await model.prepareCardIntent()
        await model.continueWithoutReservedWatch()

        XCTAssertEqual(
            CheckoutMockURLProtocol.seen(path: "/checkout/create-intent"), 0,
            "the recovery placed a wire authorization on a buyer who never chose wire"
        )
        XCTAssertNil(model.wireCheckout)
    }

    /// The review step has no pricing trigger of its own, so the tap that
    /// opens it asks for the price. A buyer whose method-step price was
    /// refused and who then chose Card reaches review priced.
    func testContinuingToReviewPricesAnUnpricedPurchase() async {
        let model = model(listingIDs: [secondWatch])
        let priced = priced([secondWatch])
        CheckoutMockURLProtocol.setHandler { request in
            guard request.url?.path == "/checkout/payment-intent" else { return (404, Data()) }
            return (200, priced)
        }
        model.method = .card

        await model.continueFromMethod()

        XCTAssertEqual(model.path.last, .review)
        XCTAssertNotNil(model.breakdown, "the review step was reached with nothing priced")
    }
}

// MARK: - Transport

/// Routes the app's `APIClient` through a handler and counts what it asked
/// for, so a test can assert on the requests that were *not* made as well as
/// the ones that were.
final class CheckoutMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func setHandler(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            counts = [:]
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            counts = [:]
        }
    }

    /// How many times this path has been asked for, the current request
    /// included — so a handler can answer the first ask differently from the
    /// second.
    static func seen(path: String) -> Int {
        lock.withLock { counts[path] ?? 0 }
    }

    static func configuration() -> APIConfiguration {
        APIConfiguration(
            baseURL: URL(string: "https://mock.rewound.test")!,
            protocolClasses: [CheckoutMockURLProtocol.self]
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let handler = Self.lock.withLock { () -> Handler? in
            Self.counts[url.path, default: 0] += 1
            return Self.handler
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
