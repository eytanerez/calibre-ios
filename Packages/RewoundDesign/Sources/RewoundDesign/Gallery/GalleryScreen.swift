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
    @State private var markPlay = 0
    @State private var walletPick = "visa"

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
                    handSection
                    marksSection
                    buttonsSection
                    badgesSection
                    listingCardSection
                    guaranteeCardSection
                    walletCardSection
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
            .rewoundPageBackground()
            .navigationTitle("Gallery")
            .toastHost(toastCenter)
            .sheet(isPresented: $offerSheetShown) { offerSheet }
        }
    }

    // MARK: - Existing sections

    private var typographySection: some View {
        section("Typography") {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Rewound").font(RewoundType.display)
                Text("Submariner Date").font(RewoundType.title)
                Text("Recent sales").font(RewoundType.sectionTitle)
                Text("$12,400").font(RewoundType.priceLarge).foregroundStyle(Color.rewound.foreground)
                Text("Body — warm, expert, unhurried. The confidence of a trusted dealer's shop.")
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.foreground)
                Eyebrow("Rolex · 2019")
            }
        }
    }

    private var handSection: some View {
        section("The hand") {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Wore it every day for six years — it has the scars to prove it.")
                    .font(RewoundType.hand)
                    .foregroundStyle(Color.rewound.foreground)
                Text("hairline on the bezel edge, only catches the light at an angle")
                    .font(RewoundType.handSmall)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
        }
    }

    private var marksSection: some View {
        section("Marks") {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("The logo the vocabulary is measured from.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                RewoundLogoMark(size: 96)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.l)], spacing: Space.xl) {
                    mark("balanceWheel") { RewoundMark.balanceWheel(size: 88) }
                    mark("stamp") { RewoundMark.stamp(size: 88, trigger: markPlay) }
                    mark("waxSeal") { RewoundMark.waxSeal(size: 88, trigger: markPlay) }
                    mark("loupe") { RewoundMark.loupe(size: 88, trigger: markPlay) }
                    mark("dialArc") { RewoundMark.dialArc(0.62, size: 88, trigger: markPlay) }
                    mark("powerReserve") { RewoundMark.powerReserve(0.78, size: 88, trigger: markPlay) }
                    mark("crown") { RewoundMark.crown(size: 88, trigger: markPlay) }
                    mark("box") { RewoundMark.box(size: 88, trigger: markPlay) }
                }

                // What the surface does when a press mark lands on it. The
                // mark stays rigid; the card takes the hit.
                HStack(spacing: Space.l) {
                    RewoundMark.stamp(size: 56, trigger: markPlay)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authenticated").font(RewoundType.bodyMedium)
                        Text("Ref. 116610LN · in-house")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.l)
                .background(Color.rewound.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        .strokeBorder(Color.rewound.border, lineWidth: 1)
                )
                .markImpact(trigger: markPlay)

                Button("Fire the marks") { markPlay += 1 }
                    .buttonStyle(.rewoundSecondary)
            }
        }
    }

    private func mark(_ name: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: Space.s) {
            content()
                .frame(height: 88)
            Text(name)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
        }
    }

    private var buttonsSection: some View {
        section("Buttons") {
            VStack(spacing: Space.m) {
                Button("Buy Now") {}.buttonStyle(.rewound(.primary, fullWidth: true))
                Button("Make Offer") {}.buttonStyle(.rewound(.secondary, fullWidth: true))
                HStack {
                    Button("Save for Later") {}.buttonStyle(.rewoundGhost)
                    Button("Remove") {}.buttonStyle(.rewoundDestructive)
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
            VStack(alignment: .leading, spacing: Space.l) {
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

                // The two cards §4 is actually about: the longest brand on the
                // marketplace beside the widest price, both with every optional
                // element present. This pair is where the brand row used to
                // clip and where the reason used to sit above the brand.
                HStack(alignment: .top, spacing: Space.l) {
                    ListingCard(model: .init(
                        id: "2",
                        brand: "Jaeger-LeCoultre",
                        year: "2021",
                        title: "Reverso Tribute Duoface",
                        reference: "Q3988482",
                        priceText: "$14,300",
                        condition: "Like New",
                        watcherCount: 231,
                        isVerifiedDealer: true,
                        reason: "Because you saved a Reverso"
                    )) { _ in placeholderWatch }
                    ListingCard(model: .init(
                        id: "3",
                        brand: "A. Lange & Söhne",
                        year: "2018",
                        title: "Datograph Up/Down",
                        reference: "405.035",
                        priceText: "$94,500",
                        condition: "Excellent",
                        watcherCount: 8,
                        isVerifiedDealer: true
                    )) { _ in placeholderWatch }
                }
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
                    title: "Authenticated by Rewound",
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
                .buttonStyle(.rewoundSecondary)
                Button("Success") {
                    toastCenter.show(
                        title: "Offer sent",
                        message: "Geneva Watch Co. has 48 hours to respond.",
                        tone: .success
                    )
                }
                .buttonStyle(.rewoundSecondary)
                Button("Error") {
                    toastCenter.show(
                        title: "Payment failed",
                        message: "Your card was declined.",
                        tone: .error,
                        action: .init(label: "Retry") {}
                    )
                }
                .buttonStyle(.rewoundSecondary)
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
            .background(Color.rewound.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
        }
    }

    private var sheetSection: some View {
        section("Sheet scaffold") {
            Button("Preview offer sheet") { offerSheetShown = true }
                .buttonStyle(.rewoundSecondary)
        }
    }

    private var offerSheet: some View {
        SheetScaffold(title: "Make an offer") {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Rolex Submariner Date · Ref. 116610LN")
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
                Text("$12,400")
                    .font(RewoundType.priceLarge)
                    .foregroundStyle(Color.rewound.foreground)
                CalloutBand(
                    icon: "info.circle",
                    message: "Offers are binding for 48 hours. The seller can accept, counter, or decline."
                )
                Button("Send Offer") { offerSheetShown = false }
                    .buttonStyle(.rewound(.primary, fullWidth: true))
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
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
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
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
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

    /// Every state and every brand mark on one screen — the seam and the dead
    /// chip are the kind of thing a passing test cannot check.
    private var guaranteeCardSection: some View {
        section("Guarantee card") {
            VStack(alignment: .leading, spacing: Space.xl) {
                GuaranteeCard(brand: .visa, last4: "4242", expiry: "04/29", status: .onFile)
                GuaranteeCard(
                    brand: .mastercard,
                    last4: "0916",
                    expiry: "08/26",
                    status: .expiringSoon
                )
                GuaranteeCard(brand: .amex, last4: "0005", expiry: "06/26", status: .lapsed)

                Text("Compact — the size that sits inside a setup step.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                HStack(alignment: .top, spacing: Space.m) {
                    GuaranteeCard(
                        brand: .discover,
                        last4: "6011",
                        expiry: "11/28",
                        status: .onFile,
                        size: .compact
                    )
                }
                GuaranteeCard(
                    brand: GuaranteeCard.Brand(stripeBrand: "jcb"),
                    last4: nil,
                    expiry: nil,
                    status: .onFile,
                    size: .compact
                )
            }
        }
    }

    /// The buyer's card, in both the places it appears. It sits next to the
    /// guarantee card on purpose: the two must not be mistakable for each
    /// other, and that is only checkable side by side.
    private var walletCardSection: some View {
        section("Wallet card") {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Checkout — the card is the choice.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                WalletCardFace(
                    brand: .visa,
                    last4: "4242",
                    expiry: "04 / 29",
                    isDefault: true,
                    context: .select(isSelected: walletPick == "visa", onSelect: { walletPick = "visa" })
                )
                WalletCardFace(
                    brand: .mastercard,
                    last4: "0916",
                    expiry: "08 / 26",
                    context: .select(isSelected: walletPick == "mc", onSelect: { walletPick = "mc" })
                )
                WalletCardFace(
                    brand: GuaranteeCard.Brand(stripeBrand: "jcb"),
                    last4: "1155",
                    expiry: nil,
                    note: "This card can't hold a wire deposit.",
                    noteIsProblem: true,
                    isDisabled: true,
                    context: .select(isSelected: false, onSelect: {})
                )

                Text("Settings — the card carries its own controls.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                WalletCardFace(
                    brand: .amex,
                    last4: "0005",
                    expiry: "06 / 26",
                    context: .manage
                ) {
                    HStack(spacing: Space.l) {
                        Text("Make default")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.primary)
                        Text("Remove")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.destructive)
                        Spacer(minLength: 0)
                    }
                }
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
                RewoundTextField(
                    "Reference number",
                    text: $referenceField,
                    placeholder: "e.g. 116610LN"
                )
                RewoundTextField(
                    "Email",
                    text: $emailField,
                    placeholder: "you@example.com",
                    error: "Enter a valid email address."
                )
                RewoundTextField(
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
            .foregroundStyle(Color.rewound.placeholder)
    }

    private var placeholderThumb: some View {
        Image(systemName: "clock")
            .font(.system(size: 20))
            .foregroundStyle(Color.rewound.placeholder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.rewound.secondary)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(title).font(RewoundType.sectionTitle).foregroundStyle(Color.rewound.foreground)
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
