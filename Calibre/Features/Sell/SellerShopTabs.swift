import CalibreDesign
import CalibreKit
import SwiftUI

// MARK: - The rooms

/// The seller's shop, in the order of their day: what am I selling, who wants
/// it, what have I sold and where is the money, how is it going, who am I. The
/// order is the point and is not configurable.
///
/// Sales and payouts used to be filed under Performance, beside the shop's
/// figures — so "when am I paid for this one" was a question answered on the
/// analytics tab. Work a seller has to do and money they are owed are not
/// analysis, and they have their own room now.
///
/// The raw values are persisted (`@AppStorage`), so they are the wire format
/// of a preference and must not be renamed to follow a title change: Insights
/// keeps `performance` as its stored value, which is also what lands a seller
/// who last used the old tab on the room that inherited its analysis.
enum SellerTab: String, CaseIterable, Identifiable {
    case listings
    case offers
    case orders
    case insights = "performance"
    case storefront

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listings: "Listings"
        case .offers: "Offers"
        case .orders: "Orders & payouts"
        case .insights: "Insights"
        case .storefront: "Storefront"
        }
    }

    /// What the tab is for. VoiceOver reads it after the name, so it says
    /// what tapping does rather than repeating the label.
    var accessibilityHint: String {
        switch self {
        case .listings: "Shows your inventory"
        case .offers: "Shows offers buyers have made"
        case .orders: "Shows your sales and your money"
        case .insights: "Shows how the shop is doing"
        case .storefront: "Shows how your storefront reads"
        }
    }
}

/// A count on a tab, and how it is spoken.
///
/// Only ever built for work that is actually waiting: a badge is a promise
/// that something is there, so there is no zero-valued badge to render.
struct SellerTabBadge: Equatable {
    let count: Int
    /// The count in words, because "2" on its own tells a screen-reader user
    /// nothing about what two of them are.
    let spoken: String

    init?(count: Int, spoken: (Int) -> String) {
        guard count > 0 else { return nil }
        self.count = count
        self.spoken = spoken(count)
    }
}

// MARK: - The strip

/// Every label at the width the word actually needs, with the strip's leftover
/// space split evenly between them, and a content-sized scrolling rail when
/// even that will not fit. `ViewThatFits` decides by measuring, so no
/// breakpoint is guessed and no label is shrunk to keep a layout that stopped
/// working.
///
/// **It used to be equal-width segments, and that is what clipped the longest
/// label mid-word.** `ViewThatFits` measures a candidate's *ideal* width and
/// that measurement was honest — the labels did sum to less than the strip.
/// What it cannot see is the division: `.frame(maxWidth: .infinity)` then hands
/// every segment an equal share of the strip regardless of what is in it, and
/// an equal share is narrower than the longest word. So the candidate that fit
/// as a whole truncated in its parts, and it truncated *only* while no tab
/// carried a count badge — with badges the sum went over and the scrolling rail
/// took over instead, which is why the clipped word came and went.
/// `TabStripLayout` distributes the slack rather than the width, so a segment
/// is never narrower than its own word.
struct TabStripLayout: Layout {
    /// The strip's natural width is the sum of what its segments need. Under
    /// an unspecified proposal — which is what `ViewThatFits` measures with —
    /// that is exactly the number that decides whether this candidate can be
    /// drawn without cutting a word.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = ideals.reduce(0) { $0 + $1.width }
        let height = ideals.map(\.height).max() ?? 0
        guard let offered = proposal.width, offered != .infinity else {
            return CGSize(width: natural, height: height)
        }
        // Reporting more than was offered is how this candidate declines: a
        // strip too narrow for its own labels must fall through to the rail
        // rather than be squeezed into one.
        return CGSize(width: max(natural, offered), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let natural = ideals.reduce(0, +)
        let share = subviews.isEmpty ? 0 : max(0, bounds.width - natural) / CGFloat(subviews.count)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = ideals[index] + share
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width
        }
    }
}

// MARK: - The bar

/// The shop's tab bar: peers over a hairline, a copper rule that wipes in under
/// the selected label, and a count on the ones with work waiting.
///
/// The labels are set one rung down the scale from `SegmentedTabs`'
/// `bodyMedium`, at `CalibreType.label`. That is what buys width back rather
/// than an abbreviation — no label here is ever shortened, and where the row
/// still will not fit a phone it scrolls instead. `SegmentedTabs` carries a few
/// short labels and no badges, so it keeps the larger size; the shared
/// treatment is the full-strength labels and the copper rule, not a point
/// size.
///
/// It draws exactly what `SegmentedTabs` draws — every label at full strength,
/// one weight, and the rule sized to the word rather than to the segment — but
/// it cannot *be* one: these tabs carry count badges. See that component for
/// why the rule is a scale and not a fade. It no longer slides between
/// segments via `matchedGeometryEffect`, so `ViewThatFits` building both
/// candidates is no longer a namespace problem: each segment now owns its own
/// rule and animates only its own x-scale.
struct SellerTabBar: View {
    @Binding var selection: SellerTab
    let badges: [SellerTab: SellerTabBadge]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            TabStripLayout() {
                ForEach(SellerTab.allCases) { tab in
                    // The frame expands the segment into the slack the layout
                    // hands it, so the hit area reaches its neighbour's and
                    // the label sits centred in it. Under the layout's
                    // unspecified measurement it reports the word's own width,
                    // which is what keeps the fit honest.
                    segment(tab)
                        .frame(maxWidth: .infinity)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xl) {
                    ForEach(SellerTab.allCases) { tab in
                        segment(tab)
                    }
                }
                .padding(.horizontal, Space.xs)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.calibre.border)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func segment(_ tab: SellerTab) -> some View {
        let isSelected = tab == selection
        let badge = badges[tab]
        return Button {
            guard !isSelected else { return }
            Haptics.shared.play(.selection)
            withAnimation(Motion.easeMedium) {
                selection = tab
            }
        } label: {
            HStack(spacing: Space.s) {
                Text(tab.title)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.foreground)
                    // Not `lineLimit(1)`, which answers a label that will not
                    // fit by cutting it. This one refuses to be compressed at
                    // all, so the layout above has to grant the word its width
                    // or hand the whole strip to the scrolling rail — the two
                    // outcomes §0.6 allows.
                    .fixedSize(horizontal: true, vertical: false)
                    // Under the word only. Hung off the HStack it would run
                    // under the count badge too, and off the padded frame it
                    // would run the width of the segment.
                    .overlay(alignment: .bottom) {
                        TabUnderline(isSelected: isSelected, reduceMotion: reduceMotion)
                    }
                if let badge {
                    countPill(badge.count)
                }
            }
            // The gaps between labels come from the slack the strip layout
            // distributes, so this is only the minimum air a word keeps when
            // there is no slack left to give.
            .padding(.horizontal, Space.xs)
            .frame(minHeight: Space.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue(badge?.spoken ?? "")
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func countPill(_ count: Int) -> some View {
        Text("\(count)")
            .font(CalibreType.caption)
            .monospacedDigit()
            .foregroundStyle(Color.calibre.primaryForeground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.calibre.primary, in: Capsule())
            // Spoken by the segment's own accessibility value, in words.
            .accessibilityHidden(true)
    }
}

// MARK: - The shop's verbs

/// Everything a tab can ask the shop to do.
///
/// One definition per verb, handed to every tab, for the same reason a row
/// declares its `RowAction`s once: an offer answered from the queue and an
/// offer answered from the Offers tab must be the same act, not two
/// implementations that drift.
@MainActor
struct SellerShopActions {
    /// Start a listing — from the header button, an empty state, or a
    /// demand suggestion that fills the first step in.
    var listWatch: (ListingPrefill?) -> Void
    /// Edit, or finish a draft: the wizard decides from the kind.
    var openWizard: (WizardContext.Kind) -> Void
    /// Tap-through for an inventory row, which lands wherever that row's
    /// status belongs.
    var openListing: (Listing) -> Void
    var confirmSubmit: (Listing) -> Void
    var confirmDelete: (Listing) -> Void
    var openSale: (String) -> Void
    var openOffer: (String) -> Void
    var openCardOnFile: () -> Void
    /// Finish the drafts a bulk import left behind.
    var continueImport: (ImportJobRef) -> Void
    var openBuyerRequests: () -> Void
    /// The seller's own public storefront, as a buyer reaches it.
    var openStorefrontPage: () -> Void
    var openDealerApplication: () -> Void
    /// Cross-tab jump: switch to Listings with one status already filtered,
    /// so a figure on Insights leads to the rows behind it.
    var showListings: (SellerListingFilter) -> Void
    var reload: () async -> Void
}

// MARK: - List row plumbing

extension View {
    /// Plain-list row chrome: no separators, quiet background, brand margins.
    func sellRow(top: CGFloat = 0, bottom: CGFloat = Space.xl) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: Space.margin, bottom: bottom, trailing: Space.margin))
    }

    /// A row for a rail that has to reach the screen edge, so its fade runs
    /// off the side instead of stopping short of it. `ChipRail` insets its own
    /// content by that fade, which lands the first chip on the standard
    /// margin.
    func sellRailRow(top: CGFloat = 0, bottom: CGFloat = Space.l) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: Space.xs, bottom: bottom, trailing: Space.xs))
    }
}

#if DEBUG
// MARK: - Looking at the strip

/// The tab strip at the widths it has to survive, reachable from the Me tab's
/// Developer section.
///
/// It exists because the seller dashboard is behind a sign-in and a Stripe
/// Connect readiness check, so the one screen this bar ships on cannot be put
/// in front of a reviewer's eyes in a few seconds — and a measurement is not a
/// look (CALIBRE_FINAL_PUSH_CONTRACTS.md §0.3). The narrowest phone the app
/// supports at its iOS 18 floor is 375pt wide, which leaves 335pt between the
/// screen margins; the other two rows are an iPhone 17 Pro and a Pro Max at
/// the same margins.
struct SellerTabStripHarness: View {
    @State private var plain: SellerTab = .listings
    @State private var badged: SellerTab = .insights

    private static let widths: [(name: String, content: CGFloat)] = [
        ("375pt phone", 335),
        ("402pt phone", 362),
        ("440pt phone", 400),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                ForEach(Self.widths, id: \.name) { width in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("\(width.name) · \(Int(width.content))pt of content")
                        SellerTabBar(selection: $plain, badges: [:])
                            .frame(width: width.content)
                        SellerTabBar(
                            selection: $badged,
                            badges: [
                                .listings: SellerTabBadge(count: 12, spoken: { "\($0) need your attention" })!,
                                .offers: SellerTabBadge(count: 34, spoken: { "\($0) waiting on you" })!,
                            ]
                        )
                        .frame(width: width.content)
                    }
                }
            }
            .padding(Space.margin)
        }
        .calibrePageBackground()
        .navigationTitle("Seller tab strip")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
