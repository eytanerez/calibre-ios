import CalibreDesign
import CalibreKit
import SwiftUI

/// The order detail — the lead, the journey, the record's own panels, and a
/// quiet block of detail at the foot. Auto-refreshes while a watch is in
/// transit.
///
/// What the screen says about the order is not decided here. `Order.nextStep()`
/// and `Order.timeline()` in `CalibreKit` decide it, so this screen and the
/// list cannot word the same order two different ways, and so the readings can
/// be tested without a screen.
struct OrderDetailScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.routePush) private var routePush
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
                // A page waiting, so the wheel says work is still going and
                // unmounts with the wait. Never keyed and never held still: a
                // loop that restarts is a stutter, and a stopped balance wheel
                // is a stopped watch. The line beside it carries the meaning —
                // a still wheel is not self-evidently "loading".
                VStack(spacing: Space.m) {
                    CalibreMark.balanceWheel(size: 24)
                    Text("Opening your order")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Opening your order")
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
        let step = order.nextStep()
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                lead(order, step)

                if order.status == .awaitingWire {
                    wireBanner(order)
                }

                // A return in progress is the order's current state — it sits
                // above the journey it interrupted.
                if let returnFlow, hasLiveReturn(order) {
                    ReturnCaseCard(model: returnFlow)
                }

                // Nil for a cancelled or refunded order: a column of steps
                // nothing will ever reach is not a journey, and the lead has
                // already said in one line what happened instead.
                if let steps = order.timeline() {
                    OrderTimelineView(steps: steps, mark: progressMark(order))
                }

                purchaseGroupNote(order)

                packingNoteCard(order)

                // The record's own panels, in the order a buyer meets them.
                // The hold is not among them any more: it is the lead's own
                // headline and paragraph, and a card repeating them underneath
                // was the same words twice.
                if let caseRef = order.authentication?.authCase {
                    AuthCaseCard(caseID: caseRef.id) { Task { await load() } }
                }

                if let report = order.authentication?.report {
                    AuthenticationReportRow(source: .order(order.id), reference: report)
                }

                aftermarketNote(order)

                returnTermsSection(order)

                detailsBlock(order)

                if order.status == .delivered {
                    reviewSection(order)
                }
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
    }

    // MARK: - The lead

    /// The watch, and the one thing that is true about it right now.
    ///
    /// Whose move it is comes first, because it is the question a buyer opens
    /// this screen with. It used to be answered last and only by implication:
    /// a status badge in the marketplace's vocabulary, over a sentence keyed to
    /// the status word — which is the one thing that cannot tell a seller still
    /// holding the watch from the bench holding it.
    ///
    /// The photograph is new here. Every other surface that names this watch
    /// shows it; the screen the buyer opens to look at their own watch was the
    /// one that did not.
    private func lead(_ order: Order, _ step: OrderNextStep) -> some View {
        let tone = leadTone(order, step.actor)
        return VStack(alignment: .leading, spacing: Space.l) {
            if let image = order.listing?.image?.url {
                ListingImageWell(url: image, targetWidth: 900)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(order.listing?.title ?? "Your watch")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(identityLine(order))
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Color.calibre.borderBright)

            VStack(alignment: .leading, spacing: Space.s) {
                if let actor = step.actor {
                    Eyebrow(actor.label)
                }
                Text(step.headline)
                    .font(CalibreType.title)
                    .foregroundStyle(
                        tone == .stopped ? Color.calibre.destructive : Color.calibre.foreground
                    )
                    .fixedSize(horizontal: false, vertical: true)
                if let body = step.body {
                    Text(body)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Null wherever the server gave no date. A "we expect" line
                // the client made up is a promise nobody made, so there is no
                // fallback sentence here to fall back to.
                if let next = step.next {
                    Text(next)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                [step.actor?.label, step.sentence, step.body].compactMap { $0 }.joined(separator: ". ")
            )

            if let checkoutKey = order.checkoutMarkKey() {
                checkoutMoment(checkoutKey)
            }

            VStack(spacing: Space.s) {
                contactSellerRow(order)
                passportRow(order)
                trackingRow(order)
            }

            policyLine(order)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .strokeBorder(tone.stroke, lineWidth: 1)
        )
    }

    /// Paid, and nothing shipped yet: the parcel is being packed, and the
    /// carton packs itself beside the sentence that says so. The lead's mark
    /// rather than the journey's — the journey has no leg to draw yet — and
    /// `Order.checkoutMarkKey()` is what says it is this screen's only one.
    /// Keyed to the order, so the sixty-second refetch leaves a packed parcel
    /// packed, and announced once per session like every other milestone.
    ///
    /// No `label`: the headline above already says the seller is preparing
    /// the watch, in words a screen reader reads, and the sentence beside the
    /// mark carries the rest.
    private func checkoutMoment(_ key: String) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            CalibreMark.box(size: 40, trigger: key)
                .markAnnounces(key)
            Text("Its journey to you starts now — authentication first, then your door.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The ground the lead sits on carries the state, so it reads before the
    /// words do.
    private enum LeadTone {
        /// The buyer owes the next move.
        case ask
        /// The journey ended somewhere it was not meant to.
        case stopped
        /// Nothing is being asked of anybody who is reading.
        case calm

        var fill: Color {
            switch self {
            case .ask: Color.calibre.accent.opacity(0.4)
            case .stopped: Color.calibre.destructive.opacity(0.08)
            case .calm: Color.calibre.card
            }
        }

        var stroke: Color {
            switch self {
            case .ask: Color.calibre.borderBright
            case .stopped: Color.calibre.destructive.opacity(0.35)
            case .calm: Color.calibre.border
            }
        }
    }

    /// `disputed` is a status the web's table also keys on and this one does
    /// not, because the backend's `OrderStatus` has no such member — a payload
    /// cannot carry it, so there is nothing here to read.
    private func leadTone(_ order: Order, _ actor: OrderActor?) -> LeadTone {
        if order.status == .authFail { return .stopped }
        return actor == .you ? .ask : .calm
    }

    /// Price, when it was placed, and the listing's own number.
    ///
    /// The listing number is a different number from the order's, which is why
    /// a listing without one says nothing rather than borrowing it. The order's
    /// own number is in the navigation bar, where support asks for it.
    private func identityLine(_ order: Order) -> String {
        var parts = [PriceFormatter.format(order.grandTotal.value, currency: order.currency)]
        if let placed = order.createdAt {
            parts.append("Placed " + placed.formatted(.dateTime.month(.wide).day().year()))
        }
        if let number = order.listing?.listingNumber {
            parts.append("Listing #\(number)")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The policy, in one line each, with the screen that holds the rest.
    private func policyLine(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(returnTermsLine(order.returns))
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            // Said plainly, because a buyer will look for a cancel button and
            // there is not one. A person can still help before the watch is on
            // its way, and this is where they are.
            Text("Orders can\u{2019}t be cancelled once the seller ships.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Button("Talk to your Calibre contact") {
                Haptics.shared.play(.press)
                routePush(.supportChat)
            }
            .buttonStyle(.calibreGhost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What this order's own terms say, either way.
    private func returnTermsLine(_ terms: OrderReturnTerms?) -> String {
        guard let terms, terms.accepted else { return "Final sale \u{2014} no returns." }
        guard let hours = terms.windowHours else { return "Returns accepted." }
        return "Returns accepted for \(hours) hours after delivery."
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
        .background(Color.calibre.accent.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
    }

    /// The amount is the payload's own — never a remembered $250.
    private func wireHoldLine(_ hold: OrderWireHold) -> String {
        let amount = hold.amount.map { PriceFormatter.format($0.value) } ?? "The"
        return "\(amount) authorization placed \u{2014} released when your transfer arrives. If the transfer isn\u{2019}t sent by the deadline it is charged and split between the seller and Calibre."
    }

    // MARK: - Cards

    private func listingCard(_ order: Order) -> some View {
        Button {
            routePush(.listing(order.listingId))
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
                            routePush(.order(other))
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

    /// The one thing the verdict card said that the lead does not.
    ///
    /// What it replaces re-announced the verdict — "Authenticated by Calibre",
    /// or the whole refund paragraph — directly under a lead that had just
    /// said the same thing, because the lead could not say it before. This is
    /// the remainder: a note about the watch itself, not about the outcome.
    @ViewBuilder private func aftermarketNote(_ order: Order) -> some View {
        if order.authResult?.aftermarketFlag == true {
            Label("Aftermarket parts were noted during inspection.", systemImage: "wrench.and.screwdriver")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .cardSurface()
        }
    }

    // MARK: - The Passport

    /// The way into the booklet, from the moment the bench mints the code —
    /// which is authentication, days before the watch reaches the doorstep.
    ///
    /// Deliberately not gated on delivery. The Vault is the only other place
    /// this row exists, and the Vault holds watches the buyer already has, so
    /// until now the one document a buyer wanted to show somebody was out of
    /// reach for exactly as long as the watch was in the air. Nil-checked
    /// rather than status-checked because the code's presence *is* the fact:
    /// an order that never passed the bench has none.
    @ViewBuilder private func passportRow(_ order: Order) -> some View {
        if let code = order.passportCode {
            Button {
                routePush(.passport(code))
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.calibre.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This watch's Passport")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .multilineTextAlignment(.leading)
                        Text("The record that travels with it.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.calibre.placeholder)
                }
                .padding(Space.m)
                .leadRowSurface()
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens this watch's Passport")
        }
    }

    // MARK: - Reaching the seller

    /// The way to the person who sold this watch, under the card that shows it.
    ///
    /// The only conversation this screen offered was Support, and a buyer with
    /// a question about their own watch — which links came in the box, what it
    /// was serviced with — was being sent to Calibre staff to ask it. Those are
    /// the seller's answers. Support keeps its place further down for the order
    /// itself; this is for the watch.
    ///
    /// Same thread the listing screen opens, through the same `openThread`.
    /// The server keys it on (listing, buyer), so a buyer who wrote before
    /// buying carries on in the conversation they already have rather than
    /// starting a second one beside it.
    @ViewBuilder private func contactSellerRow(_ order: Order) -> some View {
        if canContactSeller(order) {
            Button {
                Haptics.shared.play(.press)
                contactSeller(order)
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.calibre.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contact seller")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .multilineTextAlignment(.leading)
                        Text("Ask about the watch itself.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.calibre.placeholder)
                }
                .padding(Space.m)
                .leadRowSurface()
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens your conversation with the seller")
        }
    }

    /// Two facts, read separately, because either one alone would be wrong.
    ///
    /// The payload has to name a seller to reach — `ListingSummary.seller` is
    /// optional and is absent on older order payloads, and a button that opens
    /// a conversation with nobody is worse than no button.
    ///
    /// And the viewer has to be this order's buyer. A seller looking at their
    /// own sale gets nothing: the thread is keyed on (listing, buyer), so the
    /// only thread they could open is one with themselves — which is why
    /// calibre-messaging answers `seller_id == user.id` with a 400 rather than
    /// creating it. Withheld here so nobody has to read that error to find out.
    private func canContactSeller(_ order: Order) -> Bool {
        guard let sellerID = order.listing?.seller?.id,
              let viewer = session.user?.id
        else { return false }
        return viewer == order.buyerId && viewer != sellerID
    }

    /// Opens (or resumes) the thread and pushes it, the same way the listing
    /// screen does.
    ///
    /// `listingTitle` is sent for the same reason the listing screen sends it
    /// and with the same weight: none. calibre-messaging refetches the listing
    /// itself and writes its own title and reference onto the thread
    /// (`create_thread` in `app/api/views/threads.py`), so what goes up here
    /// cannot name the conversation wrongly — which is also why the reference
    /// this payload does not carry is not a gap worth filling with a guess.
    private func contactSeller(_ order: Order) {
        guard let sellerID = order.listing?.seller?.id else { return }
        let routePush = routePush
        let toasts = toasts
        let messaging = services.messaging
        let listingID = order.listingId
        let listingTitle = order.listing?.title
        session.require("Sign in to contact the seller") {
            do {
                let thread = try await messaging.openThread(
                    listingID: listingID,
                    sellerID: sellerID,
                    listingTitle: listingTitle,
                    listingReference: nil
                )
                routePush(.messageThread(thread.id))
            } catch {
                Haptics.shared.play(.error)
                toasts.show(
                    title: "Couldn't start this conversation",
                    message: error.orderMessage,
                    tone: .error
                )
            }
        }
    }

    // MARK: - Tracking

    /// The tracking number, while the watch is actually travelling.
    ///
    /// An action for exactly as long as that is true, and a line in the detail
    /// at the foot for the rest of the time — one control either way. Gated on
    /// the shipment record and its number both existing: there is no carrier to
    /// fall back on and no scan to assume.
    @ViewBuilder private func trackingRow(_ order: Order) -> some View {
        if order.isTravelling, let shipment = travellingShipment(order), let tracking = shipment.trackingNumber {
            Button {
                UIPasteboard.general.string = tracking
                Haptics.shared.play(.selection)
                toasts.show(title: "Tracking number copied")
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.calibre.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tracking number")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .multilineTextAlignment(.leading)
                        Text(tracking)
                            .font(CalibreType.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.calibre.placeholder)
                }
                .padding(Space.m)
                .leadRowSurface()
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Copies the tracking number")
        }
    }

    /// The leg the watch is on, and nothing invented when there is none.
    private func travellingShipment(_ order: Order) -> Shipment? {
        order.status == .toBuyer ? order.toBuyerShipment : order.toAuthShipment
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

    // MARK: - The detail at the foot

    /// Receipt, shipment and address as one quiet block.
    ///
    /// Three section headings of the same rank used to stand between the
    /// journey and the review, each holding a short table, and none of them is
    /// what a buyer opened the screen for. They are what you look up once,
    /// so they are one block with headings a rank below the screen's own.
    private func detailsBlock(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Details")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            detailGroup("Receipt", rows: receiptRows(order))

            // A block about a parcel needs a parcel. Every pre-shipment order
            // has none, and used to get this block anyway — with a carrier
            // line invented under a lead that correctly said the seller still
            // had the watch. It draws off the record or not at all, and each
            // row is a fact the record actually carries.
            if let shipment = order.latestShipment ?? order.toBuyerShipment ?? order.toAuthShipment {
                detailGroup("Shipment", rows: shipmentRows(shipment))
            }

            detailGroup("Expected", rows: expectedRows(order))

            if let address = order.shippingAddress {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Delivery address").font(CalibreType.label).foregroundStyle(Color.calibre.mutedForeground)
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = address.fullName { Text(name).font(CalibreType.bodyMedium) }
                        if let line1 = address.line1 { Text(line1).font(CalibreType.body) }
                        if let line2 = address.line2, !line2.isEmpty { Text(line2).font(CalibreType.body) }
                        Text([address.city, address.region, address.postalCode].compactMap { $0 }.joined(separator: ", "))
                            .font(CalibreType.body)
                    }
                    .foregroundStyle(Color.calibre.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .cardSurface()
    }

    /// One titled table, or nothing at all when there is nothing to put in it.
    @ViewBuilder private func detailGroup(_ title: String, rows: [(String, String)]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(title).font(CalibreType.label).foregroundStyle(Color.calibre.mutedForeground)
                SpecList(rows)
            }
        }
    }

    /// Only what the shipment record actually says. No carrier stood in for,
    /// and no scan described that the carrier has not made.
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

    /// The backend's own estimates. Every one of them is nullable — a date we
    /// don't have is left unsaid rather than guessed at.
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
                HStack(alignment: .top, spacing: Space.m) {
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

                    // The needle takes a real reading: how much of the window
                    // is still ahead, from the window's own two timestamps.
                    // Both come off the server, so there is no assumption here
                    // about what the window ought to be — and a pair that does
                    // not parse draws nothing, because a gauge with a guessed
                    // denominator is worse than no gauge.
                    //
                    // It sweeps up to the reading once and then holds. It does
                    // not re-animate as the hours pass: a return window is
                    // measured in hours and a needle that twitches is
                    // decoration. The date in words above is the deadline; the
                    // arc never carries it alone.
                    if order.mark() == .dialArc, let remaining = terms.remainingFraction() {
                        CalibreMark.dialArc(remaining, size: 40, trigger: order.id)
                            .markAnnounces("return-window:\(order.id)")
                    }
                }

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
        // Item 1.22 — the duration leads, because it is what the buyer is
        // actually deciding against.
        let opening = terms.windowHours.map {
            "\($0)-hour returns, starting at delivery."
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
            // The same predicate the parcel is gated on, so the set of
            // statuses that refetch and the set that draw a box cannot drift.
            guard order?.isTravelling == true else { continue }
            // Only replace on success — a transient failure must not wipe the
            // rendered order and strand the screen on a spinner.
            if let refreshed = try? await services.commerce.order(id: orderID) {
                // The lead and the journey both change under a reader who is
                // still on the old ones and is told nothing. What is announced
                // is the sentence the lead itself now reads, so the spoken
                // update and the seen one cannot differ — and it is announced
                // only when it actually changed, which is what keeps a
                // sixty-second poll from talking over somebody every minute.
                let previous = order?.nextStep().sentence
                let updated = refreshed.nextStep().sentence
                order = refreshed
                syncReturnFlow(refreshed)
                if updated != previous {
                    A11y.announce("Order updated. \(updated)")
                }
            }
        }
    }

    // MARK: - The one illustrated moment

    /// The mark this screen draws, chosen by `Order.mark(now:)` so the
    /// precedence lives in one place and is testable without a screen. The
    /// budget is one per step of a journey, so the return window's gauge
    /// checks the same helper and stays away when it is not the answer.
    ///
    /// No `label` on any of them: the journey's own steps and the lead above
    /// them already say where the watch is and what the bench found, in words
    /// a screen reader reads. `CalibreMark` hides every drawing from
    /// accessibility for this reason.
    private func progressMark(_ order: Order) -> AnyView? {
        switch order.mark() {
        case .box:
            // The carton comes to rest in frame, packed and square, because
            // the departure is the journey and not the destination — and it
            // draws for the travelling statuses alone. Delivered, cancelled,
            // refunded and failed get no parcel: a carton leaving the frame on
            // a delivered order would read as the watch going away again.
            //
            // Keyed to the milestone itself, which is what stops the
            // sixty-second refetch re-sealing the same parcel while still
            // sending it off again on a status that moves under the buyer.
            return AnyView(
                CalibreMark.box(size: 48, trigger: order.status)
                    .markAnnounces(order.transitMarkKey)
            )
        case .stamp:
            // Calibre's bench passed this specific watch. Gated on the verdict
            // and never on how far along the journey is: the step a failed
            // order stops on is the step a passed one completes.
            guard let verdict = order.verdictMarkKey else { return nil }
            return AnyView(
                CalibreMark.stamp(size: 44, trigger: verdict)
                    .markAnnounces(verdict)
            )
        case .dialArc, .none:
            // The gauge belongs to the return panel, beside the window it is
            // reading; nothing goes here.
            return nil
        }
    }
}

private extension View {
    /// A row inside the lead, which already sits on a card of its own — so the
    /// rows are a shade of the ground they are on rather than cards on a card.
    func leadRowSurface() -> some View {
        background(
            Color.calibre.card.opacity(0.85),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    /// Standard bordered card surface used throughout the order detail.
    func cardSurface() -> some View {
        background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
}
