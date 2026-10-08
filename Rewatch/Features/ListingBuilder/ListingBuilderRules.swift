import Foundation
import RewatchKit

/// The listing builder's answers and the rules over them, with no SwiftUI in
/// sight: what each step needs before Continue opens, what the answers send,
/// which step a server refusal belongs to, and where Next goes in the watch
/// fields. The site keeps the same rules in `listingBuilderModel.ts`; the
/// names here follow it so the two can be read side by side.
///
/// What the answers SEND is not decided here either. `sellValues` maps them
/// onto the site's `SellListingValues` and `SellListingBody` (RewatchKit, the
/// site's `sellListingPayload`) turns those into the body.

// MARK: - Steps

enum BuilderStep: String, CaseIterable, Identifiable, Codable {
    case watch, year, condition, box, history, photos, price, returns, review

    var id: String { rawValue }

    /// The eight questions before the review.
    static let questionCount = 8

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var label: String {
        switch self {
        case .watch: "Watch"
        case .year: "Year"
        case .condition: "Condition"
        case .box: "In the box"
        case .history: "History"
        case .photos: "Photos"
        case .price: "Price"
        case .returns: "Returns"
        case .review: "Review"
        }
    }

    var next: BuilderStep {
        Self.allCases[min(index + 1, Self.allCases.count - 1)]
    }

    var previous: BuilderStep {
        Self.allCases[max(index - 1, 0)]
    }

    /// The heading and the line under it, in the site's words.
    var question: (title: String, help: String) {
        switch self {
        case .watch: ("Which watch are you selling?", "Brand, then model, then reference. The model's specs come with it.")
        case .year: ("What year was it made?", SellFieldHelp.year)
        case .condition: ("How does it look today?", "Pick the grade for the watch as a whole. WPB Watch Co checks it when the watch arrives.")
        case .box: ("What comes with it?", "Tap everything that goes in the box with the watch.")
        case .history: ("A little history.", "Three quick ones. \u{201C}I don't know\u{201D} is a fine answer.")
        case .photos: ("Add the photos.", SellFieldHelp.photos)
        case .price: ("What's your price?", "What you keep updates as you type.")
        case .returns: ("Do you take returns?", "Taking returns can help a watch sell. You're paid when the window closes.")
        case .review: ("Here's your listing.", "Exactly what buyers will see. Tap any part to change it.")
        }
    }
}

/// `live` writes the listing. `demo` (the DEBUG preview harness) runs the same
/// screens and writes nothing.
enum BuilderMode: Equatable {
    case live
    case demo
}

// MARK: - Returns

enum ReturnsChoice: String, CaseIterable, Codable, Identifiable {
    case none
    case hours24 = "24"
    case hours48 = "48"
    case hours72 = "72"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No returns"
        case .hours24: "24 hours"
        case .hours48: "48 hours"
        case .hours72: "72 hours"
        }
    }

    var detail: String {
        switch self {
        case .none: "You're paid once the watch passes authentication."
        case .hours24: "Paid when the 24-hour window closes."
        case .hours48: "Paid when the 48-hour window closes."
        case .hours72: "Paid when the 72-hour window closes."
        }
    }

    var hours: Int? { Int(rawValue) }
}

// MARK: - Answers

/// What the seller has said so far. Photos are not here: they are files and
/// upload jobs, held by the model (`BuilderPhotoSlot`).
struct BuilderAnswers: Equatable, Codable {
    var brand = ""
    var model = ""
    var reference = ""
    /// Four digits, "unknown", or blank.
    var year = ""
    var sku = ""
    var grade: String?
    var partsMatch: Bool?
    /// Part (`ConditionPart.rawValue`, never "overall") to grade, once the
    /// seller said some parts differ.
    var parts: [String: String] = [:]
    /// The few words beside each grade, keyed like the server's map, overall
    /// included. Optional.
    var conditionNotes: [String: String] = [:]
    var box = false
    var papers = false
    var booklets = false
    /// "Anything else buyers should know?": the listing's description.
    var notes = ""
    var polish: String?
    var originality: String?
    var serviceHistory: String?
    var replaced = ""
    var serviceYear = ""
    /// The price as typed ("3,450.50").
    var priceText = ""
    var returns: ReturnsChoice?
    /// Non-US dealers only.
    var customsCountry = ""
    var customsHTS = ""
    /// The seller's yes to "is this the watch from your Vault?".
    var vaultWatchID: String?
    /// What to call that watch on the confirmation line.
    var vaultWatchTitle: String?
    /// They said no, for this listing.
    var vaultDeclined = false

    var price: Decimal? { BuilderRules.parsePrice(priceText) }

    func historyAnswer(_ question: HistoryQuestion) -> String? {
        switch question {
        case .polish: polish
        case .originality: originality
        case .service: serviceHistory
        }
    }

    mutating func setHistory(_ value: String, for question: HistoryQuestion) {
        switch question {
        case .polish: polish = value
        case .originality: originality = value
        case .service: serviceHistory = value
        }
    }
}

/// The three watch fields, for keyboard order.
enum IdentityField: String, CaseIterable, Hashable {
    case brand, model, reference
}

/// Every focusable field, for Next and Done.
enum BuilderField: Hashable {
    case brand, model, reference
    case year, sku
    case note(String)
    case sellerNotes
    case replaced, serviceYear
    case price, customsCountry, customsHTS
}

// MARK: - Rules

enum BuilderRules {
    static let earliestManufactureYear = 1900
    static let earliestServiceYear = 1900
    /// The builder's price floor (the site's `MIN_PRICE`).
    static let minPrice: Decimal = 100
    /// The server's ceiling on `price` (max_digits 12, two decimals).
    static let maxPrice = Decimal(string: "9999999999.99")!
    static let sellerNotesMax = 2000
    static let skuMax = 64
    static let conditionNoteMax = ConditionNote.limit
    static let replacedNoteMax = WizardHistory.noteLimit

    /// The seven parts graded beside the overall grade, in the site's order.
    static let parts: [ConditionPart] = [.watchCase, .dial, .bezel, .crystal, .bracelet, .clasp, .caseback]

    /// The six angles as the builder lays them out: front, the two sides,
    /// caseback, clasp, everything included.
    static let photoLayout: [ListingImageCategory] = [.front, .leftProfile, .rightProfile, .caseback, .clasp, .fullSet]

    /// The order a buyer's gallery shows them in (`sort_index`): front,
    /// caseback, the two profiles, clasp, everything included, then extras.
    static let uploadOrder: [ListingImageCategory] = [.front, .caseback, .leftProfile, .rightProfile, .clasp, .fullSet]

    static func sortIndex(for category: ListingImageCategory) -> Int {
        uploadOrder.firstIndex(of: category) ?? 0
    }

    /// The first extra photo's sort index: after the six angles.
    static let firstExtraSortIndex = 6

    /// The server's matching key (`normalize_key`).
    static func catalogKey(_ value: String?) -> String {
        CatalogReference.key(value)
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A typed price as a number: commas dropped, at most two decimals. Nil
    /// when blank or not a price.
    static func parsePrice(_ text: String) -> Decimal? {
        let normalized = trimmed(text).replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty,
              normalized.range(of: #"^\d+(\.\d{0,2})?$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// "3450.5" grouped as it is typed: "3,450.5". Digits and one point only,
    /// two decimals at most (the site's `formatMoneyInput`).
    static func formatMoneyInput(_ raw: String) -> String {
        var digits = ""
        var fraction: String?
        for character in raw {
            if character.isASCII, character.isNumber {
                if fraction != nil {
                    if fraction!.count < 2 { fraction!.append(character) }
                } else {
                    digits.append(character)
                }
            } else if character == ".", fraction == nil {
                fraction = ""
            }
        }
        if digits.isEmpty, fraction != nil { digits = "0" }
        var grouped = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let whole = String(grouped.reversed())
        guard let fraction else { return whole }
        return "\(whole).\(fraction)"
    }

    static func isFourDigits(_ value: String) -> Bool {
        value.count == 4 && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Why the year would be refused, or nil. The window is the server's.
    static func yearProblem(_ year: String, currentYear: Int) -> String? {
        guard year != "unknown", isFourDigits(year), let value = Int(year) else { return nil }
        if value < earliestManufactureYear || value > currentYear + 1 {
            return "Enter a year between \(earliestManufactureYear) and \(currentYear + 1), or pick Unknown."
        }
        return nil
    }

    static func yearIsValid(_ year: String, currentYear: Int) -> Bool {
        year == "unknown" || (isFourDigits(year) && yearProblem(year, currentYear: currentYear) == nil)
    }

    /// Blank is fine: "Serviced" with no year is an allowed answer.
    static func serviceYearProblem(_ value: String, currentYear: Int) -> String? {
        let text = trimmed(value)
        guard !text.isEmpty else { return nil }
        guard isFourDigits(text), let year = Int(text), (earliestServiceYear...currentYear).contains(year) else {
            return "Enter a year between \(earliestServiceYear) and \(currentYear), or leave it blank."
        }
        return nil
    }

    static func priceProblem(_ priceText: String) -> String? {
        guard !trimmed(priceText).isEmpty else { return nil }
        guard let price = parsePrice(priceText) else {
            return "Enter a price in dollars, with up to two decimals."
        }
        if price < minPrice { return "Listings start at $\(minPrice)." }
        if price > maxPrice { return "That price is too large." }
        return nil
    }

    static func customsProblem(country: String, hts: String) -> String? {
        let code = trimmed(country)
        if !code.isEmpty, !(code.count == 2 && code.allSatisfy { $0.isASCII && $0.isLetter }) {
            return "Use a two-letter country code."
        }
        if trimmed(hts).count > 32 { return "HTS code must be 32 characters or less." }
        return nil
    }

    struct Options: Equatable {
        var mode: BuilderMode = .live
        /// A non-US dealer: the price step also asks for customs details.
        var needsCustomsFields = false
        var currentYear = Calendar.current.component(.year, from: .now)
    }

    /// The photos a listing needs before Continue: all six live (the server's
    /// rule), the front alone in the demo.
    static func requiredPhotos(_ mode: BuilderMode) -> [ListingImageCategory] {
        mode == .live ? photoLayout : [.front]
    }

    static func missingPhotos(filled: Set<ListingImageCategory>, mode: BuilderMode) -> [ListingImageCategory] {
        requiredPhotos(mode).filter { !filled.contains($0) }
    }

    /// Whether a step's answers are enough for Continue to move on.
    static func canContinue(
        _ step: BuilderStep,
        _ answers: BuilderAnswers,
        photosFilled: Set<ListingImageCategory>,
        options: Options
    ) -> Bool {
        switch step {
        case .watch:
            // All three. A watch the catalog does not know yet still goes
            // through: review is what adds it.
            return !trimmed(answers.brand).isEmpty && !trimmed(answers.model).isEmpty && !trimmed(answers.reference).isEmpty
        case .year:
            return yearIsValid(answers.year, currentYear: options.currentYear) && trimmed(answers.sku).count <= skuMax
        case .condition:
            return answers.grade != nil
                && answers.partsMatch != nil
                && answers.conditionNotes.values.allSatisfy { !ConditionNote.isTooLong($0) }
        case .box:
            return trimmed(answers.notes).count <= sellerNotesMax
        case .history:
            return HistoryQuestion.allCases.allSatisfy { answers.historyAnswer($0) != nil }
                && serviceYearProblem(answers.serviceHistory == "serviced" ? answers.serviceYear : "", currentYear: options.currentYear) == nil
                && ConditionNote.normalized(answers.replaced).unicodeScalars.count <= replacedNoteMax
        case .photos:
            return missingPhotos(filled: photosFilled, mode: options.mode).isEmpty
        case .price:
            return answers.price != nil
                && priceProblem(answers.priceText) == nil
                && (!options.needsCustomsFields || customsProblem(country: answers.customsCountry, hts: answers.customsHTS) == nil)
        case .returns:
            return answers.returns != nil
        case .review:
            return true
        }
    }

    /// The first step whose answers are not enough yet, or `.review`.
    static func firstOpenStep(
        _ answers: BuilderAnswers,
        photosFilled: Set<ListingImageCategory>,
        options: Options
    ) -> BuilderStep {
        BuilderStep.allCases.first {
            $0 != .review && !canContinue($0, answers, photosFilled: photosFilled, options: options)
        } ?? .review
    }

    /// Next in one of the three watch fields: the next required field still
    /// empty (after this one, else the first), or nil when all three are
    /// filled and Next belongs to Continue.
    static func nextEmptyIdentityField(after field: IdentityField, in answers: BuilderAnswers) -> IdentityField? {
        func value(_ field: IdentityField) -> String {
            switch field {
            case .brand: answers.brand
            case .model: answers.model
            case .reference: answers.reference
            }
        }
        let order = IdentityField.allCases
        if trimmed(value(field)).isEmpty { return field }
        let here = order.firstIndex(of: field) ?? 0
        let rest = Array(order[(here + 1)...]) + Array(order[..<here])
        return rest.first { trimmed(value($0)).isEmpty }
    }

    // MARK: What it sends

    /// Every part's grade as the seller gave it: the overall grade when they
    /// said all parts match.
    static func partGrades(_ answers: BuilderAnswers) -> [ConditionPart: String] {
        var grades: [ConditionPart: String] = [:]
        for part in parts {
            grades[part] = (answers.partsMatch == false ? answers.parts[part.rawValue] : nil) ?? answers.grade ?? ""
        }
        return grades
    }

    /// The notes that are on screen. A part's note belongs to the part grid,
    /// so once the seller says every part matches only the overall note is
    /// theirs.
    static func visibleConditionNotes(_ answers: BuilderAnswers) -> [String: String] {
        if answers.partsMatch == false { return answers.conditionNotes }
        if let overall = answers.conditionNotes["overall"], !overall.isEmpty { return ["overall": overall] }
        return [:]
    }

    static func returnsTerms(_ returns: ReturnsChoice?) -> (accepted: Bool, windowHours: Int) {
        guard let returns, let hours = returns.hours else {
            // The long form's defaults when returns are off.
            return (false, 48)
        }
        return (true, hours)
    }

    /// The answers, under the site's `SellListingValues` names
    /// (`builderSellValues`).
    static func sellValues(_ answers: BuilderAnswers) -> SellListingBody.Values {
        let grades = partGrades(answers)
        return SellListingBody.Values(
            brand: answers.brand,
            model: answers.model,
            referenceNumber: answers.reference,
            sellerSku: answers.sku,
            conditionCase: grades[.watchCase] ?? "",
            conditionDial: grades[.dial] ?? "",
            conditionBezel: grades[.bezel] ?? "",
            conditionCrystal: grades[.crystal] ?? "",
            conditionBracelet: grades[.bracelet] ?? "",
            conditionClasp: grades[.clasp] ?? "",
            conditionCaseback: grades[.caseback] ?? "",
            condition: answers.grade ?? "",
            conditionNotes: visibleConditionNotes(answers),
            polish: answers.polish ?? "",
            originality: answers.originality ?? "",
            replacedPartsNote: answers.replaced,
            serviceHistory: answers.serviceHistory ?? "",
            lastServiceYear: answers.serviceHistory == "serviced" ? answers.serviceYear : "",
            manufactureYear: answers.year,
            price: answers.price ?? 0,
            notes: answers.notes,
            countryOfOrigin: answers.customsCountry,
            htsCode: answers.customsHTS
        )
    }

    /// The create/PATCH body (`builderListingPayload`).
    static func body(_ answers: BuilderAnswers, needsCustomsFields: Bool) -> SellListingBody {
        let terms = returnsTerms(answers.returns)
        return SellListingBody(
            values: sellValues(answers),
            context: SellListingBody.Context(
                box: answers.box,
                papers: answers.papers,
                booklets: answers.booklets,
                returnsAccepted: terms.accepted,
                returnWindowHours: terms.windowHours,
                vaultWatchID: answers.vaultWatchID,
                needsCustomsFields: needsCustomsFields
            )
        )
    }

    // MARK: Where a refusal belongs

    private static let detailFieldSteps: [(pattern: String, step: BuilderStep)] = [
        (#"^(brand|model|reference|title|vault_watch_id)$"#, .watch),
        (#"^(production_year|seller_sku)$"#, .year),
        (#"^condition_"#, .condition),
        (#"^(box_papers|box_included|papers_included|booklets_included|description)$"#, .box),
        (#"^(polish|originality|replaced_parts_note|service_history|last_service_year)$"#, .history),
        (#"^(price|currency|country_of_origin|hts_code)$"#, .price),
        (#"^(returns_accepted|return_window_hours)$"#, .returns),
    ]

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The step a server refusal is about, so the seller lands where they can
    /// fix it (the site's `serverErrorStep`). Anything it cannot place (a
    /// seller-setup refusal, a network failure) stays on the review.
    static func serverErrorStep(_ error: Error) -> BuilderStep {
        guard case let .server(message, serverCode, _, details) = error as? APIError else { return .review }
        let code = serverCode ?? details?["code"]
        if matches(message, #"condition grades? missing"#) { return .condition }
        if matches(message, "photo") { return .photos }
        if code == "duplicate_sku" || matches(message, #"\bsku\b"#) { return .year }
        if code == "vault_watch_already_listed" || matches(message, "vault") { return .watch }
        for key in (details ?? [:]).keys.sorted() {
            if let hit = detailFieldSteps.first(where: { matches(key, $0.pattern) }) {
                return hit.step
            }
        }
        if matches(message, "production year|year of manufacture") { return .year }
        if matches(message, "country of origin|hts code") { return .price }
        if matches(message, "return window|returns") { return .returns }
        if matches(message, #"\bprice\b"#) { return .price }
        return .review
    }

    // MARK: Words the screens share

    /// Brand, model and reference as the listing shows them: the catalog's
    /// spelling once it matched.
    static func identity(_ answers: BuilderAnswers, watch: CatalogReference?) -> (brand: String, model: String, reference: String) {
        (
            trimmed(watch?.brand ?? answers.brand),
            trimmed(watch?.model ?? answers.model),
            trimmed(watch?.reference ?? answers.reference)
        )
    }

    static func boxSummary(_ answers: BuilderAnswers) -> String {
        let items = [answers.box ? "Box" : nil, answers.papers ? "Papers" : nil, answers.booklets ? "Booklets" : nil]
            .compactMap { $0 }
        if items.isEmpty { return "The watch only" }
        if items.count == 3 { return "Full set: box, papers and booklets" }
        return items.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }.joined(separator: " and ")
    }

    static func historyLabel(_ question: HistoryQuestion, _ value: String?) -> String? {
        guard let value else { return nil }
        return question.options.first { $0.value == value }?.label
    }

    static func historySummary(_ answers: BuilderAnswers) -> String {
        let replaced = ConditionNote.normalized(answers.replaced)
        return [
            historyLabel(.polish, answers.polish),
            answers.originality == "replaced" && !replaced.isEmpty
                ? "Some parts replaced: \(replaced)"
                : historyLabel(.originality, answers.originality),
            answers.serviceHistory == "serviced" && !answers.serviceYear.isEmpty
                ? "Serviced \(answers.serviceYear)"
                : historyLabel(.service, answers.serviceHistory),
        ]
        .compactMap { $0 }
        .joined(separator: " \u{00B7} ")
    }

    /// "Case: Good", or "3 parts below Very Good", or nil.
    static func partsBelow(_ answers: BuilderAnswers) -> String? {
        guard let grade = answers.grade, answers.partsMatch == false else { return nil }
        let order = ConditionPart.grades
        guard let overall = order.firstIndex(of: grade) else { return nil }
        let below = parts.filter { part in
            guard let partGrade = answers.parts[part.rawValue], let at = order.firstIndex(of: partGrade) else { return false }
            return at > overall
        }
        if below.isEmpty { return nil }
        if below.count == 1, let only = below.first {
            return "\(only.label): \(answers.parts[only.rawValue] ?? "")"
        }
        return "\(below.count) parts below \(grade)"
    }

    /// The encouraging line over each question, chosen at random from what
    /// fits the seller's answers (the site's `encouragement`).
    static func encouragement(_ step: BuilderStep, _ answers: BuilderAnswers, watch: CatalogReference?) -> String {
        let remaining = BuilderStep.questionCount - step.index
        let names = identity(answers, watch: watch)
        let model = names.model.isEmpty ? (names.brand.isEmpty ? "watch" : names.brand) : names.model
        let count = remaining <= 1 ? "Last one." : remaining == 2 ? "Two to go." : "\(remaining) to go."
        let lines: [String]
        switch step {
        case .watch:
            lines = ["Start with the watch. We fill in the rest of the model's details."]
        case .year:
            lines = watch != nil
                ? ["The \(model). Its specs are already in.", "Specs filled in from the catalog. That part's done.", "Good start. \(count)"]
                : ["The \(model). Good start.", "Good start. \(count)"]
        case .condition:
            lines = [
                answers.year.isEmpty || answers.year == "unknown" ? "Noted. \(count)" : "A \(answers.year) \(model). Nice.",
                "\(count) You're moving.",
            ]
        case .box:
            lines = [answers.grade == "New" ? "Unworn. Buyers notice that." : "\(answers.grade ?? "Graded"). \(count)", "The hard part's done."]
        case .history:
            lines = [answers.box && answers.papers ? "Box and papers. Buyers look for that." : "Halfway there.", count]
        case .photos:
            lines = [answers.polish == "unpolished" ? "Never polished. Collectors notice." : "Getting close.", "\(count) Nearly there."]
        case .price:
            lines = ["Almost there.", "Last real question. Then a quick check."]
        case .returns:
            lines = ["One tap and it's ready to review.", "Last one."]
        case .review:
            lines = ["That's everything. Here's your listing.", "Done. Have a look before it goes in."]
        }
        return lines.randomElement() ?? lines[0]
    }
}
