import CalibreDesign
import CalibreKit
import StripePaymentSheet
import SwiftUI

/// The offer entry sheet — amount with live serif rendering, an optional
/// note to the seller, the $250 hold consent, and the hold PaymentSheet.
/// Present in a `.sheet` (large detent comes from the scaffold).
struct MakeOfferSheet: View {
    let listingID: String

    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var model: MakeOfferModel?

    var body: some View {
        Group {
            if !session.isAuthenticated {
                SheetScaffold(title: "Make an offer", detents: [.large]) {
                    EmptyState(
                        icon: "arrow.left.arrow.right",
                        title: "Sign in to make an offer",
                        message: "Offers are backed by a small card hold, so we need to know it's you.",
                        actionTitle: "Sign in",
                        action: {
                            dismiss()
                            session.require("Sign in to make an offer") {}
                        }
                    )
                }
            } else if let model {
                sheetBody(model)
            } else {
                SheetScaffold(title: "Make an offer", detents: [.large]) {
                    ListingMiniCardSkeleton()
                }
            }
        }
        .task {
            guard session.isAuthenticated, model == nil else { return }
            let created = MakeOfferModel(
                listingID: listingID,
                catalog: services.catalog,
                commerce: services.commerce,
                client: services.client
            )
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func sheetBody(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        switch model.phase {
        case .existing(let offer):
            // An open offer already exists — show its negotiation instead.
            NavigationStack {
                OfferDetailScreen(offerID: offer.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                                .font(CalibreType.bodySemiBold)
                                .tint(Color.calibre.primary)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationBackground(Color.calibre.background)
            .presentationCornerRadius(Radius.overlay)
        default:
            SheetScaffold(title: scaffoldTitle(model), detents: [.large]) {
                ScrollView {
                    content(model)
                        .padding(.bottom, Space.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(paymentSheetHost(model))
        }
    }

    private func scaffoldTitle(_ model: MakeOfferModel) -> String? {
        switch model.phase {
        case .sent: nil
        default: "Make an offer"
        }
    }

    @ViewBuilder
    private func content(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        switch model.phase {
        case .loading:
            VStack(spacing: Space.l) {
                ListingMiniCardSkeleton()
                Rectangle().frame(height: 52).shimmer()
                Rectangle().frame(height: 44).shimmer()
            }
        case .failed(let message):
            EmptyState(
                icon: "wifi.exclamationmark",
                title: "We couldn't load this listing",
                message: message,
                actionTitle: "Try again",
                action: { Task { await model.load() } }
            )
        case .input:
            inputForm(model)
        case .holdIssue(let message):
            holdIssue(model, message: message)
        case .sent(let offer):
            sentMoment(model, offer: offer)
        case .existing:
            EmptyView()
        }
    }

    // MARK: - Input

    @ViewBuilder
    private func inputForm(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Space.l) {
            if let listing = model.listing {
                ListingMiniCard(listing: listing)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow("Your offer")
                Text(model.displayAmountText)
                    .font(CalibreType.priceLarge)
                    .foregroundStyle(Color.calibre.foreground)
                    .contentTransition(.numericText())
                    .animation(Motion.easeMedium, value: model.displayAmountText)

                CalibreTextField(
                    "Amount",
                    text: $model.amountText,
                    placeholder: "0",
                    error: model.amountError
                ) {
                    Text("USD")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .keyboardType(.decimalPad)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text("Message to the seller (optional)")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                TextField(
                    "",
                    text: $model.message,
                    prompt: Text("Anything they should know?")
                        .foregroundStyle(Color.calibre.placeholder),
                    axis: .vertical
                )
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.foreground)
                .tint(Color.calibre.primary)
                .lineLimit(3...6)
                .padding(Space.m)
                .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Color.calibre.border, lineWidth: 1)
                )
                .onChange(of: model.message) { _, newValue in
                    if newValue.count > 1000 {
                        model.message = String(newValue.prefix(1000))
                    }
                }
            }

            consentRow(model)

            if let error = model.error {
                InlineErrorLine(message: error)
            }

            Button {
                Haptics.shared.play(.press)
                Task { await model.submit() }
            } label: {
                BusyLabel(title: "Continue — authorize the $250 hold", busy: model.creating)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(!model.canSubmit || model.creating)
        }
        .animation(Motion.easeFast, value: model.error)
    }

    private func consentRow(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        return HStack(alignment: .top, spacing: Space.m) {
            Text("I authorize a $250 hold on my card. If the seller accepts and I back out or miss the payment window, Calibre may charge this hold.")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("", isOn: $model.consented)
                .labelsHidden()
                .tint(Color.calibre.primary)
        }
        .padding(Space.l)
        .background(Color.calibre.accent.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hold issue (failed / canceled PaymentSheet)

    private func holdIssue(_ model: MakeOfferModel, message: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let listing = model.listing {
                ListingMiniCard(listing: listing)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text("Your offer isn't sent yet")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Text("The $250 hold wasn't completed, so the seller hasn't seen your offer. You can finish the hold or withdraw the offer.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                InlineErrorLine(message: message)
            }

            Button {
                Haptics.shared.play(.press)
                model.retryHold()
            } label: {
                Text("Try the hold again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))

            Button {
                Task {
                    if await model.cancelOffer() {
                        toasts.show(title: "Offer withdrawn", message: "No hold was kept on your card.")
                        dismiss()
                    }
                }
            } label: {
                BusyLabel(title: "Cancel offer", busy: model.cancelling)
                    .foregroundStyle(Color.calibre.destructive)
            }
            .buttonStyle(.calibreGhost)
            .disabled(model.cancelling)
        }
    }

    // MARK: - Sent

    private func sentMoment(_ model: MakeOfferModel, offer: Offer) -> some View {
        VStack(spacing: Space.l) {
            Spacer(minLength: Space.xxl)
            IconTile(systemName: "paperplane")
            VStack(spacing: Space.s) {
                Text("Offer sent.")
                    .font(CalibreType.display)
                    .foregroundStyle(Color.calibre.foreground)
                Text("\(model.sellerName) has 24 hours to respond. We'll let you know the moment they do.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Space.s) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                Text("$250 hold authorized · released after payment")
                    .font(CalibreType.caption)
            }
            .foregroundStyle(Color.calibre.mutedForeground)

            Spacer(minLength: Space.xxl)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Haptics.shared.play(.success)
        }
    }

    // MARK: - PaymentSheet host

    @ViewBuilder
    private func paymentSheetHost(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        if let sheet = model.paymentSheet {
            Color.clear
                .paymentSheet(isPresented: $model.presentingPaymentSheet, paymentSheet: sheet) { result in
                    model.handleHoldResult(result)
                }
        }
    }
}

/// State for the offer entry sheet: listing, form fields, offer creation,
/// the hold PaymentSheet and its aftermath.
@MainActor
@Observable
final class MakeOfferModel {
    enum Phase {
        case loading
        case input
        case holdIssue(message: String?)
        case sent(Offer)
        case existing(Offer)
        case failed(String)
    }

    let listingID: String
    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let checkout: CheckoutStore

    var phase: Phase = .loading
    var listing: Listing?

    var amountText = ""
    var message = ""
    var consented = false
    var error: String?
    private(set) var creating = false
    private(set) var cancelling = false

    private(set) var offer: Offer?
    private(set) var paymentSheet: PaymentSheet?
    var presentingPaymentSheet = false

    init(listingID: String, catalog: CatalogStore, commerce: CommerceStore, client: APIClient) {
        self.listingID = listingID
        self.catalog = catalog
        self.commerce = commerce
        self.checkout = CheckoutStore(client: client)
    }

    var sellerName: String {
        listing?.seller?.username ?? "The seller"
    }

    func load() async {
        phase = .loading
        do {
            let listing = try await catalog.listing(id: listingID)
            self.listing = listing
            if amountText.isEmpty {
                amountText = plainAmount(listing.price.value)
            }
            phase = .input
        } catch {
            phase = .failed(friendlyMessage(error))
        }
    }

    // MARK: Amount

    var parsedAmount: Decimal? {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    var displayAmountText: String {
        guard let amount = parsedAmount else { return "$0" }
        return PriceFormatter.format(amount, currency: listing?.currency ?? "USD")
    }

    var amountError: String? {
        amountText.isEmpty || parsedAmount != nil ? nil : "Enter a valid amount."
    }

    var canSubmit: Bool {
        parsedAmount != nil && consented
    }

    // MARK: Create + hold

    func submit() async {
        guard let amount = parsedAmount, consented, !creating else { return }
        creating = true
        error = nil
        defer { creating = false }
        do {
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let offer = try await commerce.createOffer(
                listingID: listingID,
                amount: amount,
                currency: listing?.currency ?? "USD",
                message: trimmedMessage.isEmpty ? nil : trimmedMessage
            )
            self.offer = offer
            presentHold(for: offer)
        } catch let apiError as APIError {
            if case .server(let message, _, let status, _) = apiError, status == 409 {
                if let existing = await findOpenOffer() {
                    phase = .existing(existing)
                } else {
                    error = message
                }
            } else {
                error = apiError.errorDescription
            }
        } catch {
            self.error = friendlyMessage(error)
        }
    }

    private func presentHold(for offer: Offer) {
        guard let clientSecret = offer.hold?.clientSecret else {
            phase = .holdIssue(message: "We couldn't start the card hold. Please try again.")
            return
        }
        if let key = offer.publishableKey {
            STPAPIClient.shared.publishableKey = key
        }
        // The create response carries a mobile CustomerSession secret but no
        // Stripe customer id, which PaymentSheet's customer configuration
        // requires — so the hold sheet runs customer-less (cards + Apple Pay
        // still work; saved cards just don't redisplay).
        let configuration = CalibreStripe.configuration(
            customerID: nil,
            customerSessionClientSecret: nil
        )
        paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        presentingPaymentSheet = true
    }

    func retryHold() {
        guard let offer else { return }
        if paymentSheet == nil {
            presentHold(for: offer)
        } else {
            presentingPaymentSheet = true
        }
    }

    func handleHoldResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            Task { await confirmHold() }
        case .canceled:
            phase = .holdIssue(message: nil)
        case .failed(let failure):
            phase = .holdIssue(message: CalibreStripe.failureMessage(for: failure))
        }
    }

    private func confirmHold() async {
        guard let offer else { return }
        do {
            let confirmed = try await commerce.confirmHold(offerID: offer.id)
            self.offer = confirmed
            phase = .sent(confirmed)
        } catch {
            phase = .holdIssue(message: friendlyMessage(error))
        }
    }

    func cancelOffer() async -> Bool {
        guard let offer, !cancelling else { return false }
        cancelling = true
        defer { cancelling = false }
        do {
            _ = try await commerce.cancelOffer(offerID: offer.id)
            return true
        } catch {
            phase = .holdIssue(message: friendlyMessage(error))
            return false
        }
    }

    // MARK: Conflict → existing offer

    private func findOpenOffer() async -> Offer? {
        guard let offers = try? await checkout.offers(onListing: listingID) else { return nil }
        return offers.first { $0.perspective == "sent" && offerIsOpen($0) }
    }

    // MARK: Helpers

    private func plainAmount(_ value: Decimal) -> String {
        var rounded = value
        var result = Decimal()
        NSDecimalRound(&result, &rounded, 2, .plain)
        return "\(result)"
    }

    private func friendlyMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
