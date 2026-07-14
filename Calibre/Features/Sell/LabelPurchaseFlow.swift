import CalibreDesign
import CalibreKit
import StripePaymentSheet
import SwiftUI

/// Package details → live quote → PaymentSheet on the seller-label
/// PaymentIntent → finalize. Pushed from `SaleDetailScreen`.
struct LabelPurchaseFlow: View {
    let order: Order
    /// Called with the advanced order once the label is finalized.
    let onLabelReady: (Order) -> Void

    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts

    // Carrier limits (backend defaults; the server re-validates).
    private static let maxLengthIn = Decimal(108)
    private static let maxGirthPlusLengthIn = Decimal(108)

    @State private var lengthText = "10"
    @State private var widthText = "8"
    @State private var heightText = "5"
    @State private var weightText = "2"
    @State private var notes = ""

    @State private var validationError: String?
    @State private var quote: SellerLabelQuote?
    @State private var quoting = false
    @State private var quoteError: String?
    @State private var quoteTask: Task<Void, Never>?

    @State private var paying = false
    @State private var finalizing = false
    @State private var paymentSheet: PaymentSheet?
    @State private var presentingSheet = false
    @State private var pendingIntent: SellerLabelIntent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("How is it packed?")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Box dimensions and weight set the exact label price. Watches ship fully insured to our authentication center.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                packageForm

                if let validationError {
                    Text(validationError)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.destructive)
                        .transition(.opacity)
                }

                quoteCard

                Button {
                    startPayment()
                } label: {
                    if paying || finalizing {
                        ProgressView().tint(Color.calibre.primaryForeground)
                    } else if let quote {
                        Text("Pay \(PriceFormatter.format(quote.amount.value)) for the label")
                    } else {
                        Text("Get the label")
                    }
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(quote == nil || validationError != nil || paying || finalizing)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Shipping label")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Motion.easeFast, value: validationError)
        .onAppear {
            revalidateAndQuote()
        }
        .paymentSheet(
            isPresented: $presentingSheet,
            paymentSheet: paymentSheet ?? placeholderSheet,
            onCompletion: handlePaymentResult
        )
    }

    // MARK: - Form

    private var packageForm: some View {
        VStack(spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                dimensionField("Length", text: $lengthText)
                dimensionField("Width", text: $widthText)
                dimensionField("Height", text: $heightText)
            }
            CalibreTextField("Weight", text: $weightText, placeholder: "2") {
                Text("lb")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .keyboardType(.decimalPad)
            .onChange(of: weightText) { _, _ in revalidateAndQuote() }

            CalibreTextField("Notes for the carrier (optional)", text: $notes, placeholder: "Leave at the front desk")
                .onChange(of: notes) { _, value in
                    if value.count > 500 { notes = String(value.prefix(500)) }
                }
        }
    }

    private func dimensionField(_ label: String, text: Binding<String>) -> some View {
        CalibreTextField(label, text: text, placeholder: "0") {
            Text("in")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .keyboardType(.decimalPad)
        .onChange(of: text.wrappedValue) { _, _ in revalidateAndQuote() }
    }

    // MARK: - Validation + quote

    private var package: SellerLabelPackagePayload? {
        guard let length = Decimal.fromMoneyText(lengthText),
              let width = Decimal.fromMoneyText(widthText),
              let height = Decimal.fromMoneyText(heightText),
              let weight = Decimal.fromMoneyText(weightText),
              length > 0, width > 0, height > 0, weight > 0 else {
            return nil
        }
        return SellerLabelPackagePayload(
            boxLengthIn: length,
            boxWidthIn: width,
            boxHeightIn: height,
            weightLb: weight,
            notes: InputValidation.isNonBlank(notes) ? InputValidation.trimmed(notes) : nil
        )
    }

    /// Same rule the carriers enforce: longest side ≤ 108", and longest side
    /// plus twice the other two ≤ 108".
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
        if sides[0] > Self.maxLengthIn {
            return "That's longer than carriers accept — keep the longest side under \(Self.maxLengthIn) inches."
        }
        let girthPlusLength = sides[0] + 2 * (sides[1] + sides[2])
        if girthPlusLength > Self.maxGirthPlusLengthIn {
            return "Length plus girth comes to \(girthPlusLength)\" — carriers cap it at \(Self.maxGirthPlusLengthIn)\". A smaller box will do it."
        }
        return nil
    }

    private func revalidateAndQuote() {
        validationError = validate()
        quoteTask?.cancel()
        guard validationError == nil, let package else {
            quote = nil
            quoting = false
            return
        }
        quoting = true
        quoteError = nil
        quoteTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                let result = try await sell.ops.labelQuote(orderID: order.id, package: package)
                guard !Task.isCancelled else { return }
                if result.alreadyCreated == true {
                    // Label already exists — jump straight to it.
                    onLabelReady(order)
                    return
                }
                quote = result.quote
            } catch {
                quote = nil
                quoteError = sellErrorMessage(error)
            }
            quoting = false
        }
    }

    @ViewBuilder
    private var quoteCard: some View {
        SellCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Label price")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                    if quoting {
                        ProgressView().controlSize(.small).tint(Color.calibre.primary)
                    } else if let quote {
                        Text(PriceFormatter.format(quote.amount.value))
                            .font(CalibreType.priceLarge)
                            .foregroundStyle(Color.calibre.foreground)
                            .contentTransition(.numericText())
                    } else if let quoteError {
                        Text(quoteError)
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.destructive)
                    } else {
                        Text("Enter the box size for a live quote.")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }
                Spacer()
                Image(systemName: "shippingbox")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.calibre.primary)
            }
            .padding(Space.l)
        }
    }

    // MARK: - Payment

    /// Never presented — satisfies the modifier while `paymentSheet` is nil.
    private var placeholderSheet: PaymentSheet {
        PaymentSheet(paymentIntentClientSecret: "pi_placeholder_secret_placeholder", configuration: .init())
    }

    private func startPayment() {
        guard let package, validationError == nil, !paying else { return }
        paying = true
        Task {
            defer { paying = false }
            do {
                let intent = try await sell.ops.labelPaymentIntent(orderID: order.id, package: package)
                if intent.alreadyCreated == true {
                    onLabelReady(order)
                    return
                }
                guard let paymentIntent = intent.paymentIntent, let key = intent.publishableKey else {
                    toasts.show(title: "Couldn't start the payment", message: "Please try again.", tone: .error)
                    return
                }
                STPAPIClient.shared.publishableKey = key

                var configuration = PaymentSheet.Configuration()
                configuration.merchantDisplayName = "Calibre"
                configuration.style = .automatic
                configuration.primaryButtonColor = UIColor(Color.calibre.primary)
                if let customerID = intent.customerId, let session = intent.customerSessionClientSecret {
                    configuration.customer = .init(id: customerID, customerSessionClientSecret: session)
                }

                pendingIntent = intent
                paymentSheet = PaymentSheet(
                    paymentIntentClientSecret: paymentIntent.clientSecret,
                    configuration: configuration
                )
                presentingSheet = true
            } catch {
                toasts.show(title: "Couldn't start the payment", message: sellErrorMessage(error), tone: .error)
            }
        }
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            Haptics.shared.play(.paymentSuccess)
            finalize()
        case .canceled:
            break
        case .failed(let error):
            toasts.show(title: "Payment didn't go through", message: error.localizedDescription, tone: .error)
        }
    }

    private func finalize() {
        guard !finalizing,
              let pendingIntent,
              let paymentIntent = pendingIntent.paymentIntent,
              let package else { return }
        finalizing = true
        Task {
            defer { finalizing = false }
            do {
                let result = try await sell.ops.finalizeLabel(
                    orderID: order.id,
                    paymentIntentID: paymentIntent.id,
                    package: package
                )
                if let updated = result.order {
                    onLabelReady(updated)
                } else {
                    onLabelReady(try await sell.ops.order(id: order.id))
                }
            } catch {
                // The webhook finalizes too — re-fetch before giving up.
                if let refreshed = try? await sell.ops.order(id: order.id), refreshed.toAuthShipment != nil {
                    onLabelReady(refreshed)
                } else {
                    toasts.show(
                        title: "Payment received",
                        message: "The label is still being prepared — check back in a moment.",
                        tone: .neutral
                    )
                }
            }
        }
    }
}

/// The purchased label: PDF, tracking, destination and the ship-by clock.
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
