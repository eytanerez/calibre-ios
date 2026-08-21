import CalibreDesign
import CalibreKit
import SwiftUI

/// A first-party explanation of the marketplace, available without leaving
/// the app or signing in.
struct MarketplaceGuideScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero
                howItWorks
                concierge
                details
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("How Calibre works")
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text("A clear path from a watch you love to a watch you can trust.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorks: some View {
        VStack(spacing: 0) {
            guideRow(
                icon: "magnifyingglass",
                title: "Find the right watch",
                message: "Browse the market, save a shortlist, or make an offer to the seller. Listings never expire — a listing stays live until it sells or the seller takes it down."
            )
            divider
            guideRow(
                icon: "lock",
                title: "Checkout holds the watch",
                message: "Starting checkout reserves the watch so nobody else can buy it while you finish. If you step away, the reservation releases on its own."
            )
            divider
            guideRow(
                icon: "checkmark.shield",
                title: "Every sale is authenticated",
                message: "The seller ships to the authentication centre first, where a third-party partner verifies the watch before it goes anywhere near the buyer."
            )
            divider
            guideRow(
                icon: "shippingbox",
                title: "It ships insured, on every leg",
                message: "Every label requires a direct signature and is insured for the full sale price. Calibre buys the inbound label to the authentication centre once the seller submits their shipping details, and what it actually costs comes off the seller\u{2019}s payout. The buyer pays outbound at checkout."
            )
        }
        .infoCard()
    }

    private var concierge: some View {
        CalloutBand(
            icon: "person.crop.circle",
            title: "One person, start to finish",
            message: "Every customer has one named Calibre contact, and messages come personally from them at support@buycalibre.com. Email there or write to us in the app — it is the same conversation either way."
        )
    }

    private var details: some View {
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
                    message: "Seller rates, what a card and a wire cost, sales tax, and how prices are shown."
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                AuthenticationGuideScreen()
            } label: {
                destinationRow(
                    icon: "checkmark.shield",
                    title: "Authentication",
                    message: "What the partner checks, how long it takes, and what happens if a watch does not pass."
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                ReturnsPolicyScreen()
            } label: {
                destinationRow(
                    icon: "arrow.uturn.backward",
                    title: "Returns",
                    message: "How a return window runs, what a refund includes, and what it means for the seller."
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                SellerPayoutsGuideScreen()
            } label: {
                destinationRow(
                    icon: "banknote",
                    title: "When sellers get paid",
                    message: "The two payout rules, the dates you see, and what happens if a payout fails."
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                DealerProgramGuideScreen()
            } label: {
                destinationRow(
                    icon: "checkmark.seal",
                    title: "The dealer program",
                    message: "How a verified business qualifies, and exactly what dealer status brings."
                )
            }
            .buttonStyle(PressableStyle())
        }
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
        .accessibilityElement(children: .combine)
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
        .accessibilityElement(children: .combine)
    }
}

/// The canonical in-app fee explanation. Seller rates are intentionally
/// explicit; contextual checkout and listing screens show final dollar values.
///
/// Every figure here prefers the live marketplace config and falls back to the
/// canonical wording only when the config has not landed yet.
struct FeeBreakdownScreen: View {
    @Environment(AppServices.self) private var services: AppServices?

    private var config: MarketplaceConfig? { services?.config.config }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero
                sellerRates
                minimumCommission
                payingByCard
                payingByWire
                howPricesAreShown
                footer
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("Fees and payments")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { services?.config.warm() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Fees, without surprises")
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text("Calibre shows the final dollar breakdown before you list and before you pay. These are the rules behind those numbers.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sellerRates: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            feeSection("Selling on Calibre") {
                feeRateRow(
                    title: "Private seller",
                    rate: "\(PolicyCopy.sellerRate(config, dealer: false)) seller fee",
                    detail: "You keep \(PolicyCopy.sellerKeep(config, dealer: false)) of the final agreed watch price."
                )
                divider
                feeRateRow(
                    title: "Verified dealer",
                    rate: "\(PolicyCopy.sellerRate(config, dealer: true)) seller fee",
                    detail: "You keep \(PolicyCopy.sellerKeep(config, dealer: true)) of the final agreed watch price."
                )
                divider
                detailRow(
                    title: "Free to list",
                    message: "There are no listing fees, no monthly fees, and no buyer premium."
                )
            }

            CalloutBand(
                icon: "shippingbox",
                message: "Estimated shipping is listed separately in the payout preview, so it is never hidden inside the seller rate."
            )
        }
    }

    private var minimumCommission: some View {
        feeSection("The minimum commission") {
            detailRow(
                title: "Every sale carries a \(PolicyCopy.minimumCommission(config)) minimum",
                message: "The seller fee is whichever is greater — the percentage or the minimum — and it applies per sale. You always see it worked into a real dollar figure before you publish a listing or accept an offer."
            )
            divider
            detailRow(
                title: "A worked example",
                message: "On a $10,000 sale a private seller is paid $9,400, and a verified dealer is paid $9,600. On smaller sales the minimum can be the larger of the two, and then it is the minimum that applies."
            )
        }
    }

    private var payingByCard: some View {
        feeSection("Paying by card") {
            detailRow(
                title: "What a card costs",
                message: "A card costs \(PolicyCopy.cardFee(config)). That is exactly our cost of accepting the card, never more. It appears as its own line on the receipt before you pay, and you can switch to wire once you have seen it."
            )
            divider
            detailRow(
                title: "The card fee on a return",
                message: "If the watch is returned, the card fee is not refunded. We say so at checkout, before you buy."
            )
            divider
            detailRow(
                title: "Which cards work",
                message: "Prepaid cards are not accepted anywhere on Calibre. Debit cards are accepted only where the discount presentation applies. The card form tells you at card entry, while you can still choose wire."
            )
        }
    }

    private var payingByWire: some View {
        feeSection("Paying by wire") {
            detailRow(
                title: "No processing cost",
                message: "A wire costs nothing to process, and wire is available at any price."
            )
            divider
            detailRow(
                title: "The watch is held while it arrives",
                message: "Choosing wire holds the watch for \(PolicyCopy.wireHold(config)) while the transfer arrives. The order advances on its own the moment the transfer lands, and if the funds do not arrive in time the hold releases automatically."
            )
        }
    }

    private var howPricesAreShown: some View {
        feeSection("How prices are shown") {
            detailRow(
                title: "Where wire is presented as a discount",
                message: "In \(PolicyCopy.discountStates(config)), where a surcharge is prohibited and a discount is permitted, the listed price is the card price and paying by wire receives a discount off it. The final total is identical in every state — only the way it is presented differs. Debit is accepted there; prepaid still is not."
            )
            divider
            detailRow(
                title: "Sales tax",
                message: "Sales tax is calculated on the actual transaction price for the payment method you choose, and it is itemized before you pay."
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Seller fees are calculated on the final agreed watch price, and an accepted offer is the agreed price. Completed sales keep the rate recorded when the order was placed.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            Link("Read the Terms of Service", destination: URL(string: "https://buycalibre.com/terms")!)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.primary)
        }
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

    /// Deliberately *not* combined into one accessibility element: the rate
    /// ("6% seller fee") is the load-bearing string on this screen, and it has
    /// to stay individually addressable for VoiceOver's rotor and for the
    /// UI test that pins it.
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
    }

    private func detailRow(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
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
                hero
                checks
                commitment
                outcomes
                sellerCard
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("Authentication")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Inspected before it ships")
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every watch sold on Calibre travels to the authentication centre before it travels to the buyer. The inspection is carried out by a third-party partner, not by us.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checks: some View {
        VStack(spacing: 0) {
            checkRow(
                icon: "checkmark.shield",
                title: "Authenticity",
                message: "The partner's watchmakers examine the movement, case, dial, and papers against the reference's factory specification."
            )
            divider
            checkRow(
                icon: "clock.badge.checkmark",
                title: "Condition",
                message: "The listing's grading is verified part by part, and what arrived is compared with what the buyer ordered."
            )
            divider
            checkRow(
                icon: "shippingbox",
                title: "Insured delivery",
                message: "A watch that passes ships fully insured, with a direct signature required on delivery."
            )
        }
        .infoCard()
    }

    private var commitment: some View {
        CalloutBand(
            icon: "clock",
            title: "72 hours, committed",
            message: "Authentication runs on a 72-hour commitment from arrival to verdict. If it runs long, the buyer hears from their Calibre contact before having to ask."
        )
    }

    private var outcomes: some View {
        section("If a watch does not pass") {
            detailRow(
                title: "Counterfeit",
                message: "Authentication is free. The buyer is refunded in full, including the card fee. The seller is charged 5% of the sale price to the card they have on file, and the watch is destroyed — it cannot legally be returned to anyone. The evidence, the destruction, and every message about it are recorded permanently."
            )
            plainDivider
            detailRow(
                title: "Genuine, but not as described",
                message: "This is urgent and settled case by case. Either the buyer takes a partial refund and the payout is reduced to match, or the watch ships back and the seller is charged 5% plus the cost of the label."
            )
        }
    }

    private var sellerCard: some View {
        section("Sellers: the card on file") {
            detailRow(
                title: "A credit card, before you list",
                message: "Sellers finish onboarding with a credit card on file — credit only, no debit and no prepaid. It is what makes the outcomes above enforceable. If that card is close to expiring, we tell the seller before it lapses rather than after."
            )
        }
    }

    private var divider: some View {
        Divider().overlay(Color.calibre.border).padding(.leading, Space.touchTarget + Space.m)
    }

    private var plainDivider: some View {
        Divider().overlay(Color.calibre.border)
    }

    private func section<Content: View>(
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
        .accessibilityElement(children: .combine)
    }

    private func detailRow(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Returns

/// The returns policy in one place, from both sides of the sale.
struct ReturnsPolicyScreen: View {
    @Environment(AppServices.self) private var services: AppServices?

    private var config: MarketplaceConfig? { services?.config.config }

    var body: some View {
        PolicyScaffold(
            title: "Returns",
            intro: "Sellers decide whether they accept returns, and buyers see that decision before they buy.",
            navigationTitle: "Returns"
        ) {
            sellerChoice
            howTheWindowRuns
            whatIsRefunded
            examples
            sellerSide
            footnote
        }
        .onAppear { services?.config.warm() }
    }

    private var sellerChoice: some View {
        PolicySection("The seller decides") {
            PolicyRow(
                "Set at listing time",
                "A seller chooses whether they accept returns and, if they do, whether the window is \(PolicyCopy.returnWindows(config)). The choice is visible to buyers before purchase, and it is locked onto the order at the moment of sale."
            )
            PolicyDivider()
            PolicyRow(
                "The trade-off, plainly",
                "A listing without returns pays out when authentication passes. A listing with returns pays out when the return window closes. That is the whole difference."
            )
        }
    }

    private var howTheWindowRuns: some View {
        PolicySection("How the window runs") {
            PolicyRow(
                "When the clock starts",
                "The window starts when the buyer signs for the watch, or two business days after the first delivery attempt, whichever comes first."
            )
            PolicyDivider()
            PolicyRow(
                "Starting a return stops the clock",
                "The buyer then has 48 hours, counted in business days, to send the watch back, with an \u{201C}I shipped it\u{201D} button to confirm it is on its way."
            )
            PolicyDivider()
            PolicyRow(
                "Calibre generates the label",
                "The return label requires a direct signature and is insured for the full sale price, and its cost is deducted from the refund. The watch goes back to the authentication centre and is verified before anything is refunded."
            )
        }
    }

    private var whatIsRefunded: some View {
        PolicySection("What a verified return refunds") {
            PolicyRow(
                "The refund",
                "The watch price and the sales tax are refunded in full, less a \(PolicyCopy.returnFee(config)) return fee with a \(PolicyCopy.returnMinimum(config)) minimum — calculated on the watch price alone — and less the original outbound shipping label. The card fee is not refunded. A buyer who paid by wire had no card fee, so an equivalent processing cost is withheld instead and the two outcomes stay comparable."
            )
            PolicyDivider()
            PolicyRow(
                "Before you confirm",
                "The exact refund figure is shown before a return is confirmed, so there is no arithmetic left for you to do."
            )
        }
    }

    private var examples: some View {
        PolicySection("Two worked examples") {
            PolicyRow(
                "A $10,000 purchase paid by card",
                "With a $150 outbound label, the refund is $10,000 plus tax, less $700 for the return fee and less $150 for the label. The card fee of roughly $294 is not refunded."
            )
            PolicyDivider()
            PolicyRow(
                "A $2,000 purchase",
                "The return fee is $250 — the minimum, since 7% of the watch price would only be $140."
            )
        }
    }

    private var sellerSide: some View {
        PolicySection("The seller's side") {
            PolicyRow(
                "The seller pays nothing",
                "On a return the seller pays nothing, receives the watch back, and chooses whether to relist it or take it down."
            )
            PolicyDivider()
            PolicyRow(
                "If the returned watch fails verification",
                "If the wrong watch comes back, or it is damaged, or it turns out to be counterfeit: there is no refund, the seller is paid as though the sale completed, the watch is held, and the buyer's Calibre contact takes the case over urgently."
            )
            PolicyDivider()
            PolicyRow(
                "If a watch is lost on the way back",
                "A watch lost or damaged on the return leg is Calibre's to claim and settle on both sides. Neither customer deals with a carrier."
            )
        }
    }

    private var footnote: some View {
        Text("Returns apply identically to an accepted offer. An accepted offer is a sale, with the same fees and the same return terms as any other purchase.")
            .font(CalibreType.caption)
            .foregroundStyle(Color.calibre.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Payout timing

/// When a seller's money moves, and why the date is what it is.
struct SellerPayoutsGuideScreen: View {
    var body: some View {
        PolicyScaffold(
            title: "When sellers get paid",
            intro: "There are two rules, and you always see which one applies to a sale and why.",
            navigationTitle: "Seller payouts"
        ) {
            rules
            dates
            ifSomethingGoesWrong
            disputes
        }
    }

    private var rules: some View {
        PolicySection("The two rules") {
            PolicyRow(
                "A listing without returns",
                "The payout releases when authentication passes — before the buyer even has the watch."
            )
            PolicyDivider()
            PolicyRow(
                "A listing that accepts returns",
                "The payout releases when the return window closes. The watch has to be settled with the buyer before the money is settled with you."
            )
        }
    }

    private var dates: some View {
        PolicySection("The dates you see") {
            PolicyRow(
                "Two dates, not one",
                "You see the date the payout released, and the date it should reach your bank — about two business days later."
            )
            PolicyDivider()
            PolicyRow(
                "Your first payout",
                "A new seller's first payout can take 7 to 14 days whichever rule applies. We tell you during onboarding, and the date you see already reflects it."
            )
        }
    }

    private var ifSomethingGoesWrong: some View {
        PolicySection("If something goes wrong") {
            PolicyRow(
                "A payout that fails",
                "You hear about it immediately, with the actual reason and what to fix — not a generic error and not silence."
            )
            PolicyDivider()
            PolicyRow(
                "Changing your bank details",
                "Changing where your money goes never affects a payout already on its way. New payouts go to the new bank account."
            )
        }
    }

    private var disputes: some View {
        CalloutBand(
            icon: "checkmark.shield",
            title: "A dispute after payout is ours",
            message: "If a buyer disputes a sale after you have been paid, that is Calibre's problem to work through, not yours. You keep your money."
        )
    }
}

// MARK: - Dealer program

/// What dealer status is, how a business gets it, and exactly what it brings.
struct DealerProgramGuideScreen: View {
    @Environment(AppServices.self) private var services: AppServices?

    private var config: MarketplaceConfig? { services?.config.config }

    var body: some View {
        PolicyScaffold(
            title: "The dealer program",
            intro: "A dealer on Calibre is a verified business. Verification is the whole test — there is no queue and nobody to persuade.",
            navigationTitle: "Dealer program"
        ) {
            howToApply
            whatItBrings
            howItHolds
            footnote
        }
        .onAppear { services?.config.warm() }
    }

    private var howToApply: some View {
        PolicySection("How to become one") {
            PolicyRow(
                "Apply with your business details",
                "You complete a second verification step with your EIN and your business details. When verification clears you are a dealer automatically — no approval queue, and no waiting on a person."
            )
            PolicyDivider()
            PolicyRow(
                "What we collect, and why",
                "Your business legal name and EIN are verified so buyers know they are dealing with a real business. Your banking details stay with our payment processor and are never seen by Calibre."
            )
        }
    }

    private var whatItBrings: some View {
        PolicySection("Exactly three things") {
            PolicyRow(
                "The \(PolicyCopy.sellerRate(config, dealer: true)) rate",
                "Your seller fee moves from \(PolicyCopy.sellerRate(config, dealer: false)) to \(PolicyCopy.sellerRate(config, dealer: true)) on every sale, so you keep \(PolicyCopy.sellerKeep(config, dealer: true)) of the agreed watch price."
            )
            PolicyDivider()
            PolicyRow(
                "A dealer badge",
                "Buyers see the verified-business mark on your listings and on your profile."
            )
            PolicyDivider()
            PolicyRow(
                "Bulk import and volume tools",
                "Bulk import is dealer-only, alongside the tools for running inventory at volume."
            )
        }
    }

    private var howItHolds: some View {
        PolicySection("How it holds") {
            PolicyRow(
                "It does not expire",
                "Dealer status does not expire, and it is not tied to how much inventory you carry."
            )
            PolicyDivider()
            PolicyRow(
                "It can be revoked for cause",
                "If status is revoked, the badge, the tools, and the rate revert. Existing listings stay live."
            )
        }
    }

    private var footnote: some View {
        Text("Nothing else about how you sell on Calibre changes with dealer status.")
            .font(CalibreType.caption)
            .foregroundStyle(Color.calibre.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shared policy-screen furniture

/// The shared shape of a policy screen: a title, a settling sentence, then
/// stacked card sections.
private struct PolicyScaffold<Content: View>: View {
    private let title: String
    private let intro: String
    private let navigationTitle: String
    private let content: Content

    init(
        title: String,
        intro: String,
        navigationTitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.intro = intro
        self.navigationTitle = navigationTitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(title)
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(intro)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A titled card of stacked rows — the same idiom as `feeSection`.
private struct PolicySection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) { content }
                .infoCard()
        }
    }
}

/// One labelled paragraph inside a `PolicySection` — the same shape as
/// `detailRow`, read as a single element by VoiceOver.
private struct PolicyRow: View {
    private let title: String
    private let message: String

    init(_ title: String, _ message: String) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
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

private struct PolicyDivider: View {
    var body: some View {
        Divider().overlay(Color.calibre.border)
    }
}

// MARK: - Policy figures

/// Renders the figures these screens are allowed to state.
///
/// A live figure from `/config/marketplace` always wins; the fallback is the
/// canonical wording, used only until the config lands. Nothing here invents a
/// number — the "you keep" figure is the complement of the server's own rate,
/// which is exactly how canonical copy defines it.
private enum PolicyCopy {
    /// "6.00" → "6%", "2.90" → "2.9%". Never rounds to a different number.
    static func percentText(_ value: APIDecimal?) -> String? {
        guard let value else { return nil }
        return decimalText(value.value) + "%"
    }

    static func money(_ value: APIDecimal?) -> String? {
        guard let value else { return nil }
        return PriceFormatter.format(value.value)
    }

    static func sellerRate(_ config: MarketplaceConfig?, dealer: Bool) -> String {
        percentText(rawRate(config, dealer: dealer)) ?? (dealer ? "4%" : "6%")
    }

    static func sellerKeep(_ config: MarketplaceConfig?, dealer: Bool) -> String {
        guard let rate = rawRate(config, dealer: dealer) else {
            return dealer ? "96%" : "94%"
        }
        return decimalText(100 - rate.value) + "%"
    }

    static func minimumCommission(_ config: MarketplaceConfig?) -> String {
        money(config?.sellerFeeMinimum) ?? "$250"
    }

    static func cardFee(_ config: MarketplaceConfig?) -> String {
        guard let fee = config?.cardFee,
              let percent = percentText(fee.percent),
              let fixed = money(fee.fixed)
        else { return "2.9% + $0.30" }
        return "\(percent) + \(fixed)"
    }

    static func wireHold(_ config: MarketplaceConfig?) -> String {
        config?.wireReservationText ?? "24–48 hours"
    }

    static func returnFee(_ config: MarketplaceConfig?) -> String {
        percentText(config?.returnFee?.percent) ?? "7%"
    }

    static func returnMinimum(_ config: MarketplaceConfig?) -> String {
        money(config?.returnFee?.minimum) ?? "$250"
    }

    static func returnWindows(_ config: MarketplaceConfig?) -> String {
        let windows = config?.returnWindows ?? []
        switch windows.count {
        case 0:
            return "24, 48 or 72 hours"
        case 1:
            return "\(windows[0]) hours"
        default:
            let parts = windows.map { String($0) }
            let head = parts.dropLast().joined(separator: ", ")
            return head + " or " + (parts.last ?? "") + " hours"
        }
    }

    static func discountStates(_ config: MarketplaceConfig?) -> String {
        config?.discountStatesText ?? "Connecticut and Massachusetts"
    }

    private static func rawRate(_ config: MarketplaceConfig?, dealer: Bool) -> APIDecimal? {
        dealer ? config?.sellerFeePercentDealer : config?.sellerFeePercentMember
    }

    /// Trims a trailing `.00` without changing the value.
    private static func decimalText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
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
