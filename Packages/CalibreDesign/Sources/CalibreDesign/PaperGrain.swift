import SwiftUI
import UIKit

public extension View {
    /// The sanctioned page ground: the warm background token with its paper
    /// grain laid over it. Use this on a screen's root instead of
    /// `.background(Color.calibre.background)`; anything smaller than a screen
    /// takes the plain token.
    ///
    /// The grain is only reachable through here on purpose. It belongs to the
    /// page and nothing else — put it on a card and the card stops reading as
    /// something resting on the page, put it under text and the text loses its
    /// edges. Routing it through the page background is what keeps it there.
    func calibrePageBackground() -> some View {
        background {
            Color.calibre.background
                .overlay { PaperGrain() }
                .ignoresSafeArea()
        }
    }
}

/// A seamless tile at a whisper of opacity, so a flat fill reads as stock
/// rather than as screen. Deliberately not public — see `calibrePageBackground`.
struct PaperGrain: View {
    @Environment(\.displayScale) private var displayScale

    /// Enough to break the flatness, not enough to read as noise.
    private static let opacity: Double = 0.035

    var body: some View {
        Image(uiImage: Self.tile(at: displayScale))
            .resizable(resizingMode: .tile)
            .opacity(Self.opacity)
            .allowsHitTesting(false)
            // Texture, not content. Without this VoiceOver stops on an
            // unnamed image on the ground of every screen in the app.
            .accessibilityHidden(true)
    }

    /// One tile pixel to one device pixel. Laid out at its nominal point size
    /// the grain is magnified by the screen's own scale and stops reading as
    /// paper — it becomes soft mottling with a repeat you can find. Re-tagging
    /// the scale is only a relabel; the pixels are the shipped pixels.
    private static func tile(at scale: CGFloat) -> UIImage {
        guard let pixels = source.cgImage else { return source }
        return UIImage(cgImage: pixels, scale: scale, orientation: .up)
    }

    /// Loaded from the bundle the way the fonts are — the tile is shipped as a
    /// file, not an asset catalog entry, because the same bytes ship to web and
    /// Android and a catalog would re-encode them.
    private static let source: UIImage = {
        guard let url = Bundle.module.url(forResource: "paper-grain", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            assertionFailure("CalibreDesign paper-grain resource missing from bundle")
            return UIImage()
        }
        return image
    }()
}

#Preview("Paper grain — light") {
    VStack(alignment: .leading, spacing: Space.l) {
        Text("Submariner Date").font(CalibreType.title)
        Text("The grain sits on the page. The card sits on the grain.")
            .font(CalibreType.body)
        Text("Wore it every day for six years.")
            .font(CalibreType.hand)
            .foregroundStyle(Color.calibre.mutedForeground)
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
    .padding(Space.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .calibrePageBackground()
}

#Preview("Paper grain — dark") {
    Color.clear
        .calibrePageBackground()
        .preferredColorScheme(.dark)
}
