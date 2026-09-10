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

// MARK: - The bar

/// Content-sized pills, matching the inventory's filter rail. Every label
/// keeps its full width; narrower screens reveal the remaining pages by swiping.
struct SellerTabBar: View {
    @Binding var selection: SellerTab
    let badges: [SellerTab: SellerTabBadge]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ChipRail {
                ForEach(SellerTab.allCases) { tab in
                    segment(tab)
                        .id(tab)
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, tab in
                withAnimation(reduceMotion ? nil : Motion.easeMedium) {
                    proxy.scrollTo(tab, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func segment(_ tab: SellerTab) -> some View {
        let isSelected = tab == selection
        let badge = badges[tab]
        return Button {
            guard !isSelected else { return }
            Haptics.shared.play(.selection)
            selection = tab
        } label: {
            HStack(spacing: Space.s) {
                Text(tab.title)
                    .font(CalibreType.label)
                if let badge {
                    countPill(badge.count, isSelected: isSelected)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isSelected ? Color.calibre.primaryForeground : Color.calibre.foreground)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(minHeight: Space.touchTarget)
            .background(isSelected ? Color.calibre.primary : Color.calibre.card, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.clear : Color.calibre.border, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(reduceMotion ? nil : Motion.easeFast, value: isSelected)
        .accessibilityLabel(tab.title)
        .accessibilityValue(badge?.spoken ?? "")
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func countPill(_ count: Int, isSelected: Bool) -> some View {
        Text("\(count)")
            .font(CalibreType.caption)
            .monospacedDigit()
            .foregroundStyle(isSelected ? Color.calibre.primary : Color.calibre.primaryForeground)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 2)
            .background(isSelected ? Color.calibre.primaryForeground : Color.calibre.primary, in: Capsule())
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
