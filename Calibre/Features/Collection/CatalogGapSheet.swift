import CalibreDesign
import CalibreKit
import SwiftUI

/// "We don't have this watch yet — tell us what it is."
///
/// What this sends is not a catalog row. It is the owner's account of their
/// own watch, which goes to somebody with Market access to accept or reject:
/// the best-informed person alive about a watch is also the least accountable
/// for what they type, and the catalog is read by pricing, by search and by
/// every listing that autofills from it.
///
/// The refusals are the server's sentences, shown as sent. There is no second
/// copy of "a case diameter is between 10 and 100 millimetres" here — a rule
/// written twice drifts, and the reviewer's copy is the one that decides.
struct CatalogGapSheet: View {
    let watch: VaultWatch
    /// Called after a suggestion is accepted for review, so the page behind
    /// can pick up its `pending_suggestion`.
    let onSubmit: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    /// The identity fields start from the watch, because the owner already
    /// told us this much when they added it.
    @State private var brand: String
    @State private var model: String
    @State private var reference: String
    @State private var year: String
    @State private var notes = ""
    @State private var specs = WatchReferenceSpecsDraft()
    @State private var saving = false

    /// The longest a spec value can be. Trimming as it is typed keeps the
    /// owner from writing a paragraph the server would only refuse.
    private let specLimit = 120

    init(watch: VaultWatch, onSubmit: @escaping () -> Void) {
        self.watch = watch
        self.onSubmit = onSubmit
        _brand = State(initialValue: watch.brand ?? "")
        _model = State(initialValue: watch.model ?? "")
        _reference = State(initialValue: watch.reference ?? "")
        _year = State(initialValue: watch.productionYear.map(String.init) ?? "")
    }

    var body: some View {
        SheetScaffold(title: "Tell us about this watch", detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Fill in what you know \u{2014} blanks are fine. Someone on our team checks it before it joins the catalog.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)

                    CalibreTextField("Brand (required)", text: $brand, kind: .sentence)
                    CalibreTextField("Model", text: $model, kind: .sentence)
                    CalibreTextField("Reference (required)", text: $reference, kind: .reference)
                    CalibreTextField("Year", text: $year, error: yearError, kind: .integer)

                    Text("The spec sheet")
                        .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
                        .foregroundStyle(Color.calibre.foreground)
                        .padding(.top, Space.s)

                    specField("Material", $specs.material, placeholder: "Stainless steel")
                    specField("Bezel", $specs.bezel, placeholder: "Fixed, tachymeter")
                    specField("Glass", $specs.glass, placeholder: "Sapphire")
                    specField("Back", $specs.back, placeholder: "Solid screw-down")
                    specField("Shape", $specs.shape, placeholder: "Round")
                    CalibreTextField(
                        "Diameter (mm)",
                        text: $specs.diameterMm,
                        placeholder: "41",
                        error: diameterError,
                        kind: .integer
                    )
                    specField("Finish", $specs.finish, placeholder: "Brushed with polished sides")
                    specField("Dial", $specs.dial, placeholder: "Black")
                    specField("Indexes", $specs.indexes, placeholder: "Applied baton")
                    specField("Hands", $specs.hands, placeholder: "Mercedes")

                    CalibreTextField("Anything else", text: $notes, kind: .sentence)
                        .onChange(of: notes) { _, value in
                            if value.count > 2_000 { notes = String(value.prefix(2_000)) }
                        }

                    Button(saving ? "Sending\u{2026}" : "Send to Calibre") {
                        Task { await submit() }
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(!canSubmit)
                }
                .padding(Space.margin)
                .padding(.bottom, Space.xxl)
            }
        }
    }

    private func specField(_ label: String, _ text: Binding<String>, placeholder: String) -> some View {
        CalibreTextField(label, text: text, placeholder: placeholder, kind: .sentence)
            .onChange(of: text.wrappedValue) { _, value in
                if value.count > specLimit { text.wrappedValue = String(value.prefix(specLimit)) }
            }
    }

    private var yearError: String? {
        InputValidation.isNonBlank(year) && InputValidation.productionYear(year) == nil
            ? "Enter a 4-digit year, or leave it blank."
            : nil
    }

    /// Format only. Whether 8mm is a watch is the server's call, and it has a
    /// sentence for it.
    private var diameterError: String? {
        InputValidation.isNonBlank(specs.diameterMm) && Int(InputValidation.trimmed(specs.diameterMm)) == nil
            ? "Enter a whole number of millimetres, or leave it blank."
            : nil
    }

    private var canSubmit: Bool {
        InputValidation.isNonBlank(brand)
            && InputValidation.isNonBlank(reference)
            && yearError == nil
            && diameterError == nil
            && !saving
    }

    private func submit() async {
        guard canSubmit else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await services.vault.submitReferenceSuggestion(
                id: watch.id,
                brand: brand,
                model: model,
                reference: reference,
                productionYear: InputValidation.productionYear(year),
                notes: notes,
                specs: specs
            )
            onSubmit()
            Haptics.shared.play(.success)
            toasts.show(
                title: "Sent to Calibre",
                message: "We'll take a look and add it to the catalog.",
                tone: .success
            )
            dismiss()
        } catch {
            toasts.show(title: "Couldn't send that", message: error.orderMessage, tone: .error)
        }
    }
}
