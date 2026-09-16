import SwiftUI

/// Display-only data the card needs — CalibreKit models map into this.
public struct ListingCardModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let brand: String
    public let year: String?
    public let title: String
    public let reference: String?
    public let priceText: String
    public let condition: String?
    public let watcherCount: Int?
    public let imageURL: URL?
    /// Seller is a verified business — earns the dealer badge.
    public let isVerifiedDealer: Bool
    /// "Why you're seeing this" — a recommendation reason, when the surface
    /// supplies one. It renders directly above the price, which is Eytan's
    /// ruling: the reason is what makes the price make sense, so it is read
    /// first.
    ///
    /// The reason a shelf of cards used to stay level was that this line sat
    /// last, where nothing followed it. Above the price it is load-bearing
    /// again, and `reservesReasonLine` is what keeps the shelf level instead.
    public let reason: String?
    /// This watch is already in the buyer's cart.
    ///
    /// Drawn over the photograph, never in the text block below it — see
    /// `InCartPill`. Defaults to `false` so every surface that does not know
    /// about the cart (a seller's own listings, a storefront seen signed-out)
    /// keeps rendering exactly as it did.
    public let isInCart: Bool
    /// Hold the reason's height on this card whether or not it has a reason.
    ///
    /// A shelf where some cards were justified and some were not put its
    /// prices on two different lines the moment the reason moved above them.
    /// The shelf is the only thing that knows whether any of its cards carry
    /// a reason, so the shelf sets this on all of them; a browse grid, which
    /// never carries one, leaves it off and spends no space.
    public let reservesReasonLine: Bool

    public init(
        id: String,
        brand: String,
        year: String? = nil,
        title: String,
        reference: String? = nil,
        priceText: String,
        condition: String? = nil,
        watcherCount: Int? = nil,
        imageURL: URL? = nil,
        isVerifiedDealer: Bool = false,
        isInCart: Bool = false,
        reason: String? = nil,
        reservesReasonLine: Bool = false
    ) {
        self.id = id
        self.brand = brand
        self.year = year
        self.title = title
        self.reference = reference
        self.priceText = priceText
        self.condition = condition
        self.watcherCount = watcherCount
        self.imageURL = imageURL
        self.isVerifiedDealer = isVerifiedDealer
        self.isInCart = isInCart
        self.reason = reason
        self.reservesReasonLine = reservesReasonLine
    }
}

/// The dealer mark: a verified business is behind this listing. Small,
/// quiet, and never louder than the watch.
public struct DealerBadge: View {
    private let compact: Bool
    /// The seal is the only part of the badge that would not grow with the
    /// word it certifies — at an accessibility size a frozen 11pt glyph reads
    /// as a speck beside "Dealer". Identical at the default size, where
    /// `ScaledMetric` returns the value it was given.
    @ScaledMetric private var sealSize: CGFloat

    public init(compact: Bool = false) {
        self.compact = compact
        _sealSize = ScaledMetric(wrappedValue: compact ? 9 : 11)
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: sealSize, weight: .semibold))
            Text("Dealer")
                .font(compact ? CalibreType.caption : CalibreType.label)
        }
        .foregroundStyle(Color.calibre.primary)
        .padding(.horizontal, compact ? 6 : Space.s)
        .padding(.vertical, compact ? 2 : 3)
        .background(Color.calibre.accent.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verified dealer")
    }
}

/// A text row that keeps its full-size line height even when
/// `minimumScaleFactor` shrinks the glyphs inside it.
///
/// Shrinking is how §0.6 is honoured on this card — a long brand, a long model
/// name and a long reference each keep every character instead of ending in an
/// ellipsis — but SwiftUI shrinks the *row* along with the type, and the
/// difference is small enough to be invisible on one card and impossible to
/// miss on a shelf of them. Measured before this existed, four cards that
/// differed only in the length of their text came out 262.33, 262.67, 263.33
/// and 265.00pt tall, and their prices stood at four different heights.
///
/// The hidden twin is drawn at the unscaled size and never shrinks, so it —
/// not the visible text — decides how tall the row is. It is invisible, it is
/// hidden from VoiceOver, and it is the only thing here that is constant.
private struct SteadyLine<Content: View>: View {
    let font: Font
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .leading) {
            Text(verbatim: "Ag")
                .font(font)
                .hidden()
                .accessibilityHidden(true)
            content
        }
    }
}

/// How many lines of the caption face a recommendation reason may print, and
/// therefore how tall the slot that holds one is. One number, read by the
/// reason itself and by the ghost that reserves its space, so the two can
/// never come to disagree.
private let listingCardReasonLines = 2

/// The reason's slot, whose height does not depend on whether this card has a
/// reason to put in it.
///
/// Same trick as `SteadyLine` and for the same reason, one size larger: the
/// ghost is as many lines of the caption face as a reason may print, drawn at
/// zero opacity and hidden from VoiceOver, so a card with nothing to say
/// spends exactly the space a card with something to say spends. At an
/// accessibility size the reason is allowed to run as long as it needs, so the
/// ghost stands down rather than fighting real text for the height.
private struct SteadyReasonSlot<Content: View>: View {
    let reserved: Bool
    let unlimited: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            if reserved, !unlimited {
                Text(verbatim: ghost)
                    .font(CalibreType.caption)
                    .hidden()
                    .accessibilityHidden(true)
            }
            content
        }
    }

    private var ghost: String {
        Array(repeating: "Ag", count: listingCardReasonLines).joined(separator: "\n")
    }
}

/// The one listing card. Every grid and lane of watches on every surface uses
/// it, and the element order below is fixed across the product
/// (CALIBRE_FINAL_PUSH_CONTRACTS.md §4):
///
///     [ photo, bleeding to the card edge, square, radius = card ]
///        ⌐ condition pill (top-left, over the photo)
///        ⌐ watcher count (top-right, over the photo)
///     BRAND                                          year
///     Model name
///     Ref. 0000000
///     [ reason, when supplied — its slot held for the whole shelf ]
///     $ price                        [ verified-dealer chip ]
///
/// The dealer mark sits on the price row rather than on a line of its own —
/// Eytan, 2026-08-30: *"make the dealer mark on the right of the listing cards
/// next to the price, not on top of it, in the consumer apps — this way
/// everything stays lined up."* A row that renders only for a verified dealer
/// is a row that moves the price down a line on every other card, and the
/// element order §4 writes down was drawn before that was noticed. Same
/// element, same card, one row higher.
///
/// Borders define the card; the watch is the hero. Image loading is injected
/// so CalibreDesign stays UI-only.
public struct ListingCard<ImageContent: View>: View {
    let model: ListingCardModel
    @ViewBuilder let image: (URL?) -> ImageContent

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(model: ListingCardModel, @ViewBuilder image: @escaping (URL?) -> ImageContent) {
        self.model = model
        self.image = image
    }

    /// The mark is measured in the price row and drawn over it.
    ///
    /// Standing in the `HStack` as an ordinary child it reserved its width —
    /// which is what keeps it from ever sitting on top of a $1,250,000 — but
    /// it also lent the row 1.667pt of its own height, hanging below the
    /// price's descender, and a dealer card came out 265.00pt tall beside a
    /// 263.33pt one. Measured, not guessed: `ListingCardAlignmentTests`.
    ///
    /// So it does both jobs from two places. The copy inside the row is
    /// hidden and forced to zero height, so it contributes width and nothing
    /// else; the copy in the `.overlay` draws, centred on the price's line
    /// box, and an overlay by definition cannot change the size of what it
    /// covers. Same view, same size, one of them invisible.
    private var dealerMark: some View {
        DealerBadge(compact: true).fixedSize()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // `.aspectRatio(1, contentMode: .fill)` alone can't guarantee a
            // square when the proposed height is ambiguous (a flexible-height
            // ancestor, e.g. a LazyVGrid cell) — it can size well past the
            // proposed width and bleed into neighboring cells. Reserving the
            // footprint with `.fit` against a GeometryReader, then forcing the
            // content to that exact square, is square in every context.
            GeometryReader { proxy in
                let side = proxy.size.width
                ZStack(alignment: .topLeading) {
                    image(model.imageURL)
                        .frame(width: side, height: side)
                        .background(Color.calibre.secondary.opacity(0.5))
                        .clipped()

                    if let condition = model.condition {
                        ConditionPill(condition)
                            .padding(Space.s)
                    }

                    if let watchers = model.watcherCount, watchers > 0 {
                        WatcherPill(count: watchers)
                            .padding(Space.s)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }

                    // Bottom-left, under the condition pill and clear of the
                    // watcher count. Inside the square, so it adds nothing to
                    // the card's height and the shelf stays level.
                    if model.isInCart {
                        InCartPill()
                            .padding(Space.s)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                // A brand is a name and a year is a figure, and §0.6 lets
                // neither be clipped. Measured at 390pt in a two-up grid,
                // "Jaeger-LeCoultre" and "A. Lange & Söhne" both overran the
                // eyebrow's box once the year joined them on the line.
                //
                // The year is four characters and cannot usefully shrink, so
                // it takes its width first and is pinned against compression.
                // The brand takes what is left and gives way the one way that
                // keeps every character AND keeps the row one line high: it
                // scales down, to 0.65 of the eyebrow. It used to be allowed
                // a second line as well, and that second line is what dropped
                // the price of a Jaeger-LeCoultre 15pt below the price of the
                // Rolex standing beside it. Nothing here can produce an
                // ellipsis — which is the whole point, because putting the
                // brand's own width first is what cut "2…" off the year the
                // first time. `ListingCardAlignmentTests` measures the two
                // worst real brands against the width they actually get.
                SteadyLine(font: CalibreType.eyebrow) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Eyebrow(model.brand)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        if let year = model.year {
                            Spacer(minLength: Space.xs)
                            Eyebrow(year)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                        }
                    }
                }
                // One line each at the default size, so the price rows of two
                // cards standing side by side land level. Both shrink before
                // they clip: a model name is a name and a reference is an
                // identifier, and §0.6 lets neither end in an ellipsis —
                // "Santos…" identifies nothing, and the reference is how a
                // buyer checks a listing. Above the accessibility threshold
                // the limits lift entirely instead.
                SteadyLine(font: CalibreType.bodyMedium) {
                    Text(model.title)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.8)
                }
                // The reference row holds its line whether or not this
                // listing has a reference. A row that is simply absent is the
                // second thing that moved the price: two cards side by side,
                // one with a Ref. and one without, put their prices 15pt
                // apart. The placeholder is a real word rather than a space so
                // it carries the font's own line metrics, drawn at zero
                // opacity and hidden from VoiceOver — there is nothing there
                // to read, only a line to hold.
                SteadyLine(font: CalibreType.caption) {
                    Text(model.reference.map { "Ref. \($0)" } ?? "Ref.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.8)
                        .opacity(model.reference == nil ? 0 : 1)
                        .accessibilityHidden(model.reference == nil)
                }
                // The price is the one thing on this card that may never be
                // lost. It keeps the leading edge of its row — the watcher
                // count that used to share it (and truncate it to "$…" on a
                // $94,500 watch) rides on the photograph instead — and the
                // dealer mark joins it at the trailing edge.
                //
                // `.firstTextBaseline` is what makes the mark free: the row's
                // baseline is the deepest first-baseline among its children,
                // and the price's is deeper than the badge's at every
                // non-accessibility size, so adding the badge cannot push the
                // price down. The price takes its width first (`layoutPriority`)
                // and the badge is `.fixedSize()` so "Dealer" can never wrap
                // into a second line and change the row's height.
                // Why this watch, before what it costs. A reason read after
                // the figure is a justification; read before it, it is the
                // thing that makes the figure mean something.
                //
                // On a shelf that carries reasons at all, the slot is held on
                // every card — see `reservesReasonLine`. Without that, one
                // unjustified card among five would lift its own price two
                // lines and the shelf would read as a staircase, which is the
                // misalignment that put this line under the price in the
                // first place.
                if model.reservesReasonLine || !(model.reason ?? "").isEmpty {
                    SteadyReasonSlot(
                        reserved: model.reservesReasonLine,
                        unlimited: typeSize.isAccessibilitySize
                    ) {
                        if let reason = model.reason, !reason.isEmpty {
                            Text(reason)
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : listingCardReasonLines)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(model.priceText)
                        .font(CalibreType.price)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    if model.isVerifiedDealer {
                        Spacer(minLength: 0)
                        dealerMark
                            .frame(height: 0)
                            .hidden()
                    }
                }
                .overlay(alignment: .trailing) {
                    if model.isVerifiedDealer { dealerMark }
                }
                .padding(.top, 1)
            }
            .padding(.horizontal, 2)
        }
    }
}

#Preview("Listing card", traits: .sizeThatFitsLayout) {
    ListingCard(model: .init(
        id: "1",
        brand: "Rolex",
        year: "2019",
        title: "Submariner Date",
        reference: "116610LN",
        priceText: "$12,400",
        condition: "Very Good",
        watcherCount: 14,
        isVerifiedDealer: true,
        reason: "Because you saved a Submariner"
    )) { _ in
        Image(systemName: "clock")
            .resizable()
            .scaledToFit()
            .padding(40)
            .foregroundStyle(Color.calibre.placeholder)
    }
    .frame(width: 180)
    .padding()
    .background(Color.calibre.background)
}
