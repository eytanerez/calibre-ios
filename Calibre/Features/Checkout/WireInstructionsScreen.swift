import CalibreDesign
import CalibreKit
import SwiftUI

/// The wire path terminus — bank details with per-row copy, the reference
/// warning, the 24 h reservation countdown, and "I've sent the wire".
struct WireInstructionsScreen: View {
    @Bindable var model: CheckoutModel
    let onReserved: (Order) -> Void

    @Environment(ToastCenter.self) private var toasts
    @State private var confirmingSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let checkout = model.wireCheckout {
                    header(checkout)

                    if let instructions = checkout.wire.instructions {
                        detailRows(instructions, breakdown: checkout.breakdown)

                        CalloutBand(
                            icon: "number",
                            title: "The reference matters",
                            message: "Include the reference or your transfer can't be matched to this order."
                        )
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
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Wire transfer")
        .navigationBarTitleDisplayMode(.inline)
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
        .confirmationDialog(
            "Confirm your wire transfer",
            isPresented: $confirmingSent,
            titleVisibility: .visible
        ) {
            Button("Yes, I've sent it") {
                Task {
                    if let order = await model.confirmWireSent() {
                        Haptics.shared.play(.success)
                        onReserved(order)
                    }
                }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Once you continue, this order is marked as sent and we'll wait for the transfer to arrive. Only confirm once you've actually completed the wire with your bank.")
        }
    }

    // MARK: - Pieces

    private func header(_ checkout: WireCheckout) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow("Send exactly")
            Text(PriceFormatter.format(checkout.breakdown.grandTotal.value, currency: checkout.breakdown.currency))
                .font(CalibreType.priceLarge)
                .foregroundStyle(Color.calibre.foreground)

            HStack(spacing: Space.m) {
                CountdownChip(until: reservationDeadline(checkout))
                Text("Your watch is held for 24 hours.")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .padding(.top, 2)
        }
    }

    private func reservationDeadline(_ checkout: WireCheckout) -> Date {
        checkout.session?.expiresAtDate ?? Date.now.addingTimeInterval(24 * 3600)
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
