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
    /// supplies one. Renders last, under the price. §4 puts it there because
    /// a reason above the brand pushes brand/model/price down by a line and
    /// breaks the alignment of every card standing beside it.
    public let reason: String?

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
        reason: String? = nil
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
        self.reason = reason
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
///     [ verified-dealer chip, only when true ]
///     $ price
///     [ reason, when supplied ]
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
                // The brand takes what is left and gives way in the two ways
                // that keep every character: it scales down, and past that it
                // wraps to a second line. Nothing here can produce an ellipsis
                // — which is the whole point, because putting the brand's own
                // width first is what cut "2…" off the year the first time.
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Eyebrow(model.brand)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                    if let year = model.year {
                        Spacer(minLength: Space.xs)
                        Eyebrow(year)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                }
                // One line each at the default size, so the price rows of two
                // cards standing side by side land level. Both shrink before
                // they clip: a model name is a name and a reference is an
                // identifier, and §0.6 lets neither end in an ellipsis —
                // "Santos…" identifies nothing, and the reference is how a
                // buyer checks a listing. Above the accessibility threshold
                // the limits lift entirely instead.
                Text(model.title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
                if let reference = model.reference {
                    Text("Ref. \(reference)")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.8)
                }
                if model.isVerifiedDealer {
                    DealerBadge(compact: true)
                        .padding(.top, 2)
                }
                // The price is the one thing on this card that may never be
                // lost, and now it holds its row alone — the watcher count
                // that used to share it (and truncate it to "$…" on a $94,500
                // watch) rides on the photograph instead.
                Text(model.priceText)
                    .font(CalibreType.price)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
                if let reason = model.reason, !reason.isEmpty {
                    Text(reason)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
