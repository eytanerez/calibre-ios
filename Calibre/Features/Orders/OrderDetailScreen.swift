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
        .background(Color.calibre.background)
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: orderID) { await load() }
        .task(id: orderID) { await autoRefreshWhileInTransit() }
    }

    private func content(_ order: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero(order)

                if order.status == .awaitingWire {
                    wireBanner(order)
                }

                if showsTracker(order) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("Progress").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
                        ProgressCheckpoints(steps: trackerSteps, currentIndex: trackerIndex(order))
                    }
                }

                listingCard(order)

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
            StatusBadge(order.statusLabel, tone: order.statusTone)
            Text(heroHeadline(order))
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
            Text(order.statusSummary)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .padding(Space.l)
        .background(Color.calibre.accent.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Cards

    private func listingCard(_ order: Order) -> some View {
        Button {
            services.router.open(.listing(order.listingId))
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
        if let tax = money(order.taxTotal) { rows.append(("Tax", tax)) }
        rows.append(("Total", PriceFormatter.format(order.grandTotal.value, currency: order.currency)))
        return rows
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
                        text: $reviewComment
                    )
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
        submittingReview = true
        defer { submittingReview = false }
        do {
            let saved = try await services.commerce.submitReview(
                orderID: order.id,
                rating: reviewRating,
                comment: reviewComment.isEmpty ? nil : reviewComment
            )
            review = saved
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
            order = try await services.commerce.order(id: orderID)
            review = try? await services.commerce.review(forOrder: orderID)
        } catch {
            if order == nil { failed = true }
        }
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
