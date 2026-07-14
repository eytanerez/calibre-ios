import CalibreDesign
import CalibreKit
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Capture → upload-ready file: normalize orientation, downscale the longest
/// side to 2048px, encode efficiently (JPEG fallback), write into the
/// listing's photo folder.
enum PhotoPipeline {
    // 2048 px preserves useful detail for the full-screen gallery while
    // avoiding multi-megabyte originals on every cold card/image request.
    static let maxDimension: CGFloat = 2048

    @MainActor
    static func store(_ image: UIImage, listingID: String, label: String) -> URL? {
        let scaled = downscale(image)
        let directory = DraftStore.photosDirectory(listingID: listingID)
        let stamp = Int(Date.now.timeIntervalSince1970)

        let heicURL = directory.appending(path: "\(label)-\(stamp).heic")
        if write(scaled, to: heicURL, type: UTType.heic, quality: 0.72) {
            return heicURL
        }
        // Simulators (and some devices) have no HEIC encoder — fall back.
        let jpegURL = directory.appending(path: "\(label)-\(stamp).jpg")
        if write(scaled, to: jpegURL, type: UTType.jpeg, quality: 0.76) {
            return jpegURL
        }
        return nil
    }

    /// Re-render at target size — also bakes in EXIF orientation.
    private static func downscale(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = min(1, maxDimension / max(longest * image.scale, 1)) * image.scale
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        guard target.width >= 1, target.height >= 1 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func write(_ image: UIImage, to url: URL, type: UTType, quality: CGFloat) -> Bool {
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, type.identifier as CFString, 1, nil
              ) else {
            return false
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    #if DEBUG
    /// Simulator/testing helper: six generated placeholder shots, one per
    /// required category — solid warm fields with a big label.
    @MainActor
    static func sampleImages() -> [(ListingImageCategory, UIImage)] {
        let palette: [UIColor] = [
            UIColor(red: 0.49, green: 0.33, blue: 0.25, alpha: 1),
            UIColor(red: 0.62, green: 0.48, blue: 0.36, alpha: 1),
            UIColor(red: 0.35, green: 0.28, blue: 0.22, alpha: 1),
            UIColor(red: 0.72, green: 0.60, blue: 0.47, alpha: 1),
            UIColor(red: 0.42, green: 0.36, blue: 0.30, alpha: 1),
            UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1),
        ]
        return ListingImageCategory.allCases.enumerated().map { index, category in
            (category, placeholder(text: category.label, background: palette[index % palette.count]))
        }
    }

    @MainActor
    private static func placeholder(text: String, background: UIColor) -> UIImage {
        let side: CGFloat = 1400
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))

            // A quiet watch-dial circle so the frame reads as a photo.
            let circle = UIBezierPath(
                ovalIn: CGRect(x: side * 0.2, y: side * 0.16, width: side * 0.6, height: side * 0.6)
            )
            UIColor(white: 1, alpha: 0.18).setFill()
            circle.fill()
            UIColor(white: 1, alpha: 0.5).setStroke()
            circle.lineWidth = 8
            circle.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 96, weight: .semibold),
                .foregroundColor: UIColor(white: 1, alpha: 0.92),
                .paragraphStyle: paragraph,
            ]
            (text as NSString).draw(
                in: CGRect(x: 0, y: side * 0.82, width: side, height: 120),
                withAttributes: attributes
            )
        }
    }
    #endif
}
