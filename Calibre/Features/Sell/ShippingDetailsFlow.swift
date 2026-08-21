import CalibreDesign
import CalibreKit
import SwiftUI

/// The seller's part of fulfillment, start to finish: the box they measured,
/// what that box costs, what it leaves them, and then the label.
///
/// The seller no longer buys their own label — there is no checkout here and
/// nothing is charged to them. They give the real dimensions, Calibre buys
/// the label, and what it actually cost is what comes off the payout. That is
/// why the form shows the consequence next to the cause before the button
/// does anything.
struct ShippingDetailsFlow: View {
    let order: Order
    /// Called with the advanced order once the label exists.
    let onLabelReady: (Order) -> Void

    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts

    @State private var lengthText = ""
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var notes = ""

    @State private var validationError: String?
    /// The quote, and the exact box it priced. A quote for a box that no
    /// longer exists is never shown next to a different box.
    @State private var quote: FulfillmentShippingQuote?
    @State private var quotedKey: String?
    @State private var quoting = false
    @State private var quoteError: String?

    @State private var submitting = false
    @State private var submitError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                packageForm

                if let validationError {
                    InlineErrorLine(message: validationError)
                }

                if let quoteError {
                    InlineErrorLine(message: quoteError)
                }

                if quoteIsCurrent, let quote, let amount = quote.amount?.value {
                    quoteCard(quote, amount: amount)
                } else {
                    priceButton
                }

                if let submitError {
                    InlineErrorLine(message: submitError)
                }

                if let deadline = order.fulfillmentDeadlineAt {
                    HStack(spacing: Space.m) {
                        Text("Ship by")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        CountdownChip(until: deadline)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Shipping details")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Motion.easeFast, value: validationError)
        .animation(Motion.easeFast, value: quotedKey)
        .onAppear(perform: hydrateFromOrder)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text([order.listing?.title, order.displayNumber].compactMap { $0 }.joined(separator: " \u{00B7} "))
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text("How big is the box?")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            Text("Measure the box you are actually sending. Calibre buys the label \u{2014} you pay nothing now, and what the label costs comes off your payout.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text("It ships to our authentication centre, insured for the full sale price, signature required.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Form

    private var packageForm: some View {
        VStack(spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                dimensionField("Length", text: $lengthText)
                dimensionField("Width", text: $widthText)
                dimensionField("Height", text: $heightText)
            }
            CalibreTextField("Weight", text: $weightText, placeholder: "2", kind: .decimal) {
                Text("lb")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .onChange(of: weightText) { _, _ in boxChanged() }

            CalibreTextField(
                "Notes for the carrier (optional)",
                text: $notes,
                placeholder: "Leave at the front desk",
                kind: .sentence
            )
            .onChange(of: notes) { _, value in
                if value.count > 500 { notes = String(value.prefix(500)) }
            }
        }
    }

    private func dimensionField(_ label: String, text: Binding<String>) -> some View {
        CalibreTextField(label, text: text, placeholder: "0", kind: .decimal) {
            Text("in")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .onChange(of: text.wrappedValue) { _, _ in boxChanged() }
    }

    // MARK: - Quote

    private var priceButton: some View {
        VStack(spacing: Space.s) {
            Button {
                Haptics.shared.play(.press)
                Task { await priceThisBox() }
            } label: {
                BusyLabel(title: "Price this box", busy: quoting)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(package == nil || validationError != nil || quoting)

            Text("Nothing is bought and nothing is charged \u{2014} this is only what the box would cost.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quoteCard(_ quote: FulfillmentShippingQuote, amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("This box costs \(PriceFormatter.format(amount, currency: quote.currency ?? order.currency))")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Calibre buys the label. The actual cost comes off your payout \u{2014} here is what that leaves.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = quote.payoutPreview {
                PayoutLedger(breakdown: preview, currency: order.currency)
            }

            Button {
                Haptics.shared.play(.press)
                Task { await confirm() }
            } label: {
                BusyLabel(title: "Confirm and get my label", busy: submitting)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(submitting)

            Button("Change the box") {
                quotedKey = nil
            }
            .buttonStyle(.calibre(.ghost, fullWidth: true))
            .disabled(submitting)
        }
    }

    // MARK: - The box

    private var package: FulfillmentPackagePayload? {
        guard let length = Decimal.fromMoneyText(lengthText),
              let width = Decimal.fromMoneyText(widthText),
              let height = Decimal.fromMoneyText(heightText),
              let weight = Decimal.fromMoneyText(weightText),
              length > 0, width > 0, height > 0, weight > 0 else {
            return nil
        }
        return FulfillmentPackagePayload(
            length: length,
            width: width,
            height: height,
            weight: weight,
            notes: InputValidation.isNonBlank(notes) ? InputValidation.trimmed(notes) : nil
        )
    }

    /// Identity of the box currently typed, so a quote is never shown beside
    /// a box it did not price.
    private var boxKey: String? {
        guard let package else { return nil }
        return "\(package.length)x\(package.width)x\(package.height)@\(package.weight)"
    }

    private var quoteIsCurrent: Bool {
        quotedKey != nil && quotedKey == boxKey
    }

    private var maxLengthIn: Decimal {
        order.shippingPackageLimits?.maxLengthIn.map { Decimal($0) } ?? 22
    }

    private var maxGirthPlusLengthIn: Decimal {
        order.shippingPackageLimits?.maxGirthPlusLengthIn.map { Decimal($0) } ?? 130
    }

    /// The carrier's own rule, checked here so a refusal costs a tap rather
    /// than a round trip. The server checks it again.
    private func validate() -> String? {
        guard let length = Decimal.fromMoneyText(lengthText),
              let width = Decimal.fromMoneyText(widthText),
              let height = Decimal.fromMoneyText(heightText),
              let weight = Decimal.fromMoneyText(weightText) else {
            return nil // incomplete, not wrong — just wait
        }
        guard length > 0, width > 0, height > 0 else {
            return "Each side needs to be more than zero inches."
        }
        guard weight > 0 else {
            return "The package needs a weight."
        }
        let sides = [length, width, height].sorted(by: >)
        if sides[0] > maxLengthIn {
            return "Longest side exceeds the carrier maximum of \(maxLengthIn) inches."
        }
        if sides[0] + 2 * (sides[1] + sides[2]) > maxGirthPlusLengthIn {
            return "Length plus girth exceeds the carrier maximum of \(maxGirthPlusLengthIn) inches. A smaller box will do it."
        }
        return nil
    }

    private func boxChanged() {
        validationError = validate()
        // The quote priced a box that no longer exists.
        quotedKey = nil
        quoteError = nil
        submitError = nil
    }

    /// A box already recorded on the order is the box the seller last told us
    /// about, so the form opens on it rather than on blanks.
    private func hydrateFromOrder() {
        guard lengthText.isEmpty, let stored = order.sellerLabelPackage, !stored.isEmpty else { return }
        lengthText = stored.boxLengthIn.map { "\($0.value)" } ?? ""
        widthText = stored.boxWidthIn.map { "\($0.value)" } ?? ""
        heightText = stored.boxHeightIn.map { "\($0.value)" } ?? ""
        weightText = stored.weightLb.map { "\($0.value)" } ?? ""
        notes = stored.notes ?? ""
        validationError = validate()
    }

    // MARK: - Calls

    private func priceThisBox() async {
        guard let package, validationError == nil, !quoting else { return }
        quoting = true
        quoteError = nil
        defer { quoting = false }
        do {
            let result = try await sell.ops.shippingQuote(orderID: order.id, package: package)
            if result.alreadyCreated == true {
                // A label already exists. Nothing is re-priced and nothing is
                // bought again — this order is simply further along.
                await handOffExistingLabel()
                return
            }
            quote = result
            quotedKey = boxKey
        } catch {
            quote = nil
            quotedKey = nil
            quoteError = sellErrorMessage(error)
        }
    }

    private func confirm() async {
        guard let package, !submitting else { return }
        submitting = true
        submitError = nil
        defer { submitting = false }
        do {
            let result = try await sell.ops.submitShippingDetails(orderID: order.id, package: package)
            Haptics.shared.play(.success)
            toasts.show(
                title: result.alreadyCreated
                    ? "This order already had a label"
                    : "Your label is ready",
                message: result.alreadyCreated
                    ? "Nothing was bought twice."
                    : "Print it and hand the watch to the carrier.",
                tone: .success
            )
            if let advanced = result.order {
                onLabelReady(advanced)
            } else {
                await handOffExistingLabel()
            }
        } catch {
            Haptics.shared.play(.error)
            submitError = sellErrorMessage(error)
        }
    }

    /// Re-reads the order so the label screen is drawn from the server's own
    /// account of it rather than from a stale copy.
    private func handOffExistingLabel() async {
        if let refreshed = try? await sell.ops.order(id: order.id) {
            onLabelReady(refreshed)
        } else {
            onLabelReady(order)
        }
    }
}

/// The label Calibre bought: the PDF, tracking, where it is going, the ship-by
/// clock, and what that label did to the payout.
struct LabelReadyScreen: View {
    let order: Order

    @Environment(ToastCenter.self) private var toasts

    private var shipment: Shipment? { order.toAuthShipment ?? order.latestShipment }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Your label is ready")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Print it, pack the watch snugly, and drop it off. Tracking updates land in your Activity feed.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let labelURL = shipment?.labelUrl?.url {
                    ShareLink(item: labelURL) {
                        Label("Download label PDF", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                }

                trackingCard

                if let breakdown = order.payoutBlock?.breakdown {
                    PayoutLedger(
                        breakdown: breakdown,
                        currency: order.currency,
                        title: "What this label did to your payout"
                    )
                }

                destinationCard

                if let deadline = order.fulfillmentDeadlineAt {
                    HStack(spacing: Space.m) {
                        Text("Ship by")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        CountdownChip(until: deadline)
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Shipping label")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var trackingCard: some View {
        if let shipment {
            SellCard {
                VStack(spacing: 0) {
                    if let tracking = shipment.trackingNumber, !tracking.isEmpty {
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
                            Spacer()
                            Button {
                                UIPasteboard.general.string = tracking
                                Haptics.shared.play(.save)
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
                        Rectangle().fill(Color.calibre.border).frame(height: 1)
                    }
                    HStack {
                        Text("Carrier")
                            .font(CalibreType.body)
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Spacer()
                        Text(shipment.carrier?.uppercased() == shipment.carrier
                            ? (shipment.carrier ?? "—")
                            : (shipment.carrier?.capitalized ?? "—"))
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                }
            }
        }
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Destination")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            SellCard {
                HStack(alignment: .top, spacing: Space.m) {
                    IconTile(systemName: "checkmark.shield")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calibre Authentication Center")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                        ForEach(addressLines, id: \.self) { line in
                            Text(line)
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        Text("The label is pre-addressed — nothing to write.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .padding(.top, Space.xs)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.l)
            }
        }
    }

    private var addressLines: [String] {
        guard let address = order.authCenterAddress else { return [] }
        let cityLine = [address.city, address.region, address.postalCode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return [address.line1, address.line2, cityLine.isEmpty ? nil : cityLine]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }
}
