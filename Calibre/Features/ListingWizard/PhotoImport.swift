import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Decodes the bytes Photos actually supplies, without guessing their format
/// from its list of available representations or allocating a full-size image.
enum PhotoImport {
    static let maximumPixelDimension = 2048

    enum Failure: LocalizedError {
        case unreadable
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "This photo couldn’t be read. Try choosing it again."
            case .encodingFailed:
                "This photo couldn’t be prepared for upload. Try choosing another photo."
            }
        }
    }

    static func decode(_ data: Data) -> UIImage? {
        guard let image = try? thumbnail(data) else { return nil }
        return UIImage(cgImage: image)
    }

    /// JPEG is accepted by every photo endpoint and keeps large HEIC/ProRAW
    /// originals below the upload cap. Orientation is already baked into the
    /// pixels and location/camera metadata is not copied into the upload.
    static func jpegData(_ data: Data) throws -> Data {
        let image = try thumbnail(data)
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure.encodingFailed }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let opaque = context.makeImage() else { throw Failure.encodingFailed }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw Failure.encodingFailed }
        CGImageDestinationAddImage(destination, opaque, [
            kCGImageDestinationLossyCompressionQuality: 0.82,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else {
            throw Failure.encodingFailed
        }
        return output as Data
    }

    private static func thumbnail(_ data: Data) throws -> CGImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                CGImageSourceGetPrimaryImageIndex(source),
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
              ) else { throw Failure.unreadable }
        return image
    }
}
