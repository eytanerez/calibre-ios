import Foundation
import XCTest
@testable import RewoundKit

/// `GET /vault/{id}`'s `listing_photos`, and the one gallery the detail
/// screen draws from it: the cover, then the owner's own photographs, then the
/// seller's, never the same picture twice.
final class VaultListingPhotosTests: XCTestCase {

    /// A watch bought here whose owner has photographed it twice. The cover is
    /// their first photograph; the listing it came from had three, the first of
    /// which is also on the row as `photo_url` (the lead carried at delivery),
    /// spelled root-relative there and absolute in `listing_photos`.
    private static let boughtAndPhotographed = """
    {
      "id": "v1", "source": "rewound_order", "authenticated": true,
      "order_id": "o1", "listing_id": "l1", "passport_code": "CAL-1",
      "brand": "Tudor", "model": "Black Bay", "reference": "79030N",
      "production_year": 2021, "nickname": null, "notes": null,
      "photo_url": "/media/listings/l1/front.jpg",
      "cover_url": "/secure-media/vault_photos/v1/one.jpg",
      "photos": [
        {"id": "p1", "url": "/secure-media/vault_photos/v1/one.jpg", "position": 0},
        {"id": "p2", "url": "/secure-media/vault_photos/v1/two.jpg", "position": 1}
      ],
      "acquired_price": null, "acquired_date": null,
      "estimated_value": null, "estimated_at": null, "created_at": null,
      "service_records": [], "reference_row": null, "pending_suggestion": false,
      "listing_photos": [
        {"url": "https://api.test/media/listings/l1/front.jpg", "width": 1600, "height": 1600},
        {"url": "/media/listings/l1/caseback.jpg", "width": null, "height": null},
        {"url": "/media/listings/l1/clasp.jpg", "width": 1200, "height": 900}
      ]
    }
    """

    private func decode(_ json: String) throws -> VaultWatchDetail {
        try apiDecoder().decode(VaultWatchDetail.self, from: Data(json.utf8))
    }

    func testListingPhotosDecodeInGalleryOrderAgainstTheOrigin() throws {
        let detail = try decode(Self.boughtAndPhotographed)

        XCTAssertEqual(detail.listingPhotos.map { $0.url?.url?.absoluteString }, [
            "https://api.test/media/listings/l1/front.jpg",
            "https://api.test/media/listings/l1/caseback.jpg",
            "https://api.test/media/listings/l1/clasp.jpg",
        ])
        XCTAssertEqual(detail.listingPhotos.first?.width, 1600)
        XCTAssertNil(detail.listingPhotos[1].width)
    }

    /// A server that predates the key, and a watch with no linked listing,
    /// both mean "nothing of the seller's to show". Neither may fail the
    /// screen.
    func testAnAbsentOrNullKeyIsAnEmptyList() throws {
        var withoutKey = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(Self.boughtAndPhotographed.utf8)) as? [String: Any]
        )
        withoutKey.removeValue(forKey: "listing_photos")
        let absent = try apiDecoder().decode(
            VaultWatchDetail.self,
            from: JSONSerialization.data(withJSONObject: withoutKey)
        )
        XCTAssertEqual(absent.listingPhotos, [])

        withoutKey["listing_photos"] = NSNull()
        let null = try apiDecoder().decode(
            VaultWatchDetail.self,
            from: JSONSerialization.data(withJSONObject: withoutKey)
        )
        XCTAssertEqual(null.listingPhotos, [])
    }

    func testTheGalleryIsCoverThenOwnerThenSellerWithNoPictureTwice() throws {
        let detail = try decode(Self.boughtAndPhotographed)

        let gallery = detail.watch.viewingGallery(listingPhotos: detail.listingPhotos)

        XCTAssertEqual(gallery.map(\.absoluteString), [
            // The cover, which is also the owner's first photograph: once.
            "https://api.test/secure-media/vault_photos/v1/one.jpg",
            "https://api.test/secure-media/vault_photos/v1/two.jpg",
            // The seller's three, all of them, lead first.
            "https://api.test/media/listings/l1/front.jpg",
            "https://api.test/media/listings/l1/caseback.jpg",
            "https://api.test/media/listings/l1/clasp.jpg",
        ])
    }

    /// Before the owner has photographed it, the cover IS the listing's lead,
    /// carried on the row. The pager must not open on the same photograph
    /// twice in a row.
    func testALeadCarriedAsTheCoverIsNotRepeated() throws {
        let json = Self.boughtAndPhotographed
            .replacingOccurrences(
                of: "\"cover_url\": \"/secure-media/vault_photos/v1/one.jpg\"",
                with: "\"cover_url\": \"/media/listings/l1/front.jpg\""
            )
            .replacingOccurrences(
                of: #""photos": \[[^\]]*\]"#,
                with: #""photos": []"#,
                options: .regularExpression
            )
        let detail = try decode(json)
        XCTAssertTrue(detail.watch.gallery.isEmpty, "the fixture edit took")

        let gallery = detail.watch.viewingGallery(listingPhotos: detail.listingPhotos)

        XCTAssertEqual(gallery.map(\.absoluteString), [
            "https://api.test/media/listings/l1/front.jpg",
            "https://api.test/media/listings/l1/caseback.jpg",
            "https://api.test/media/listings/l1/clasp.jpg",
        ])
    }

    /// A watch typed in by hand has no listing, and an owner photograph that
    /// cannot be addressed is left out rather than drawn as a blank page.
    func testAManualWatchShowsOnlyWhatCanBeDrawn() throws {
        let json = """
        {"id": "v2", "source": "manual", "authenticated": false, "order_id": null,
         "listing_id": null, "passport_code": null, "brand": "Seiko", "model": null,
         "reference": "SBGA211", "production_year": null, "nickname": null, "notes": null,
         "photo_url": null, "cover_url": "/secure-media/vault_photos/v2/a.jpg",
         "photos": [
           {"id": "a", "url": "/secure-media/vault_photos/v2/a.jpg", "position": 0},
           {"id": "b", "url": null, "position": 1}
         ],
         "acquired_price": null, "acquired_date": null, "estimated_value": null,
         "estimated_at": null, "created_at": null,
         "service_records": [], "reference_row": null, "pending_suggestion": false,
         "listing_photos": []}
        """
        let detail = try decode(json)

        let gallery = detail.watch.viewingGallery(listingPhotos: detail.listingPhotos)

        XCTAssertEqual(gallery.map(\.absoluteString), ["https://api.test/secure-media/vault_photos/v2/a.jpg"])
    }

    /// With nothing at all, the list is empty, which is what tells the screen
    /// to draw the monogram rather than a pager of nothing.
    func testNothingToShowIsAnEmptyGallery() throws {
        let json = """
        {"id": "v3", "source": "manual", "authenticated": false, "order_id": null,
         "listing_id": null, "passport_code": null, "brand": "Seiko", "model": null,
         "reference": null, "production_year": null, "nickname": null, "notes": null,
         "photo_url": null, "acquired_price": null, "acquired_date": null,
         "estimated_value": null, "estimated_at": null, "created_at": null,
         "service_records": [], "reference_row": null, "pending_suggestion": false}
        """
        let detail = try decode(json)
        XCTAssertTrue(detail.watch.viewingGallery(listingPhotos: detail.listingPhotos).isEmpty)
    }
}
