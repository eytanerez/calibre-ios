import SwiftUI
import UIKit
import XCTest

@testable import CalibreDesign

/// Eytan, looking at a shelf of cards in the app:
///
/// > "app listing cards need to line up — right now a big brand or title or a
/// > dealer card make them not line up with each other and it does not look
/// > good"
///
/// and then, on the fix:
///
/// > "make the dealer mark on the right of the listing cards next to the price,
/// > not on top of it, in the consumer apps — this way everything stays lined
/// > up."
///
/// A screenshot of four similar cards proves nothing here — the bug only shows
/// on cards that *differ*. So these tests render the four cards that differ in
/// the ways that used to move the price (no reference; a brand long enough to
/// have wrapped; a verified dealer; all three at once) and measure where the
/// price actually landed, from the rendered accessibility geometry rather than
/// from the source.
final class ListingCardAlignmentTests: XCTestCase {
    /// A two-up grid at 390pt: 20pt margins, 12pt gutter.
    private static let cardWidth: CGFloat = (390 - 40 - 12) / 2

    private enum Variant: CaseIterable {
        /// Short brand, no reference, no dealer — the plainest card there is.
        case plain
        /// The longest brand on the marketplace. `.lineLimit(2)` used to let
        /// this one take a second line and drop its own price by ~15pt.
        case longBrand
        /// A verified dealer. The badge used to hold a row of its own.
        case dealer
        /// Long brand + reference + dealer, all at once.
        case everything

        var model: ListingCardModel {
            switch self {
            case .plain:
                .init(id: "plain", brand: "Rolex", year: "2019",
                      title: "Submariner Date", reference: nil,
                      priceText: "$12,400", condition: "Very Good",
                      watcherCount: 14, isVerifiedDealer: false)
            case .longBrand:
                .init(id: "long", brand: "Jaeger-LeCoultre", year: "2021",
                      title: "Reverso Tribute Duoface", reference: "Q3988482",
                      priceText: "$14,300", condition: "Like New",
                      watcherCount: 231, isVerifiedDealer: false)
            case .dealer:
                .init(id: "dealer", brand: "Omega", year: "2020",
                      title: "Speedmaster Professional", reference: nil,
                      priceText: "$4,950", condition: "Excellent",
                      watcherCount: 8, isVerifiedDealer: true)
            case .everything:
                .init(id: "all", brand: "A. Lange & Söhne", year: "2018",
                      title: "Datograph Up/Down", reference: "405.035",
                      priceText: "$94,500", condition: "Excellent",
                      watcherCount: 41, isVerifiedDealer: true)
            }
        }
    }

    /// The whole row of four, as one image.
    @MainActor
    private func rowImage(_ scheme: ColorScheme) -> UIImage? {
        let row = HStack(alignment: .top, spacing: 12) {
            ForEach(Array(Variant.allCases.enumerated()), id: \.offset) { _, variant in
                ListingCard(model: variant.model) { _ in
                    Rectangle().fill(Color.calibre.secondary)
                }
                .frame(width: Self.cardWidth)
            }
        }
        .padding(20)
        .background(Color.calibre.background)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// One card, alone, on a fixed canvas so that a y read off one image means
    /// the same thing as a y read off the next.
    @MainActor
    private func cardImage(_ variant: Variant) -> UIImage? {
        let card = ListingCard(model: variant.model) { _ in
            Rectangle().fill(Color.calibre.secondary)
        }
        .frame(width: Self.cardWidth)
        .frame(width: Self.cardWidth, height: 320, alignment: .top)
        .background(Color.calibre.background)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = Self.pixelScale
        return renderer.uiImage
    }

    private static let pixelScale: CGFloat = 2

    /// Rows of the image that carry ink, within a horizontal band. Reads the
    /// drawn pixels — not the view tree, not the source — because what has to
    /// be equal is where the price was actually painted.
    private func inkRows(_ image: UIImage, xFrom: Int, xTo: Int, yFrom: Int) -> [Int] {
        guard let cgImage = image.cgImage else { return [] }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // The page ground is the lightest thing in the frame; ink is anything
        // meaningfully darker than it. Sampled rather than assumed, so the
        // threshold survives a change to the background token.
        let ground = Int(pixels[(height / 2) * width + (width - 2)])
        let threshold = UInt8(max(0, ground - 60))

        var rows: [Int] = []
        for y in yFrom..<height {
            var inked = 0
            for x in xFrom..<min(xTo, width) where pixels[y * width + x] < threshold {
                inked += 1
            }
            if inked >= 2 { rows.append(y) }
        }
        return rows
    }

    /// THE test. Four cards that differ in every way that used to move the
    /// price; one price, painted at one height.
    @MainActor
    func testThePriceLandsAtTheSameHeightOnCardsThatDiffer() {
        CalibreFonts.register()
        let scale = Int(Self.pixelScale)
        // Below the square photo, and only the leading half of the card: the
        // price lives at the leading edge and the dealer mark at the trailing
        // one, so this band sees the price and nothing else.
        let belowPhoto = Int(Self.cardWidth) * scale + 8 * scale
        let priceColumn = (0, Int(Self.cardWidth * 0.55) * scale)

        var bands: [(Variant, Int, Int)] = []
        for variant in Variant.allCases {
            guard let image = cardImage(variant) else {
                XCTFail("\(variant) did not render")
                continue
            }
            let rows = inkRows(image, xFrom: priceColumn.0, xTo: priceColumn.1, yFrom: belowPhoto)
            // An empty read would make every comparison below vacuously true.
            XCTAssertFalse(rows.isEmpty, "\(variant) drew no text under the photo — nothing was measured")
            guard let bottom = rows.last else { continue }
            // Walk up the last contiguous run: that is the price, the lowest
            // thing on a card with no reason line.
            var top = bottom
            var index = rows.count - 1
            while index > 0, rows[index - 1] >= rows[index] - 1 {
                index -= 1
                top = rows[index]
            }
            bands.append((variant, top, bottom))
        }

        XCTAssertEqual(bands.count, Variant.allCases.count)
        print("PRICE-BAND " + bands.map { "\($0.0)=\($0.1)...\($0.2)" }.joined(separator: " "))
        guard let reference = bands.first else { return XCTFail("nothing measured") }
        for band in bands {
            XCTAssertEqual(
                band.1, reference.1,
                "\(band.0)'s price is painted \(band.1 - reference.1) device pixels from \(reference.0)'s — the cards do not line up"
            )
            XCTAssertEqual(band.2, reference.2, "\(band.0)'s price bottom differs from \(reference.0)'s")
        }
    }

    /// The corollary: if the price is level and the reason line is absent, the
    /// whole card is the same height, so a grid of them is a grid and not a
    /// staircase. Cross-checks the measurement above from the other side.
    @MainActor
    func testCardsThatDifferAreTheSameHeight() {
        CalibreFonts.register()
        let heights = Variant.allCases.map { variant -> CGFloat in
            let host = UIHostingController(rootView: ListingCard(model: variant.model) { _ in
                Rectangle().fill(Color.calibre.secondary)
            })
            return host.sizeThatFits(in: CGSize(width: Self.cardWidth, height: .greatestFiniteMagnitude)).height
        }
        print("CARD-HEIGHTS " + zip(Variant.allCases, heights).map { "\($0)=\($1)" }.joined(separator: " "))
        for height in heights {
            XCTAssertEqual(height, heights[0], accuracy: 0.5)
        }
    }

    /// §0.6: a brand name may not be clipped. The brand is now held to one
    /// line, so `.minimumScaleFactor(0.65)` is the only thing standing between
    /// "Jaeger-LeCoultre" and an ellipsis. This measures the two worst real
    /// brands in the Eyebrow's own face against the width the card actually
    /// gives them, at the two-up grid size.
    @MainActor
    func testTheWorstBrandsFitOnOneLineWithoutClipping() {
        CalibreFonts.register()
        guard let eyebrow = UIFont(name: CalibreFonts.Name.sansMedium, size: 11) else {
            return XCTFail("Geist-Medium missing — the measurement below would be against the system font")
        }
        let tracking = CalibreType.eyebrowTracking

        func width(_ text: String) -> CGFloat {
            (text.uppercased() as NSString)
                .size(withAttributes: [.font: eyebrow, .kern: tracking])
                .width
        }

        // The card's text column, minus what the year row spends before the
        // brand gets what is left: HStack spacing on both sides of the Spacer
        // plus the Spacer's own minimum, then the year itself.
        let column = Self.cardWidth - 4
        let gaps = Space.xs * 3
        let year = width("2021")
        let available = column - gaps - year

        for brand in ["Jaeger-LeCoultre", "A. Lange & Söhne"] {
            let full = width(brand)
            // Tracking is a fixed point value and does not shrink with the
            // font, so only the glyphs take the 0.65. The conservative figure.
            let glyphs = full - tracking * CGFloat(brand.count)
            let smallest = glyphs * 0.65 + tracking * CGFloat(brand.count)
            print("BRAND \(brand) full=\(full) at0.65=\(smallest) available=\(available)")
            XCTAssertLessThanOrEqual(
                smallest, available,
                "\"\(brand)\" cannot fit one line at the 0.65 floor in \(available)pt — it would clip, and §0.6 forbids that"
            )
        }
    }

    /// Writes the four-card row out as a PNG so the render can be looked at,
    /// not just asserted about (§0.3). The path is printed; the file lands in
    /// the simulator's temp directory.
    @MainActor
    func testWriteFourCardSnapshot() {
        CalibreFonts.register()
        for (scheme, name) in [(ColorScheme.light, "listing-cards-light.png"), (.dark, "listing-cards-dark.png")] {
            guard let image = rowImage(scheme), let data = image.pngData() else {
                return XCTFail("the row did not render")
            }
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
            try? data.write(to: url)
            print("SNAPSHOT \(url.path)")
        }
    }
}
