import SwiftUI
import UIKit
import XCTest

@testable import RewoundDesign

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
                    Rectangle().fill(Color.rewound.secondary)
                }
                .frame(width: Self.cardWidth)
            }
        }
        .padding(20)
        .background(Color.rewound.background)
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
            Rectangle().fill(Color.rewound.secondary)
        }
        .frame(width: Self.cardWidth)
        .frame(width: Self.cardWidth, height: 320, alignment: .top)
        .background(Color.rewound.background)
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
        RewoundFonts.register()
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
        RewoundFonts.register()
        let heights = Variant.allCases.map { variant -> CGFloat in
            let host = UIHostingController(rootView: ListingCard(model: variant.model) { _ in
                Rectangle().fill(Color.rewound.secondary)
            })
            return host.sizeThatFits(in: CGSize(width: Self.cardWidth, height: .greatestFiniteMagnitude)).height
        }
        print("CARD-HEIGHTS " + zip(Variant.allCases, heights).map { "\($0)=\($1)" }.joined(separator: " "))
        for height in heights {
            XCTAssertEqual(height, heights[0], accuracy: 0.5)
        }
    }

    /// The In-cart pill rides on the photograph, so it must cost no height.
    ///
    /// Eytan asked that a watch already in the buyer's cart say so on the card.
    /// The obvious place to put "In cart" is the text block, and that is the
    /// exact shape of the bug the two tests above exist to stop: a row that
    /// renders for some cards and not others moves every price beneath it. This
    /// measures the same card with and without the pill and holds them to the
    /// same height, to the half point.
    @MainActor
    func testTheInCartPillDoesNotMoveAnything() {
        RewoundFonts.register()

        func height(_ model: ListingCardModel) -> CGFloat {
            let host = UIHostingController(rootView: ListingCard(model: model) { _ in
                Rectangle().fill(Color.rewound.secondary)
            })
            return host.sizeThatFits(
                in: CGSize(width: Self.cardWidth, height: .greatestFiniteMagnitude)
            ).height
        }

        for variant in Variant.allCases {
            let plain = variant.model
            let inCart = ListingCardModel(
                id: plain.id, brand: plain.brand, year: plain.year, title: plain.title,
                reference: plain.reference, priceText: plain.priceText,
                condition: plain.condition, watcherCount: plain.watcherCount,
                imageURL: plain.imageURL, isVerifiedDealer: plain.isVerifiedDealer,
                isInCart: true, reason: plain.reason,
                reservesReasonLine: plain.reservesReasonLine
            )
            XCTAssertTrue(inCart.isInCart, "the variant under test did not actually get the pill")
            XCTAssertEqual(
                height(inCart), height(plain), accuracy: 0.5,
                "\(variant) grew by \(height(inCart) - height(plain))pt when it went into the cart"
            )
        }
    }

    /// And it is genuinely drawn — otherwise the height test above passes for
    /// the wrong reason.
    ///
    /// Reads ink out of the photograph's bottom-left corner, which is empty on
    /// a card that is not in the cart and carries the pill on one that is. The
    /// image well is filled with a flat `secondary` fill by these tests, so any
    /// row that changes between the two renders is the pill.
    @MainActor
    func testTheInCartPillIsActuallyPainted() {
        RewoundFonts.register()
        let scale = Int(Self.pixelScale)

        func image(_ inCart: Bool) -> UIImage? {
            let base = Variant.plain.model
            let model = ListingCardModel(
                id: base.id, brand: base.brand, year: base.year, title: base.title,
                reference: base.reference, priceText: base.priceText,
                condition: base.condition, watcherCount: base.watcherCount,
                imageURL: base.imageURL, isVerifiedDealer: base.isVerifiedDealer,
                isInCart: inCart, reason: base.reason,
                reservesReasonLine: base.reservesReasonLine
            )
            let card = ListingCard(model: model) { _ in
                Rectangle().fill(Color.rewound.background)
            }
            .frame(width: Self.cardWidth)
            .frame(width: Self.cardWidth, height: 320, alignment: .top)
            .background(Color.rewound.background)
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: card)
            renderer.scale = Self.pixelScale
            return renderer.uiImage
        }

        guard let without = image(false), let with = image(true) else {
            return XCTFail("the card did not render")
        }
        // The lower third of the square photo, leading half — where the pill
        // sits and where nothing else on the card ever does.
        let photoBottom = Int(Self.cardWidth) * scale
        let band = (from: photoBottom - Int(Self.cardWidth * 0.3) * scale, to: photoBottom)
        let column = (0, Int(Self.cardWidth * 0.6) * scale)

        let bare = inkRows(without, xFrom: column.0, xTo: column.1, yFrom: band.from)
            .filter { $0 < band.to }
        let marked = inkRows(with, xFrom: column.0, xTo: column.1, yFrom: band.from)
            .filter { $0 < band.to }

        XCTAssertTrue(bare.isEmpty, "something already occupies the photo's bottom-left corner: \(bare.count) inked rows")
        XCTAssertFalse(marked.isEmpty, "the In-cart pill drew nothing — the height test above proves only that nothing changed")
    }

    /// The grade line and the part chip (contracts, 2026-09-30, Part D) vary
    /// card to card and wrap rather than truncate, so a card that carries
    /// them is taller. On a shelf that gives every card the tallest one's
    /// height and sets `listingCardPinsPrice`, the prices still land level.
    @MainActor
    func testAPinnedShelfKeepsPricesLevelBesideFactsAndAChip() {
        RewoundFonts.register()
        let scale = Int(Self.pixelScale)
        let plain = ListingCardModel(
            id: "plain", brand: "Rolex", year: "2019", title: "Submariner Date",
            reference: "126610LN", priceText: "$12,400", condition: "Very Good"
        )
        let busy = ListingCardModel(
            id: "busy", brand: "Omega", year: "2020", title: "Speedmaster Professional",
            reference: "310.30.42", priceText: "$4,950", condition: "Very Good",
            facts: ["Unpolished", "All original", "Full set"],
            partException: "2 parts below Very Good"
        )
        let gutter: CGFloat = 12
        let row = HStack(alignment: .top, spacing: gutter) {
            ForEach([plain, busy], id: \.id) { model in
                ListingCard(model: model) { _ in Rectangle().fill(Color.rewound.secondary) }
                    .frame(width: Self.cardWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.listingCardPinsPrice, true)
        .background(Color.rewound.background)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: row)
        renderer.scale = Self.pixelScale
        guard let image = renderer.uiImage else { return XCTFail("the shelf did not render") }

        let belowPhoto = Int(Self.cardWidth) * scale + 8 * scale
        func priceTop(columnStart: CGFloat) -> Int? {
            let from = Int(columnStart) * scale
            let rows = inkRows(image, xFrom: from, xTo: from + Int(Self.cardWidth * 0.45) * scale, yFrom: belowPhoto)
            guard var index = rows.indices.last else { return nil }
            while index > 0, rows[index - 1] >= rows[index] - 1 { index -= 1 }
            return rows[index]
        }
        guard let left = priceTop(columnStart: 0),
              let right = priceTop(columnStart: Self.cardWidth + gutter) else {
            return XCTFail("no price was painted under one of the photos")
        }
        print("PINNED-PRICES plain=\(left) busy=\(right)")
        XCTAssertEqual(left, right, "the prices stand \(right - left) device pixels apart on a pinned shelf")

        // And the busy card really is taller on its own, or the pin proved
        // nothing.
        func height(_ model: ListingCardModel) -> CGFloat {
            UIHostingController(rootView: ListingCard(model: model) { _ in Rectangle() })
                .sizeThatFits(in: CGSize(width: Self.cardWidth, height: .greatestFiniteMagnitude)).height
        }
        XCTAssertGreaterThan(height(busy), height(plain) + 10)
    }

    // MARK: - Option D: every row level, whatever is in it

    /// A Home lane card: `rewoundLaneCardWidth(168)` at the default size.
    private static let laneCardWidth: CGFloat = 168

    /// Eytan, choosing Option D: "one has a bigger title than the other, still
    /// line everything up."
    ///
    /// Three cards on one pinned shelf that differ in every way the card can
    /// differ: a long title with a part graded lower (a note under the title
    /// block that makes this card taller than its neighbours') and all
    /// three facts; a short card with a grade and the same facts but no part
    /// and no reference; and a card with no grade, no part, no facts and no
    /// reference. The grade row, the facts row
    /// and the price are each read off the painted pixels and held to one y.
    private enum ShelfCard: CaseIterable {
        case busy, plain, bare

        var model: ListingCardModel {
            switch self {
            case .busy:
                .init(id: "busy", brand: "Tudor", year: "2022",
                      title: "Black Bay Fifty-Eight Navy Blue", reference: "M79030B-0001",
                      priceText: "$3,450", condition: "Like New",
                      facts: ["Unpolished", "All original", "Full set"],
                      partException: "Bracelet: Very Good",
                      watcherCount: 99, isVerifiedDealer: true)
            case .plain:
                .init(id: "plain", brand: "Omega", year: "2019",
                      title: "Speedmaster", reference: nil,
                      priceText: "$6,200", condition: "Very Good",
                      // The busy card's facts, word for word: the run is
                      // shrunk to fit, and the same words at the same scale
                      // paint the same ink, so any difference in where the
                      // two rows land is position and nothing else.
                      facts: ["Unpolished", "All original", "Full set"],
                      watcherCount: 31)
            case .bare:
                .init(id: "bare", brand: "Cartier", year: nil,
                      title: "Tank", reference: nil,
                      priceText: "$2,950")
            }
        }
    }

    /// The shelf as `FeedCardLane` builds it: each card at the lane width,
    /// stretched to the tallest, with `listingCardPinsPrice` set.
    @MainActor
    private func shelfImage() -> UIImage? {
        let row = HStack(alignment: .top, spacing: Space.l) {
            ForEach(ShelfCard.allCases, id: \.self) { card in
                ListingCard(model: card.model) { _ in Rectangle().fill(Color.rewound.secondary) }
                    .frame(width: Self.laneCardWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.listingCardPinsPrice, true)
        .background(Color.rewound.background)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: row)
        renderer.scale = Self.pixelScale
        return renderer.uiImage
    }

    /// Contiguous runs of inked rows, top to bottom.
    private func bands(_ rows: [Int]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for row in rows {
            if let last = result.last, row <= last.upperBound + 1 {
                result[result.count - 1] = last.lowerBound...row
            } else {
                result.append(row...row)
            }
        }
        return result
    }

    /// The first row, at or below `yFrom`, holding a run of pixels painted in
    /// the grade pill's own fill (`accent`, light: #ECE7E0). That is the top of
    /// the grade pill: nothing else on a card is filled with that colour (the
    /// dealer mark is `accent` at 60% over the page, a different pixel).
    private func firstAccentRow(_ image: UIImage, xFrom: Int, xTo: Int, yFrom: Int) -> Int? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let target = (236, 231, 224)
        for y in yFrom..<height {
            var run = 0
            for x in xFrom..<min(xTo, width) {
                let i = (y * width + x) * 4
                let match = abs(Int(pixels[i]) - target.0) <= 3
                    && abs(Int(pixels[i + 1]) - target.1) <= 3
                    && abs(Int(pixels[i + 2]) - target.2) <= 3
                run = match ? run + 1 : 0
                if run >= 12 { return y }
            }
        }
        return nil
    }

    @MainActor
    func testRowsStandLevelOnAShelfOfCardsThatDiffer() {
        RewoundFonts.register()
        let scale = Int(Self.pixelScale)
        guard let image = shelfImage() else { return XCTFail("the shelf did not render") }
        let belowPhoto = Int(Self.laneCardWidth) * scale + 4 * scale

        struct Read { let card: ShelfCard; let accentBelowPhoto: Int?; let bands: [ClosedRange<Int>] }
        var reads: [Read] = []
        for (index, card) in ShelfCard.allCases.enumerated() {
            let x0 = Int((Self.laneCardWidth + Space.l) * CGFloat(index)) * scale
            // The leading 55% of the card: the price, the facts and the note
            // live at the leading edge, and the dealer mark at the trailing one.
            let x1 = x0 + Int(Self.laneCardWidth * 0.55) * scale
            let rows = inkRows(image, xFrom: x0, xTo: x1, yFrom: belowPhoto)
            XCTAssertFalse(rows.isEmpty, "\(card) drew nothing under its photo; nothing was measured")
            reads.append(Read(
                card: card,
                accentBelowPhoto: firstAccentRow(image, xFrom: x0, xTo: x0 + Int(Self.laneCardWidth) * scale, yFrom: belowPhoto),
                bands: bands(rows)
            ))
        }
        print("ROWS " + reads.map { "\($0.card): bands=\($0.bands)" }.joined(separator: " | "))

        guard reads.count == ShelfCard.allCases.count,
              let busy = reads.first(where: { $0.card == .busy }),
              let plain = reads.first(where: { $0.card == .plain }) else {
            return XCTFail("not every card was read")
        }

        // The price: the lowest band on every card.
        let prices = reads.compactMap { $0.bands.last?.lowerBound }
        XCTAssertEqual(prices.count, 3)
        XCTAssertEqual(Set(prices).count, 1, "the prices stand on different lines: \(prices)")

        // The facts: the band directly above the price, on the two cards that
        // have facts. The busy card's part note took a line; that line must
        // not have pushed its facts below the plain card's.
        guard busy.bands.count >= 2, plain.bands.count >= 2 else {
            return XCTFail("a card with facts drew fewer than two bands")
        }
        let busyFacts = busy.bands[busy.bands.count - 2]
        let plainFacts = plain.bands[plain.bands.count - 2]
        XCTAssertEqual(
            busyFacts.lowerBound, plainFacts.lowerBound,
            "the facts rows stand \(busyFacts.lowerBound - plainFacts.lowerBound) device pixels apart"
        )

        // The grade is on the photograph now (Eytan, 2026-10-02), so the text
        // block paints none of the grade pill's accent fill on any card.
        for read in reads {
            XCTAssertNil(read.accentBelowPhoto, "\(read.card) still paints a grade pill under its photo")
        }

        // The bare card holds the facts row: on its own, unpinned, it is
        // exactly as tall as the plain card that has facts. And the busy card
        // really did add its part note, or the shelf above proved nothing: it
        // is a note line taller than the plain card.
        func height(_ card: ShelfCard) -> CGFloat {
            UIHostingController(rootView: ListingCard(model: card.model) { _ in Rectangle() })
                .sizeThatFits(in: CGSize(width: Self.laneCardWidth, height: .greatestFiniteMagnitude)).height
        }
        print("ROW-HEIGHTS busy=\(height(.busy)) plain=\(height(.plain)) bare=\(height(.bare))")
        XCTAssertEqual(height(.bare), height(.plain), accuracy: 0.5, "the bare card does not hold the rows it has nothing for")
        XCTAssertGreaterThan(height(.busy), height(.plain) + 12, "the busy card's part note did not add a line")
    }

    // MARK: - The photograph is as wide as its card

    /// The width, in points, of the painted photograph at mid height of a card
    /// drawn in `view`'s layout context. The photograph is flat blue so it is
    /// the only thing of that colour on the card.
    @MainActor
    private func paintedPhotoWidth<V: View>(_ view: V) -> Int? {
        let renderer = ImageRenderer(content: view.background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 1
        guard let image = renderer.uiImage?.cgImage else { return nil }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let y = 100
        var first = w, last = -1
        for x in 0..<min(w, Int(Self.laneCardWidth) + 2) {
            let i = (y * w + x) * 4
            if pixels[i + 2] > 200 && pixels[i] < 90 { first = min(first, x); last = max(last, x) }
        }
        return last < first ? nil : last - first + 1
    }

    /// Found by looking at the app: on Home the photograph was 148pt inside a
    /// 168pt card, because with nothing to hold it open it was the most flexible
    /// view in the card and gave way to the text block when the card was sized
    /// from its content. It is measured in the layout contexts the app uses.
    @MainActor
    func testThePhotographIsAsWideAsItsCardWhateverSizesTheCard() {
        RewoundFonts.register()
        let model = ListingCardModel(
            id: "x", brand: "Rolex", year: "2022", title: "Day-Date 40", reference: "228238",
            priceText: "$44,900", condition: "Like New", watcherCount: 72
        )
        func card() -> some View {
            ListingCard(model: model) { _ in Rectangle().fill(Color(red: 0.2, green: 0.4, blue: 0.9)) }
        }
        let width = Int(Self.laneCardWidth)
        XCTAssertEqual(paintedPhotoWidth(card().frame(width: Self.laneCardWidth)), width, "alone")
        XCTAssertEqual(
            paintedPhotoWidth(card().frame(width: Self.laneCardWidth).environment(\.listingCardPinsPrice, true)),
            width, "pinned, sized from its content"
        )
        let shelf = HStack(alignment: .top, spacing: Space.l) {
            card().frame(width: Self.laneCardWidth).frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.listingCardPinsPrice, true)
        XCTAssertEqual(paintedPhotoWidth(shelf), width, "in a lane")
    }

    // MARK: - The badges on the photograph

    /// A lane card's photograph is `laneCardWidth` wide and the badges sit in
    /// `Space.s` of padding either side.
    private static var badgeWidth: CGFloat { laneCardWidth - Space.s * 2 }

    @MainActor
    private func badgeSize(
        condition: String?, watchers: Int?, signal: ListingCardSignal? = nil, width: CGFloat? = nil
    ) -> CGSize {
        RewoundFonts.register()
        let view = CardPhotoBadges(condition: condition, watchers: watchers, signal: signal)
        return UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width ?? Self.badgeWidth, height: .greatestFiniteMagnitude))
    }

    /// Eytan: "push it up to the top of the image like before just make sure
    /// that the long ones don't cut off with the views." What cut off before was
    /// a long grade lying under the watcher count, because each was placed on
    /// its own. Measured at the real fonts: "Very Good" is 81pt, a count of 999
    /// is 65pt, and a lane photograph leaves 152pt, so the longest grade and any
    /// count up to 999 share one line.
    @MainActor
    func testALongGradeAndABigWatcherCountShareOneLine() {
        let alone = badgeSize(condition: "Very Good", watchers: nil)
        let together = badgeSize(condition: "Very Good", watchers: 999)
        print("BADGES alone=\(alone) together=\(together)")
        XCTAssertGreaterThan(alone.height, 15, "the grade pill measured as nothing")
        XCTAssertEqual(together.height, alone.height, accuracy: 0.5, "the grade and the count did not fit one line")
        XCTAssertLessThanOrEqual(together.width, Self.badgeWidth + 0.5)
    }

    /// Past 999 the two no longer fit one line (81 + 72 + the gap is 157pt
    /// against 152). The count moves under the grade; it does not lie on it and
    /// it is not shrunk or cut. The row grows by the count's own height.
    @MainActor
    func testAFourDigitCountDropsUnderTheGradeInsteadOfCoveringIt() {
        let alone = badgeSize(condition: "Very Good", watchers: nil)
        let crowded = badgeSize(condition: "Very Good", watchers: 1234)
        print("BADGES grade=\(alone) withBigCount=\(crowded)")
        XCTAssertGreaterThan(crowded.height, alone.height + 12, "the count did not move under the grade; it is lying on it")
        XCTAssertLessThanOrEqual(crowded.width, Self.badgeWidth + 0.5)
    }

    /// A price chip is wider than a watcher count. When the grade and the chip
    /// cannot share a line, the chip drops under the grade instead of lying on
    /// it: the row is taller than one pill, and still no wider than the photo.
    @MainActor
    func testAWideChipDropsUnderTheGradeInsteadOfCoveringIt() {
        let chip = ListingCardSignal(label: "Price drop \u{2212}12%", isPriceDrop: true)
        let alone = badgeSize(condition: "Very Good", watchers: nil)
        let stacked = badgeSize(condition: "Very Good", watchers: nil, signal: chip)
        print("BADGES grade=\(alone) withChip=\(stacked)")
        XCTAssertGreaterThan(stacked.height, alone.height + 12, "the chip did not move under the grade; it is lying on it")
        XCTAssertLessThanOrEqual(stacked.width, Self.badgeWidth + 0.5)

        // And on a photograph wide enough for both, they stand on one line.
        let wide = badgeSize(condition: "Very Good", watchers: nil, signal: chip, width: 340)
        XCTAssertEqual(wide.height, alone.height, accuracy: 0.5, "a wide photograph still stacked the badges")
    }

    /// Every grade the sell form can write fits one line next to a three-digit
    /// count at the lane width: the badge is measured, not assumed.
    @MainActor
    func testEveryGradeFitsBesideAThreeDigitCount() {
        let one = badgeSize(condition: "Good", watchers: nil).height
        for grade in ["New", "Like New", "Very Good", "Good", "Worn"] {
            let size = badgeSize(condition: grade, watchers: 999)
            XCTAssertEqual(size.height, one, accuracy: 0.5, "\"\(grade)\" did not fit beside a three-digit count")
        }
    }

    /// The facts never end in an ellipsis. One line is held by
    /// `.lineLimit(1)`, so the only way a fact could be lost is the run not
    /// fitting even at the 0.75 shrink floor; this measures the longest run
    /// the contract can produce, in the caption's own face, against a lane
    /// card's text column. And an empty facts row holds exactly one line.
    @MainActor
    func testTheLongestFactsRunFitsOneLineAtTheLaneWidth() {
        RewoundFonts.register()
        guard let caption = UIFont(name: RewoundFonts.Name.sansRegular, size: 12) else {
            return XCTFail("Geist-Regular missing; the measurement would be against the system font")
        }
        let column = Self.laneCardWidth - 4
        let longest = ["Unpolished", "All original", "Full set"].joined(separator: " \u{00B7} ")
        let full = (longest as NSString).size(withAttributes: [.font: caption]).width
        print("FACTS-WIDTH full=\(full) at0.75=\(full * 0.75) column=\(column)")
        XCTAssertLessThanOrEqual(full * 0.75, column, "the longest facts run cannot fit one line at the 0.75 floor")

        func height(_ facts: [String]) -> CGFloat {
            UIHostingController(rootView: CardFactsLine(facts: facts))
                .sizeThatFits(in: CGSize(width: column, height: .greatestFiniteMagnitude)).height
        }
        let three = height(["Unpolished", "All original", "Full set"])
        let one = height(["Box"])
        let none = height([])
        print("FACTS-HEIGHTS three=\(three) one=\(one) none=\(none)")
        XCTAssertGreaterThan(one, 10, "a facts row measured as nothing; the comparisons below would be vacuous")
        XCTAssertEqual(three, one, accuracy: 0.5, "the longest facts run took more than one line")
        XCTAssertEqual(none, one, accuracy: 0.5, "an empty facts row does not hold its line")
    }

    /// §0.6: a brand name may not be clipped. The brand is now held to one
    /// line, so `.minimumScaleFactor(0.65)` is the only thing standing between
    /// "Jaeger-LeCoultre" and an ellipsis. This measures the two worst real
    /// brands in the Eyebrow's own face against the width the card actually
    /// gives them, at the two-up grid size.
    @MainActor
    func testTheWorstBrandsFitOnOneLineWithoutClipping() {
        RewoundFonts.register()
        guard let eyebrow = UIFont(name: RewoundFonts.Name.sansMedium, size: 11) else {
            return XCTFail("Geist-Medium missing — the measurement below would be against the system font")
        }
        let tracking = RewoundType.eyebrowTracking

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
        RewoundFonts.register()
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
