import RewoundDesign
import RewoundKit
import ImageIO
import SwiftUI
import UIKit

/// Where a private image has got to. Shaped like `LazyImage`'s state on
/// purpose — every other picture in the app is drawn through that, and a
/// second vocabulary for the same three outcomes would make the two read as
/// different things.
enum PrivateImagePhase {
    case loading
    case loaded(Image)
    case failed
}

/// Draws an object Rewound serves behind the member's own session.
///
/// Nuke cannot be pointed at these: the address needs a bearer token, and the
/// token is fetched asynchronously from the session that may be mid-refresh.
/// So the bytes come from `PrivateMediaLoader`, which holds the credential and
/// refuses to send it anywhere but Rewound's own origin, and the decode
/// happens here.
///
/// The decode is a thumbnail, not the whole picture. Eight photographs of one
/// watch, taken on the phone that is now drawing them, is upwards of a hundred
/// megapixels if each one is decoded at full size into a tile the width of a
/// finger. `CGImageSourceCreateThumbnailAtIndex` reads them down on the way in
/// instead, at the size actually being drawn.
struct PrivateImage<Content: View>: View {
    let url: URL
    /// The drawn side in points. The caller measures it; the decode is sized
    /// from it, so the same photograph in a card and in a hero are two
    /// entries rather than one oversized one shared between them.
    let side: CGFloat
    @ViewBuilder let content: (PrivateImagePhase) -> Content

    @Environment(AppServices.self) private var services
    @Environment(\.displayScale) private var displayScale
    @State private var phase: PrivateImagePhase = .loading

    var body: some View {
        content(phase)
            .task(id: TaskKey(url: url, pixels: pixels)) { await load() }
    }

    private var pixels: CGFloat { max(1, (side * displayScale).rounded()) }

    /// URL and size together, so a frame that grows re-decodes rather than
    /// stretching a thumbnail cut for a smaller tile.
    private struct TaskKey: Equatable {
        let url: URL
        let pixels: CGFloat
    }

    private func load() async {
        let pixelSide = Int(pixels)
        if let hit = PrivateImageCache.shared.image(for: url, pixels: pixelSide) {
            phase = .loaded(Image(uiImage: hit))
            return
        }
        phase = .loading
        do {
            let data = try await services.privateMedia.data(for: url)
            guard let decoded = await Self.thumbnail(from: data, pixels: pixelSide) else {
                phase = .failed
                return
            }
            PrivateImageCache.shared.store(decoded, for: url, pixels: pixelSide)
            phase = .loaded(Image(uiImage: decoded))
        } catch {
            phase = .failed
        }
    }

    private static func thumbnail(from data: Data, pixels: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                // A format ImageIO will not thumbnail can still decode whole.
                return UIImage(data: data)
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

/// Decoded private images, in this process only.
///
/// `NSCache` rather than a dictionary so the system can take the memory back
/// under pressure: these are pictures, and a photograph that has to be decoded
/// again is a moment's wait, while a photograph that cannot be evicted is a
/// crash. The bytes behind them are held by `PrivateMediaLoader`, and both are
/// dropped when the session ends.
final class PrivateImageCache: @unchecked Sendable {
    static let shared = PrivateImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(for url: URL, pixels: Int) -> UIImage? {
        cache.object(forKey: Self.key(url, pixels))
    }

    func store(_ image: UIImage, for url: URL, pixels: Int) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: Self.key(url, pixels), cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
    }

    private static func key(_ url: URL, _ pixels: Int) -> NSString {
        "\(url.absoluteString)|\(pixels)" as NSString
    }
}
