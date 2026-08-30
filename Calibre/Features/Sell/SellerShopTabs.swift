import CalibreDesign
import CalibreKit
import SwiftUI

// MARK: - The four rooms

/// The seller's shop, in the order of their day: what am I selling, who wants
/// it, how is it going, who am I.
///
/// The raw values are persisted (`@AppStorage`), so they are the wire format
/// of a preference and must not be renamed to follow a title change.
enum SellerTab: String, CaseIterable, Identifiable {
    case listings
    case offers
    case performance
    case storefront

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listings: "Listings"
        case .offers: "Offers"
        case .performance: "Performance"
        case .storefront: "Storefront"
        }
    }

    /// What the tab is for. VoiceOver reads it after the name, so it says
    /// what tapping does rather than repeating the label.
    var accessibilityHint: String {
        switch self {
        case .listings: "Shows your inventory"
        case .offers: "Shows offers buyers have made"
        case .performance: "Shows how your shop is doing"
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

/// The shop's tab bar: four peers over a hairline, a copper rule that wipes in
/// under the selected label, and a count on the ones with work waiting.
///
/// Equal-width segments while the four labels fit, and a content-sized
/// scrolling rail when they don't — which happens at the larger Dynamic Type
/// sizes long before it happens on a narrow phone. `ViewThatFits` decides by
/// measuring, so no breakpoint is guessed and no label is shrunk to keep a
/// layout that stopped working.
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
            HStack(spacing: 0) {
                ForEach(SellerTab.allCases) { tab in
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
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(1)
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
            .padding(.horizontal, Space.s)
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
    /// so a figure on Performance leads to the rows behind it.
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
