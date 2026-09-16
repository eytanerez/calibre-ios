import SwiftUI
import UIKit
import XCTest

@testable import RewoundDesign

/// The recommendation reason moved above the price, which is where Eytan wants
/// it read: the reason is what makes the figure mean something.
///
/// Moving it there put back the exact misalignment the old order was chosen to
/// avoid. On a shelf of five cards where the server justified three, the two
/// unjustified ones had nothing above their price, so their prices sat two
/// lines higher than their neighbors' and the shelf read as a staircase.
/// `reservesReasonLine` is the fix, and these are the measurements that say
/// whether it works — taken off the rendered pixels, because the bug is about
/// where ink lands and a passing assertion about the source would not have
/// caught it the first time either.
final class ListingCardReasonSlotTests: XCTestCase {
    /// A two-up grid at 390pt: 20pt margins, 12pt gutter. The same card width
    /// the alignment tests measure at, so a figure printed by one of these
    /// files means the same thing in the other.
    private static let cardWidth: CGFloat = (390 - 40 - 12) / 2
    private static let pixelScale: CGFloat = 2

    /// The four cards a justified shelf actually holds: one with no reason at
    /// all, one whose reason fits a line, one whose reason takes both lines,
    /// and one that also carries the dealer mark — the badge is the other
    /// thing that has historically moved a price.
    private enum Card: CaseIterable {
        case noReason
        case shortReason
        case longReason
        case longReasonDealer

        var reason: String? {
            switch self {
            case .noReason: nil
            case .shortReason: "Because you saved a Submariner"
            case .longReason, .longReasonDealer:
                "Because you saved a Submariner and watched two more like it this week"
            }
        }

        var isDealer: Bool { self == .longReasonDealer }

        /// Every card on a justified shelf reserves the slot, whether or not
        /// it has anything to put in it. That is the whole mechanism.
        func model(reserving: Bool) -> ListingCardModel {
            .init(
                id: "\(self)",
                brand: "Rolex",
                year: "2019",
                title: "Submariner Date",
                reference: "116610LN",
                priceText: "$12,400",
                condition: "Very Good",
                watcherCount: 14,
                isVerifiedDealer: isDealer,
                reason: reason,
                reservesReasonLine: reserving
            )
        }
    }

    @MainActor
    private func height(_ card: Card, reserving: Bool) -> CGFloat {
        let host = UIHostingController(rootView: ListingCard(model: card.model(reserving: reserving)) { _ in
            Rectangle().fill(Color.rewound.secondary)
        })
        return host.sizeThatFits(
            in: CGSize(width: Self.cardWidth, height: .greatestFiniteMagnitude)
        ).height
    }

    /// One card on a fixed canvas, so a y read off one image means the same
    /// thing as a y read off the next.
    @MainActor
    private func image(_ card: Card, reserving: Bool) -> UIImage? {
        let view = ListingCard(model: card.model(reserving: reserving)) { _ in
            Rectangle().fill(Color.rewound.secondary)
        }
        .frame(width: Self.cardWidth)
        .frame(width: Self.cardWidth, height: 360, alignment: .top)
        .background(Color.rewound.background)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.pixelScale
        return renderer.uiImage
    }

    /// Rows of the image that carry ink, within a horizontal band. Reads the
    /// drawn pixels rather than the view tree, because what has to be equal is
    /// where the price was actually painted. Same method as the alignment
    /// tests; kept here rather than shared so neither file's measurement can
    /// be changed out from under the other.
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
        // meaningfully darker. Sampled rather than assumed, so the threshold
        // survives a change to the background token.
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

    /// The top pixel row of the lowest run of ink under the photograph, in the
    /// card's leading column. With the reason above it, the price is the
    /// lowest thing on the card, and the leading column sees the price and not
    /// the dealer mark.
    @MainActor
    private func priceTop(_ card: Card, reserving: Bool) -> Int? {
        let scale = Int(Self.pixelScale)
        let belowPhoto = Int(Self.cardWidth) * scale + 8 * scale
        guard let image = image(card, reserving: reserving) else { return nil }
        let rows = inkRows(
            image,
            xFrom: 0,
            xTo: Int(Self.cardWidth * 0.55) * scale,
            yFrom: belowPhoto
        )
        guard let bottom = rows.last else { return nil }
        var top = bottom
        var index = rows.count - 1
        while index > 0, rows[index - 1] >= rows[index] - 1 {
            index -= 1
            top = rows[index]
        }
        return top
    }

    /// THE test. A justified shelf holds cards that carry a reason and cards
    /// that do not, and every price on it is painted at one height.
    @MainActor
    func testPricesLineUpOnAShelfWhereOnlySomeCardsCarryAReason() {
        RewoundFonts.register()
        var tops: [(Card, Int)] = []
        for card in Card.allCases {
            guard let top = priceTop(card, reserving: true) else {
                XCTFail("\(card) drew no ink under the photo — nothing was measured")
                continue
            }
            tops.append((card, top))
        }
        // An empty or short read would make every comparison below vacuously
        // true, so the count is checked before the equality is.
        XCTAssertEqual(tops.count, Card.allCases.count)
        print("REASON-SHELF-PRICE-TOP " + tops.map { "\($0.0)=\($0.1)" }.joined(separator: " "))
        guard let reference = tops.first else { return XCTFail("nothing measured") }
        for entry in tops {
            XCTAssertEqual(
                entry.1, reference.1,
                "\(entry.0)'s price is painted \(entry.1 - reference.1) device pixels from \(reference.0)'s — the shelf is a staircase"
            )
        }
    }

    /// The corollary, from the other side: same price height means same card
    /// height, so a grid of them is a grid.
    @MainActor
    func testCardsOnAJustifiedShelfAreTheSameHeight() {
        RewoundFonts.register()
        let heights = Card.allCases.map { height($0, reserving: true) }
        print("REASON-SHELF-HEIGHTS " + zip(Card.allCases, heights).map { "\($0)=\($1)" }.joined(separator: " "))
        for height in heights {
            XCTAssertEqual(height, heights[0], accuracy: 0.5)
        }
    }

    /// The reservation has to cost something, or the two tests above would
    /// pass just as happily against a flag that does nothing. A browse grid,
    /// which never carries a reason, must not be paying for a slot it will
    /// never fill.
    @MainActor
    func testAnUnjustifiedShelfSpendsNoSpaceOnTheSlot() {
        RewoundFonts.register()
        let reserved = height(.noReason, reserving: true)
        let plain = height(.noReason, reserving: false)
        print("REASON-SLOT-COST reserved=\(reserved) plain=\(plain)")
        XCTAssertGreaterThan(
            reserved, plain,
            "reservesReasonLine reserved nothing — the flag is inert and the shelf only looks level by luck"
        )
    }
}
