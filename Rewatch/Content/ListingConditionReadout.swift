import RewatchKit

// The condition card and the seller's three history answers, as words and as
// groupings, worked out here once so the listing page, the cards, the deck and
// the sell form cannot come to disagree (contracts, 2026-09-30, Parts A to D).
// Pure: nothing in this file draws anything.

// MARK: - The grade scale

enum GradeScale {
    /// Best first: New > Like New > Very Good > Good > Worn.
    static let grades = ConditionPart.grades

    /// 0 for New, 4 for Worn, nil for a word that is not one of the five.
    /// Letter case aside, as the site reads it.
    static func rank(_ grade: String?) -> Int? {
        guard let grade = cleaned(grade)?.lowercased() else { return nil }
        return grades.firstIndex { $0.lowercased() == grade }
    }

    /// The same grade, letter case aside; never true of two blanks.
    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = cleaned(a)?.lowercased(), let b = cleaned(b)?.lowercased() else { return false }
        return a == b
    }

    /// The grade's definition, when it is one of the five.
    static func definition(for grade: String?) -> ConditionGradeDefinition? {
        guard let grade = cleaned(grade) else { return nil }
        return ConditionGrades.definitions.first { $0.grade == grade }
    }

    /// Trimmed, or nil when there is nothing there.
    static func cleaned(_ grade: String?) -> String? {
        guard let text = grade?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

// MARK: - Parts against the overall grade

/// The seven part grades set against the overall one: whether they all match
/// it, which of them differ, or (on a listing made before the overall grade
/// was asked) the parts on their own. Parts with no grade are in no group.
struct ConditionBreakdown: Equatable {
    struct Part: Equatable, Identifiable {
        /// The server's part name: `case`, `dial`, `bezel`, ...
        let key: String
        /// "Case", "Dial", ...
        let label: String
        let grade: String
        /// The seller's note on this part, trimmed, or nil for none.
        let note: String?

        var id: String { key }
    }

    /// How a differing part sits against the overall grade.
    enum Direction: Equatable {
        /// Graded below the whole: the warning tint.
        case worse
        /// Graded above it: neutral.
        case better
        /// A word off the five-grade scale on either side: neutral, since
        /// nothing can be said about which way it goes.
        case unranked
    }

    enum Shape: Equatable {
        /// No part was graded at all. Nothing to show beside the overall grade.
        case noParts
        /// Every graded part equals the overall grade.
        case allMatch([Part])
        /// At least one graded part differs. `matching` may be empty.
        case differ(differing: [Part], matching: [Part])
        /// No overall grade: the parts as a plain list. Never an invented
        /// overall.
        case noOverall([Part])
    }

    /// The order the contract lists them in, which is the sell form's.
    static let partOrder: [(key: String, label: String)] = [
        ("case", "Case"),
        ("dial", "Dial"),
        ("bezel", "Bezel"),
        ("crystal", "Crystal"),
        ("bracelet", "Bracelet"),
        ("clasp", "Clasp"),
        ("caseback", "Caseback"),
    ]

    let overall: String?
    /// `condition_notes.overall`, trimmed.
    let overallNote: String?
    let shape: Shape

    init(condition: ListingCondition?, notes: [String: String]?) {
        let notes = notes ?? [:]
        func note(_ key: String) -> String? { conditionNoteText(notes[key]) }
        let grades: [String: String?] = [
            "case": condition?.caseCondition,
            "dial": condition?.dial,
            "bezel": condition?.bezel,
            "crystal": condition?.crystal,
            "bracelet": condition?.bracelet,
            "clasp": condition?.clasp,
            "caseback": condition?.caseback,
        ]
        let parts: [Part] = Self.partOrder.compactMap { key, label in
            guard let grade = GradeScale.cleaned(grades[key] ?? nil) else { return nil }
            return Part(key: key, label: label, grade: grade, note: note(key))
        }
        overall = GradeScale.cleaned(condition?.overall)
        overallNote = note("overall")

        guard let overall else {
            shape = parts.isEmpty ? .noParts : .noOverall(parts)
            return
        }
        guard !parts.isEmpty else {
            shape = .noParts
            return
        }
        let differing = parts.filter { !GradeScale.same($0.grade, overall) }
        shape = differing.isEmpty
            ? .allMatch(parts)
            : .differ(differing: differing, matching: parts.filter { GradeScale.same($0.grade, overall) })
    }

    init(listing: Listing) {
        self.init(condition: listing.condition, notes: listing.conditionNotes)
    }

    /// Which way a part leans from the overall grade.
    func direction(of part: Part) -> Direction {
        guard let partRank = GradeScale.rank(part.grade), let overallRank = GradeScale.rank(overall) else {
            return .unranked
        }
        return partRank > overallRank ? .worse : .better
    }

    /// The parts graded apart from the whole; empty unless `.differ`.
    var differing: [Part] {
        if case .differ(let differing, _) = shape { return differing }
        return []
    }

    /// "Case, dial, crystal, clasp: Very Good": the matching parts beside the
    /// grade they share, under the "Worth knowing" cards. Nil when nothing
    /// matches.
    var matchingLine: String? {
        guard case .differ(_, let matching) = shape, !matching.isEmpty, let overall else { return nil }
        let names = matching.enumerated().map { index, part in
            index == 0 ? part.label : part.label.lowercased()
        }
        return names.joined(separator: ", ") + ": " + overall
    }

    /// The seller's notes on parts that print as lines rather than inside a
    /// part's own card: every note under "All parts match", and the notes on
    /// the matching parts under the matching line.
    var lineNotes: [Part] {
        switch shape {
        case .allMatch(let parts): parts.filter { $0.note != nil }
        case .differ(_, let matching): matching.filter { $0.note != nil }
        case .noParts, .noOverall: []
        }
    }

    /// "Seller's note, Case:" — the bold lead-in of a note line.
    static func noteLead(_ part: Part) -> String {
        "Seller's note, \(part.label):"
    }

    /// The differing parts graded WORSE than the overall grade: what a card's
    /// warning chip and the deck's callout are about. A part graded better is
    /// still a difference, and the listing screen's "Worth knowing" shows it in
    /// a neutral tint, but a warning on a card is a caution and a better part
    /// is not one. Off-scale words have no direction, so they are left out.
    var worseParts: [Part] {
        differing.filter { direction(of: $0) == .worse }
    }

    /// The note under a grid card's grade: "Bracelet: Good" for one worse part,
    /// "2 parts below Very Good" for more, nil when no part is worse. The count
    /// names the grade it is below, because "graded lower" on its own left a
    /// reader asking lower than what.
    var cardChip: String? {
        let worse = worseParts
        switch worse.count {
        case 0: return nil
        case 1: return "\(worse[0].label): \(worse[0].grade)"
        default: return "\(worse.count) parts below \(overall ?? "the overall grade")"
        }
    }

    /// The callout title on a full-width card: "Bracelet graded Good".
    static func calloutTitle(_ part: Part) -> String {
        "\(part.label) graded \(part.grade)"
    }
}

// MARK: - The three history answers

/// The words each history answer prints as (contracts, 2026-09-30, Part A's
/// table). A nil answer (nobody asked) prints nothing on a consumer surface.
enum ListingHistoryWords {
    // Listing page rows.

    static func polishRow(_ value: String?) -> String? {
        switch value {
        case "unpolished": "Never polished"
        case "polished": "Polished"
        case "unknown": "Not known"
        default: nil
        }
    }

    static func originalityRow(_ value: String?, note: String?) -> String? {
        switch value {
        case "all_original": return "All original parts"
        case "replaced":
            guard let note = conditionNoteText(note) else { return "Some parts replaced" }
            return "Some parts replaced: \(note)"
        case "unknown": return "Not known"
        default: return nil
        }
    }

    static func serviceRow(_ value: String?, year: Int?) -> String? {
        switch value {
        case "serviced": year.map { "Serviced in \($0)" } ?? "Serviced, year not known"
        case "never": "Never serviced"
        case "unknown": "Not known"
        default: nil
        }
    }

    // Card facts.

    static func polishFact(_ value: String?) -> String? {
        switch value {
        case "unpolished": "Unpolished"
        case "polished": "Polished"
        default: nil
        }
    }

    static func originalityFact(_ value: String?) -> String? {
        value == "all_original" ? "All original" : nil
    }

    /// "Full set", "Box" or "Papers" for a card; nil when neither came with it
    /// or nobody said.
    static func boxFact(boxIncluded: Bool?, papersIncluded: Bool?, boxPapers: Bool?) -> String? {
        guard boxIncluded != nil || papersIncluded != nil else {
            // A listing made before the question was split: the one bit, and
            // it meant box AND papers.
            return boxPapers == true ? "Full set" : nil
        }
        switch (boxIncluded == true, papersIncluded == true) {
        case (true, true): return "Full set"
        case (true, false): return "Box"
        case (false, true): return "Papers"
        case (false, false): return nil
        }
    }

    /// The facts a card prints after the grade, in the contract's order:
    /// polish, originality, box.
    static func cardFacts(for listing: Listing) -> [String] {
        [
            polishFact(listing.history?.polish),
            originalityFact(listing.history?.originality),
            boxFact(
                boxIncluded: listing.boxIncluded,
                papersIncluded: listing.papersIncluded,
                boxPapers: listing.boxPapers
            ),
        ].compactMap { $0 }
    }

    /// The History table on the listing page: Polish, Originality, Last
    /// service, Box & papers, each only when there is an answer. Empty hides
    /// the section.
    static func rows(for listing: Listing) -> [ListingDetailRow] {
        let history = listing.history
        let values: [(String, String?)] = [
            ("Polish", polishRow(history?.polish)),
            ("Originality", originalityRow(history?.originality, note: history?.replacedPartsNote)),
            ("Last service", serviceRow(history?.serviceHistory, year: history?.lastServiceYear)),
            ("Box & papers", BoxPapersPhrase.text(for: listing)),
        ]
        return values.compactMap { label, value in
            value.map { ListingDetailRow(label: label, value: $0, helpKey: nil) }
        }
    }
}

// MARK: - Box and papers, as the app already says it

/// The one phrase the app prints for what came with the watch: the listing's
/// Box & papers tile, and the History table's Box & papers row. One function,
/// so the two cannot come to say it two ways.
enum BoxPapersPhrase {
    /// "Full set", "Box only", "Papers only" or "Watch only"; nil when nothing
    /// is known.
    static func text(boxIncluded: Bool?, papersIncluded: Bool?, bookletsIncluded: Bool?, boxPapers: Bool?) -> String? {
        if boxIncluded != nil || papersIncluded != nil || bookletsIncluded != nil {
            switch (boxIncluded == true, papersIncluded == true) {
            case (true, true): return "Full set"
            case (true, false): return "Box only"
            case (false, true): return "Papers only"
            case (false, false): return "Watch only"
            }
        }
        return switch boxPapers {
        case true: "Full set"
        case false: "Watch only"
        default: nil
        }
    }

    static func text(for listing: Listing) -> String? {
        text(
            boxIncluded: listing.boxIncluded,
            papersIncluded: listing.papersIncluded,
            bookletsIncluded: listing.bookletsIncluded,
            boxPapers: listing.boxPapers
        )
    }
}

// MARK: - The sell form's three questions

/// The three questions the sell form asks after the grades (contracts,
/// 2026-09-30, Part B). Timekeeping is deliberately not one of them: only the
/// bench can measure it.
///
/// Copied verbatim from `frontend/src/content/sellFieldHelp.ts`
/// (`SELL_HISTORY_QUESTIONS`): change them there and here together.
/// `SharedWordingParityTests` holds the two to each other.
enum HistoryQuestion: String, CaseIterable, Identifiable, Hashable {
    case polish, originality, service

    var id: String { rawValue }

    var question: String {
        switch self {
        case .polish: "Has the case or bracelet been polished?"
        case .originality: "Are all the parts original?"
        case .service: "When was it last serviced?"
        }
    }

    /// The (?) sentence.
    var help: String {
        switch self {
        case .polish:
            "Polishing takes scratches out by removing metal. Collectors often pay more for a watch that has never been polished."
        case .originality:
            "Original means the parts the watch left the factory with. Parts fitted by the brand during a service count as replaced; say which ones if you know."
        case .service:
            "A service is when a watchmaker takes the movement apart, cleans it and oils it. A rough year is fine."
        }
    }

    /// What VoiceOver says for the (?): the question it answers.
    var helpLabel: String {
        switch self {
        case .polish: "What does polishing do to a watch?"
        case .originality: "What counts as an original part?"
        case .service: "What is a service?"
        }
    }

    /// Said beside an unanswered question on a new listing once Continue has
    /// been pressed.
    var requiredMessage: String {
        switch self {
        case .polish: "Say whether the case or bracelet has been polished."
        case .originality: "Say whether all the parts are original."
        case .service: "Say when the watch was last serviced."
        }
    }

    /// The optional field under "Some parts replaced" and under "Serviced".
    var followUpLabel: String? {
        switch self {
        case .polish: nil
        case .originality: "What was replaced?"
        case .service: "Year of the last service"
        }
    }

    /// The answers, as the server stores them and as the chips say them.
    var options: [(value: String, label: String)] {
        switch self {
        case .polish: [("unpolished", "Never polished"), ("polished", "Polished"), ("unknown", "I don't know")]
        case .originality: [("all_original", "All original"), ("replaced", "Some parts replaced"), ("unknown", "I don't know")]
        case .service: [("serviced", "Serviced"), ("never", "Never serviced"), ("unknown", "I don't know")]
        }
    }

    /// The row label the listing page and the review step print it under.
    var rowLabel: String {
        switch self {
        case .polish: "Polish"
        case .originality: "Originality"
        case .service: "Last service"
        }
    }
}
