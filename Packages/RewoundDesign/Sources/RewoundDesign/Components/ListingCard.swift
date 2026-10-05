import SwiftUI

/// A price drop or a "just listed", as the server tinted it: one short chip on
/// the photograph. The card draws it in the same row as the grade and the
/// watcher count (`CardPhotoBadges`), so the three can never lie on top of each
/// other.
public struct ListingCardSignal: Hashable, Sendable {
    public let label: String
    /// A price drop is green; everything else wears the brand colour. Neutral
    /// is the default so a tone this build has never heard of still reads.
    public let isPriceDrop: Bool

    public init(label: String, isPriceDrop: Bool = false) {
        self.label = label
        self.isPriceDrop = isPriceDrop
    }
}

/// Display-only data the card needs — RewoundKit models map into this.
public struct ListingCardModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let brand: String
    public let year: String?
    public let title: String
    public let reference: String?
    public let priceText: String
    /// The overall grade, drawn as a pill at the top-left of the photograph.
    public let condition: String?
    /// The seller's answers worth a buyer's glance, in the contract's order
    /// (polish, originality, box): "Unpolished", "All original", "Full set".
    /// Printed on one line of their own under the grade, joined with " · ";
    /// the line is held, empty, on a card with none.
    public let facts: [String]
    /// "Bracelet: Worn" when one graded part is worse than the overall grade,
    /// "2 parts graded lower" when several are; nil when none is.
    /// A neutral outlined pill beside the grade pill.
    public let partException: String?
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
    /// A price drop or "just listed" chip, on the photograph beside the grade.
    public let signal: ListingCardSignal?

    public init(
        id: String,
        brand: String,
        year: String? = nil,
        title: String,
        reference: String? = nil,
        priceText: String,
        condition: String? = nil,
        facts: [String] = [],
        partException: String? = nil,
        watcherCount: Int? = nil,
        imageURL: URL? = nil,
        isVerifiedDealer: Bool = false,
        isInCart: Bool = false,
        reason: String? = nil,
        reservesReasonLine: Bool = false,
        signal: ListingCardSignal? = nil
    ) {
        self.id = id
        self.brand = brand
        self.year = year
        self.title = title
        self.reference = reference
        self.priceText = priceText
        self.condition = condition
        self.facts = facts
        self.partException = partException
        self.watcherCount = watcherCount
        self.imageURL = imageURL
        self.isVerifiedDealer = isVerifiedDealer
        self.isInCart = isInCart
        self.reason = reason
        self.reservesReasonLine = reservesReasonLine
        self.signal = signal
    }
}

/// The overall grade as a small pill on the page ground, where a listing
/// card's text block prints it: "Like New", first on the condition row.
///
/// Not `ConditionPill`, which is the frosted plate that rides on a photograph.
/// This one sits on the card's own ground, so it wears the accent fill rather
/// than a plate that only reads over an image.
public struct GradePill: View {
    let grade: String

    /// The space either side of the word. A row that sets this pill in a text
    /// column hangs it left by exactly this much so the word stands on the text
    /// edge (see `CardConditionRow`).
    static let horizontalPadding: CGFloat = Space.s

    public init(_ grade: String) {
        self.grade = grade
    }

    public var body: some View {
        Text(grade)
            .font(RewoundType.sans(.semiBold, 12, relativeTo: .caption))
            .foregroundStyle(Color.rewound.accentForeground)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 3)
            .background(Color.rewound.accent, in: Capsule())
            // A grade is two words at most and never breaks across lines.
            .fixedSize()
    }
}

/// "Bracelet: Worn" when one part of the watch was graded below the whole,
/// "2 parts below Like New" when several were: a plain line of text under the
/// grade pill (2026-10-02).
///
/// It was an outlined pill beside the grade pill (Option D, 2026-10-01), and
/// Eytan, seeing it on a phone: "the x parts lower look terrible on mobile and
/// is a little confusing". Two capsules fighting for one row read as two
/// grades, and "graded lower" never said lower than what. A pill says what the
/// watch IS; this says what to look at, so it is text, and the count names the
/// grade it is below.
///
/// Neutral on purpose. A part graded lower is something to read, not an
/// alarm, so it wears the page's own ink, never the warning tint.
public struct PartExceptionChip: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(RewoundType.sans(.medium, 11, relativeTo: .caption2))
            .foregroundStyle(Color.rewound.foreground)
            // Never an ellipsis. The longest line this prints, "3 parts below
            // Very Good", is about 125pt against a 164pt shelf column; at an
            // accessibility size it takes a second line rather than a cut.
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

/// The grade pill, and under it the part note when a part was graded below
/// the whole: the first of a listing card's two condition rows.
///
/// The pill's LABEL stands on the same edge as every other line of the card.
/// The pill is a capsule with padding either side of its word, and set flush
/// to the text column it put "Like New" that far to the right of "Day-Date 40"
/// and "Ref." above it and the facts below (Eytan: it "feels shifted over and
/// looks off"). So the row is pulled left by the pill's own padding, and the
/// capsule hangs into the card's text inset while its word lines up with the
/// rest.
///
/// The grid card and the swipe deck no longer use this: their grade rides the
/// photograph again (`CardPhotoBadges`), where hanging into a margin is not a
/// question. It is the compact list row's (a 64pt thumbnail has no room for a
/// badge), where the capsule hangs into the gap beside the thumbnail.
///
/// The row is never absent: a card with no grade holds the grade pill's height
/// with a zero-opacity twin hidden from VoiceOver, the same way the card holds
/// its Ref. line, so a shelf's condition rows stand on one line.
public struct CardConditionRow: View {
    let grade: String?
    let part: String?
    /// Off on a surface that is not a shelf (the swipe deck, a list row),
    /// where an empty row would only be a gap.
    let reserves: Bool

    public init(grade: String?, part: String?, reserves: Bool = true) {
        self.grade = grade
        self.part = part
        self.reserves = reserves
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if reserves {
                GradePill("Very Good")
                    .hidden()
                    .accessibilityHidden(true)
            }
            if grade != nil || part != nil {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let grade {
                        GradePill(grade)
                            // The capsule hangs left by its own padding; the
                            // note below stays on the text edge.
                            .padding(.leading, -GradePill.horizontalPadding)
                    }
                    if let part {
                        PartExceptionChip(part)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([grade, part].compactMap { $0 }.joined(separator: ", "))
            }
        }
    }
}

/// The badges that ride the top of a listing photograph: the grade at the
/// top-left, and at the top-right the watcher count and, when the server has one,
/// the price-drop or "just listed" chip.
///
/// The grade was under the title from 2026-09-30 and went back onto the photo
/// on 2026-10-02 (Eytan: "push it up to the top of the image like before just
/// make sure that the long ones don't cut off with the views"). What cut off
/// before was a long grade ("Very Good") lying under a three-digit watcher
/// count, or under a "Price drop −12%" chip, because each was placed on its own
/// and nothing knew about the other. They are one row now, and the row decides.
/// If the grade and everything beside it fit on one line they stand at either
/// end of it; if they do not, the right-hand badges drop under the grade at the
/// left, which is the one place nothing else is. No badge is shrunk, wrapped or
/// truncated: each is `fixedSize`, and the row gives way by moving instead.
public struct CardPhotoBadges: View {
    let condition: String?
    let watchers: Int?
    let signal: ListingCardSignal?

    public init(condition: String?, watchers: Int?, signal: ListingCardSignal? = nil) {
        self.condition = condition
        self.watchers = watchers
        self.signal = signal
    }

    private var showsWatchers: Bool { (watchers ?? 0) > 0 }

    @ViewBuilder private var grade: some View {
        if let condition, !condition.isEmpty {
            ConditionPill(condition).fixedSize()
        }
    }

    @ViewBuilder private var trailing: some View {
        if showsWatchers || signal != nil {
            VStack(alignment: .trailing, spacing: Space.xs) {
                if let watchers, watchers > 0 {
                    WatcherPill(count: watchers).fixedSize()
                }
                if let signal {
                    CardSignalPill(signal: signal).fixedSize()
                }
            }
        }
    }

    @ViewBuilder private var stackedTrailing: some View {
        if showsWatchers || signal != nil {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let watchers, watchers > 0 {
                    WatcherPill(count: watchers).fixedSize()
                }
                if let signal {
                    CardSignalPill(signal: signal).fixedSize()
                }
            }
        }
    }

    public var body: some View {
        if (condition?.isEmpty == false) || showsWatchers || signal != nil {
            ViewThatFits(in: .horizontal) {
                // One line: the grade at the left end, the rest at the right.
                //
                // The gap is the spacer's own minimum rather than the stack's
                // spacing, which would be spent on both sides of the spacer and
                // cost a point and a half of room the badges need.
                HStack(alignment: .top, spacing: 0) {
                    grade
                    Spacer(minLength: Space.xs)
                    trailing
                }
                // Not enough width for that: everything at the left, one under
                // the next, so nothing lies on anything.
                VStack(alignment: .leading, spacing: Space.xs) {
                    grade
                    stackedTrailing
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// The price-drop or "just listed" chip as it rides on a photograph: the same
/// frosted plate the grade and the watcher count sit on.
public struct CardSignalPill: View {
    let signal: ListingCardSignal

    public init(signal: ListingCardSignal) {
        self.signal = signal
    }

    public var body: some View {
        Text(signal.label)
            .font(RewoundType.label)
            .foregroundStyle(signal.isPriceDrop ? Color.rewound.success : Color.rewound.primary)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 4)
            .background(Color.rewound.background.opacity(0.95), in: Capsule())
    }
}

/// The seller's answers on one line, in the contract's order and joined with
/// " · ": "Unpolished · All original · Full set". The second condition row.
///
/// One line at every non-accessibility size: the whole run shrinks (to 0.75
/// of the caption, the same floor family as the Ref. line) before any fact
/// could be cut, and nothing here can produce an ellipsis. The longest run
/// the contract can produce is 176pt at full size against a 164pt shelf
/// column. Above the accessibility threshold the limit lifts and the run
/// wraps instead.
///
/// A card with no answers holds the line anyway (`reserves`), so its price
/// stands level with a neighbour that has three.
public struct CardFactsLine: View {
    let facts: [String]
    let font: Font
    let reserves: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(facts: [String], font: Font = RewoundType.caption, reserves: Bool = true) {
        self.facts = facts
        self.font = font
        self.reserves = reserves
    }

    public var body: some View {
        if reserves || !facts.isEmpty {
            SteadyLine(font: font) {
                Text(facts.isEmpty ? "Ag" : facts.joined(separator: " \u{00B7} "))
                    .font(font)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.75)
                    .opacity(facts.isEmpty ? 0 : 1)
                    .accessibilityHidden(facts.isEmpty)
                    .accessibilityLabel(facts.joined(separator: ", "))
            }
        }
    }
}

extension EnvironmentValues {
    /// Set by a shelf or grid that gives each of its cards the height of the
    /// tallest one: the card then takes the extra height between its two
    /// condition rows, so a part pill that needed a second line on one card
    /// moves nothing on its neighbours (facts, reason and price stay level).
    /// Off by default, where a card is exactly as tall as its content.
    @Entry public var listingCardPinsPrice: Bool = false

    /// Whether a card holds its two condition rows (the grade row and the
    /// facts row) when it has nothing to put in them. On by default, which is
    /// what keeps a shelf's rows level card to card. A surface whose data can
    /// never carry a grade or facts (the Saved grid, fed by the account
    /// summary, which sends neither) turns it off rather than printing two
    /// empty lines under every watch.
    @Entry public var listingCardHoldsConditionRows: Bool = true
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
                .font(compact ? RewoundType.caption : RewoundType.label)
        }
        .foregroundStyle(Color.rewound.primary)
        .padding(.horizontal, compact ? 6 : Space.s)
        .padding(.vertical, compact ? 2 : 3)
        .background(Color.rewound.accent.opacity(0.6), in: Capsule())
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
                    .font(RewoundType.caption)
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
/// (REWOUND_FINAL_PUSH_CONTRACTS.md §4):
///
///     [ photo, bleeding to the card edge, square, radius = card ]
///        ⌐ grade (top-left) ... watcher count / price chip (top-right)
///     BRAND                                          year
///     Model name
///     Ref. 0000000
///     2 parts below Like New        (only when a part was graded lower)
///     Unpolished · All original · Full set
///     [ reason, when supplied — its slot held for the whole shelf ]
///     $ price                        [ verified-dealer chip ]
///
/// The grade left the photograph for the text block on 2026-09-30 (the
/// condition card contracts, Part D) and came back to it on 2026-10-02, at the
/// top-left, in a row with the watcher count and the price chip so a long grade
/// is never cut off by either (`CardPhotoBadges`). What stays in the text block
/// is the note on a part graded lower, and the seller's facts on a line of
/// their own. Every text row stands on the same line as its neighbours' whatever
/// is in it: "one has a bigger title than the other, still line everything up".
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
/// so RewoundDesign stays UI-only.
public struct ListingCard<ImageContent: View>: View {
    let model: ListingCardModel
    @ViewBuilder let image: (URL?) -> ImageContent

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.listingCardPinsPrice) private var pinsPrice
    @Environment(\.listingCardHoldsConditionRows) private var holdsConditionRows

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
                        .background(Color.rewound.secondary.opacity(0.5))
                        .clipped()

                    // The grade, the watcher count and the price chip are one
                    // row (`CardPhotoBadges`), because laid on separately a long
                    // grade went under the others and was cut off.
                    //
                    // No flexible frame around it: a frame that is flexible in
                    // height inside this `GeometryReader` made the photograph
                    // come out narrower than its card in a lane (measured: 140pt
                    // of 168). The row fills the width on its own and the stack
                    // is already top-leading.
                    CardPhotoBadges(condition: model.condition, watchers: model.watcherCount, signal: model.signal)
                        .padding(Space.s)

                    // Bottom-left, clear of the
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
            // The photograph is the first thing to be given its full square.
            // Without a priority it is the most flexible view in the stack, so
            // when the card is sized from its content (a lane, a pinned grid)
            // the text block was measured first and the photograph took what
            // was left: 140pt of a 168pt card.
            .layoutPriority(1)
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
                SteadyLine(font: RewoundType.eyebrow) {
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
                SteadyLine(font: RewoundType.bodyMedium) {
                    Text(model.title)
                        .font(RewoundType.bodyMedium)
                        .foregroundStyle(Color.rewound.foreground)
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
                SteadyLine(font: RewoundType.caption) {
                    Text(model.reference.map { "Ref. \($0)" } ?? "Ref.")
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.8)
                        .opacity(model.reference == nil ? 0 : 1)
                        .accessibilityHidden(model.reference == nil)
                }
                // The note on a part graded lower, when there is one. The grade
                // itself is on the photograph. A card with no note has no row
                // here at all; on a shelf that pins its cards to the tallest,
                // the slack below absorbs the line the noted card spent.
                if let part = model.partException {
                    PartExceptionChip(part)
                        .padding(.top, 3)
                }
                // On a shelf that gives every card the tallest one's height,
                // the slack goes HERE, between the part note and the facts.
                // Above it everything is anchored to the top (brand, title,
                // Ref., note); below it everything is anchored to the bottom
                // (facts, reason, price), and every one of those rows is a
                // fixed height. So the one row whose height varies, the note
                // on a part graded lower, is the only thing the slack has to
                // absorb, and every other row stands level with its
                // neighbours'.
                if pinsPrice {
                    Spacer(minLength: 0)
                }
                if holdsConditionRows || !model.facts.isEmpty {
                    CardFactsLine(facts: model.facts, reserves: holdsConditionRows)
                        .padding(.top, 1)
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
                                .font(RewoundType.caption)
                                .foregroundStyle(Color.rewound.mutedForeground)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : listingCardReasonLines)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(model.priceText)
                        .font(RewoundType.price)
                        .foregroundStyle(Color.rewound.foreground)
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
            .foregroundStyle(Color.rewound.placeholder)
    }
    .frame(width: 180)
    .padding()
    .background(Color.rewound.background)
}
