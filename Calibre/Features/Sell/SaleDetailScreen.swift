import CalibreDesign
import CalibreKit
import NukeUI
import SwiftUI

/// One sale, from the seller's side: what sold, who bought it, the money
/// breakdown, and the fulfillment path (label purchase → label ready).
/// Owns its NavigationStack — present it modally, don't push it.
struct SaleDetailScreen: View {
    let orderID: String

    @Environment(AppServices.self) private var services
    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    private enum FlowStep: Hashable {
        case shippingDetails
        case labelReady
    }

    @State private var order: Order?
    @State private var loadError: String?
    @State private var path: [FlowStep] = []
    @State private var decidingRelist = false
    @State private var relistError: String?
    /// The seller's own handover declaration, and the grace period the server
    /// granted for the carrier's first scan.
    @State private var declaringShipped = false
    @State private var outboundDeclaration: FulfillmentShipped?
    @State private var declareError: String?
    @State private var packingNote = ""
    /// Payout details, opened from a failed payout.
    @State private var openingPayoutDetails = false
    @State private var payoutDetailsError: String?
    @State private var payoutConnect: PayoutConnectSession?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let order {
                    content(order)
                } else if let loadError {
                    EmptyState(
                        icon: "shippingbox",
                        title: "This sale didn't load",
                        message: loadError,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    saleSkeleton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .calibrePageBackground()
            .navigationTitle("Your sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: FlowStep.self) { step in
                switch step {
                case .shippingDetails:
                    if let order {
                        ShippingDetailsFlow(order: order) { updated in
                            self.order = updated
                            path = [.labelReady]
                        }
                    }
                case .labelReady:
                    if let order {
                        LabelReadyScreen(order: order)
                    }
                }
            }
        }
        .task {
            await load()
        }
        .fullScreenCover(item: $payoutConnect) { pending in
            ConnectOnboardingScreen(
                clientSecret: pending.clientSecret,
                publishableKey: pending.key,
                title: "Update payout details",
                onExit: {
                    payoutConnect = nil
                    Task { await load() }
                },
                onLoadFailure: { message in
                    payoutConnect = nil
                    payoutDetailsError = message
                }
            )
        }
    }

    private func load() async {
        loadError = nil
        do {
            let order = try await sell.ops.order(id: orderID)
            self.order = order
            // Only a failed payout needs to know how the payouts account
            // stands, and only then is the round trip worth taking: it decides
            // whether the recovery on this screen is a form or a person.
            if order.payoutBlock?.failureReason?.isEmpty == false {
                _ = try? await services.seller.loadReadiness()
            }
        } catch {
            loadError = sellErrorMessage(error)
        }
    }

    /// Stripe has rejected the account this payout would have landed in.
    ///
    /// Nil readiness is not a rejection — an unanswered question is not a "no",
    /// and treating it as one would hide the working recovery from a seller
    /// whose only problem is a wrong routing number.
    private var payoutAccountRejected: Bool {
        services.seller.readiness?.connect.status == .rejected
    }

    private var awaitingLabel: Bool {
        guard let order else { return false }
        return order.sellerActionState == "sold_awaiting_label_creation"
            || (order.status == .purchased && order.toAuthShipment == nil)
    }

    /// A label exists and the carrier hasn't scanned it yet — the same rule
    /// (and the same button) as the buyer's return leg.
    private func awaitingOutboundHandover(_ order: Order) -> Bool {
        guard let shipment = order.toAuthShipment else { return false }
        return shipment.shippedAt == nil && shipment.deliveredAt == nil
    }

    // MARK: - Content

    private func content(_ order: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                summary(order)

                if let deadline = order.fulfillmentDeadlineAt, awaitingLabel {
                    HStack(spacing: Space.m) {
                        Text("Ship by")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        CountdownChip(until: deadline)
                    }
                }

                financials(order)

                payoutTiming(order)

                if let summary = order.returnSummary {
                    returnSection(order, summary)
                }

                if awaitingLabel {
                    VStack(spacing: Space.s) {
                        Button("Add your shipping details") {
                            path.append(.shippingDetails)
                        }
                        .buttonStyle(.calibre(.primary, fullWidth: true))
                        Text("Tell us the box you are sending and Calibre buys the label \u{2014} prepaid, insured for the full sale price, to our authentication centre. You pay nothing now; the actual cost comes off your payout, and you see the figure before you confirm.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if order.toAuthShipment != nil {
                    Button("View shipping label") {
                        path.append(.labelReady)
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))

                    outboundHandover(order)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
    }

    private func summary(_ order: Order) -> some View {
        let badge = SellerStatusDisplay.badge(forOrder: order.status)
        return SellCard {
            HStack(spacing: Space.m) {
                SellThumb(url: order.listing?.image?.url, size: 64)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(order.listing?.title ?? "Sold watch")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(2)
                    // The number a person says out loud, and the one support
                    // will ask for.
                    Text(order.displayNumber)
                        .font(CalibreType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.calibre.mutedForeground)
                    StatusBadge(badge.text, tone: badge.tone)
                    if let buyer = order.shippingAddress?.fullName, !buyer.isEmpty {
                        Text("Sold to \(buyer)")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
        }
    }

    /// The payout ledger, from the order's own `payout.breakdown`: sale
    /// price, commission (with its rate and whether the minimum applied), the
    /// label Calibre bought, and the payout. Not one figure is arithmetic done
    /// here, and no money figure is ever shortened to fit.
    ///
    /// When the payload predates the breakdown the legacy rows stand in, and
    /// a figure the server did not state is simply not a row.
    private func financials(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Your payout")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            if let breakdown = order.payoutBlock?.breakdown {
                PayoutLedger(breakdown: breakdown, currency: order.currency)
            } else {
                SpecList(legacyFinancialRows(order))
            }

            SpecList(payoutStatusRows(order))
        }
    }

    /// Only for payloads recorded before `payout.breakdown` existed.
    private func legacyFinancialRows(_ order: Order) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Sale price", PriceFormatter.format(order.subtotal.value, currency: order.currency)),
        ]
        if let fee = order.sellerFeeAmount?.value {
            let percent = order.sellerFeePercentApplied?.value
            let label = percent.map { "Commission (\(compactPercent($0))%)" } ?? "Commission"
            rows.append((label, "− \(PriceFormatter.format(fee, currency: order.currency))"))
        }
        if let labelCost = order.sellerLabelPriceTotal?.value, labelCost > 0 {
            rows.append((
                "Shipping label to authentication",
                "− \(PriceFormatter.format(labelCost, currency: order.currency))"
            ))
        }
        if let receive = order.payoutBlock?.amount?.value {
            rows.append(("Your payout", PriceFormatter.format(receive, currency: order.currency)))
        }
        return rows
    }

    /// The backend's own status line, and the date it released on.
    private func payoutStatusRows(_ order: Order) -> [(String, String)] {
        var rows: [(String, String)] = [("Payout status", payoutStatusText(order))]
        if let released = order.payoutBlock?.releasedAt ?? order.payoutReleasedAt {
            rows.append(("Released", released.formatted(date: .abbreviated, time: .omitted)))
        }
        return rows
    }

    // MARK: - Outbound handover

    /// The seller's side of the same rule the buyer's return leg follows:
    /// declaring the handover buys a short grace period for the carrier's
    /// first scan, and the grace window granted is shown once it exists.
    @ViewBuilder
    private func outboundHandover(_ order: Order) -> some View {
        if awaitingOutboundHandover(order) {
            VStack(alignment: .leading, spacing: Space.s) {
                if let grace = outboundDeclaration?.autoCancelGraceUntil {
                    HStack(spacing: Space.m) {
                        Text("Scan expected by")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        CountdownChip(until: grace)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    Text("Thank you — noted. We'll watch for the carrier's first scan. If no scan follows, the original clock resumes and your Calibre contact takes it from there.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                } else if outboundDeclaration != nil {
                    Text("Thank you — noted. We'll watch for the carrier's first scan. If no scan follows, the original clock resumes and your Calibre contact takes it from there.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Written here or not at all: the declaration is the one
                    // moment the seller is holding the parcel, and only the
                    // first one records a note. It travels with the watch and
                    // the buyer reads it when the box arrives.
                    CalibreTextField(
                        "A line for the buyer (optional)",
                        text: $packingNote,
                        placeholder: "Set it running before I boxed it \u{2014} enjoy.",
                        kind: .sentence
                    )
                    .onChange(of: packingNote) { _, newValue in
                        if newValue.count > FulfillmentShipped.packingNoteLimit {
                            packingNote = String(newValue.prefix(FulfillmentShipped.packingNoteLimit))
                        }
                    }

                    Button {
                        Haptics.shared.play(.press)
                        Task { await declareOutboundShipped(order) }
                    } label: {
                        BusyLabel(title: "I shipped it", busy: declaringShipped)
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))
                    .disabled(declaringShipped)

                    Text("Tap this once you've handed the parcel over. Telling us buys a short grace period for the carrier's first scan.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Read back from the server rather than from the field, so
                // what is shown is what was actually recorded. The field is
                // gone by now and there is no second chance to write one.
                if let note = outboundDeclaration?.packingNote, !note.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Going with the watch")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        Text(note)
                            .font(CalibreType.hand)
                            .foregroundStyle(Color.calibre.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Space.xs)
                }

                if let declareError {
                    InlineErrorLine(message: declareError)
                }
            }
            .animation(Motion.easeFast, value: outboundDeclaration?.autoCancelGraceUntil)
        }
    }

    private func declareOutboundShipped(_ order: Order) async {
        guard !declaringShipped else { return }
        declaringShipped = true
        declareError = nil
        defer { declaringShipped = false }
        do {
            outboundDeclaration = try await sell.ops.declareOutboundShipped(
                orderID: order.id,
                packingNote: InputValidation.isNonBlank(packingNote) ? InputValidation.trimmed(packingNote) : nil
            )
            Haptics.shared.play(.success)
            toasts.show(
                title: "Thank you — noted",
                message: "We'll watch for the carrier's first scan.",
                tone: .success
            )
            await load()
        } catch {
            Haptics.shared.play(.error)
            declareError = sellErrorMessage(error)
        }
    }

    // MARK: - Payout timing

    /// The two dates a seller actually needs — when the payout released and
    /// when it should reach their bank — plus which rule decided the timing
    /// and why. A seller should never have to guess which one applies to them.
    @ViewBuilder
    private func payoutTiming(_ order: Order) -> some View {
        let payout = order.payoutBlock
        VStack(alignment: .leading, spacing: Space.m) {
            Text("When you get paid")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            VStack(alignment: .leading, spacing: Space.s) {
                Text(payoutTriggerSentence(order))
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                if payout?.firstPayoutHold == true {
                    Text("This is one of your first sales, so this payout may take 7 to 14 days to arrive. After that, payouts settle on the normal schedule.")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            let dates = payoutDateRows(order)
            if !dates.isEmpty {
                SpecList(dates)
            }

            if let failure = payout?.failureReason, !failure.isEmpty {
                CalloutBand(
                    icon: "exclamationmark.triangle",
                    title: "This payout didn't go through",
                    message: failure
                )

                if payoutAccountRejected {
                    // Stripe has rejected the account behind this payout, and
                    // that is terminal. "Update payout details" would mint a
                    // session into an account no set of details can revive —
                    // so the recovery here is a person, not a form.
                    Text("Stripe wasn't able to approve payouts for this account. Correcting your bank details won't release this payout.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)

                    NavigationLink {
                        SupportChatScreen(seed: payoutRejectedSupportMessage)
                    } label: {
                        Text("Talk to us about this").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))

                    Text("Someone from our team may already be reaching out about it.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // The reason alone isn't guidance. This says what to do
                    // about it, and the button opens the place to do it.
                    Text(payoutFixSentence(failure))
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Haptics.shared.play(.press)
                        Task { await openPayoutDetails() }
                    } label: {
                        BusyLabel(title: "Update payout details", busy: openingPayoutDetails)
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(openingPayoutDetails)

                    if let payoutDetailsError {
                        InlineErrorLine(message: payoutDetailsError)
                    }

                    Text("Changing your bank details never affects a payout already on its way — new payouts use the new account.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("If a buyer disputes a sale after you've been paid, that's ours to handle. You keep your money.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Which rule applies and why, in the seller's own terms. The trigger is
    /// the server's; only the sentence is ours.
    private func payoutTriggerSentence(_ order: Order) -> String {
        let released = order.payoutBlock?.releasedAt != nil
        switch order.payoutBlock?.trigger {
        case "auth_pass":
            return released
                ? "This listing doesn't accept returns, so your payout released when authentication passed."
                : "This listing doesn't accept returns, so your payout releases when authentication passes."
        case "return_window_close":
            // Item 1.22 — name the window where the order carries it.
            let window = order.returns?.windowHours.map { "\($0)-hour returns" } ?? "Returns are accepted"
            return released
                ? "\(window) on this listing, so your payout released when that window closed."
                : "\(window) on this listing, so your payout releases when that window closes."
        default:
            // No trigger on the payload — fall back to the listing's own
            // terms rather than inventing a rule.
            if let terms = order.returns {
                guard terms.accepted else {
                    return "This listing doesn't accept returns, so your payout releases when authentication passes."
                }
                // Item 1.22 — say the window. A seller waiting on money wants
                // to know how long, not that there is a wait.
                return terms.windowHours.map {
                    "This listing has \($0)-hour returns, so your payout releases when that window closes."
                } ?? "This listing accepts returns, so your payout releases when the return window closes."
            }
            return "Your payout releases once this sale is settled, and we'll show both dates here."
        }
    }

    /// What to fix, in the seller's terms. The server's reason is shown
    /// verbatim above this; these sentences only say what to do about it, and
    /// they never name the processor, a balance, or a connected account.
    private func payoutFixSentence(_ reason: String) -> String {
        let lowered = reason.lowercased()
        if lowered.contains("closed") || lowered.contains("no longer") {
            return "Your bank account looks closed. Add the account you'd like to be paid into and we'll send this payout again."
        }
        if lowered.contains("routing") || lowered.contains("account number") || lowered.contains("invalid")
            || lowered.contains("incorrect") || lowered.contains("could not be found") {
            return "Check the account and routing numbers on file — one of them isn't matching your bank. Correcting them is all this needs."
        }
        if lowered.contains("name") || lowered.contains("owner") || lowered.contains("mismatch") {
            return "The name on the bank account needs to match the name your account is verified under. Update it and we'll send this payout again."
        }
        return "Check your bank details and correct whatever the reason above points at. We'll send this payout again once they're right."
    }

    /// Opens payout details in the same embedded onboarding host the sell gate
    /// uses. The backend ignores the SSN field for an existing account.
    private func openPayoutDetails() async {
        guard !openingPayoutDetails else { return }
        openingPayoutDetails = true
        payoutDetailsError = nil
        defer { openingPayoutDetails = false }
        do {
            let session = try await sell.ops.connectAccountSession(ssn: "")
            let key = try await sell.stripeKey()
            payoutConnect = PayoutConnectSession(clientSecret: session.clientSecret, key: key)
        } catch {
            payoutDetailsError = sellErrorMessage(error)
        }
    }

    private func payoutDateRows(_ order: Order) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let released = order.payoutBlock?.releasedAt ?? order.payoutReleasedAt {
            rows.append(("Payout released", released.formatted(date: .abbreviated, time: .omitted)))
        }
        if let arrival = order.payoutBlock?.expectedArrivalAt {
            rows.append(("Expected in your bank", arrival.formatted(date: .abbreviated, time: .omitted)))
        }
        return rows
    }

    // MARK: - Returns

    /// A return on this sale. The seller pays nothing and gets the watch
    /// back; once it's refunded the only thing left is their choice.
    @ViewBuilder
    private func returnSection(_ order: Order, _ summary: OrderReturnSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("This sale was returned")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            Text("You pay nothing on a return, and the watch comes back to you. Calibre's label is insured for the full sale price on every leg.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if let tracking = summary.label?.trackingNumber, !tracking.isEmpty {
                SpecList([("Return tracking", tracking)])
            }

            if summary.isRefunded, summary.relistDecision == nil {
                relistPrompt(order)
            } else if let decision = summary.relistDecision {
                Text(
                    decision == "relist"
                        ? "It's back on the market."
                        : "It's been taken off the market and is yours to keep."
                )
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            }

            if let error = relistError {
                InlineErrorLine(message: error)
            }
        }
    }

    private func relistPrompt(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Would you like to list it again?")
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)

            HStack(spacing: Space.m) {
                Button {
                    Task { await decideRelist(order, relist: true) }
                } label: {
                    BusyLabel(title: "List it again", busy: decidingRelist)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(decidingRelist)

                Button {
                    Task { await decideRelist(order, relist: false) }
                } label: {
                    Text("Take it off the market").frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
                .disabled(decidingRelist)
            }
        }
    }

    private func decideRelist(_ order: Order, relist: Bool) async {
        guard !decidingRelist else { return }
        decidingRelist = true
        relistError = nil
        defer { decidingRelist = false }
        do {
            _ = try await sell.ops.relistDecision(orderID: order.id, relist: relist)
            Haptics.shared.play(.success)
            await load()
        } catch {
            relistError = sellErrorMessage(error)
        }
    }

    private func compactPercent(_ value: Decimal) -> String {
        var raw = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    /// The backend's own status line wins when it sends one — it is written
    /// for the seller. The local fallbacks only exist for older payloads, and
    /// every one of them talks about money reaching a bank account: the words
    /// Stripe, balance and connected account are never a seller's problem.
    private func payoutStatusText(_ order: Order) -> String {
        if let label = order.payoutBlock?.statusLabel, !label.isEmpty {
            return label
        }
        return switch order.payoutStatus {
        case "released": "Released — on its way to your bank"
        case "pending_connect": "Waiting on your payout details"
        case "reversed": "Reversed"
        case "refunded": "Refunded"
        case .some(let other) where !other.isEmpty:
            other.replacingOccurrences(of: "_", with: " ").capitalized
        default: "Scheduled"
        }
    }

    private var saleSkeleton: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Rectangle().frame(maxWidth: .infinity).frame(height: 96).shimmer()
            Rectangle().frame(width: 160, height: 20).shimmer()
            Rectangle().frame(maxWidth: .infinity).frame(height: 180).shimmer()
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.l)
    }
}

/// Identity for the payout-details cover.
private struct PayoutConnectSession: Identifiable {
    let clientSecret: String
    let key: String
    var id: String { clientSecret }
}
