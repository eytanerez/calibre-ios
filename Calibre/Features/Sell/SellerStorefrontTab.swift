import CalibreDesign
import CalibreKit
import SwiftUI

/// Who the seller is, to a buyer.
///
/// One row of the shop's list rather than a stack of them: the tab is short,
/// and a single row is the only shape where one `.task` means one fetch — the
/// same modifier on a `Group` of rows would run once per row.
struct SellerStorefrontTab: View {
    @Environment(AppServices.self) private var services

    let username: String
    /// Where the seller stands in the dealer program. Absent until the
    /// dashboard has answered.
    let application: DealerApplication?
    let actions: SellerShopActions

    /// The dealer's line, as its author sees it. Loaded here rather than
    /// inside the editor because the preview above the editor reads the same
    /// object — one fetch, two views of it.
    @State private var bio: DealerBio?
    @State private var bioFailed = false

    private var isVerifiedDealer: Bool {
        application?.isVerified == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            storefrontPreview

            if isVerifiedDealer {
                lineSection
            }

            if let application {
                dealerCard(application)
            }
        }
        .sellRow()
        .task {
            // The line sits beside a verified-business badge, so there is no
            // version of it for a seller Calibre has not verified — and the
            // endpoint refuses them. Don't ask on their behalf.
            guard isVerifiedDealer, bio == nil else { return }
            await loadBio()
        }
    }

    // MARK: - How buyers see you

    private var storefrontPreview: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("How buyers see you")

            SellCard {
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack(spacing: Space.m) {
                        AvatarInitial(name: username, size: .m)
                        HStack(spacing: Space.s) {
                            Text("@\(username)")
                                .font(CalibreType.sectionTitle)
                                .foregroundStyle(Color.calibre.foreground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if isVerifiedDealer {
                                StatusBadge("Dealer", tone: .info)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    livePreviewLine
                }
                .padding(Space.l)
            }
            .accessibilityElement(children: .combine)

            Button("View your storefront") {
                actions.openStorefrontPage()
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))

            Text("The page a buyer lands on from search, exactly as they see it.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What a buyer is reading right now — the last words that cleared
    /// review, never whatever the dealer has typed since. Set in the hand,
    /// the same way the storefront sets it, because this is the one place on
    /// Calibre where a seller speaks in their own voice.
    ///
    /// A verified dealer with nothing live gets Calibre describing an
    /// absence, in the sans: putting that sentence in the hand would put
    /// words in their mouth. A seller who is not a dealer has no line to be
    /// missing.
    @ViewBuilder
    private var livePreviewLine: some View {
        if let live = bio?.live, !live.isEmpty {
            Text(live)
                .font(CalibreType.hand)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if isVerifiedDealer, bio != nil {
            Text("@\(username) hasn't written a storefront line yet.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        } else if isVerifiedDealer, !bioFailed {
            Rectangle()
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .shimmer()
        }
    }

    // MARK: - The line itself

    @ViewBuilder
    private var lineSection: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Say who you are, in one line")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Text("It sits under your name on your storefront, beside your dealer badge. One line, no line breaks. Someone reads it before it goes up.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let bio {
                StorefrontLineEditor(state: bio) { saved in
                    self.bio = saved
                }
            } else if bioFailed {
                EmptyState(
                    icon: "wifi.slash",
                    title: "Couldn't load your storefront line",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    Task { await loadBio() }
                }
            } else {
                VStack(alignment: .leading, spacing: Space.m) {
                    Rectangle().frame(maxWidth: .infinity).frame(height: 18).shimmer()
                    Rectangle().frame(maxWidth: .infinity).frame(height: 92).shimmer()
                }
            }
        }
    }

    private func loadBio() async {
        bioFailed = false
        do {
            bio = try await services.seller.dealerBio()
        } catch {
            if bio == nil { bioFailed = true }
        }
    }

    // MARK: - The dealer program

    /// A dealer is a verified business — no inventory threshold, no queue.
    /// Every rate on this card is quoted from the application payload; when
    /// the server hasn't stated one, the sentence runs without the number.
    @ViewBuilder
    private func dealerCard(_ application: DealerApplication) -> some View {
        switch application.status {
        case .none:
            dealerApplyCard(application)
        case .pending:
            dealerStatusCard(
                badgeText: "Verification in progress",
                badgeTone: .info,
                headline: "Your business details are being verified",
                lines: [
                    "Nothing more is needed from you. There is no approval queue and no one to wait on — when verification clears, dealer status turns on by itself."
                ]
            )
        case .verified:
            dealerVerifiedCard(application)
        case .revoked:
            dealerStatusCard(
                badgeText: "Dealer status ended",
                badgeTone: .neutral,
                headline: "You're selling as a private seller again",
                lines: dealerRevokedLines(application)
            )
        case .unknown:
            EmptyView()
        }
    }

    private func dealerApplyCard(_ application: DealerApplication) -> some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.m) {
                Eyebrow("Dealer program")

                Text("Apply as a dealer")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)

                Text("A dealer is a verified business. We collect your business legal name and EIN, verified through Stripe, so buyers know they are dealing with a real business. Calibre never sees your banking details — they stay with Stripe.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Space.s) {
                    dealerBenefit(dealerRateLine(application))
                    dealerBenefit("A dealer badge buyers can see")
                    dealerBenefit("A line about yourself on your storefront")
                    dealerBenefit("Bulk import and volume tools — bulk import is dealer-only")
                }

                Text("There is no approval queue and no waiting on a person. When verification clears, you are a dealer automatically.")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    actions.openDealerApplication()
                } label: {
                    Text("Apply as a dealer")
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .padding(.top, Space.xs)
            }
            .padding(Space.l)
        }
    }

    private func dealerVerifiedCard(_ application: DealerApplication) -> some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow("Dealer program")
                    Spacer()
                    DealerBadge()
                }

                if let name = application.companyName, InputValidation.isNonBlank(name) {
                    Text(name)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                }

                Text(verifiedDealerRateLine(application))
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Dealer status does not expire, and it isn't tied to how much you have listed.")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
        }
        .accessibilityElement(children: .combine)
    }

    private func dealerStatusCard(
        badgeText: String,
        badgeTone: StatusBadge.Tone,
        headline: String,
        lines: [String]
    ) -> some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow("Dealer program")
                    Spacer()
                    StatusBadge(badgeText, tone: badgeTone)
                }

                Text(headline)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.l)
        }
        .accessibilityElement(children: .combine)
    }

    private func dealerBenefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.calibre.primary)
            Text(text)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "The 4% dealer rate, instead of 6%" — both figures from the payload,
    /// and the sentence still works when neither has arrived.
    private func dealerRateLine(_ application: DealerApplication) -> String {
        switch (application.dealerFeePercent?.value, application.memberFeePercent?.value) {
        case (.some(let dealerRate), .some(let memberRate)):
            return "The \(feePercentText(dealerRate))% dealer rate, instead of \(feePercentText(memberRate))%"
        case (.some(let dealerRate), .none):
            return "The \(feePercentText(dealerRate))% dealer rate on every sale"
        default:
            return "The lower dealer rate on every sale"
        }
    }

    private func verifiedDealerRateLine(_ application: DealerApplication) -> String {
        guard let dealerRate = application.dealerFeePercent?.value else {
            return "Your sales are commissioned at the dealer rate."
        }
        return "Your sales are commissioned at the \(feePercentText(dealerRate))% dealer rate."
    }

    private func dealerRevokedLines(_ application: DealerApplication) -> [String] {
        var lines: [String] = []
        if let reason = application.revokedReason, InputValidation.isNonBlank(reason) {
            lines.append(reason)
        }
        lines.append("The badge, the bulk tools and the dealer rate have reverted. Your existing listings stay live and nothing about them changes.")
        return lines
    }
}
