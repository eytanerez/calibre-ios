import Foundation
import XCTest
@testable import CalibreKit

/// `Order.passport_code` — the field the order detail's Passport row is
/// gated on. The row appears exactly when this decodes to something, so a
/// silent decoding miss here is a door that never opens.
final class OrderPassportTests: XCTestCase {

    func testOrderCarriesThePassportCode() throws {
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "to_buyer",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD",
          "passport_code": "do3bgntrgzgphfml"
        }
        """
        let order = try apiDecoder().decode(Order.self, from: Data(json.utf8))
        XCTAssertEqual(order.passportCode, "do3bgntrgzgphfml")
    }

    /// The code arrives when the bench mints it, which is authentication —
    /// so every order before that point, and every payload recorded before
    /// the order carried the field at all, has to decode without it rather
    /// than failing the whole order.
    func testOrderWithoutAPassportCodeStillDecodes() throws {
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "purchased",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD"
        }
        """
        let order = try apiDecoder().decode(Order.self, from: Data(json.utf8))
        XCTAssertNil(order.passportCode)
        // The rest of the order is untouched by the new field.
        XCTAssertEqual(order.status, .purchased)
    }

    /// An explicit null is what the serializer sends for an order the bench
    /// has not reached, and it must read the same as an absent key.
    func testExplicitNullPassportCodeReadsAsAbsent() throws {
        let json = """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b", "buyer_id": "b1",
          "listing_id": "l1", "status": "to_auth",
          "subtotal": "1.00", "fees_total": "0.00", "grand_total": "1.00",
          "currency": "USD",
          "passport_code": null
        }
        """
        let order = try apiDecoder().decode(Order.self, from: Data(json.utf8))
        XCTAssertNil(order.passportCode)
    }
}
