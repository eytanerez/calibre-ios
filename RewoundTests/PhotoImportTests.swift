import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Rewound

final class PhotoImportTests: XCTestCase {
    @MainActor
    func testRapidReplacementUsesDistinctJPEGFiles() throws {
        let image = try XCTUnwrap(PhotoImport.decode(encodedImage(width: 96, height: 48, type: .png)))
        let listingID = "photo-import-test-\(UUID().uuidString)"
        var files: [URL] = []
        defer {
            for file in files { try? FileManager.default.removeItem(at: file) }
            if let directory = files.first?.deletingLastPathComponent(),
               (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let first = try XCTUnwrap(PhotoPipeline.store(image, listingID: listingID, label: "dial"))
        files.append(first)
        let replacement = try XCTUnwrap(PhotoPipeline.store(image, listingID: listingID, label: "dial"))
        files.append(replacement)

        XCTAssertNotEqual(first, replacement, "A replacement must not overwrite a file still being uploaded")
        for file in files {
            XCTAssertEqual(file.pathExtension, "jpg")
            let stored = try source(Data(contentsOf: file))
            XCTAssertEqual(CGImageSourceGetType(stored) as String?, UTType.jpeg.identifier)
        }
    }

    func testRealHEICBecomesJPEGWithItsOriginalAspectRatio() throws {
        let input = try XCTUnwrap(Data(base64Encoded: Self.heicFixture))
        let source = try source(input)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.heic.identifier)

        let output = try PhotoImport.jpegData(input)

        let result = try self.source(output)
        XCTAssertEqual(CGImageSourceGetType(result) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(result, 0, nil))
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 8)
        XCTAssertNotNil(PhotoImport.decode(input), "Listing previews must decode the same HEIC bytes as Vault uploads")
    }

    func testLargeCameraPhotoIsDownsampledBeforeUpload() throws {
        let input = try encodedImage(width: 4800, height: 3200, type: .jpeg)

        let output = try PhotoImport.jpegData(input)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source(output), 0, nil))

        XCTAssertEqual(image.width, 2048)
        XCTAssertLessThanOrEqual(image.height, 1366)
        XCTAssertGreaterThanOrEqual(image.height, 1365)
        XCTAssertLessThan(output.count, 25 * 1024 * 1024)
        let preview = try XCTUnwrap(PhotoImport.decode(input)?.cgImage)
        XCTAssertEqual(preview.width, image.width)
        XCTAssertEqual(preview.height, image.height)
    }

    func testOrientationIsAppliedOnceAndLocationMetadataIsRemoved() throws {
        let input = try encodedImage(width: 96, height: 48, type: .jpeg, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 40.1,
                kCGImagePropertyGPSLatitudeRef: "N",
            ],
        ])

        let output = try PhotoImport.jpegData(input)
        let result = try source(output)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(result, 0, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(result, 0, nil) as? [CFString: Any])

        XCTAssertEqual(image.width, 48)
        XCTAssertEqual(image.height, 96)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? Int) ?? 1, 1)
        let preview = try XCTUnwrap(PhotoImport.decode(input))
        XCTAssertEqual(preview.imageOrientation, .up)
        XCTAssertEqual(preview.cgImage?.width, 48)
        XCTAssertEqual(preview.cgImage?.height, 96)
    }

    func testTransparentPNGHasWhiteBackgroundInJPEG() throws {
        let input = try encodedImage(width: 8, height: 8, type: .png, transparent: true)
        let output = try PhotoImport.jpegData(input)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source(output), 0, nil))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)

        XCTAssertGreaterThan(pixel[0], 248)
        XCTAssertGreaterThan(pixel[1], 248)
        XCTAssertGreaterThan(pixel[2], 248)
    }

    func testUnreadableSelectionsProduceFailureInsteadOfAnEmptyUpload() {
        for input in [Data(), Data("not an image".utf8)] {
            XCTAssertThrowsError(try PhotoImport.jpegData(input)) { error in
                XCTAssertTrue(error is PhotoImport.Failure)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            XCTAssertNil(PhotoImport.decode(input))
        }
    }

    private func source(_ data: Data) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    }

    private func encodedImage(
        width: Int,
        height: Int,
        type: UTType,
        transparent: Bool = false,
        properties: [CFString: Any] = [:]
    ) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if !transparent {
            context.setFillColor(CGColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // Generated with pillow-heif from a 16×8 solid-color image. Real HEVC
    // bytes make this a decode regression even on simulators with no encoder.
    private static let heicFixture = "AAAAHGZ0eXBoZWljAAAAAG1pZjFoZWljbWlhZgAAAXxtZXRhAAAAAAAAACFoZGxyAAAAAAAAAABwaWN0AAAAAAAAAAAAAAAAAAAAACJpbG9jAAAAAERAAAEAAQAAAAABoAABAAAAAAAAADYAAAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAAAA5waXRtAAAAAAABAAAA/GlwcnAAAADcaXBjbwAAAHVodmNDAQNwAAAAAAAAAAAAHvAA/P34+AAADwNgAAEAGEABDAH//wNwAAADAJAAAAMAAAMAHroCQGEAAQApQgEBA3AAAAMAkAAAAwAAAwAeoCCBBZbqrprm4CGgwIAAAAyAAAADAIRiAAEABkQBwXPBiQAAABNjb2xybmNseAABAA0ABoAAAAAUaXNwZQAAAAAAAABAAAAAQAAAAChjbGFwAAAAEAAAAAEAAAAIAAAAAf///9AAAAAC////yAAAAAIAAAAQcGl4aQAAAAADCAgIAAAAGGlwbWEAAAAAAAAAAQABBYECAwWEAAAAPm1kYXQAAAAyKAGvBPIWhzRxZNLf/DD///70u7L9VQASbVCOz9BSxGAmv3XroGTEzROpbNAoK6inXqY="
}
