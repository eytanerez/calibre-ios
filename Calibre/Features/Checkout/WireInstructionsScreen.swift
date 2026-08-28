import CalibreDesign
import CalibreKit
import SwiftUI

/// The wire path terminus — bank details with per-row copy, the reference
/// warning, the reservation countdown, and "I've sent the wire". The window
/// itself is the marketplace config's, matching what the method step quoted.
///
/// A purchase covering several watches is one transfer for one combined
/// amount, said once: "I've sent the wire" reserves the whole group.
struct WireInstructionsScreen: View {
    @Bindable var model: CheckoutModel
    let onReserved: ([Order]) -> Void

    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @State private var confirmingSent = false
    @State private var tutorial = TutorialController(
        id: "checkout.wire",
        steps: [
            TutorialStep(
                id: "copy",
                anchor: "wire.details",
                title: "Tap to copy",
                message: "Every field has a copy button — tap one to drop it straight onto your clipboard for your bank's transfer form.",
                advance: .perform(event: "copy"),
                hint: .tap,
                cutout: .roundedRect(Radius.card),
                actionPrompt: "Tap a copy button"
            ),
            TutorialStep(
                id: "reference",
                anchor: "wire.reference",
                title: "Two things that matter",
                message: "Include the reference or your transfer can't be matched to this order. And “I've sent the wire” only tells us to expect it — tap that after you've actually sent the money from your bank.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.card)
            ),
        ]
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let checkout = model.wireCheckout, let breakdown = checkout.payableBreakdown {
                    header(checkout, breakdown: breakdown)

                    if model.isMultiItem {
                        CheckoutItemsCard(items: model.items)
                    }

                    // The $250 the buyer can see on their statement, said
                    // where they are looking for it. There is no release
                    // control here or anywhere else: it comes off when the
                    // transfer arrives.
                    if model.wireHold != nil {
                        depositBand
                    }

                    if let instructions = checkout.wire.instructions {
                        detailRows(instructions, breakdown: breakdown)
                            .tutorialAnchor("wire.details")

                        CalloutBand(
                            icon: "number",
                            title: "The reference matters",
                            message: "Include the reference or your transfer can't be matched to this order."
                        )
                        .tutorialAnchor("wire.reference")
                    } else {
                        EmptyState(
                            icon: "building.columns",
                            title: "Instructions on their way",
                            message: "We couldn't display the bank details right now. Go back and try again, or pay by card instead."
                        )
                    }

                    if let error = model.pricingError {
                        InlineErrorLine(message: error)
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
        .calibrePageBackground()
        .tutorialOverlay(tutorial)
        .navigationTitle("Wire transfer")
        .navigationBarTitleDisplayMode(.inline)
        .task { try? await services.config.load() }
        .onAppear {
            if model.wireCheckout?.wire.instructions != nil { tutorial.startIfNeeded() }
        }
        .onChange(of: model.wireCheckout?.wire.instructions != nil) { _, hasInstructions in
            if hasInstructions { tutorial.startIfNeeded() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CheckoutCloseButton() }
        }
        .safeAreaInset(edge: .bottom) {
            if model.wireCheckout?.wire.instructions != nil {
                Button {
                    Haptics.shared.play(.press)
                    confirmingSent = true
                } label: {
                    BusyLabel(title: "I've sent the wire", busy: model.sendingWireReservation)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.sendingWireReservation)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.m)
                .background(Color.calibre.background.opacity(0.97))
            }
        }
        .animation(Motion.easeFast, value: model.pricingError)
        .alert(
            "Confirm your wire transfer",
            isPresented: $confirmingSent
        ) {
            Button("Yes, I've sent it") {
                Task {
                    let orders = await model.confirmWireSent()
                    if !orders.isEmpty {
                        Haptics.shared.play(.success)
                        onReserved(orders)
                    }
                }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    /// One transfer covers the whole purchase, so this is confirmed once —
    /// and the sentence says what "once" covers.
    private var confirmationMessage: String {
        if model.isMultiItem {
            return "Once you continue, all \(model.itemCount) orders are marked as sent and we'll wait for the single transfer to arrive. Only confirm once you've actually completed the wire with your bank."
        }
        return "Once you continue, this order is marked as sent and we'll wait for the transfer to arrive. Only confirm once you've actually completed the wire with your bank."
    }

    // MARK: - Pieces

    /// The authorization, and \u{2014} when the issuer wanted a challenge the buyer
    /// walked away from \u{2014} the way to finish it. The same intent is retried;
    /// a new checkout would place a second $250 and abandon this one.
    @ViewBuilder
    private var depositBand: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            CalloutBand(
                icon: "creditcard",
                title: CheckoutCopy.wireHoldPlaced,
                message: CheckoutCopy.wireHoldDisclosure
            )

            if let holdError = model.wireHoldError {
                InlineErrorLine(message: holdError)
                Button("Finish the check with your bank") {
                    Haptics.shared.play(.press)
                    Task { await model.confirmWireHoldChallenge() }
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
            }
        }
        .animation(Motion.easeFast, value: model.wireHoldError)
    }

    private func header(_ checkout: WireCheckout, breakdown: CheckoutBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // One transfer, one amount — the combined total the server priced
            // for the whole purchase, never a per-watch figure.
            Eyebrow(model.isMultiItem ? "Send exactly, in one transfer" : "Send exactly")
            Text(PriceFormatter.format(breakdown.grandTotal.value, currency: breakdown.currency))
                .font(CalibreType.priceLarge)
                .foregroundStyle(Color.calibre.foreground)

            HStack(spacing: Space.m) {
                CountdownChip(until: reservationDeadline(checkout))
                // The same window the method step quoted, from the same
                // config — never a second, differently remembered number.
                Text(model.isMultiItem
                    ? "All \(model.itemCount) watches are held for \(reservationPhrase)."
                    : "Your watch is held for \(reservationPhrase).")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var reservationPhrase: String {
        CheckoutCopy.wireReservationPhrase(services.config.config?.wireReservationText)
    }

    /// The server's own expiry when it sent one. The local fallback only
    /// covers the seconds before the payload lands, and takes the shortest
    /// window the config states rather than a remembered one.
    private func reservationDeadline(_ checkout: WireCheckout) -> Date {
        if let expiry = checkout.session?.expiresAtDate { return expiry }
        let hours = services.config.config?.wireReservationHours.min() ?? 24
        return Date.now.addingTimeInterval(TimeInterval(hours) * 3600)
    }

    private func detailRows(_ instructions: WireInstructions, breakdown: CheckoutBreakdown) -> some View {
        var rows: [(label: String, value: String, emphasized: Bool)] = []
        let details = instructions.financialAddresses.first?.details

        if let bank = details?.bankName {
            rows.append(("Bank", bank, false))
        }
        if let routing = details?.routingNumber {
            rows.append(("Routing", routing, false))
        }
        if let account = details?.accountNumber {
            rows.append(("Account", account, false))
        }
        if let swiftDetails = instructions.financialAddresses.first(where: { $0.swift != nil })?.swift,
           let code = swiftDetails.swiftCode {
            rows.append(("SWIFT", code, false))
        }
        rows.append((
            "Amount",
            PriceFormatter.format(
                instructions.amountRemaining?.value ?? breakdown.grandTotal.value,
                currency: instructions.currency ?? breakdown.currency
            ),
            false
        ))
        if let reference = instructions.reference {
            rows.append(("Reference / memo", reference, true))
        }

        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                CopyRow(
                    label: rows[index].label,
                    value: rows[index].value,
                    emphasized: rows[index].emphasized
                ) {
                    UIPasteboard.general.string = rows[index].value
                    Haptics.shared.play(.selection)
                    toasts.show(title: "Copied", message: "\(rows[index].label) is on your clipboard.")
                    // A real copy advances the hands-on step.
                    tutorial.fire("copy")
                }
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color.calibre.border)
                        .frame(height: 1)
                }
            }
        }
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}

/// A SpecList-styled row with a trailing copy affordance.
private struct CopyRow: View {
    let label: String
    let value: String
    let emphasized: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            Text(label)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
            Spacer(minLength: Space.l)
            Text(value)
                .font(emphasized ? CalibreType.bodySemiBold : CalibreType.bodyMedium)
                .foregroundStyle(emphasized ? Color.calibre.primary : Color.calibre.foreground)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .frame(width: 32, height: 32)
                    .background(Color.calibre.secondary, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Copy \(label)")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(minHeight: Space.touchTarget)
    }
}
