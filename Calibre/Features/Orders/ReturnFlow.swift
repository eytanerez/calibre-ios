import CalibreDesign
import CalibreKit
import Foundation
import SwiftUI

// The buyer's return, start to finish: the exact refund itemized before
// anything is committed, then the label, the ship-by clock, and the two
// controls that follow it.
//
// Every figure on this screen arrives from `ReturnQuote` or the order's own
// `returnSummary`. Nothing about money, percentages or deadlines is worked
// out on the device — if the payload leaves a line out, the line is left out.

// MARK: - Model

@MainActor
@Observable
final class ReturnFlowModel {
    enum Phase: Equatable {
        /// Fetching the quote.
        case loading
        /// The itemized refund, waiting on the buyer.
        case quote
        /// A return exists — label, deadline, and the controls that follow.
        case open
        /// Nothing to confirm: the server says the window is shut.
        case closed(String)
        /// The quote itself didn't load.
        case failed(String)
    }

    let orderID: String
    /// The order's currency, used for anything the quote doesn't carry.
    let currency: String

    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let toasts: ToastCenter

    private(set) var phase: Phase = .loading
    private(set) var quote: ReturnQuote?
    /// The order payload's own account of the return — the source of truth
    /// for everything after the return is open. Kept in step with the screen
    /// through `adopt(_:)`.
    private(set) var summary: OrderReturnSummary?
    /// What `POST /orders/{id}/return` handed back. Only covers the moment
    /// between starting the return and the order payload catching up.
    private(set) var startResult: ReturnStartResult?

    private(set) var busy = false
    var actionError: String?
    /// Set when a cancelled return should close the sheet it was cancelled in.
    private(set) var requestsDismiss = false

    /// The order re-fetched after anything that changes it, plus a token the
    /// screen can watch — `Order` isn't Equatable, so `onChange` needs one.
    private(set) var refreshedOrder: Order?
    private(set) var refreshToken = 0

    init(orderID: String, currency: String, commerce: CommerceStore, toasts: ToastCenter) {
        self.orderID = orderID
        self.currency = currency
        self.commerce = commerce
        self.toasts = toasts
    }

    // MARK: Order sync

    /// Keeps the flow in step with the screen's order. A cancelled return is
    /// not a live case — the window resumes and the buyer may start again.
    func adopt(_ order: Order) {
        summary = order.returnSummary
        if hasLiveCase {
            phase = .open
        }
    }

    var hasLiveCase: Bool {
        if let summary { return !summary.isCancelled }
        if let existing = quote?.existingReturn { return !existing.isFinished }
        return startResult != nil
    }

    // MARK: Loading

    func loadQuote() async {
        requestsDismiss = false
        actionError = nil
        if hasLiveCase {
            phase = .open
            return
        }
        phase = .loading
        do {
            let fetched = try await commerce.returnQuote(orderID: orderID)
            quote = fetched
            if let existing = fetched.existingReturn, !existing.isFinished {
                phase = .open
                return
            }
            // The order payload said the window was open; the quote is the
            // authority, so a closed window here ends the flow honestly.
            if let window = fetched.window, !window.open {
                phase = .closed(
                    "The return window on this order has closed, so a return can't be started now. If something isn't right with the watch, your Calibre contact can help."
                )
                return
            }
            phase = .quote
        } catch {
            phase = .failed(returnErrorMessage(error))
        }
    }

    // MARK: Actions

    func start() async {
        guard !busy else { return }
        busy = true
        actionError = nil
        defer { busy = false }
        do {
            let result = try await commerce.startReturn(orderID: orderID)
            startResult = result
            phase = .open
            Haptics.shared.play(.success)
            toasts.show(
                title: "Return started",
                message: "The clock on your return window has stopped.",
                tone: .success
            )
            await refreshOrder()
        } catch {
            Haptics.shared.play(.error)
            let message = returnErrorMessage(error)
            switch (error as? APIError)?.serverCode {
            case "return_already_open":
                // A return was opened elsewhere — show the truth rather than
                // an error about it.
                await refreshOrder()
                phase = .open
            case "return_window_closed":
                phase = .closed(message)
            default:
                actionError = message
                // Whatever the server did or didn't do, the order payload is
                // the honest account of it.
                await refreshOrder()
            }
        }
    }

    func declareShipped() async {
        guard !busy else { return }
        busy = true
        actionError = nil
        defer { busy = false }
        do {
            _ = try await commerce.declareReturnShipped(orderID: orderID)
            Haptics.shared.play(.success)
            toasts.show(
                title: "Thank you — noted",
                message: "We'll watch for the carrier's first scan.",
                tone: .success
            )
        } catch {
            Haptics.shared.play(.error)
            actionError = returnErrorMessage(error)
        }
        await refreshOrder()
    }

    func cancelReturn() async {
        guard !busy else { return }
        busy = true
        actionError = nil
        defer { busy = false }
        do {
            _ = try await commerce.cancelReturn(orderID: orderID)
            startResult = nil
            quote = nil
            Haptics.shared.play(.success)
            toasts.show(
                title: "Return called off",
                message: "Your return window picks up where it left off."
            )
            await refreshOrder()
            requestsDismiss = true
        } catch {
            Haptics.shared.play(.error)
            actionError = returnErrorMessage(error)
            // 409 `return_in_transit` races the buyer: refreshing drops the
            // cancel control, so the screen stops offering what can't happen.
            await refreshOrder()
        }
    }

    private func refreshOrder() async {
        guard let refreshed = try? await commerce.order(id: orderID) else { return }
        refreshedOrder = refreshed
        summary = refreshed.returnSummary
        refreshToken += 1
    }

    // MARK: Case display

    /// The open return as the start call or the quote described it — the
    /// stand-in until the order payload carries the case itself.
    private var liveReturn: OrderReturn? {
        if let started = startResult?.`return` { return started }
        if let existing = quote?.existingReturn, !existing.isFinished { return existing }
        return nil
    }

    var labelURL: URL? {
        summary?.label?.labelUrl?.url
            ?? startResult?.label?.labelUrl?.url
            ?? liveReturn?.label?.labelUrl?.url
    }

    var trackingNumber: String? {
        let candidate = summary?.label?.trackingNumber
            ?? startResult?.label?.trackingNumber
            ?? liveReturn?.label?.trackingNumber
        guard let candidate, !candidate.isEmpty else { return nil }
        return candidate
    }

    var shipDeadline: Date? {
        summary?.shipDeadlineAt ?? startResult?.shipDeadlineAt ?? liveReturn?.shipDeadlineAt
    }

    var refundTotalText: String? {
        if let total = summary?.refundTotal {
            return PriceFormatter.format(total.value, currency: currency)
        }
        if let total = liveReturn?.refundTotal {
            return PriceFormatter.format(total.value, currency: liveReturn?.currency ?? currency)
        }
        return nil
    }

    /// The return label's cost, frozen onto the return when it was created —
    /// the same figure the quote promised, still stated after the fact.
    var returnLabelDeductionText: String? {
        let frozen = summary?.returnLabelDeduction
            ?? liveReturn?.returnLabelDeduction
            ?? quote?.returnLabelDeduction
        guard let frozen else { return nil }
        return PriceFormatter.format(frozen.value, currency: currency)
    }

    /// The money rows on an open or settled return. A figure the payload
    /// doesn't carry is simply not a row.
    var caseSummaryRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let deduction = returnLabelDeductionText {
            rows.append(("Return label", "− " + deduction))
        }
        if isRefunded, let refund = refundTotalText {
            rows.append(("Refunded", refund))
        }
        return rows
    }

    private var state: String? { summary?.state ?? liveReturn?.status }

    var isInTransit: Bool { summary?.isInTransit ?? liveReturn?.isInTransit ?? false }
    var isRefunded: Bool { summary?.isRefunded ?? (liveReturn?.refundedAt != nil) }
    var isCancelled: Bool { summary?.isCancelled ?? (liveReturn?.cancelledAt != nil) }
    var isBackWithUs: Bool { state == "received" }

    /// Cancelling stops being on offer the moment the watch is moving — the
    /// server 409s `return_in_transit` from there on.
    var canCancel: Bool { !isInTransit && !isRefunded && !isCancelled && !isBackWithUs }
    var canDeclareShipped: Bool { canCancel }

    var badge: (text: String, tone: StatusBadge.Tone) {
        if isRefunded { return ("Refunded", .success) }
        if isCancelled { return ("Return called off", .neutral) }
        if isBackWithUs { return ("Back with us", .info) }
        if isInTransit { return ("On its way back", .info) }
        return ("Return open", .warning)
    }

    var headline: String {
        if isRefunded { return "Your refund is on its way" }
        if isCancelled { return "This return was called off" }
        if isBackWithUs { return "The watch is back with us" }
        if isInTransit { return "The watch is on its way back" }
        return "Send the watch back to us"
    }

    var detail: String {
        if isRefunded {
            return "The watch passed its check and your refund has been issued. Card refunds usually take a few days to appear on your statement."
        }
        if isCancelled {
            return "Your return window picks up where it left off."
        }
        if isBackWithUs {
            return "Our authenticators are checking that it's the same watch, in the same condition, and still genuine. Your refund follows that check."
        }
        if isInTransit {
            return "Once it arrives, we check that it's the same watch, in the same condition, and still genuine. Your refund follows that check."
        }
        return "Use the label below, and let us know once you've handed it over. The clock on your return window has stopped."
    }
}

// MARK: - Error copy

/// The server's own words come first — it knows why it said no. The
/// fallbacks below only speak when the message came back empty.
func returnErrorMessage(_ error: Error) -> String {
    guard let apiError = error as? APIError else { return error.orderMessage }
    guard case .server(let message, let code, _, _) = apiError else {
        return apiError.errorDescription ?? "Something went wrong. Please try again."
    }
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }

    switch code {
    case "returns_not_accepted":
        return "This watch was listed without returns, so this order can't be returned."
    case "order_not_delivered":
        return "A return can start once the watch has been delivered to you."
    case "return_already_open":
        return "There's already a return open on this order."
    case "return_window_closed":
        return "The return window on this order has closed."
    case "return_already_shipped":
        return "You've already told us this one is on its way."
    case "return_in_transit":
        return "The watch is already on its way back, so the return can't be called off now."
    case "return_label_unavailable":
        return "We couldn't produce the return label just now. Please try again in a moment, or your Calibre contact can sort it out for you."
    default:
        return "Something went wrong. Please try again."
    }
}

/// Renders a percentage exactly as the server sent it: "7.00" reads as 7,
/// anything finer keeps its own digits. Never rounded to a different number.
private func returnPercentText(_ value: Decimal) -> String {
    var raw = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &raw, 0, .plain)
    return rounded == value ? "\(rounded)" : "\(value)"
}

// MARK: - Sheet

/// Presented from the order detail. Quote first, always: the buyer sees the
/// exact refund and its line items before any button commits them to it.
struct ReturnFlowSheet: View {
    let model: ReturnFlowModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    switch model.phase {
                    case .loading:
                        loading
                    case .quote:
                        if let quote = model.quote {
                            ReturnQuoteView(quote: quote, model: model)
                        }
                    case .open:
                        openedHeader
                        ReturnCaseBody(model: model)
                    case .closed(let message):
                        EmptyState(
                            icon: "clock.badge.xmark",
                            title: "The return window has closed",
                            message: message
                        )
                    case .failed(let message):
                        EmptyState(
                            icon: "wifi.exclamationmark",
                            title: "We couldn't load your return",
                            message: message,
                            actionTitle: "Try again",
                            action: { Task { await model.loadQuote() } }
                        )
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxl)
            }
            .background(Color.calibre.background.ignoresSafeArea())
            .navigationTitle("Return this watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.calibre.foreground)
                }
            }
        }
        .task { await model.loadQuote() }
        .onChange(of: model.requestsDismiss) { _, requested in
            if requested { dismiss() }
        }
    }

    private var loading: some View {
        VStack(spacing: Space.l) {
            ProgressView()
            Text("Working out your exact refund.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl)
    }

    private var openedHeader: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            StatusBadge(model.badge.text, tone: model.badge.tone)
            Text(model.headline)
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
            Text(model.detail)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The quote

/// The refund, itemized, before anything is confirmed. Every line comes from
/// the payload and a line the payload omits is simply not drawn.
private struct ReturnQuoteView: View {
    let quote: ReturnQuote
    let model: ReturnFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("What comes back to you")
                    .font(CalibreType.title)
                    .foregroundStyle(Color.calibre.foreground)
                Text("Here is the exact refund on this return, line by line, before you decide anything.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Your refund")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                Text(money(quote.refundTotal))
                    .font(CalibreType.priceLarge)
                    .foregroundStyle(Color.calibre.foreground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
            .returnCardSurface()
            .accessibilityElement(children: .combine)

            SpecList(rows)

            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Space.m) {
                Text("How a return goes")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                ReturnFactRow(
                    icon: "pause.circle",
                    text: "Starting the return stops the clock on your return window."
                )
                ReturnFactRow(
                    icon: "shippingbox",
                    text: "We create the return label for you — signature required, insured for the full sale price. Its cost is deducted from your refund."
                )
                ReturnFactRow(
                    icon: "clock",
                    text: "You then have 48 business hours to hand the watch to the carrier. Deadlines that need a person to act run on business days."
                )
                ReturnFactRow(
                    icon: "checkmark.shield",
                    text: "The watch goes back to our authentication center and is checked — the same watch, in the same condition, still genuine — before anything is refunded."
                )
            }

            VStack(spacing: Space.s) {
                Button {
                    Haptics.shared.play(.press)
                    Task { await model.start() }
                } label: {
                    BusyLabel(title: "Start the return", busy: model.busy)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.busy)

                Text("Nothing changes until you tap this.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .multilineTextAlignment(.center)

                if let actionError = model.actionError {
                    InlineErrorLine(message: actionError)
                }
            }
            .animation(Motion.easeFast, value: model.actionError)
        }
    }

    // MARK: Rows

    private var rows: [(String, String)] {
        var rows: [(String, String)] = [("Watch", money(quote.watchPrice))]
        if let tax = quote.taxRefund {
            rows.append(("Sales tax, refunded in full", money(tax)))
        }
        rows.append((returnFeeLabel, "− " + money(quote.returnFee.amount)))
        if let outbound = quote.outboundLabelDeduction {
            rows.append(("Original shipping label", "− " + money(outbound)))
        }
        // Calibre's return label is deducted from the refund too, and the
        // buyer sees it here rather than discovering it afterwards.
        if let returnLabel = quote.returnLabelDeduction {
            rows.append(("Return label", "− " + money(returnLabel)))
        }
        if let withholding = quote.processingWithholding {
            rows.append((withholdingLabel, "− " + money(withholding)))
        }
        rows.append(("Your refund", money(quote.refundTotal)))
        return rows
    }

    private var minimumApplied: Bool {
        quote.returnFee.amount.value == quote.returnFee.minimum.value
    }

    private var returnFeeLabel: String {
        if minimumApplied {
            return "Return fee (\(money(quote.returnFee.minimum)) minimum)"
        }
        return "Return fee (\(returnPercentText(quote.returnFee.percent.value))%)"
    }

    private var withholdingLabel: String {
        quote.processingWithholdingBasis == "card_fee_never_refunded" ? "Card fee" : "Processing"
    }

    private var notes: [String] {
        var notes: [String] = []
        let percent = returnPercentText(quote.returnFee.percent.value)
        let minimum = money(quote.returnFee.minimum)
        if minimumApplied {
            notes.append(
                "The return fee is \(percent)% of the watch price with a \(minimum) minimum. On this order the minimum is what applied."
            )
        } else {
            notes.append("The return fee is \(percent)% of the watch price, with a \(minimum) minimum.")
        }

        if quote.processingWithholding != nil {
            switch quote.processingWithholdingBasis {
            case "card_fee_never_refunded":
                notes.append("The card fee you paid at checkout is not refunded.")
            case "card_fee_equivalent":
                notes.append(
                    "You paid by wire, so there was no card fee. An equivalent processing cost is withheld instead, so a wire return comes out the same as a card one."
                )
            default:
                break
            }
        }
        return notes
    }

    private func money(_ value: APIDecimal) -> String {
        PriceFormatter.format(value.value, currency: quote.currency)
    }
}

// MARK: - The open return

/// Everything after the return is open: the label, the ship-by clock, and the
/// two controls. Rendered from the order payload's `returnSummary` wherever
/// it has arrived, falling back to the start call's own result for the few
/// seconds before the order refreshes.
struct ReturnCaseBody: View {
    let model: ReturnFlowModel

    @Environment(ToastCenter.self) private var toasts
    @State private var confirmingCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            let summaryRows = model.caseSummaryRows
            if !summaryRows.isEmpty {
                SpecList(summaryRows)
            }

            if let labelURL = model.labelURL {
                ShareLink(item: labelURL) {
                    Label("Get the return label", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
            }

            if let tracking = model.trackingNumber {
                trackingRow(tracking)
            }

            if let deadline = model.shipDeadline, model.canDeclareShipped {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.m) {
                        Text("Ship by")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        CountdownChip(until: deadline)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)

                    Text("You have 48 business hours from the moment this return opened. Deadlines that need a person to act run on business days.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.canDeclareShipped {
                VStack(alignment: .leading, spacing: Space.s) {
                    Button {
                        Haptics.shared.play(.press)
                        Task { await model.declareShipped() }
                    } label: {
                        BusyLabel(title: "I shipped it", busy: model.busy)
                    }
                    .buttonStyle(.calibre(shippedButtonVariant, fullWidth: true))
                    .disabled(model.busy)

                    Text("Telling us buys a short grace period for the carrier's first scan. If no scan follows, the original clock resumes and your Calibre contact takes the case from there.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.canCancel {
                Button("Cancel this return") {
                    confirmingCancel = true
                }
                .buttonStyle(.calibre(.ghost, fullWidth: true))
                .disabled(model.busy)
                .confirmationDialog(
                    "Cancel this return?",
                    isPresented: $confirmingCancel,
                    titleVisibility: .visible
                ) {
                    Button("Cancel the return", role: .destructive) {
                        Task { await model.cancelReturn() }
                    }
                    Button("Keep it open", role: .cancel) {}
                } message: {
                    Text("Your return window picks up where it left off, and the label is voided.")
                }
            }

            if let actionError = model.actionError {
                InlineErrorLine(message: actionError)
            }
        }
        .animation(Motion.easeFast, value: model.actionError)
    }

    /// The label download is the loud action while it exists; once it does,
    /// "I shipped it" sits quietly beneath it.
    private var shippedButtonVariant: CalibreButtonVariant {
        model.labelURL == nil ? .primary : .secondary
    }

    private func trackingRow(_ tracking: String) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tracking number")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                Text(tracking)
                    .font(CalibreType.bodyMedium)
                    .monospacedDigit()
                    .foregroundStyle(Color.calibre.foreground)
            }
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = tracking
                Haptics.shared.play(.selection)
                toasts.show(title: "Tracking number copied")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.calibre.primary)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Copy tracking number")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .returnCardSurface()
    }
}

// MARK: - Order detail section

/// The live return as it appears on the order itself — the same body, wrapped
/// in the page's card chrome, driven by `order.returnSummary`.
struct ReturnCaseCard: View {
    let model: ReturnFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Your return")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    StatusBadge(model.badge.text, tone: model.badge.tone)
                    Text(model.headline)
                        .font(CalibreType.bodySemiBold)
                        .foregroundStyle(Color.calibre.foreground)
                    Text(model.detail)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                ReturnCaseBody(model: model)
            }
            .padding(Space.l)
            .returnCardSurface()
        }
    }
}

// MARK: - Small pieces

/// One plain fact about how a return works — icon, sentence, read as one.
private struct ReturnFactRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.calibre.primary)
                .frame(width: 20)
            Text(text)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// The bordered card surface the order screens share.
    func returnCardSurface() -> some View {
        background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
}
