import Foundation
import XCTest
@testable import CalibreKit

final class MediaURLTests: XCTestCase {
    func testRelativePathResolvesAgainstOrigin() throws {
        let media = try apiDecoder(origin: "http://localhost:8000").decode(
            MediaURL.self,
            from: Data("\"/media/listing_images/abc/photo.jpg\"".utf8)
        )
        XCTAssertEqual(media.url?.absoluteString, "http://localhost:8000/media/listing_images/abc/photo.jpg")
    }

    func testAbsoluteURLPassesThroughUntouched() throws {
        let media = try apiDecoder(origin: "http://localhost:8000").decode(
            MediaURL.self,
            from: Data("\"https://picsum.photos/seed/watch93a/900/900\"".utf8)
        )
        XCTAssertEqual(media.url?.absoluteString, "https://picsum.photos/seed/watch93a/900/900")
    }

    func testRelativePathWithoutOriginStaysRelative() throws {
        let decoder = JSONDecoder() // no apiOrigin in userInfo
        let media = try decoder.decode(MediaURL.self, from: Data("\"/media/x.jpg\"".utf8))
        XCTAssertEqual(media.url?.absoluteString, "/media/x.jpg")
    }
}

final class APIDecimalTests: XCTestCase {
    func testDecodesStringMoney() throws {
        let value = try JSONDecoder().decode(APIDecimal.self, from: Data("\"12400.50\"".utf8))
        XCTAssertEqual(value.value, Decimal(string: "12400.50"))
    }

    func testDecodesNumberMoney() throws {
        let value = try JSONDecoder().decode(APIDecimal.self, from: Data("21024.54".utf8))
        XCTAssertEqual(value.value, Decimal(string: "21024.54"), "number path must not pick up float drift")
    }

    func testDecodesIntegerNumber() throws {
        let value = try JSONDecoder().decode(APIDecimal.self, from: Data("2423001".utf8))
        XCTAssertEqual(value.value, Decimal(2_423_001))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try JSONDecoder().decode(APIDecimal.self, from: Data("\"not-money\"".utf8)))
    }
}

final class PriceFormatterTests: XCTestCase {
    func testWholeDollarsDropCents() {
        XCTAssertEqual(PriceFormatter.format(Decimal(12400)), "$12,400")
    }

    func testCentsShowWhenPresent() {
        XCTAssertEqual(PriceFormatter.format(Decimal(string: "12400.50")!), "$12,400.50")
    }

    func testWholeDecimalStringDropsCents() {
        XCTAssertEqual(PriceFormatter.format(Decimal(string: "4400.00")!), "$4,400")
    }
}

final class TokenStoreTests: XCTestCase {
    func testMemoryStoreRoundTrip() {
        let store = MemoryTokenStore()
        XCTAssertNil(store.load())

        let pair = TokenPair(accessToken: "access-123", refreshToken: "refresh-456")
        store.save(pair)
        XCTAssertEqual(store.load(), pair)

        let rotated = TokenPair(accessToken: "access-789", refreshToken: "refresh-456")
        store.save(rotated)
        XCTAssertEqual(store.load(), rotated)

        store.clear()
        XCTAssertNil(store.load())
    }
}

final class MultipartFormTests: XCTestCase {
    /// Byte-exact multipart layout: boundary framing, CRLF discipline, and an
    /// explicit Content-Type on every file part (HEIC must never be sent as
    /// octet-stream).
    func testEncodingIsByteExact() {
        var form = MultipartForm()
        form.addField("category", value: "front")
        form.addFile("file", filename: "IMG_0001.heic", contentType: "image/heic", data: Data([0xDE, 0xAD]))
        form.addFile("file2", filename: "IMG_0002.jpg", contentType: "image/jpeg", data: Data("JPEGDATA".utf8))

        let boundary = form.boundary
        var expected = Data()
        expected.append(Data("--\(boundary)\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"category\"\r\n".utf8))
        expected.append(Data("\r\n".utf8))
        expected.append(Data("front".utf8))
        expected.append(Data("\r\n".utf8))
        expected.append(Data("--\(boundary)\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"IMG_0001.heic\"\r\n".utf8))
        expected.append(Data("Content-Type: image/heic\r\n".utf8))
        expected.append(Data("\r\n".utf8))
        expected.append(Data([0xDE, 0xAD]))
        expected.append(Data("\r\n".utf8))
        expected.append(Data("--\(boundary)\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"file2\"; filename=\"IMG_0002.jpg\"\r\n".utf8))
        expected.append(Data("Content-Type: image/jpeg\r\n".utf8))
        expected.append(Data("\r\n".utf8))
        expected.append(Data("JPEGDATA".utf8))
        expected.append(Data("\r\n".utf8))
        expected.append(Data("--\(boundary)--\r\n".utf8))

        XCTAssertEqual(form.encoded(), expected)
    }

    func testUploadQueueContentTypeMapping() {
        XCTAssertEqual(UploadQueue.contentType(for: URL(fileURLWithPath: "/x/a.HEIC")), "image/heic")
        XCTAssertEqual(UploadQueue.contentType(for: URL(fileURLWithPath: "/x/a.heif")), "image/heic")
        XCTAssertEqual(UploadQueue.contentType(for: URL(fileURLWithPath: "/x/a.jpg")), "image/jpeg")
        XCTAssertEqual(UploadQueue.contentType(for: URL(fileURLWithPath: "/x/a.jpeg")), "image/jpeg")
        XCTAssertEqual(UploadQueue.contentType(for: URL(fileURLWithPath: "/x/a.png")), "image/png")
    }
}

final class LocalSignalsTests: XCTestCase {
    @MainActor
    func testRecentlyViewedCapsAtFiftyMostRecentFirst() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "local-signals-test-\(UUID().uuidString)")
        let signals = LocalSignals(directory: directory)

        for index in 0..<60 {
            signals.recordViewed("listing-\(index)")
        }
        XCTAssertEqual(signals.recentlyViewed.count, 50)
        XCTAssertEqual(signals.recentlyViewed.first, "listing-59")

        // Re-viewing moves to the front without duplicating.
        signals.recordViewed("listing-30")
        XCTAssertEqual(signals.recentlyViewed.first, "listing-30")
        XCTAssertEqual(signals.recentlyViewed.filter { $0 == "listing-30" }.count, 1)

        // Persists across instances.
        let reloaded = LocalSignals(directory: directory)
        XCTAssertEqual(reloaded.recentlyViewed, signals.recentlyViewed)
    }

    @MainActor
    func testDiscoverPassListCapsAtFiveHundred() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "local-signals-test-\(UUID().uuidString)")
        let signals = LocalSignals(directory: directory)

        for index in 0..<510 {
            signals.recordDiscoverPass("listing-\(index)")
        }
        XCTAssertEqual(signals.discoverPassed.count, 500)
        XCTAssertFalse(signals.hasPassed("listing-0"), "oldest passes fall off")
        XCTAssertTrue(signals.hasPassed("listing-509"))
    }
}
