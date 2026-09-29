import RewoundDesign
import RewoundKit
import SwiftUI

// MARK: - The seller's own words

/// What a listing's description says, once every generated row has been
/// taken off it — the same answer the site's "From the seller" gives
/// (`stripListingDescriptionNoise` in `frontend/src/lib/listingFacts.ts`).
///
/// The description is meant to be the seller's notes and nothing else: brand,
/// model, reference, the grades, the year and what is included are columns,
/// and the page already shows them above. Rows written before that change
/// still carry a generated block, and on the staging inventory it does not
/// only open the description: "Overall condition: Like New. Case, bezel…"
/// and "Included: box included; papers included." come after a blank line.
///
/// **A line is judged by its label alone, wherever it falls.** A line that
/// opens with one to four plain words and a colon is a field row and is
/// dropped. This used to be a leading-run test that also asked the VALUE to be
/// short and not end like a sentence, and those guards are exactly what let
/// the condition and inclusion rows through — both end in a full stop, and the
/// condition row is long — so the app showed them again under "From the
/// seller" while the site did not (Eytan, 2026-09-23: "the app shows a ton of
/// other info that is already displayed above"). The site made the same
/// finding first; the two now apply the same rule.
///
/// What a seller's own sentence keeps: a label with a digit or any sentence
/// punctuation in it is prose ("Serviced 2025: full service" is kept). The
/// cost the site accepted is accepted here too: "One owner: bought at an AD" is
/// read as a label and dropped. A false drop loses one sentence; a false keep
/// puts the spec table on the page twice.
///
/// One row is the exception in both directions: `Seller notes: …` was how the
/// old generated block carried the seller's own words, so its value is kept.
struct SellerNotes {
    let text: String

    private static let notesKey = "seller notes"
    /// The longest label a generated row uses is three words ("Year of
    /// Manufacture"); four is the site's allowance, kept identical.
    private static let maxLabelWords = 4

    init(_ description: String?) {
        var lines: [String] = []
        for rawLine in (description ?? "").components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                lines.append("")
            } else if let value = Self.sellerNotesValue(in: line) {
                if !value.isEmpty { lines.append(value) }
            } else if !Self.isGenerated(line) {
                lines.append(line)
            }
        }

        // The author's paragraph breaks stay; the gaps the dropped rows leave
        // collapse to one, and none lead or trail.
        var kept: [String] = []
        for line in lines {
            if line.isEmpty, kept.last?.isEmpty ?? true { continue }
            kept.append(line)
        }
        self.text = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The seller's words out of a `Seller notes: …` row, or nil when the line
    /// is not one.
    private static func sellerNotesValue(in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
        guard key == notesKey else { return nil }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Whether `line` is a field row: a label of one to four plain words
    /// (letters and the joiners a label uses), a colon, and something after
    /// it. The two header lines the old importer wrote are rows too.
    static func isGenerated(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower == "watchdb auto data:" { return true }

        guard let colon = line.firstIndex(of: ":") else { return false }
        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else { return false }

        // Plain A–Z, as the site's `/^[A-Za-z][A-Za-z/&' -]*$/` is.
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard let first = key.unicodeScalars.first, letters.contains(first) else { return false }
        let allowed = letters.union(CharacterSet(charactersIn: " /&'-"))
        guard key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        let words = key.split(whereSeparator: { $0 == " " })
        return words.count <= maxLabelWords
    }
}

// MARK: - Quick spec row

/// The three at-a-glance tiles under the buy box: Condition / Year / Box & papers.
struct QuickSpecRow: View {
    let listing: Listing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Three tiles across a phone give each about a third of the width. At
        // an accessibility size a third holds two or three characters, so
        // "Full set" was arriving as "Fu…" — past that point the tiles stack
        // full width instead.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.m) {
                tiles
            }
        } else {
            HStack(spacing: Space.m) {
                tiles
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        tile("Condition", listing.condition?.overall ?? "—")
        tile("Year", listing.productionYear.map(String.init) ?? "—")
        tile("Box & papers", boxPapersText)
    }

    private var boxPapersText: String {
        if listing.boxIncluded != nil || listing.papersIncluded != nil || listing.bookletsIncluded != nil {
            switch (listing.boxIncluded == true, listing.papersIncluded == true) {
            case (true, true): return "Full set"
            case (true, false): return "Box only"
            case (false, true): return "Papers only"
            case (false, false): return "Watch only"
            }
        }
        return switch listing.boxPapers {
        case true: "Full set"
        case false: "Watch only"
        default: "—"
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            // "Box & papers" fits on one line at the default size and needs a
            // second before it will fit at any larger one, so the limit lifts
            // only above the accessibility threshold. Gated rather than deleted:
            // dropping it outright left the default layout resting on a hand
            // measurement (~73pt of text in a ~96pt tile on a 375pt screen) with
            // no floor under it, so a longer localized label would silently wrap
            // the tile and grow the row for everyone.
            Text(label)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            // Two-word values ("Very Good", "Like New") need room to wrap —
            // a single line with only an 0.8 scale factor was clipping them.
            Text(value)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.m)
        .background(
            Color.rewound.secondary.opacity(0.6),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The details

/// One row of "The details": what the fact is, this watch's answer, and the
/// key of the explanation behind its (?), if it has one.
struct ListingDetailRow: Equatable {
    let label: String
    let value: String
    /// A key into `SpecHelp.sentences`, or nil for the two rows with no (?):
    /// Brand and Model, which explain themselves (Eytan, 2026-09-29).
    let helpKey: String?
}

enum ListingDetailRows {
    /// Every row the details table prints for `listing`, in order.
    static func rows(for listing: Listing) -> [ListingDetailRow] {
        var rows: [ListingDetailRow] = []
        if let brand = listing.brand { rows.append(.init(label: "Brand", value: brand, helpKey: nil)) }
        if let model = listing.model { rows.append(.init(label: "Model", value: model, helpKey: nil)) }
        if let reference = listing.referenceNumber {
            rows.append(.init(label: "Reference", value: reference, helpKey: "reference"))
        }
        if let year = listing.productionYear {
            rows.append(.init(label: "Year", value: String(year), helpKey: "year"))
        }
        // What came with the watch, as three answers where the seller gave
        // three. These used to reach a buyer only as `Key: Value` lines parsed
        // out of the description; they are columns now and are read as columns.
        // Nil is "nobody was asked" and prints nothing — an unasked question
        // must never read as a seller's "no".
        let inclusions: [(label: String, value: Bool?, helpKey: String)] = [
            ("Box", listing.boxIncluded, "box"),
            ("Papers", listing.papersIncluded, "papers"),
            ("Booklets", listing.bookletsIncluded, "booklets"),
        ]
        let answered = inclusions.compactMap { label, value, helpKey -> ListingDetailRow? in
            guard let value else { return nil }
            return .init(label: label, value: value ? "Included" : "Not included", helpKey: helpKey)
        }
        if answered.isEmpty {
            // The single bit a listing made before the question was split
            // carries, and all it can say.
            if let boxPapers = listing.boxPapers {
                rows.append(.init(
                    label: "Box & papers",
                    value: boxPapers ? "Full set" : "Watch only",
                    helpKey: "box_papers"
                ))
            }
        } else {
            rows.append(contentsOf: answered)
        }
        // The catalog's own specs, merged with whatever this one watch
        // overrides, straight off the payload.
        //
        // This used to read `ParsedDescription(listing.description).specs` —
        // the seller's description, split on its colons — because the payload
        // carried no specs at all and prose was the only thing there was to
        // read. Which meant the app showed whichever facts a seller happened to
        // type, in whatever words they used, and never the ten (now sixteen)
        // fields Rewound actually keeps.
        rows.append(contentsOf: specRows(listing.specs))
        return rows
    }

    /// The catalog's spec rows, each carrying its spec key.
    ///
    /// `ListingSpecs.rows` owns the words and the units, so the table cannot
    /// come to disagree with the storefront about them; it hands back labels
    /// without keys, and `specKeyByLabel` puts the key back. A label that
    /// misses the map still prints, only without a (?).
    static func specRows(_ specs: ListingSpecs?) -> [ListingDetailRow] {
        (specs?.rows ?? []).map { row in
            ListingDetailRow(label: row.label, value: row.value, helpKey: specKeyByLabel[row.label])
        }
    }

    /// `ListingSpecs.rows`' labels, back to the server's spec keys
    /// (`REFERENCE_SPEC_FIELDS`), which is how `SpecHelp` is keyed.
    /// `ListingDetailRowsTests` fails if a label is renamed there and not here.
    static let specKeyByLabel: [String: String] = [
        "Case material": "material",
        "Bezel": "bezel",
        "Glass": "glass",
        "Case back": "back",
        "Shape": "shape",
        "Diameter": "diameter_mm",
        "Finish": "finish",
        "Dial": "dial",
        "Indexes": "indexes",
        "Hands": "hands",
        "Movement": "movement",
        "Calibre": "calibre",
        "Bracelet": "bracelet",
        "Thickness": "thickness_mm",
        "Lug width": "lug_width_mm",
        "Water resistance": "water_resistance_m",
    ]

    /// What VoiceOver says for each row's (?): the question it answers.
    static let questions: [String: String] = [
        "reference": "What is a reference number?",
        "year": "What does the year mean?",
        "material": "What is the case material?",
        "bezel": "What is the bezel?",
        "glass": "What is the glass?",
        "back": "What is the case back?",
        "shape": "What is the case shape?",
        "diameter_mm": "What is the diameter?",
        "finish": "What is the finish?",
        "dial": "What is the dial?",
        "indexes": "What are indexes?",
        "hands": "What are the hands?",
        "movement": "What is the movement?",
        "calibre": "What is a calibre?",
        "bracelet": "What is the bracelet?",
        "thickness_mm": "What is the thickness?",
        "lug_width_mm": "What is lug width?",
        "water_resistance_m": "What is water resistance?",
        "box": "What counts as the box?",
        "papers": "What counts as papers?",
        "booklets": "What counts as booklets?",
        "box_papers": "What does box and papers mean?",
    ]
}

/// "The details": copper labels, bold values, firm lines between the rows,
/// and a (?) beside every fact that is not self-explanatory.
///
/// Its own view rather than `SpecList`, which draws a dozen other tables in
/// the app (prices, payouts, dates) that keep the quieter muted-label style
/// and have nothing to explain.
struct ListingDetailsTable: View {
    let rows: [ListingDetailRow]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                row(rows[index])
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color.rewound.borderBright)
                        .frame(height: 1)
                }
            }
        }
        .background(Color.rewound.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.borderBright, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(_ row: ListingDetailRow) -> some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(row.label)
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.primary)
                // The fact and its figure are one swipe, as `SpecList` reads
                // them; the (?) beside it is the next.
                .accessibilityLabel("\(row.label), \(row.value)")
            if let key = row.helpKey, let sentence = SpecHelp.sentences[key] {
                InfoHint(
                    ListingDetailRows.questions[key] ?? "What does \(row.label.lowercased()) mean?",
                    message: sentence
                )
            }
        }
        let value = Text(row.value)
            .font(RewoundType.bodySemiBold)
            .foregroundStyle(Color.rewound.foreground)
            .accessibilityHidden(true)

        Group {
            // `SpecList`'s rule: side by side until an accessibility size,
            // where the value would be left a word of width, then stacked.
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                    label
                    Spacer(minLength: Space.l)
                    value.multilineTextAlignment(.trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    label
                    value
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Condition grading

/// The five grades and what each one means, always on show above a listing's
/// Condition grading table and inside the sell form's (?) on its Condition
/// heading. The words are `ConditionGrades`, shared with the site.
///
/// A grade column and a meaning column until an accessibility size, where the
/// meaning is given the full width under its grade instead of a sliver of it.
struct ConditionGradeDefinitionsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    private static var gradeFont: Font { RewoundType.sans(.semiBold, 13, relativeTo: .footnote) }
    private static var meaningFont: Font { RewoundType.sans(.regular, 13, relativeTo: .footnote) }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(ConditionGrades.definitions, id: \.grade) { definition in
                    VStack(alignment: .leading, spacing: 2) {
                        gradeName(definition)
                        meaning(definition)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
                ForEach(ConditionGrades.definitions, id: \.grade) { definition in
                    GridRow {
                        gradeName(definition)
                            // The column is as wide as "Very Good" and no
                            // wider; a grade never breaks across two lines.
                            .fixedSize()
                        meaning(definition)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func gradeName(_ definition: ConditionGradeDefinition) -> some View {
        Text(definition.grade)
            .font(Self.gradeFont)
            .foregroundStyle(Color.rewound.foreground)
            // One swipe per grade, the grade and what it means together.
            .accessibilityLabel("\(definition.grade): \(definition.description)")
    }

    private func meaning(_ definition: ConditionGradeDefinition) -> some View {
        Text(definition.description)
            .font(Self.meaningFont)
            .foregroundStyle(Color.rewound.secondaryForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Per-part condition as status badges in a spec-list-styled card, with the
/// seller's own few words under any part they wrote about.
struct ConditionGradingCard: View {
    let condition: ListingCondition
    /// The seller's notes, keyed by the part names `condition` uses. Empty
    /// when they wrote none, or when the payload did not carry them; a row
    /// without a note is drawn exactly as it was before notes existed.
    var notes: [String: String] = [:]

    /// All eight parts, in the order the sell form asks for them — with the
    /// overall grade first, because that is the one a buyer reads as the
    /// summary. A part the seller left blank is simply not a row: nothing
    /// here is filled in from a grade that belongs to something else.
    private var rows: [(key: String, label: String, value: String)] {
        [
            ("overall", "Overall", condition.overall),
            ("case", "Case", condition.caseCondition),
            ("dial", "Dial", condition.dial),
            ("bezel", "Bezel", condition.bezel),
            ("crystal", "Crystal", condition.crystal),
            ("bracelet", "Bracelet", condition.bracelet),
            ("clasp", "Clasp", condition.clasp),
            ("caseback", "Caseback", condition.caseback),
        ].compactMap { key, label, value in
            value.map { (key, label, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                ConditionGradeRow(label: row.label, grade: row.value, note: conditionNoteText(notes[row.key])) {
                    StatusBadge(row.value, tone: Self.tone(for: row.value))
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)

                // The same firm line as "The details" beside it.
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color.rewound.borderBright)
                        .frame(height: 1)
                }
            }
        }
        .background(Color.rewound.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.borderBright, lineWidth: 1)
        )
    }

    // One tone for every grade, deliberately: distinct colors per grade read
    // as if they meant something (a stoplight, a ranking) rather than just
    // labeling a fact about the watch.
    static func tone(for grade: String) -> StatusBadge.Tone {
        .success
    }
}

/// One part of the watch: its name and its grade on one line, and under the
/// name, when the seller wrote one, their own few words about why.
///
/// The note is quoted in the body face, as the site sets it: the quotation
/// marks say these are the seller's words, not Rewound's (the grade is checked
/// against the watch at authentication; the note is what the seller said).
/// Eytan's call, 2026-09-25: plain text, never the hand, for these notes.
/// It runs the full width of the row under the name rather than squeezing
/// into the column beside the grade, so eighty characters take two lines,
/// not four.
struct ConditionGradeRow<Grade: View>: View {
    let label: String
    /// The grade as words, for the spoken row; the view draws `badge`.
    let grade: String
    let note: String?
    @ViewBuilder let badge: () -> Grade

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // Side by side until an accessibility size, where the grade sits
            // under the part it belongs to — `SpecList`'s rule, kept so the
            // review step's rows break where they did before notes existed.
            if typeSize.isAccessibilitySize {
                Text(label)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
                badge()
            } else {
                HStack(spacing: Space.l) {
                    Text(label)
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.mutedForeground)
                    Spacer(minLength: Space.l)
                    badge()
                }
            }
            if let note {
                Text("\u{201C}\(note)\u{201D}")
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // One swipe per part, and the note said as what it is.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.map { "\(label), \(grade). The seller says: \($0)" } ?? "\(label), \(grade)")
    }
}

/// A seller's condition note worth drawing, or nil: a blank or whitespace-only
/// note is no note, whatever the payload carried.
func conditionNoteText(_ raw: String?) -> String? {
    guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    return text
}

// MARK: - Seller card

/// The seller strip: monogram, username, sales count, star rating. Tapping
/// opens the storefront.
struct SellerCard: View {
    let seller: ListingSeller
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                AvatarInitial(name: seller.username, size: .m)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.xs) {
                        Text("@\(seller.username)")
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
                        // A verified business is behind this listing — that is
                        // the whole of what the badge claims.
                        if seller.isVerifiedDealer == true {
                            DealerBadge(compact: true)
                        }
                    }
                    if let reputation = seller.reputation {
                        Text(reputation.salesCount == 1 ? "1 sale on Rewound" : "\(reputation.salesCount) sales on Rewound")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                    }
                }

                Spacer()

                if let reputation = seller.reputation, let average = reputation.averageRating,
                   reputation.ratingCount > 0 {
                    HStack(spacing: Space.xs) {
                        StarRating(rating: average)
                        Text("(\(reputation.ratingCount))")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
            .padding(Space.l)
            .background(Color.rewound.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Seller \(seller.username). View storefront.")
    }
}

// MARK: - Authentication info sheet

/// Static editorial content behind the "Authenticated by Rewound" callout.
///
/// WPB Watch Co is named where the watch is examined, as everywhere a customer
/// reads about it (Eytan, 2026-09-29): "WPB Watch Co, our authentication
/// partner in West Palm Beach, Florida" the first time on this sheet, "WPB
/// Watch Co" after. The "Authenticated by" title stays Rewound's, as on the
/// report. Name and city only, and no credential the row does not hold.
struct AuthenticationInfoSheet: View {
    var body: some View {
        SheetScaffold(title: "Inspected before it ships", detents: [.medium, .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Every watch sold on Rewound travels to WPB Watch Co, our authentication partner in West Palm Beach, Florida, before it travels to you. Nothing ships buyer-direct.")
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.secondaryForeground)
                        .lineSpacing(5)

                    infoRow(
                        icon: "checkmark.shield",
                        title: "Authenticated by Rewound",
                        message: "Movement, case, dial, and papers are examined against the reference's factory specification, under a 72-hour commitment from arrival to verdict."
                    )
                    infoRow(
                        icon: "clock.badge.checkmark",
                        title: "Condition verified",
                        message: "The listing's condition grading is confirmed part by part. If anything doesn't match, the sale doesn't proceed."
                    )
                    infoRow(
                        icon: "wrench.and.screwdriver",
                        title: "1-year mechanical warranty",
                        message: "Every watch that passes authentication includes a one-year mechanical warranty in Rewound's name."
                    )
                    infoRow(
                        icon: "shippingbox",
                        title: "Insured on every leg",
                        message: "Every label on every leg requires a direct signature and is insured for the full sale price."
                    )

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("If something is wrong")
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
                        Text("If a watch is found to be counterfeit, authentication costs you nothing, you're refunded in full including the card fee, and the watch is destroyed. It cannot legally be returned to anyone.")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If a watch is genuine but not as described, your Rewound contact treats it as urgent and settles it case by case: either a partial refund, or the watch goes back.")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If authentication runs past its commitment, you hear from your Rewound contact before you have to ask.")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Space.xs)
                }
                .padding(.bottom, Space.xxl)
            }
        }
    }

    private func infoRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Text(message)
                    .font(RewoundType.label)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .lineSpacing(3)
            }
        }
    }
}
