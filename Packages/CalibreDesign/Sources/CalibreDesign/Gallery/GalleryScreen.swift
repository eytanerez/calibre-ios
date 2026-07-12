import SwiftUI

/// Design-system gallery — renders every component in the current appearance.
/// Not shipped in any user-facing navigation; used to verify the system and
/// catch visual regressions cheaply. Extended as components land.
public struct GalleryScreen: View {
    @State private var toastCenter = ToastCenter()
    @State private var offerSheetShown = false
    @State private var dealTab: DealTab = .offers
    @State private var priceLower: Double = 5_200
    @State private var priceUpper: Double = 38_000
    @State private var reviewRating = 4
    @State private var searchQuery = ""
    @State private var selectedBrands: Set<String> = ["Rolex"]
    @State private var referenceField = ""
    @State private var emailField = "not-an-email"
    @State private var passwordField = "hunter2!"

    private enum DealTab: CaseIterable {
        case offers, orders, saved

        var label: String {
            switch self {
            case .offers: "Offers"
            case .orders: "Orders"
            case .saved: "Saved"
            }
        }
    }

    private let brands = ["Rolex", "Omega", "Patek Philippe", "Cartier", "Tudor", "Audemars Piguet"]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    typographySection
                    buttonsSection
                    badgesSection
                    listingCardSection
                    specListSection
                    calloutSection
                    countdownSection
                    toastSection
                    emptyStateSection
                    sheetSection
                    segmentedTabsSection
                    priceRangeSection
                    starRatingSection
                    timelineSection
                    checkpointsSection
                    avatarSection
                    searchAndFiltersSection
                    formFieldsSection
                    photoSlotsSection
                }
                .padding(Space.margin)
            }
            .background(Color.calibre.background)
            .navigationTitle("Gallery")
            .toastHost(toastCenter)
            .sheet(isPresented: $offerSheetShown) { offerSheet }
        }
    }

    // MARK: - Existing sections

    private var typographySection: some View {
        section("Typography") {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Calibre").font(CalibreType.display)
                Text("Submariner Date").font(CalibreType.title)
                Text("Recent sales").font(CalibreType.sectionTitle)
                Text("$12,400").font(CalibreType.priceLarge).foregroundStyle(Color.calibre.foreground)
                Text("Body — warm, expert, unhurried. The confidence of a trusted dealer's shop.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                Eyebrow("Rolex · 2019")
            }
        }
    }

    private var buttonsSection: some View {
        section("Buttons") {
            VStack(spacing: Space.m) {
                Button("Buy Now") {}.buttonStyle(.calibre(.primary, fullWidth: true))
                Button("Make Offer") {}.buttonStyle(.calibre(.secondary, fullWidth: true))
                HStack {
                    Button("Save for Later") {}.buttonStyle(.calibreGhost)
                    Button("Remove") {}.buttonStyle(.calibreDestructive)
                }
            }
        }
    }

    private var badgesSection: some View {
        section("Badges & pills") {
            VStack(alignment: .leading, spacing: Space.m) {
                ConditionPill("Like New")
                HStack(spacing: Space.s) {
                    StatusBadge("Live", tone: .success)
                    StatusBadge("Pending review", tone: .info)
                    StatusBadge("Waiting on you", tone: .warning)
                    StatusBadge("Declined", tone: .danger)
                }
            }
        }
    }

    private var listingCardSection: some View {
        section("Listing card") {
            HStack(alignment: .top, spacing: Space.l) {
                ListingCard(model: .init(
                    id: "1",
                    brand: "Rolex",
                    year: "2019",
                    title: "Submariner Date",
                    reference: "116610LN",
                    priceText: "$12,400",
                    condition: "Very Good",
                    watcherCount: 14
                )) { _ in placeholderWatch }
                ListingCardSkeleton()
            }
        }
    }

    // MARK: - New sections

    private var specListSection: some View {
        section("Spec list") {
            SpecList([
                ("Reference", "116610LN"),
                ("Year", "2019"),
                ("Case", "40mm · Oystersteel"),
                ("Movement", "Calibre 3135 · Automatic"),
                ("Box & papers", "Full set"),
                ("Condition", "Very Good"),
            ])
        }
    }

    private var calloutSection: some View {
        section("Callout & icon tiles") {
            VStack(alignment: .leading, spacing: Space.m) {
                CalloutBand(
                    icon: "checkmark.shield",
                    title: "Authenticated by Calibre",
                    message: "Every watch is inspected by our in-house watchmakers before it ships to you.",
                    action: {}
                )
                CalloutBand(
                    icon: "shippingbox",
                    message: "Fully insured shipping — signature required on delivery."
                )
                HStack(spacing: Space.m) {
                    IconTile(systemName: "checkmark.shield")
                    IconTile(systemName: "shippingbox")
                    IconTile(systemName: "creditcard")
                    IconTile(systemName: "arrow.uturn.left")
                }
            }
        }
    }

    private var countdownSection: some View {
        section("Countdown") {
            HStack(spacing: Space.m) {
                CountdownChip(until: .now.addingTimeInterval(23 * 3_600 + 14 * 60))
                CountdownChip(until: .now.addingTimeInterval(14 * 60 + 22))
                CountdownChip(until: .now.addingTimeInterval(-60))
            }
        }
    }

    private var toastSection: some View {
        section("Toasts") {
            HStack(spacing: Space.s) {
                Button("Neutral") {
                    toastCenter.show(title: "Link copied")
                }
                .buttonStyle(.calibreSecondary)
                Button("Success") {
                    toastCenter.show(
                        title: "Offer sent",
                        message: "Geneva Watch Co. has 48 hours to respond.",
                        tone: .success
                    )
                }
                .buttonStyle(.calibreSecondary)
                Button("Error") {
                    toastCenter.show(
                        title: "Payment failed",
                        message: "Your card was declined.",
                        tone: .error,
                        action: .init(label: "Retry") {}
                    )
                }
                .buttonStyle(.calibreSecondary)
            }
        }
    }

    private var emptyStateSection: some View {
        section("Empty state") {
            EmptyState(
                icon: "heart",
                title: "Nothing saved yet",
                message: "Watches you save appear here so you can compare and act when the price is right.",
                actionTitle: "Browse the market",
                action: {}
            )
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
    }

    private var sheetSection: some View {
        section("Sheet scaffold") {
            Button("Preview offer sheet") { offerSheetShown = true }
                .buttonStyle(.calibreSecondary)
        }
    }

    private var offerSheet: some View {
        SheetScaffold(title: "Make an offer") {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Rolex Submariner Date · Ref. 116610LN")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                Text("$12,400")
                    .font(CalibreType.priceLarge)
                    .foregroundStyle(Color.calibre.foreground)
                CalloutBand(
                    icon: "info.circle",
                    message: "Offers are binding for 48 hours. The seller can accept, counter, or decline."
                )
                Button("Send Offer") { offerSheetShown = false }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
            }
        }
    }

    private var segmentedTabsSection: some View {
        section("Segmented tabs") {
            VStack(alignment: .leading, spacing: Space.m) {
                SegmentedTabs(
                    selection: $dealTab,
                    items: DealTab.allCases.map { ($0, $0.label) }
                )
                Text("Showing \(dealTab.label.lowercased())")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
    }

    private var priceRangeSection: some View {
        section("Price range") {
            PriceRangeSlider(
                lowerValue: $priceLower,
                upperValue: $priceUpper,
                in: 0...50_000,
                step: 100
            )
        }
    }

    private var starRatingSection: some View {
        section("Star rating") {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.s) {
                    StarRating(rating: 4.5)
                    Text("4.5 · 128 reviews")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                StarRating(selection: $reviewRating)
            }
        }
    }

    private var timelineSection: some View {
        section("Negotiation timeline") {
            VStack(spacing: Space.m) {
                TimelineRow(
                    side: .buyer,
                    heading: "You offered",
                    amount: "$11,800",
                    date: .now.addingTimeInterval(-7_200),
                    isFirst: true
                )
                TimelineRow(
                    side: .seller,
                    heading: "Geneva Watch Co. countered",
                    amount: "$12,100",
                    message: "Full set with 2019 papers — this is as low as I can go.",
                    date: .now.addingTimeInterval(-3_600)
                )
                TimelineRow(
                    side: .buyer,
                    heading: "You accepted",
                    amount: "$12,100",
                    date: .now.addingTimeInterval(-300),
                    isLast: true
                )
            }
        }
    }

    private var checkpointsSection: some View {
        section("Order progress") {
            ProgressCheckpoints(
                steps: ["Placed", "In transit", "Verified", "Shipped", "Delivered"],
                currentIndex: 2
            )
        }
    }

    private var avatarSection: some View {
        section("Avatars") {
            HStack(spacing: Space.l) {
                AvatarInitial(name: "Geneva Watch Co.", size: .s)
                AvatarInitial(name: "Geneva Watch Co.", size: .m)
                AvatarInitial(name: "Eytan Erez", size: .l)
            }
        }
    }

    private var searchAndFiltersSection: some View {
        section("Search & filters") {
            VStack(alignment: .leading, spacing: Space.m) {
                SearchField(text: $searchQuery)
                ChipRail {
                    ForEach(brands, id: \.self) { brand in
                        FilterChip(brand, isSelected: selectedBrands.contains(brand)) {
                            if selectedBrands.contains(brand) {
                                selectedBrands.remove(brand)
                            } else {
                                selectedBrands.insert(brand)
                            }
                        }
                    }
                }
                .padding(.horizontal, -Space.l)
            }
        }
    }

    private var formFieldsSection: some View {
        section("Form fields") {
            VStack(spacing: Space.xl) {
                CalibreTextField(
                    "Reference number",
                    text: $referenceField,
                    placeholder: "e.g. 116610LN"
                )
                CalibreTextField(
                    "Email",
                    text: $emailField,
                    placeholder: "you@example.com",
                    error: "Enter a valid email address."
                )
                CalibreTextField(
                    "Password",
                    text: $passwordField,
                    isSecure: true
                )
            }
        }
    }

    private var photoSlotsSection: some View {
        section("Photo slots") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.m) {
                    PhotoSlotRing(phase: .done) { placeholderThumb }
                    PhotoSlotRing(phase: .done) { placeholderThumb }
                    PhotoSlotRing(phase: .uploading(0.62)) { placeholderThumb }
                    PhotoSlotRing(phase: .failed) { placeholderThumb }
                    PhotoSlotRing(phase: .empty)
                    PhotoSlotRing(phase: .empty)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Helpers

    private var placeholderWatch: some View {
        Image(systemName: "clock")
            .resizable()
            .scaledToFit()
            .padding(40)
            .foregroundStyle(Color.calibre.placeholder)
    }

    private var placeholderThumb: some View {
        Image(systemName: "clock")
            .font(.system(size: 20))
            .foregroundStyle(Color.calibre.placeholder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.calibre.secondary)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(title).font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
            content()
        }
    }
}

#Preview("Gallery — light") {
    GalleryScreen()
}

#Preview("Gallery — dark") {
    GalleryScreen().preferredColorScheme(.dark)
}
