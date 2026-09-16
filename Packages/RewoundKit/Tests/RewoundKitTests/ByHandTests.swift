import CoreGraphics
import Foundation
import XCTest
@testable import CalibreKit

/// The seller's drawn mark: what leaves the phone, and what comes back.
final class ListingAnnotationTests: XCTestCase {

    // MARK: Simplification

    /// The cap is the server's, and a path over it is refused outright rather
    /// than trimmed — so anything the drawing surface produces has to come
    /// back under it whatever the finger did.
    func testALongScribbleIsCutDownToTheStoredCap() {
        let scribble = (0..<600).map { step -> CGPoint in
            let t = Double(step) / 599
            return CGPoint(x: t, y: 0.5 + sin(t * 40) * 0.2)
        }
        let simplified = AnnotationPath.simplify(scribble)
        XCTAssertLessThanOrEqual(simplified.count, ListingAnnotation.maxPoints)
        XCTAssertGreaterThanOrEqual(simplified.count, ListingAnnotation.minPoints)
    }

    /// A near-straight drag has almost no vertices worth keeping, so
    /// Douglas–Peucker collapses it to its two ends — under the floor the
    /// server enforces. The even-spacing fallback is what stops a legitimate
    /// long swipe from being rejected on upload.
    func testANearStraightDragStillClearsTheFloor() {
        let drag = (0..<400).map { step -> CGPoint in
            let t = Double(step) / 399
            return CGPoint(x: t, y: 0.5 + t * 0.0001)
        }
        let simplified = AnnotationPath.simplify(drag)
        XCTAssertGreaterThanOrEqual(simplified.count, ListingAnnotation.minPoints)
        XCTAssertLessThanOrEqual(simplified.count, ListingAnnotation.maxPoints)
        XCTAssertEqual(simplified.first?.x ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(simplified.last?.x ?? .nan, 1, accuracy: 0.0001)
    }

    /// A tap is not a mark. Returning nothing is what lets the caller say so
    /// instead of uploading something the server will refuse.
    func testAGestureTooShortToBeAMarkYieldsNothing() {
        let tap = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.51, y: 0.5)]
        XCTAssertTrue(AnnotationPath.simplify(tap).isEmpty)
    }

    /// A short-but-real mark is already inside the cap and must survive
    /// untouched — simplifying it further would move the line off what it was
    /// drawn around.
    func testAMarkAlreadyInsideTheCapIsLeftAlone() {
        let drawn = (0..<20).map { step -> CGPoint in
            let angle = Double(step) / 20 * 2 * .pi
            return CGPoint(x: 0.5 + cos(angle) * 0.1, y: 0.5 + sin(angle) * 0.1)
        }
        XCTAssertEqual(AnnotationPath.simplify(drawn).count, drawn.count)
    }

    /// A finger that strays off the photograph is still drawing. The server
    /// rejects anything outside the unit square, so the stray has to be
    /// brought back to the edge here rather than refused there.
    func testPointsOffThePhotographAreBroughtBackToItsEdge() {
        let strayed = (0..<30).map { step -> CGPoint in
            CGPoint(x: -0.4 + Double(step) / 20, y: 1.6)
        }
        let simplified = AnnotationPath.simplify(strayed)
        XCTAssertFalse(simplified.isEmpty)
        for point in simplified {
            XCTAssertTrue((0...1).contains(point.x), "x escaped the photograph: \(point.x)")
            XCTAssertTrue((0...1).contains(point.y), "y escaped the photograph: \(point.y)")
        }
    }

    // MARK: The wire

    func testAnnotationDecodesFromTheDocumentTheServerStores() throws {
        let json = """
        {"v": 1, "image_index": 2, "path": [[0.31, 0.52], [0.4, 0.61]],
         "note": "hairline on the bezel edge", "created_at": null, "updated_at": null}
        """
        let annotation = try apiDecoder().decode(ListingAnnotation.self, from: Data(json.utf8))
        XCTAssertEqual(annotation.v, ListingAnnotation.schemaVersion)
        XCTAssertEqual(annotation.imageIndex, 2)
        XCTAssertEqual(annotation.id, 2)
        XCTAssertEqual(annotation.path.count, 2)
        XCTAssertEqual(annotation.path[0].x, 0.31, accuracy: 0.0001)
        XCTAssertEqual(annotation.path[1].y, 0.61, accuracy: 0.0001)
        XCTAssertEqual(annotation.note, "hairline on the bezel edge")
    }

    /// Skipping a malformed pair would shift every following vertex of the
    /// line, which draws a plausible mark across the wrong part of the watch.
    /// Refusing the document is the only answer that cannot be wrong quietly.
    func testAPointThatIsNotAPairRefusesTheWholeDocument() {
        let json = """
        {"v": 1, "image_index": 0, "path": [[0.1, 0.2], [0.3]], "note": null}
        """
        XCTAssertThrowsError(
            try apiDecoder().decode(ListingAnnotation.self, from: Data(json.utf8))
        )
    }

    /// What the drawing surface uploads has to be the shape the server's
    /// validator reads, snake_case and all.
    func testAnnotationEncodesToTheShapeTheServerValidates() throws {
        let annotation = ListingAnnotation(
            imageIndex: 1,
            path: [CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.5, y: 0.5)],
            note: "clasp"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encoder.encode(annotation)) as? [String: Any]
        )
        XCTAssertEqual(object["v"] as? Int, ListingAnnotation.schemaVersion)
        XCTAssertEqual(object["image_index"] as? Int, 1)
        XCTAssertEqual(object["note"] as? String, "clasp")
        let path = try XCTUnwrap(object["path"] as? [[Double]])
        XCTAssertEqual(path, [[0.25, 0.75], [0.5, 0.5]])
    }
}

/// The gallery has to be able to tell "nobody drew one" from "this payload
/// was not asked about marks". Reading the second as the first would wipe the
/// marks off every card-sourced gallery with nothing going wrong.
final class ListingAnnotationPayloadTests: XCTestCase {
    func testACardPayloadCarriesNoOpinionAboutMarks() throws {
        let listing = try apiDecoder().decode(
            Listing.self,
            from: Data(Self.listingJSON(annotations: nil).utf8)
        )
        XCTAssertNil(listing.annotations)
    }

    func testADetailPayloadWithNoMarksSaysSoWithAnEmptyList() throws {
        let listing = try apiDecoder().decode(
            Listing.self,
            from: Data(Self.listingJSON(annotations: "[]").utf8)
        )
        XCTAssertEqual(listing.annotations?.count, 0)
    }

    func testADetailPayloadCarriesTheMarksItHas() throws {
        let marks = """
        [{"v": 1, "image_index": 0, "path": [[0.1, 0.1], [0.2, 0.2]], "note": "here"}]
        """
        let listing = try apiDecoder().decode(
            Listing.self,
            from: Data(Self.listingJSON(annotations: marks).utf8)
        )
        XCTAssertEqual(listing.annotations?.first?.note, "here")
    }

    private static func listingJSON(annotations: String?) -> String {
        let field = annotations.map { "\"annotations\": \($0)," } ?? ""
        return """
        {
          "id": "49e52179-1035-46f9-abe0-443d915d8c3b",
          "listing_number": 1041,
          "seller_id": "1a2b3c4d-0000-0000-0000-000000000000",
          "seller": null, "variant_id": null,
          "title": "Tudor Black Bay GMT", "brand": "Tudor", "model": "Black Bay",
          "reference_number": null, "seller_sku": null, "description": null,
          "price": "7200.00", "currency": "USD", "condition": null,
          "box_papers": null, "production_year": null, "status": "active",
          "review_status": null, "seller_status": "live", "review_events": null,
          "estimated_shipping": null, "metrics": null, "returns": null,
          "country_of_origin": null, "hts_code": null,
          \(field)
          "created_at": null, "updated_at": null,
          "images": ["/demo-watches/tudor-01.jpeg"]
        }
        """
    }
}

/// The booklet's own reading of the record.
final class PassportTests: XCTestCase {
    /// The server stores a service entry as one sentence, its own label
    /// included, because the web timeline reads it as prose. The booklet
    /// prints that label as a heading, so printing it inside the entry too
    /// would print it twice.
    func testAnOwnerEntryDropsTheServersLeadIn() throws {
        let passport = try decode(events: """
        [{"kind": "service_added",
          "summary": "Service record added: Watchfinder — full service, new gaskets",
          "occurred_at": "2025-04-02T10:00:00Z",
          "details": {"serviced_at": "2025-03-28", "provider": "Watchfinder"}}]
        """)
        let entry = try XCTUnwrap(passport.events.first)
        XCTAssertTrue(entry.isOwnerWritten)
        XCTAssertEqual(entry.ownerEntry, "Watchfinder — full service, new gaskets")
    }

    /// An entry with no lead-in on it is used whole rather than having its
    /// first words eaten by a prefix match that nearly fits.
    func testAnEntryWithoutTheLeadInIsPrintedWhole() throws {
        let passport = try decode(events: """
        [{"kind": "service_added", "summary": "Service record added by the owner.",
          "occurred_at": "2025-04-02T10:00:00Z", "details": {}}]
        """)
        XCTAssertEqual(passport.events.first?.ownerEntry, "Service record added by the owner.")
    }

    /// The date in the margin is when the watch was serviced, not when the
    /// owner got round to writing it down.
    /// A full timestamp still reads, so a record written before the column
    /// became a date keeps its own day rather than falling back to when it
    /// was filed.
    func testAServiceDateStillReadsWhenItArrivesAsAFullTimestamp() throws {
        let passport = try decode(events: """
        [{"kind": "service_added", "summary": "Service record added: Watchfinder",
          "occurred_at": "2026-01-01T10:00:00Z",
          "details": {"serviced_at": "2025-11-04T08:30:00.000Z", "provider": "Watchfinder"}}]
        """)
        let margin = try XCTUnwrap(passport.events.first?.marginDate)
        XCTAssertNotEqual(margin, passport.events.first?.occurredAt)
    }

    /// The server sends a calendar day here, not an instant. The client's
    /// ISO-8601 strategy throws on one, which would take the whole record
    /// down rather than one line's date — so the field is read as sent.
    func testTheMarginTakesTheServiceDateOverTheRecordingDate() throws {
        let passport = try decode(events: """
        [{"kind": "service_added", "summary": "Service record added: Watchfinder",
          "occurred_at": "2025-04-02T10:00:00Z",
          "details": {"serviced_at": "2025-03-28", "provider": "Watchfinder"}}]
        """)
        let margin = try XCTUnwrap(passport.events.first?.marginDate)
        XCTAssertEqual(
            margin.timeIntervalSince1970,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-03-28T00:00:00Z")).timeIntervalSince1970,
            accuracy: 1
        )
    }

    /// Everything Calibre states about the watch happened when it was
    /// recorded, and only the owner's entry carries a date of its own.
    func testCalibresOwnLinesAreNeitherHandwrittenNorRedated() throws {
        let passport = try decode(events: """
        [{"kind": "authenticated", "summary": "Authenticated at the Calibre authentication center.",
          "occurred_at": "2025-01-09T12:00:00Z",
          "details": {"grades": {"crystal": "Like New", "bezel": "Very Good", "clasp": null},
                      "box_papers": true, "report_pdf_url": "/media/reports/abc.pdf"}}]
        """)
        let event = try XCTUnwrap(passport.events.first)
        XCTAssertFalse(event.isOwnerWritten)
        XCTAssertEqual(event.marginDate, event.occurredAt)
        XCTAssertEqual(event.details?.boxPapers, true)
        XCTAssertEqual(
            event.details?.reportPdfUrl?.url?.absoluteString,
            "https://api.test/media/reports/abc.pdf"
        )
        // An ungraded part is not a grade, so it is left out rather than
        // shown empty.
        let grades = try XCTUnwrap(event.details?.grades)
        XCTAssertEqual(grades.rows.map(\.label), ["Crystal", "Bezel"])
    }

    func testTheCoverReadsOffTheRecordRatherThanAssemblingAName() throws {
        let passport = try decode(events: "[]", brand: "Tudor", model: "Black Bay GMT")
        XCTAssertEqual(passport.title, "Tudor Black Bay GMT")
        XCTAssertEqual(passport.subtitle, "Ref. 79830RB \u{00B7} 2021")
    }

    private func decode(
        events: String,
        brand: String = "Tudor",
        model: String = "Black Bay GMT"
    ) throws -> WatchPassport {
        let json = """
        {"public_code": "clb-7f3a2e", "brand": "\(brand)", "model": "\(model)",
         "reference": "79830RB", "production_year": 2021,
         "created_at": "2025-01-09T12:00:00Z",
         "events": \(events), "listing": null}
        """
        return try apiDecoder().decode(WatchPassport.self, from: Data(json.utf8))
    }
}

/// The line the seller sends with the parcel, and the line a dealer puts on
/// their storefront.
final class ByHandFieldTests: XCTestCase {
    func testTheShippedDeclarationCarriesThePackingNoteBack() throws {
        let json = """
        {"order_id": "1a2b3c4d-0000-0000-0000-000000000000",
         "seller_shipped_declared_at": "2025-06-01T09:00:00Z",
         "auto_cancel_grace_until": "2025-06-02T09:00:00Z",
         "packing_note": "Set it running before I boxed it — enjoy."}
        """
        let declaration = try apiDecoder().decode(FulfillmentShipped.self, from: Data(json.utf8))
        XCTAssertEqual(declaration.packingNote, "Set it running before I boxed it — enjoy.")
    }

    /// `status` is null — not a word — for a dealer who has never submitted
    /// one. Rendering "pending" there would put almost every dealer in a
    /// queue the server has not put them in.
    func testADealerWhoNeverWroteOneHasNoStatusAtAll() throws {
        let json = """
        {"bio": null, "status": null, "live": null, "submitted_at": null,
         "reviewed_at": null, "rejected_reason": null}
        """
        let state = try apiDecoder().decode(DealerBio.self, from: Data(json.utf8))
        XCTAssertNil(state.status)
        XCTAssertFalse(state.hasUnpublishedEdit)
        XCTAssertFalse(state.isAwaitingReview)
    }

    /// Mid-edit the two texts differ, and that is the point: the editor shows
    /// what was submitted, the storefront keeps what was approved.
    func testAnEditInReviewLeavesTheApprovedWordsLive() throws {
        let json = """
        {"bio": "Vintage Seiko, since 1998.", "status": "pending",
         "live": "Vintage Seiko out of Osaka.",
         "submitted_at": "2025-06-01T09:00:00Z", "reviewed_at": null,
         "rejected_reason": null}
        """
        let state = try apiDecoder().decode(DealerBio.self, from: Data(json.utf8))
        XCTAssertEqual(state.status, .pending)
        XCTAssertTrue(state.isAwaitingReview)
        XCTAssertTrue(state.hasUnpublishedEdit)
        XCTAssertNotEqual(state.bio, state.live)
    }

    func testARejectionCarriesTheReviewersOwnSentence() throws {
        let json = """
        {"bio": "Best prices anywhere!!!", "status": "rejected", "live": null,
         "submitted_at": "2025-06-01T09:00:00Z", "reviewed_at": "2025-06-01T11:00:00Z",
         "rejected_reason": "Claims about price need something behind them."}
        """
        let state = try apiDecoder().decode(DealerBio.self, from: Data(json.utf8))
        XCTAssertEqual(state.status, .rejected)
        XCTAssertEqual(state.rejectedReason, "Claims about price need something behind them.")
        XCTAssertTrue(state.hasUnpublishedEdit)
    }

    /// The vault renders the owner's own name for a watch differently from
    /// the catalog's name for it, so it has to be able to tell them apart.
    func testTheVaultKnowsWhoseWordsTheTitleIs() throws {
        let named = try decodeWatch(nickname: "\"The daily\"")
        XCTAssertTrue(named.isNicknamed)
        XCTAssertEqual(named.displayTitle, "The daily")

        let unnamed = try decodeWatch(nickname: "null")
        XCTAssertFalse(unnamed.isNicknamed)
        XCTAssertEqual(unnamed.displayTitle, "Tudor Black Bay")
    }

    private func decodeWatch(nickname: String) throws -> VaultWatch {
        let json = """
        {"id": "1a2b3c4d-0000-0000-0000-000000000000", "source": "manual",
         "authenticated": false, "order_id": null, "listing_id": null,
         "passport_code": null, "brand": "Tudor", "model": "Black Bay",
         "reference": null, "production_year": null, "nickname": \(nickname),
         "notes": null, "photo_url": null, "acquired_price": null,
         "acquired_date": null, "estimated_value": null, "estimated_at": null,
         "created_at": null}
        """
        return try apiDecoder().decode(VaultWatch.self, from: Data(json.utf8))
    }
}
