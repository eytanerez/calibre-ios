import RewoundDesign
import RewoundKit
import SwiftUI

/// Where a request form was opened from, sent as `entry_point` on
/// `watch_request_submitted`. The Requests screen is the member's own list;
/// Home and the results grid are where someone finds out the watch is not
/// here, which is the moment a request is actually worth making.
enum WatchRequestEntryPoint: String, Sendable {
    case requests
    case home
    /// The capsule on the results grid.
    case browse
    /// The capsule on a brand page.
    case brand
    /// The band under "No watches match", on either.
    case noResults = "no_results"
}

/// What the form can start with: the brand a screen is already about, and the
/// model or reference somebody filtered or searched for. Every field stays
/// editable; this only saves retyping what the screen behind the sheet knew.
struct WatchRequestPrefill: Equatable, Sendable {
    var brand: String?
    var model: String?
    var reference: String?

    init(brand: String? = nil, model: String? = nil, reference: String? = nil) {
        self.brand = Self.cleaned(brand)
        self.model = Self.cleaned(model)
        self.reference = Self.cleaned(reference)
    }

    static let empty = WatchRequestPrefill()

    var isEmpty: Bool { brand == nil && model == nil && reference == nil }

    /// The results grid's state, read as a request.
    ///
    /// A brand comes from the screen (a brand page) or the filter. A search is
    /// the reader's own words for the watch, so it is split rather than
    /// dropped: a known brand at the front of it becomes the brand, and what
    /// follows is the model, or the reference when it is one token with a
    /// digit in it ("116610LN", "5711"), which is how references are typed.
    /// `knownBrands` is the catalog's own brand list; without it a search is
    /// kept whole as the model, and the brand is left for the reader.
    static func browsing(
        filters: BrowseFilters,
        lockedBrand: String?,
        knownBrands: [String]
    ) -> WatchRequestPrefill {
        var brand = cleaned(lockedBrand) ?? cleaned(filters.brand)
        var model = cleaned(filters.model)
        var reference = cleaned(filters.reference)

        if let search = cleaned(filters.search) {
            var remainder = search
            if let named = brand {
                if let rest = stripping(prefix: named, from: search) { remainder = rest }
            } else if let match = leadingBrand(in: search, knownBrands: knownBrands) {
                brand = match.brand
                remainder = match.rest
            }
            if let words = cleaned(remainder) {
                if reference == nil, looksLikeReference(words) {
                    reference = words.uppercased()
                } else if model == nil {
                    model = words
                }
            }
        }

        return WatchRequestPrefill(brand: brand, model: model, reference: reference)
    }

    // MARK: - Parsing

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// The longest catalog brand the search starts with, whole words only, so
    /// "Omega" does not claim "Omegamatic" and "Grand Seiko" beats "Seiko".
    private static func leadingBrand(
        in search: String,
        knownBrands: [String]
    ) -> (brand: String, rest: String)? {
        let candidates = knownBrands
            .compactMap { cleaned($0) }
            .sorted { $0.count > $1.count }
        for candidate in candidates {
            if let rest = stripping(prefix: candidate, from: search) {
                return (candidate, rest)
            }
        }
        return nil
    }

    /// `text` without `prefix` when it starts with it as whole words, ignoring
    /// case and accents; nil when it does not.
    private static func stripping(prefix: String, from text: String) -> String? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
        guard let range = text.range(of: prefix, options: options) else { return nil }
        let rest = text[range.upperBound...]
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func looksLikeReference(_ words: String) -> Bool {
        guard !words.contains(" "), words.count >= 3 else { return false }
        guard words.contains(where: \.isNumber) else { return false }
        // A size is not a reference: "40mm" is somebody narrowing a search.
        return !words.lowercased().hasSuffix("mm")
    }
}

/// The request form: brand (required), model, reference, year, budget, notes.
/// Shared by the Requests screen, Home's request band and the results grid's
/// "Can't find it?" capsule, so a request reads the same wherever it starts.
struct NewRequestSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    let entryPoint: WatchRequestEntryPoint
    let onCreate: ((WatchRequest) -> Void)?

    @State private var brand: String
    @State private var model: String
    @State private var reference: String
    @State private var year = ""
    @State private var budget = ""
    @State private var notes = ""
    @State private var saving = false

    init(
        prefill: WatchRequestPrefill = .empty,
        entryPoint: WatchRequestEntryPoint,
        onCreate: ((WatchRequest) -> Void)? = nil
    ) {
        self.entryPoint = entryPoint
        self.onCreate = onCreate
        _brand = State(initialValue: prefill.brand ?? "")
        _model = State(initialValue: prefill.model ?? "")
        _reference = State(initialValue: prefill.reference ?? "")
    }

    var body: some View {
        SheetScaffold(title: "Request a watch", detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Tell us what you're hunting. Sellers see open requests and list against them.")
                        .font(RewoundType.body).foregroundStyle(Color.rewound.mutedForeground)
                    RewoundTextField("Brand (required)", text: $brand, kind: .sentence)
                    RewoundTextField("Model", text: $model, kind: .sentence)
                    RewoundTextField("Reference", text: $reference, kind: .reference)
                    RewoundTextField(
                        "Year",
                        text: $year,
                        error: yearError,
                        kind: .integer
                    )
                    RewoundTextField(
                        "Max budget (USD)",
                        text: $budget,
                        error: budgetError,
                        kind: .money
                    )
                    .moneyFormatted($budget)
                    RewoundTextField("Notes", text: $notes, kind: .sentence)
                        .onChange(of: notes) { _, value in
                            if value.count > 2_000 { notes = String(value.prefix(2_000)) }
                        }
                    Button(saving ? "Posting…" : "Post request") {
                        Task { await submit() }
                    }
                    .buttonStyle(.rewound(.primary, fullWidth: true))
                    .disabled(!canSubmit)
                }
                .padding(Space.margin)
            }
        }
    }

    private var yearError: String? {
        InputValidation.isNonBlank(year) && InputValidation.productionYear(year) == nil
            ? "Enter a 4-digit year, or leave it blank."
            : nil
    }

    private var budgetError: String? {
        InputValidation.isNonBlank(budget) && InputValidation.positiveMoney(budget) == nil
            ? "Enter an amount greater than zero, or leave it blank."
            : nil
    }

    private var canSubmit: Bool {
        InputValidation.isNonBlank(brand)
            && yearError == nil
            && budgetError == nil
            && !saving
    }

    /// Posted from the Requests screen, the new row appears in the list under
    /// the sheet. From anywhere else there is no list in sight, so the toast
    /// says where the request lives.
    private var postedMessage: String {
        entryPoint == .requests
            ? "We'll let you know when a match goes live."
            : "We'll let you know when a match goes live. You'll find it under Me, in Requests."
    }

    private func submit() async {
        guard canSubmit else { return }
        saving = true
        defer { saving = false }
        do {
            let created = try await services.seller.createWatchRequest(
                brand: InputValidation.trimmed(brand),
                model: InputValidation.isNonBlank(model) ? InputValidation.trimmed(model) : nil,
                reference: InputValidation.isNonBlank(reference) ? InputValidation.trimmed(reference) : nil,
                productionYear: InputValidation.productionYear(year),
                maxBudget: InputValidation.positiveMoney(budget),
                notes: InputValidation.isNonBlank(notes) ? InputValidation.trimmed(notes) : nil
            )
            onCreate?(created)
            // `watch_reference_id` has no client-side equivalent — the request
            // carries a free-text reference, never a catalog match — so it
            // is omitted rather than invented.
            Analytics.watchRequestSubmitted(
                brand: created.brand,
                reference: created.reference,
                watchReferenceID: nil,
                hasBudget: created.maxBudget != nil,
                entryPoint: entryPoint.rawValue
            )
            Haptics.shared.play(.success)
            toasts.show(title: "Request posted", message: postedMessage, tone: .success)
            dismiss()
        } catch {
            toasts.show(title: "Couldn't post request", message: error.orderMessage, tone: .error)
        }
    }
}
