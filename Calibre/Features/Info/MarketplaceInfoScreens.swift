import CalibreDesign
import SwiftUI

/// Current marketplace rates used by seller education and pre-listing payout
/// estimates. Completed orders keep their server-provided historical snapshot.
enum MarketplaceFees {
    static let privateSellerPercent = Decimal(6)
    static let dealerPercent = Decimal(4)
    static let privateSellerKeepPercent = 94
    static let dealerKeepPercent = 96

    static func sellerPercent(isVerifiedDealer: Bool) -> Decimal {
        isVerifiedDealer ? dealerPercent : privateSellerPercent
    }
}

/// A first-party explanation of the marketplace, available without leaving
/// the app or signing in.
struct MarketplaceGuideScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("How Calibre works")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("A clear path from a watch you love to a watch you can trust.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    guideRow(
                        icon: "magnifyingglass",
                        title: "Find the right watch",
                        message: "Browse the market, save a shortlist, or make an offer to the seller."
                    )
                    divider
                    guideRow(
                        icon: "checkmark.shield",
                        title: "We inspect every sale",
                        message: "The seller ships to Calibre first. Our watchmakers authenticate the watch and verify its condition."
                    )
                    divider
                    guideRow(
                        icon: "shippingbox",
                        title: "It ships insured",
                        message: "After inspection, the watch travels to the buyer fully insured with signature confirmation."
                    )
                }
                .infoCard()

                VStack(alignment: .leading, spacing: Space.m) {
                    Text("The details")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)

                    NavigationLink {
                        FeeBreakdownScreen()
                    } label: {
                        destinationRow(
                            icon: "percent",
                            title: "Fees and payments",
                            message: "Seller rates, card processing, wire payments, tax, and shipping."
                        )
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        AuthenticationGuideScreen()
                    } label: {
                        destinationRow(
                            icon: "checkmark.shield",
                            title: "Authentication",
                            message: "What our watchmakers check before a watch ships."
                        )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var divider: some View {
        Divider().overlay(Color.calibre.border).padding(.leading, Space.touchTarget + Space.m)
    }

    private func guideRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Text(message)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
    }

    private func destinationRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.calibre.primary)
                .frame(width: 36, height: 36)
                .background(
                    Color.calibre.accent.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Text(message)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
                .padding(.top, Space.m)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .infoCard()
    }
}

/// The canonical in-app fee explanation. Seller rates are intentionally
/// explicit; contextual checkout and listing screens show final dollar values.
struct FeeBreakdownScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Fees, without surprises")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Calibre shows the final dollar breakdown before you list or pay.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                feeSection("Selling on Calibre") {
                    feeRateRow(
                        title: "Private seller",
                        rate: "6% seller fee",
                        detail: "You keep 94% of the agreed watch price before shipping."
                    )
                    divider
                    feeRateRow(
                        title: "Verified dealer",
                        rate: "4% seller fee",
                        detail: "You keep 96% of the agreed watch price before shipping."
                    )
                }

                CalloutBand(
                    icon: "shippingbox",
                    message: "Estimated shipping is listed separately in the payout preview, so it is never hidden inside the seller rate."
                )

                feeSection("Buying on Calibre") {
                    detailRow(
                        title: "Card or Apple Pay",
                        message: "A 3% card processing cost applies. Checkout shows the exact dollar amount."
                    )
                    divider
                    detailRow(
                        title: "Wire transfer",
                        message: "There is no card processing cost. The watch is reserved for 24 hours while payment arrives."
                    )
                    divider
                    detailRow(
                        title: "Shipping and tax",
                        message: "These are calculated from the delivery address and itemized before payment."
                    )
                }

                Text("Seller fees are based on the final agreed watch price, including an accepted offer. Completed sales keep the rate recorded when the order was placed.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Link("Read the Terms of Service", destination: URL(string: "https://buycalibre.com/terms")!)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.primary)
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("Fees and payments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var divider: some View {
        Divider().overlay(Color.calibre.border)
    }

    private func feeSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            VStack(spacing: 0) { content() }
                .infoCard()
        }
    }

    private func feeRateRow(title: String, rate: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Spacer(minLength: Space.m)
                Text(rate)
                    .font(CalibreType.bodySemiBold)
                    .foregroundStyle(Color.calibre.primary)
            }
            Text(detail)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .accessibilityElement(children: .combine)
    }

    private func detailRow(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
            Text(message)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .accessibilityElement(children: .combine)
    }
}

struct AuthenticationGuideScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Inspected before it ships")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Every watch sold on Calibre travels to our authentication center before it travels to the buyer.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    checkRow(
                        icon: "checkmark.shield",
                        title: "Authenticity",
                        message: "Our watchmakers examine the movement, case, dial, and papers against the reference's factory specification."
                    )
                    divider
                    checkRow(
                        icon: "clock.badge.checkmark",
                        title: "Condition",
                        message: "We verify the listing's grading part by part and compare what arrived with what the buyer ordered."
                    )
                    divider
                    checkRow(
                        icon: "shippingbox",
                        title: "Insured delivery",
                        message: "A watch that passes inspection ships fully insured with signature confirmation."
                    )
                }
                .infoCard()

                CalloutBand(
                    icon: "arrow.uturn.backward.circle",
                    message: "If a watch fails inspection, the sale does not proceed and the buyer is refunded in full."
                )
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("Authentication")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var divider: some View {
        Divider().overlay(Color.calibre.border).padding(.leading, Space.touchTarget + Space.m)
    }

    private func checkRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Text(message)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
    }
}

private extension View {
    func infoCard() -> some View {
        background(
            Color.calibre.card,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}
