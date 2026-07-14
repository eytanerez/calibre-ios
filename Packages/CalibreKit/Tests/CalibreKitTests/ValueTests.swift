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

    func testLaptopMediaURLRebasesToDeviceReachableAPIOrigin() throws {
        let media = try apiDecoder(origin: "https://dev.api.buycalibre.com").decode(
            MediaURL.self,
            from: Data("\"http://localhost:5173/media/listing_images/watch/photo.jpg?version=2\"".utf8)
        )
        XCTAssertEqual(
            media.url?.absoluteString,
            "https://dev.api.buycalibre.com/media/listing_images/watch/photo.jpg?version=2"
        )
    }

    func testInternalHTTPSMediaURLRebasesToAPIOrigin() throws {
        let media = try apiDecoder(origin: "https://dev.api.buycalibre.com").decode(
            MediaURL.self,
            from: Data("\"https://backend.internal/media/listing_images/watch/photo.jpg\"".utf8)
        )
        XCTAssertEqual(
            media.url?.absoluteString,
            "https://dev.api.buycalibre.com/media/listing_images/watch/photo.jpg"
        )
    }

    func testPublicHTTPSMediaURLPassesThroughUntouched() throws {
        let media = try apiDecoder(origin: "https://dev.api.buycalibre.com").decode(
            MediaURL.self,
            from: Data("\"https://images.buycalibre.com/media/listing_images/watch/photo.jpg\"".utf8)
        )
        XCTAssertEqual(
            media.url?.absoluteString,
            "https://images.buycalibre.com/media/listing_images/watch/photo.jpg"
        )
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

final class InputValidationTests: XCTestCase {
    func testBlankAndWhitespaceAreNotContent() {
        XCTAssertFalse(InputValidation.isNonBlank(""))
        XCTAssertFalse(InputValidation.isNonBlank(" \n\t "))
        XCTAssertTrue(InputValidation.isNonBlank("  Rolex  "))
    }

    func testEmailRejectsIncompleteWhitespaceAndMalformedHosts() {
        for email in [
            "", "   ", "buyer", "buyer@", "@example.com", "buyer@example",
            "buyer @example.com", "buyer@example..com", ".buyer@example.com",
            "buyer.@example.com", "buyer@@example.com", "buyer@-example.com",
        ] {
            XCTAssertFalse(InputValidation.isValidEmail(email), email)
        }
        XCTAssertTrue(InputValidation.isValidEmail(" buyer+ios@example.co.uk "))
    }

    func testPhoneUsesE164BoundariesAndRejectsLetters() {
        XCTAssertFalse(InputValidation.isValidPhone("123456"))
        XCTAssertTrue(InputValidation.isValidPhone("+1 (202) 555-0143"))
        XCTAssertTrue(InputValidation.isValidPhone(String(repeating: "1", count: 15)))
        XCTAssertFalse(InputValidation.isValidPhone(String(repeating: "1", count: 16)))
        XCTAssertFalse(InputValidation.isValidPhone("202-CALIBRE"))
        XCTAssertTrue(InputValidation.isValidPhone(" ", required: false))
    }

    func testCountryCodeRequiresTwoASCIILetters() {
        XCTAssertTrue(InputValidation.isISO2CountryCode(" us "))
        XCTAssertFalse(InputValidation.isISO2CountryCode("U"))
        XCTAssertFalse(InputValidation.isISO2CountryCode("USA"))
        XCTAssertFalse(InputValidation.isISO2CountryCode("1S"))
        XCTAssertFalse(InputValidation.isISO2CountryCode("éS"))
    }

    func testPositiveMoneyRejectsZeroNegativeGarbageAndExcessPrecision() {
        XCTAssertEqual(InputValidation.positiveMoney(" $12,400.50 "), Decimal(string: "12400.50"))
        XCTAssertEqual(InputValidation.positiveMoney("0.01"), Decimal(string: "0.01"))
        for value in ["", "0", "-1", "+1", "1e3", "1.2.3", "12.345", "twelve"] {
            XCTAssertNil(InputValidation.positiveMoney(value), value)
        }
    }

    func testProductionYearBoundaries() {
        XCTAssertEqual(InputValidation.productionYear("1600", currentYear: 2026), 1600)
        XCTAssertEqual(InputValidation.productionYear(" 2027 ", currentYear: 2026), 2027)
        for value in ["", "999", "1599", "2028", "20A6", "0000"] {
            XCTAssertNil(InputValidation.productionYear(value, currentYear: 2026), value)
        }
    }

    func testPasswordRulesMatchRegistrationAndReset() {
        XCTAssertTrue(InputValidation.passwordMeetsRules("Calibre1"))
        XCTAssertFalse(InputValidation.passwordMeetsRules("calibre1"))
        XCTAssertFalse(InputValidation.passwordMeetsRules("Calibree"))
        XCTAssertFalse(InputValidation.passwordMeetsRules("Cal1"))
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
