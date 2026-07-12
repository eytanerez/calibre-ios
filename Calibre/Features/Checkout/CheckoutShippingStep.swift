import CalibreDesign
import CalibreKit
import SwiftUI

/// Step 1 — where the watch ships. Saved addresses as radio cards with the
/// default preselected; "Use a different address" expands the inline form.
/// No saved addresses puts the form front and center.
struct CheckoutShippingStep: View {
    @Bindable var model: CheckoutModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                EyebrowProgress(steps: ["Shipping", "Payment", "Review"], currentIndex: 0)

                Text("Where should it ship?")
                    .font(CalibreType.title)
                    .foregroundStyle(Color.calibre.foreground)

                switch model.phase {
                case .loading:
                    loadingSkeleton
                case .failed(let message):
                    VStack(spacing: Space.l) {
                        EmptyState(
                            icon: "wifi.exclamationmark",
                            title: "We couldn't load checkout",
                            message: message,
                            actionTitle: "Try again",
                            action: { Task { await model.load() } }
                        )
                    }
                case .ready:
                    content
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CheckoutCloseButton() }
        }
        .safeAreaInset(edge: .bottom) {
            if case .ready = model.phase {
                Button {
                    Haptics.shared.play(.press)
                    model.continueFromShipping()
                } label: {
                    Text("Continue to payment")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.selectedAddressID == nil)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.m)
                .background(Color.calibre.background.opacity(0.97))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(model.addresses) { address in
                AddressRadioCard(
                    address: address,
                    isSelected: model.selectedAddressID == address.id
                ) {
                    Haptics.shared.play(.selection)
                    model.selectedAddressID = address.id
                }
            }

            if !model.addresses.isEmpty {
                Button {
                    withAnimation(Motion.easeMedium) {
                        model.showAddressForm.toggle()
                    }
                } label: {
                    Label(
                        model.showAddressForm ? "Never mind — use a saved address" : "Use a different address",
                        systemImage: model.showAddressForm ? "chevron.up" : "plus"
                    )
                    .font(CalibreType.bodyMedium)
                }
                .buttonStyle(.calibreGhost)
            }

            if model.showAddressForm {
                AddressForm(model: model)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(Motion.easeMedium, value: model.showAddressForm)
    }

    private var loadingSkeleton: some View {
        VStack(spacing: Space.m) {
            ForEach(0..<2, id: \.self) { _ in
                Rectangle()
                    .frame(height: 88)
                    .shimmer()
            }
        }
    }
}

/// One saved address as a selectable radio card.
private struct AddressRadioCard: View {
    let address: Address
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: isSelected ? "inset.filled.circle" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Color.calibre.primary : Color.calibre.borderBright)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s) {
                        Text(displayName)
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                        if address.isDefaultShipping {
                            StatusBadge("Default", tone: .info)
                        }
                    }
                    Text(addressLines)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.calibre.primary.opacity(0.06) : Color.calibre.card,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.calibre.primary.opacity(0.5) : Color.calibre.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.easeFast, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var displayName: String {
        if let name = address.fullName, !name.isEmpty { return name }
        let joined = [address.firstName, address.lastName].compactMap(\.self).joined(separator: " ")
        return joined.isEmpty ? (address.label ?? "Shipping address") : joined
    }

    private var addressLines: String {
        var lines = [address.line1]
        if let line2 = address.line2, !line2.isEmpty { lines.append(line2) }
        let cityLine = [address.city, address.region, address.postalCode]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        lines.append(cityLine)
        lines.append(address.country)
        return lines.joined(separator: "\n")
    }
}

/// The inline new-address form. Saves via POST /account/addresses and
/// auto-selects the result.
private struct AddressForm: View {
    @Bindable var model: CheckoutModel

    @State private var fullName = ""
    @State private var street = ""
    @State private var apartment = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var country = "US"
    @State private var phone = ""
    @State private var attempted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            CalibreTextField(
                "Full name",
                text: $fullName,
                placeholder: "First and last name",
                error: fieldError(fullName, "Enter the recipient's name.")
            )
            .textContentType(.name)

            CalibreTextField(
                "Street address",
                text: $street,
                placeholder: "Street and number",
                error: fieldError(street, "Enter a street address.")
            )
            .textContentType(.streetAddressLine1)

            CalibreTextField("Apt, suite, unit (optional)", text: $apartment)
                .textContentType(.streetAddressLine2)

            CalibreTextField(
                "City",
                text: $city,
                error: fieldError(city, "Enter a city.")
            )
            .textContentType(.addressCity)

            HStack(alignment: .top, spacing: Space.m) {
                CalibreTextField(
                    "State",
                    text: $state,
                    placeholder: "e.g. NY",
                    error: fieldError(state, "Required.")
                )
                .textContentType(.addressState)

                CalibreTextField(
                    "ZIP",
                    text: $zip,
                    error: fieldError(zip, "Required.")
                )
                .textContentType(.postalCode)
                .keyboardType(.numbersAndPunctuation)
            }

            CalibreTextField(
                "Country",
                text: $country,
                error: fieldError(country, "Required.")
            )
            .textContentType(.countryName)

            CalibreTextField("Phone (optional)", text: $phone, placeholder: "For delivery questions")
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)

            if let error = model.addressFormError {
                InlineErrorLine(message: error)
            }

            Button {
                attempted = true
                guard isValid else { return }
                Haptics.shared.play(.press)
                Task { await save() }
            } label: {
                BusyLabel(title: "Save and use this address", busy: model.savingAddress)
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
            .disabled(model.savingAddress)
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .animation(Motion.easeFast, value: model.addressFormError)
    }

    private var isValid: Bool {
        ![fullName, street, city, state, zip, country].contains { trimmed($0).isEmpty }
    }

    private func fieldError(_ value: String, _ message: String) -> String? {
        attempted && trimmed(value).isEmpty ? message : nil
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        let payload = AddressPayload(
            fullName: trimmed(fullName),
            phone: trimmed(phone).isEmpty ? nil : trimmed(phone),
            line1: trimmed(street),
            line2: trimmed(apartment).isEmpty ? nil : trimmed(apartment),
            city: trimmed(city),
            region: trimmed(state),
            postalCode: trimmed(zip),
            country: trimmed(country).uppercased(),
            isDefaultShipping: model.addresses.isEmpty ? true : nil
        )
        await model.createAddress(payload)
    }
}
