import SwiftUI
import UIKit

/// The card a seller keeps on file, drawn as the object it is.
///
/// Stripe returns four facts about a saved card — brand, last four, expiry,
/// funding — and no image, so the card is drawn here in Calibre's own stock.
/// It is drawn at all because a row of key-value text reads as a billing line,
/// and this is not a billing line: it is what makes "we will make the buyer
/// whole" something Calibre can do rather than something it hopes for. It is
/// never charged for a normal sale.
///
/// `last4` is the only number that exists on the client and the only one this
/// ever draws. The other twelve digits are dots, not digits.
///
/// This is the *seller's* guarantee. A buyer's saved payment method is a
/// different object with a different meaning and must not borrow this face.
///
/// Render it only when the server says a card is present — there is no empty
/// state here, because an empty card outline is a promise of nothing.
public struct GuaranteeCard: View {
    /// How the card is standing today, as the server reads it.
    public enum Status: Sendable {
        /// On file and usable. The everyday state, and the quiet one.
        case onFile
        /// Expires this month. Surfaced before it lapses rather than after.
        case expiringSoon
        /// Cannot be charged any more. A lapsed guarantee pulls the seller's
        /// listings off the market, so this state does not get to look calm.
        case lapsed
    }

    /// The two sizes the card is printed at: a hero on its own screen, and the
    /// smaller print that sits inside a setup step beside other text.
    public enum Size: Sendable {
        case regular
        case compact
    }

    private let brand: Brand
    private let last4: String?
    private let expiry: String?
    private let status: Status
    private let size: Size

    /// - Parameters:
    ///   - brand: the network as Stripe names it; anything unrecognised draws
    ///     the plain card device rather than guessing a mark.
    ///   - last4: the last four digits. Nil masks the whole number.
    ///   - expiry: pre-formatted by the caller, so the app keeps one authority
    ///     on what an expiry date looks like.
    public init(
        brand: Brand,
        last4: String?,
        expiry: String?,
        status: Status,
        size: Size = .regular
    ) {
        self.brand = brand
        self.last4 = last4
        self.expiry = expiry
        self.status = status
        self.size = size
    }

    /// ID-1: the proportion every payment card in the world is cut to.
    private static let aspect: CGFloat = 85.60 / 53.98

    /// Text on the card grows with the reader; the chip and the brand mark do
    /// not, because print does not resize with the room. Scaling a ratio
    /// rather than a point size keeps both card sizes on one Dynamic Type
    /// curve.
    @ScaledMetric(relativeTo: .title3) private var typeScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var numberSize: CGFloat {
        (size == .compact ? 15 : 19) * typeScale
    }

    /// The mask is decoration; the four digits are the content. At
    /// accessibility sizes the full mask cannot share a line with them, and
    /// repeating it three times buys nothing — one group already says the
    /// rest is hidden.
    private var maskGroups: String {
        dynamicTypeSize.isAccessibilitySize ? "••••" : "•••• •••• ••••"
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Fixes the card proportion at ordinary type sizes. The face is
            // free to exceed it: a card that clips its own number is worse
            // than a card that grows.
            Color.clear.aspectRatio(Self.aspect, contentMode: .fit)
            face
        }
        .frame(maxWidth: size == .compact ? 250 : 320, alignment: .leading)
        .background(stock)
        .overlay(sweep)
        .overlay(alignment: .top) { litEdge }
        .overlay(alignment: .bottom) { seam }
        .clipShape(
            // Physical geometry, not the size ladder: a real ID-1 card's
            // corner is 3.18mm on an 85.6mm edge, so 250pt reads ~9pt and
            // 320pt reads ~12pt. `box` and `panel` are the two rungs those
            // land on, and the object is not a UI surface to be re-sorted
            // with the rest of them (the same reason `Stock` sits outside
            // the palette below).
            RoundedRectangle(
                cornerRadius: size == .compact ? Radius.box : Radius.panel,
                style: .continuous
            )
        )
        // An object lying on the page, not a UI surface: the border-only rule
        // in `Elevation` is about panels, and a card casts a shadow.
        .calibreShadow(.lifted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - The face

    private var face: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Card on file", color: Stock.dim)

            chip.padding(.top, size == .compact ? Space.s : Space.m)

            Spacer(minLength: Space.s)

            number

            HStack(alignment: .bottom, spacing: Space.m) {
                if let expiry {
                    expiryBlock(expiry)
                }
                Spacer(minLength: Space.s)
                CardBrandMark(brand: brand, height: size == .compact ? 18 : 22, ink: Stock.ink, dim: Stock.dim)
                    .opacity(status == .lapsed ? 0.7 : 1)
            }
            .padding(.top, Space.s)
        }
        .padding(.horizontal, size == .compact ? Space.l : Space.xl)
        .padding(.vertical, size == .compact ? Space.m : Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The masked number. Twelve dots and the four digits we actually hold —
    /// there is no path through this view that can print more.
    private var number: some View {
        (
            Text(verbatim: maskGroups).foregroundStyle(Stock.dim)
                + Text(verbatim: " ")
                + Text(verbatim: last4 ?? "••••").foregroundStyle(
                    status == .lapsed ? Stock.ink.opacity(0.7) : Stock.ink
                )
        )
        .font(.system(size: numberSize, weight: .medium, design: .monospaced))
        .tracking(numberSize * 0.1)
        // No line limit and no shrinking: at the largest type sizes the number
        // wraps and the card grows around it rather than truncating a figure.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func expiryBlock(_ expiry: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Expires")
                .font(CalibreType.caption)
                .foregroundStyle(Stock.dim)
            Text(expiry)
                .font(CalibreType.label)
                // A card that is present and invalid is an expired one: the
                // webhook refuses to store anything but a credit card, so the
                // date is the only thing that can go wrong after saving.
                .foregroundStyle(status == .lapsed ? Stock.lapsedSeam : Stock.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The contact chip. It is the part a terminal actually reads, so on a
    /// card that can no longer be charged it goes out — dead metal, not gold.
    private var chip: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: status == .lapsed ? Stock.deadChip : Stock.goldChip,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(
                width: size == .compact ? 30 : 38,
                height: size == .compact ? 22 : 28
            )
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Stock.etch, lineWidth: 1)
                    .padding(.vertical, size == .compact ? 4 : 5)
                    .padding(.horizontal, size == .compact ? 6 : 8)
            }
            .overlay {
                Rectangle()
                    .fill(Stock.etch)
                    .frame(height: 1)
                    .padding(.horizontal, size == .compact ? 6 : 8)
            }
            .accessibilityHidden(true)
    }

    // MARK: - The stock

    private var stock: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [Stock.highlight, Stock.body],
                center: UnitPoint(x: 0.12, y: -0.2),
                startRadius: 0,
                endRadius: proxy.size.width * 1.1
            )
        }
    }

    /// One quiet sweep of light across the stock — printed, not animated.
    private var sweep: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.42),
                .init(color: .white.opacity(0.05), location: 0.47),
                .init(color: .clear, location: 0.55),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
    }

    /// The lit top edge where the card stands proud of the page. It earns its
    /// keep in dark mode: the stock is darker than the page there, and without
    /// a caught edge a dark object on a dark ground has no boundary at all.
    private var litEdge: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 1)
            .allowsHitTesting(false)
    }

    /// A seam along the base carries the state, so the face stays a card and
    /// the words that explain it can live outside, next to the action.
    @ViewBuilder
    private var seam: some View {
        switch status {
        case .onFile:
            EmptyView()
        case .expiringSoon:
            Rectangle().fill(Stock.expiringSeam).frame(height: 3)
        case .lapsed:
            Rectangle().fill(Stock.lapsedSeam).frame(height: 4)
        }
    }

    private var accessibilityText: String {
        var parts = ["Card on file", brand.spokenName]
        if let last4 {
            parts.append("ending \(last4)")
        }
        if let expiry {
            parts.append(status == .lapsed ? "expired \(expiry)" : "expires \(expiry)")
        }
        switch status {
        case .onFile: break
        case .expiringSoon: parts.append("expiring soon")
        case .lapsed: parts.append("this card can no longer be charged")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Brands

public extension GuaranteeCard {
    /// The networks we draw a mark for. Stripe's `brand` string maps in;
    /// anything else gets the plain card device rather than a guessed mark.
    enum Brand: Sendable {
        case visa
        case mastercard
        case amex
        case discover
        case other

        public init(stripeBrand: String?) {
            switch (stripeBrand ?? "").lowercased().replacingOccurrences(of: " ", with: "_") {
            case "visa": self = .visa
            case "mastercard", "master_card": self = .mastercard
            case "amex", "american_express": self = .amex
            case "discover": self = .discover
            default: self = .other
            }
        }

        var spokenName: String {
            switch self {
            case .visa: "Visa"
            case .mastercard: "Mastercard"
            case .amex: "American Express"
            case .discover: "Discover"
            case .other: "card"
            }
        }
    }
}

// MARK: - The stock's own colours

/// The card's material. Deliberately not `Color.calibre` tokens: a physical
/// card does not change colour with the room, so the stock darkens between
/// themes rather than inverting, and nothing else in the app is made of it.
/// The seams take values that read on dark stock rather than the page's
/// warning and destructive tokens, which are tuned for paper.
private enum Stock {
    static let body = dynamic(light: 0x241F1A, dark: 0x0E0B09)
    static let highlight = dynamic(light: 0x322B24, dark: 0x1D1813)
    static let ink = fixed(0xF3EFE9)
    static let dim = dynamic(light: 0xB9AC9C, dark: 0xA79C8F)

    static let goldChip = [fixed(0xC9A758), fixed(0xA8801E), fixed(0xC9A758)]
    static let deadChip = [fixed(0x8A837B), fixed(0x5F5952), fixed(0x8A837B)]
    static let etch = Color.black.opacity(0.38)

    static let expiringSeam = fixed(0xD3993F)
    static let lapsedSeam = fixed(0xD96B65)

    static func fixed(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(fixed(traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Brand marks

/// Brand marks drawn locally, the way every checkout renders them: Stripe's
/// API carries no imagery for payment cards. Each is the simplest drawing that
/// is unmistakably the network — a wordmark, or the geometry where the mark
/// *is* geometry — and each keeps the network's own colours, the one thing on
/// this card that is not Calibre's to restyle.
///
/// The marks are printed at a fixed size. They do not answer to Dynamic Type,
/// because the brand is also spoken in the card's accessibility label, where
/// growing a logo would help nobody.
///
/// It is public, and it takes its ink, because two different cards draw it:
/// this one on its own dark stock, and `WalletCardFace` on the page's surface.
/// The network colours are the same on both — only the ink that stands for
/// "printed here" changes with the material.
public struct CardBrandMark: View {
    let brand: GuaranteeCard.Brand
    /// The printed height on the stock. Every measurement below is a fraction
    /// of it, so both card sizes carry the same mark rather than two drawings.
    let height: CGFloat
    /// The colour a wordmark is struck in — the material's own ink.
    let ink: Color
    /// The quieter ink, for the device drawn when there is no mark to draw.
    let dim: Color

    public init(brand: GuaranteeCard.Brand, height: CGFloat, ink: Color, dim: Color) {
        self.brand = brand
        self.height = height
        self.ink = ink
        self.dim = dim
    }

    public var body: some View {
        Group {
            switch brand {
            case .visa: visa
            case .mastercard: mastercard
            case .amex: amex
            case .discover: discover
            case .other: plainCard
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Visa's mark is an italic wordmark, so it is set rather than drawn. The
    /// system face carries a true italic; Geist ships upright only.
    private var visa: some View {
        Text(verbatim: "VISA")
            .font(.system(size: height * 0.77, weight: .heavy))
            .italic()
            .tracking(height * 0.045)
            .foregroundStyle(ink)
    }

    /// Two discs and the lens where they overlap.
    private var mastercard: some View {
        let disc = height
        let shift = disc * 0.28
        return ZStack(alignment: .topLeading) {
            Circle().fill(Self.mcRed).frame(width: disc, height: disc)
            Circle().fill(Self.mcAmber).frame(width: disc, height: disc).offset(x: shift * 2)
            MastercardLens(diameter: disc, shift: shift).fill(Self.mcOverlap)
        }
        .frame(width: disc + shift * 2, height: disc, alignment: .topLeading)
    }

    private var amex: some View {
        Text(verbatim: "AMEX")
            .font(.system(size: height * 0.45, weight: .heavy))
            .tracking(height * 0.068)
            .foregroundStyle(.white)
            .padding(.horizontal, height * 0.32)
            .frame(height: height * 0.92)
            .background(Self.amexBlue, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// The wordmark with the orange ball at its tail.
    private var discover: some View {
        HStack(spacing: height * 0.14) {
            Text(verbatim: "DISCOVER")
                .font(.system(size: height * 0.5, weight: .heavy))
                .tracking(height * 0.018)
                .foregroundStyle(ink)
            Circle()
                .fill(Self.discoverOrange)
                .frame(width: height * 0.41, height: height * 0.41)
        }
    }

    /// No mark to draw: a card device with its stripe, and no invented brand.
    private var plainCard: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(dim, lineWidth: 1.5)
            .frame(width: height * 1.45, height: height * 0.86)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(dim)
                    .frame(height: height * 0.18)
                    .padding(.top, height * 0.18)
            }
    }

    static let mcRed = Stock.fixed(0xEB001B)
    static let mcAmber = Stock.fixed(0xF79E1B)
    static let mcOverlap = Stock.fixed(0xFF5F00)
    static let amexBlue = Stock.fixed(0x2E77BC)
    static let discoverOrange = Stock.fixed(0xF48120)
}

/// Where the two discs overlap, computed rather than eyeballed — an
/// approximated lens sits off the discs' own edges and reads as a printing
/// fault.
private struct MastercardLens: Shape {
    let diameter: CGFloat
    let shift: CGFloat

    func path(in rect: CGRect) -> Path {
        let left = Path(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        let right = Path(ellipseIn: CGRect(x: shift * 2, y: 0, width: diameter, height: diameter))
        return left.intersection(right)
    }
}

// MARK: - Previews

#Preview("Guarantee card — light", traits: .sizeThatFitsLayout) {
    GuaranteeCardPreviewRow()
        .padding(Space.margin)
        .background(Color.calibre.background)
}

#Preview("Guarantee card — dark", traits: .sizeThatFitsLayout) {
    GuaranteeCardPreviewRow()
        .padding(Space.margin)
        .background(Color.calibre.background)
        .preferredColorScheme(.dark)
}

private struct GuaranteeCardPreviewRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            GuaranteeCard(brand: .visa, last4: "4242", expiry: "04/29", status: .onFile)
            GuaranteeCard(brand: .mastercard, last4: "0916", expiry: "08/26", status: .expiringSoon)
            GuaranteeCard(brand: .amex, last4: "0005", expiry: "06/26", status: .lapsed)
            GuaranteeCard(
                brand: .discover,
                last4: "6011",
                expiry: "11/28",
                status: .onFile,
                size: .compact
            )
        }
    }
}
