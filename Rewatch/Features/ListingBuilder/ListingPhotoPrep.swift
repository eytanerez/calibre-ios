import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A listing photo, brought down to what a listing can show before it leaves
/// the phone: the site's `prepareListingImage`, in ImageIO.
///
/// At most 2400 px on the longest side, re-encoded as a JPEG at quality 0.9.
/// The orientation is drawn into the pixels, so a portrait shot stays
/// portrait, and nothing of the original's metadata is copied: the GPS
/// position the camera wrote, the camera model and the capture time are all
/// gone. An iPhone original is 3 to 12 MB; this is well under 2 MB, which is
/// the difference between six photos going up in seconds and in minutes on a
/// phone connection. The server shrinks every photo to 2048 px anyway.
enum ListingPhotoPrep {
    static let maxEdge = 2400
    static let jpegQuality: CGFloat = 0.9

    enum Failure: LocalizedError {
        case unreadable
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "This photo couldn\u{2019}t be read. Try choosing it again."
            case .encodingFailed: "This photo couldn\u{2019}t be prepared for upload. Try another photo."
            }
        }
    }

    /// The size to draw at: unchanged within the edge, otherwise scaled to fit.
    static func scaledSize(width: Int, height: Int, maxEdge: Int = maxEdge) -> (width: Int, height: Int, resized: Bool) {
        let longest = max(width, height)
        guard longest > maxEdge, longest > 0 else { return (width, height, false) }
        let scale = Double(maxEdge) / Double(longest)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded())),
            true
        )
    }

    /// From the bytes Photos hands over (HEIC, JPEG, PNG, ProRAW previews).
    static func jpeg(from data: Data) throws -> Data {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw Failure.unreadable }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? Int) ?? maxEdge
        let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? Int) ?? maxEdge
        // Never asked to grow: the thumbnail is the original size or smaller.
        let edge = min(maxEdge, max(pixelWidth, pixelHeight))
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the EXIF orientation to the pixels.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { throw Failure.unreadable }
        return try encode(image)
    }

    /// From a camera capture, which arrives as a `UIImage` with an orientation
    /// flag rather than rotated pixels.
    static func jpeg(from image: UIImage) throws -> Data {
        let pixelWidth = Int((image.size.width * image.scale).rounded())
        let pixelHeight = Int((image.size.height * image.scale).rounded())
        let target = scaledSize(width: pixelWidth, height: pixelHeight)
        let size = CGSize(width: target.width, height: target.height)
        guard size.width >= 1, size.height >= 1 else { throw Failure.unreadable }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Drawing the UIImage applies its orientation.
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = drawn.cgImage else { throw Failure.encodingFailed }
        return try encode(cgImage)
    }

    /// An opaque sRGB JPEG with no metadata at all. A transparent PNG is laid
    /// on white, as the site's canvas does, rather than turning black.
    private static func encode(_ image: CGImage) throws -> Data {
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
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        guard let opaque = context.makeImage() else { throw Failure.encodingFailed }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        // Only the quality: no properties dictionary, so no EXIF, no GPS, no
        // TIFF block travels with the file.
        CGImageDestinationAddImage(destination, opaque, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else { throw Failure.encodingFailed }
        return output as Data
    }

    /// Writes a prepared photo into the builder's folder under a fresh name,
    /// so a replacement never overwrites a file an upload is still reading.
    static func store(_ jpeg: Data, in folder: URL, label: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(label)-\(UUID().uuidString.prefix(8)).jpg")
        try jpeg.write(to: url, options: .atomic)
        return url
    }
}
