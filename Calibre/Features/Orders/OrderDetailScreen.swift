import CalibreDesign
import CalibreKit
import SwiftUI

/// The order detail — status hero, the five-checkpoint tracker, authentication
/// result, shipment tracking, receipt, and (once delivered) leaving a review.
/// Auto-refreshes while a watch is in transit.
struct OrderDetailScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    let orderID: String

    @State private var order: Order?
    @State private var review: SellerReview?
    @State private var failed = false
    @State private var reviewRating = 0
    @State private var reviewComment = ""
    @State private var submittingReview = false
    /// Owns the return: the quote, the start call, and the controls that
    /// follow. Created once the order is known, kept in step with it.
    @State private var returnFlow: ReturnFlowModel?
    @State private var showingReturnFlow = false

    private let trackerSteps = [
        "Shipped to authentication",
        "At authentication",
        "Authenticated",
        "Shipped to you",
        "Delivered",
    ]

    var body: some View {
        Group {
            if let order {
                content(order)
            } else if failed {
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load this order",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again"
                ) { failed = false; Task { await load() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .calibrePageBackground()
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: orderID) { await load() }
        .task(id: orderID) { await autoRefreshWhileInTransit() }
        // The return flow re-fetches the order after anything that changes it;
        // `Order` isn't Equatable, so the model hands over a token instead.
        .onChange(of: returnFlow?.refreshToken) { _, _ in
            if let refreshed = returnFlow?.refreshedOrder {
                order = refreshed
            }
        }
        .sheet(isPresented: $showingReturnFlow) {
            if let returnFlow {
                ReturnFlowSheet(model: returnFlow)
            }
        }
    }

    private func content(_ order: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero(order)

                if order.status == .awaitingWire {
                    wireBanner(order)
                }

                // A return in progress is the order's current state — it sits
                // above the journey it interrupted.
                if let returnFlow, hasLiveReturn(order) {
                    ReturnCaseCard(model: returnFlow)
                }

                if showsTracker(order) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("Progress").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
                        ProgressCheckpoints(steps: trackerSteps, currentIndex: trackerIndex(order))
                        expectedDates(order)
                    }
                }

                listingCard(order)

                packingNoteCard(order)

                purchaseGroupNote(order)

                if let auth = order.authResult, order.status == .authPass || order.status == .authFail {
                    authResultCard(order, auth)
                }

                if let shipment = order.toBuyerShipment ?? order.toAuthShipment ?? order.latestShipment,
                   shipment.trackingNumber != nil {
                    shipmentCard(shipment)
                }

                if let address = order.shippingAddress {
                    shippingCard(address)
                }

                receiptCard(order)

                returnTermsSection(order)

                cancellationNote(order)

                if order.status == .delivered {
                    reviewSection(order)
                }
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
    }

    // MARK: - Hero

    private func hero(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                StatusBadge(order.statusLabel, tone: order.statusTone)
                // The order's identity, in the form a person reads it out:
                // this is the number support will ask for.
                Text(order.displayNumber)
                    .font(CalibreType.label)
                    .monospacedDigit()
                    .foregroundStyle(Color.calibre.mutedForeground)
                Spacer(minLength: 0)
            }
            Text(heroHeadline(order))
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
            Text(order.statusSummary)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Order \(order.displayNumber), \(order.statusLabel). \(order.statusSummary)")
    }

    private func heroHeadline(_ order: Order) -> String {
        switch order.status {
        case .awaitingWire: "Complete your wire"
        case .purchased: "You bought it"
        case .toAuth: "On its way to authentication"
        case .authPass: "Authenticated"
        case .authFail: "A note on your order"
        case .toBuyer: "On its way to you"
        case .delivered: "It's yours"
        case .cancelled: "Order cancelled"
        case .refunded: "Order refunded"
        case .unknown: "Your order"
        }
    }

    private func wireBanner(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let due = order.paymentDueAt {
                HStack {
                    Text("Payment due").font(CalibreType.label).foregroundStyle(Color.calibre.accentForeground)
                    Spacer()
                    CountdownChip(until: due)
                }
            }
            Text("Send your wire to secure this watch. We'll email you the moment it clears.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.accentForeground)

            // The authorization the buyer can see on their statement, said
            // where they will look for it. There is no control here to take
            // it off: it comes off when the transfer arrives.
            if let hold = order.wireHold, hold.isLive {
                Text(wireHoldLine(hold))
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.accentForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
        .background(Color.calibre.accent.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// The amount is the payload's own — never a remembered $250.
    private func wireHoldLine(_ hold: OrderWireHold) -> String {
        let amount = hold.amount.map { PriceFormatter.format($0.value) } ?? "The"
        return "\(amount) authorization placed \u{2014} released when your transfer arrives. If the transfer isn\u{2019}t sent by the deadline it is charged and goes to the seller."
    }

    // MARK: - Cards

    private func listingCard(_ order: Order) -> some View {
        Button {
            services.router.push(.listing(order.listingId))
        } label: {
            HStack(spacing: Space.m) {
                OrderThumb(url: order.listing?.image?.url)
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.listing?.title ?? "Your watch")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(PriceFormatter.format(order.subtotal.value, currency: order.currency))
                        .font(CalibreType.price)
                        .foregroundStyle(Color.calibre.foreground)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .cardSurface()
        }
        .buttonStyle(PressableStyle())
    }

    /// A quiet line saying this watch was bought alongside others, with a way
    /// to reach them. It is deliberately understated: this order is complete
    /// on its own — its own shipment, its own authentication, its own return
    /// — and the purchase is context, not a container.
    @ViewBuilder private func purchaseGroupNote(_ order: Order) -> some View {
        if let group = order.group {
            let siblings = group.siblingIDs(of: order.id)
            if !siblings.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Label {
                        Text("Part of a purchase with \(siblings.count == 1 ? "1 other watch" : "\(siblings.count) other watches"). Each one is its own order, tracked separately.")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "square.stack")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    if siblings.count == 1, let other = siblings.first {
                        Button("View the other order") {
                            services.router.push(.order(other))
                        }
                        .buttonStyle(.calibreGhost)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .cardSurface()
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func authResultCard(_ order: Order, _ auth: OrderAuthResult) -> some View {
        let passed = order.status == .authPass
        return VStack(alignment: .leading, spacing: Space.s) {
            Label(
                passed ? "Authenticated by Calibre" : "Authentication issue",
                systemImage: passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(CalibreType.bodySemiBold)
            .foregroundStyle(passed ? Color.calibre.success : Color.calibre.destructive)

            if let notes = auth.notes, !notes.isEmpty {
                Text(notes).font(CalibreType.body).foregroundStyle(Color.calibre.foreground)
            }
            if auth.aftermarketFlag == true {
                Text("Aftermarket parts were noted during inspection.")
                    .font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
            }
            if !passed {
                Text("Our team will follow up by email with the details and your options.")
                    .font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .cardSurface()
    }

    // MARK: - What the seller sent with it

    /// The seller's own line, held back until the parcel is actually in the
    /// buyer's hands.
    ///
    /// A note that reads "enjoy it" while the watch is still in transit is a
    /// spoiler; the same words next to a watch on the table are the person
    /// who packed it. Delivery is the moment it means what it says, so it is
    /// gated on the order being delivered rather than on the note existing.
    @ViewBuilder
    private func packingNoteCard(_ order: Order) -> some View {
        if order.status == .delivered, let note = order.packingNote, !note.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("From the seller").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
                Text(note)
                    .font(CalibreType.hand)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.l)
                    .cardSurface()
            }
        }
    }

    private func shipmentCard(_ shipment: Shipment) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Tracking").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
            SpecList(shipmentRows(shipment))
            if let tracking = shipment.trackingNumber {
                Button {
                    UIPasteboard.general.string = tracking
                    Haptics.shared.play(.selection)
                    toasts.show(title: "Tracking number copied")
                } label: {
                    Label("Copy tracking number", systemImage: "doc.on.doc")
                }
                .buttonStyle(.calibre(.secondary))
            }
        }
    }

    private func shipmentRows(_ shipment: Shipment) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let carrier = shipment.carrier { rows.append(("Carrier", carrier)) }
        if let tracking = shipment.trackingNumber { rows.append(("Tracking", tracking)) }
        if let shipped = shipment.shippedAt {
            rows.append(("Shipped", shipped.formatted(date: .abbreviated, time: .omitted)))
        }
        if let delivered = shipment.deliveredAt {
            rows.append(("Delivered", delivered.formatted(date: .abbreviated, time: .omitted)))
        }
        return rows
    }

    private func shippingCard(_ address: OrderShippingAddress) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Shipping to").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
            VStack(alignment: .leading, spacing: 2) {
                if let name = address.fullName { Text(name).font(CalibreType.bodyMedium) }
                if let line1 = address.line1 { Text(line1).font(CalibreType.body) }
                if let line2 = address.line2, !line2.isEmpty { Text(line2).font(CalibreType.body) }
                Text([address.city, address.region, address.postalCode].compactMap { $0 }.joined(separator: ", "))
                    .font(CalibreType.body)
            }
            .foregroundStyle(Color.calibre.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
            .cardSurface()
        }
    }

    private func receiptCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Receipt").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
            SpecList(receiptRows(order))
        }
    }

    private func receiptRows(_ order: Order) -> [(String, String)] {
        func money(_ value: APIDecimal?) -> String? {
            value.map { PriceFormatter.format($0.value, currency: order.currency) }
        }
        var rows: [(String, String)] = [("Watch", PriceFormatter.format(order.subtotal.value, currency: order.currency))]
        if let shipping = money(order.shippingTotal) { rows.append(("Shipping", shipping)) }
        // The card's processing cost is its own receipt line, exactly as it
        // was before payment — without it the rows don't add up to the total.
        // Buyer-side fees are only ever the card cost, and a wire order sends
        // zero here, so the row appears when there is something to state.
        if order.feesTotal.value > 0 {
            rows.append(("Card processing", PriceFormatter.format(order.feesTotal.value, currency: order.currency)))
        }
        if let tax = money(order.taxTotal) { rows.append(("Tax", tax)) }
        rows.append(("Total", PriceFormatter.format(order.grandTotal.value, currency: order.currency)))
        return rows
    }

    // MARK: - Expected dates

    /// The backend's own estimates for the legs ahead, under the tracker.
    /// Every one of them is nullable — a date we don't have is left unsaid
    /// rather than guessed at.
    @ViewBuilder private func expectedDates(_ order: Order) -> some View {
        let rows = expectedRows(order)
        if !rows.isEmpty {
            SpecList(rows)
        }
    }

    private func expectedRows(_ order: Order) -> [(String, String)] {
        guard let expected = order.expected else { return [] }
        func day(_ date: Date) -> String {
            date.formatted(date: .abbreviated, time: .omitted)
        }
        var rows: [(String, String)] = []
        if let date = expected.authenticationVerdictBy {
            rows.append(("Authentication verdict by", day(date)))
        }
        if let date = expected.shippedToYouBy {
            rows.append(("Shipped to you by", day(date)))
        }
        if let date = expected.deliveredBy {
            rows.append(("Delivered by", day(date)))
        }
        if let date = expected.returnWindowEndsAt {
            rows.append(("Return window closes", day(date)))
        }
        return rows
    }

    // MARK: - Cancellation

    /// Said plainly, because the buyer will look for a button and there isn't
    /// one. An order cannot be cancelled from here at all — a person can still
    /// help before the watch is on its way, and this says where to find them.
    @ViewBuilder
    private func cancellationNote(_ order: Order) -> some View {
        if !order.status.isFinished {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Cancelling")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Text("Orders can\u{2019}t be cancelled once the seller ships. If something has changed, message your Calibre contact \u{2014} the sooner the better.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Message Calibre") {
                    Haptics.shared.play(.press)
                    services.router.push(.supportChat)
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
            }
        }
    }

    // MARK: - Returns

    /// A return exists on this order and hasn't been called off.
    private func hasLiveReturn(_ order: Order) -> Bool {
        guard let summary = order.returnSummary else { return false }
        return !summary.isCancelled
    }

    /// Where a buyer looks for the answer to "can I send this back?" — stated
    /// either way, and never at all on payloads that predate return terms.
    @ViewBuilder private func returnTermsSection(_ order: Order) -> some View {
        if let terms = order.returns, !hasLiveReturn(order) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Returns")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)

                if terms.accepted {
                    acceptedReturnsCard(order, terms)
                } else {
                    returnsNote(
                        "This watch was listed without returns, so this order can't be sent back. If something isn't right with it, your Calibre contact will help — they're one message away."
                    )
                }
            }
        }
    }

    @ViewBuilder private func acceptedReturnsCard(_ order: Order, _ terms: OrderReturnTerms) -> some View {
        if order.status == .delivered, terms.isOpen() {
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Your return window is open")
                        .font(CalibreType.bodySemiBold)
                        .foregroundStyle(Color.calibre.foreground)
                    Text(openWindowDetail(order, terms))
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Button("Start a return") {
                    Haptics.shared.play(.press)
                    showingReturnFlow = true
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))

                Text("We'll show you the exact refund, line by line, before anything is confirmed.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
            .cardSurface()
        } else if order.status == .delivered {
            returnsNote(
                "The return window on this order has closed. If something isn't right with the watch, your Calibre contact will help."
            )
        } else {
            returnsNote(pendingWindowDetail(terms))
        }
    }

    private func openWindowDetail(_ order: Order, _ terms: OrderReturnTerms) -> String {
        guard let ends = terms.windowEndsAt ?? order.expected?.returnWindowEndsAt else {
            return "You can send this watch back to us. Starting a return stops the clock while you arrange it."
        }
        return "You have until \(ends.formatted(date: .abbreviated, time: .shortened)) to start a return. Starting one stops the clock."
    }

    private func pendingWindowDetail(_ terms: OrderReturnTerms) -> String {
        let opening = terms.windowHours.map {
            "This seller accepts returns for \($0) hours after delivery."
        } ?? "This seller accepts returns after delivery."
        return opening
            + " The window starts when you sign for the watch, or two business days after the first delivery attempt, whichever comes first."
    }

    private func returnsNote(_ message: String) -> some View {
        Text(message)
            .font(CalibreType.body)
            .foregroundStyle(Color.calibre.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
            .cardSurface()
    }

    // MARK: - Review

    @ViewBuilder private func reviewSection(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Rate the seller").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
            if let review {
                VStack(alignment: .leading, spacing: Space.s) {
                    StarRating(rating: Double(review.rating))
                    if let comment = review.comment, !comment.isEmpty {
                        Text(comment).font(CalibreType.body).foregroundStyle(Color.calibre.foreground)
                    }
                    Text("Thanks for sharing how it went.")
                        .font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .cardSurface()
            } else {
                VStack(alignment: .leading, spacing: Space.m) {
                    StarRating(selection: $reviewRating)
                    CalibreTextField(
                        "Anything you'd like to add? (optional)",
                        text: $reviewComment,
                        kind: .sentence
                    )
                    .onChange(of: reviewComment) { _, value in
                        if value.count > 2_000 {
                            reviewComment = String(value.prefix(2_000))
                        }
                    }
                    Button(submittingReview ? "Sending…" : "Submit review") {
                        Task { await submitReview(order) }
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(reviewRating == 0 || submittingReview)
                }
                .padding(Space.l)
                .cardSurface()
            }
        }
    }

    private func submitReview(_ order: Order) async {
        guard (1...5).contains(reviewRating), !submittingReview else { return }
        submittingReview = true
        defer { submittingReview = false }
        do {
            let saved = try await services.commerce.submitReview(
                orderID: order.id,
                rating: reviewRating,
                comment: InputValidation.isNonBlank(reviewComment)
                    ? InputValidation.trimmed(reviewComment)
                    : nil
            )
            review = saved
            Analytics.reviewLeft(
                orderID: order.id,
                listingID: order.listingId,
                rating: saved.rating
            )
            Haptics.shared.play(.success)
            toasts.show(title: "Review shared", message: "Thanks for helping other buyers.", tone: .success)
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't submit", message: error.orderMessage, tone: .error)
        }
    }

    // MARK: - Loading

    private func load() async {
        do {
            let loaded = try await services.commerce.order(id: orderID)
            order = loaded
            syncReturnFlow(loaded)
            review = try? await services.commerce.review(forOrder: orderID)
        } catch {
            if order == nil { failed = true }
        }
    }

    /// One return model per order, handed the freshest payload each time —
    /// the order's own `returnSummary` is what the return renders from.
    private func syncReturnFlow(_ order: Order) {
        if returnFlow == nil {
            returnFlow = ReturnFlowModel(
                orderID: order.id,
                currency: order.currency,
                commerce: services.commerce,
                toasts: toasts
            )
        }
        returnFlow?.adopt(order)
    }

    private func autoRefreshWhileInTransit() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            let inTransit = order?.status == .toAuth || order?.status == .toBuyer
            guard inTransit else { continue }
            // Only replace on success — a transient failure must not wipe the
            // rendered order and strand the screen on a spinner.
            if let refreshed = try? await services.commerce.order(id: orderID) {
                order = refreshed
                syncReturnFlow(refreshed)
            }
        }
    }

    // MARK: - Tracker mapping

    private func showsTracker(_ order: Order) -> Bool {
        switch order.status {
        // authFail diverges from the happy path — the auth-result card tells
        // that story instead of lighting the "Authenticated" checkpoint.
        case .awaitingWire, .authFail, .cancelled, .refunded, .unknown: false
        default: true
        }
    }

    private func trackerIndex(_ order: Order) -> Int {
        switch order.status {
        case .purchased, .toAuth: 0
        case .authPass: 2
        case .toBuyer: 3
        case .delivered: 5
        default: 0
        }
    }
}

private extension View {
    /// Standard bordered card surface used throughout the order detail.
    func cardSurface() -> some View {
        background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
}
