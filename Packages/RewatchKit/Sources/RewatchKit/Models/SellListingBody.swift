import Foundation

/// What "List a watch" sends, as the website sends it.
///
/// The site writes its create/PATCH body once, in `sellListingPayload.ts`, and
/// both of its sell forms build their request there. This is that function in
/// Swift, field for field, so a listing made in the app and one made on the
/// site for the same answers are the same request: the same keys, the three
/// box answers beside the derived `box_papers`, the condition-notes map, the
/// history keys and the returns pair. `SellListingPayloadParityTests` holds the
/// two to one fixture computed by the site's own code.
///
/// The rules, as the site states them:
/// - eight grades, each from its own answer, nothing copied across parts;
/// - `box_papers` is box AND papers, kept as the derived summary the cards and
///   facets read, with the three real answers in their own columns;
/// - `condition_notes` goes on every write, because the server REPLACES its
///   stored map with whatever arrives; blank notes are left out;
/// - history sends only answered questions, each follow-up beside its answer
///   and `null` when there is nothing to keep;
/// - `vault_watch_id` is left off entirely unless the seller said yes.
public struct SellListingBody: Encodable, Sendable, Equatable {
    /// The eight grades in the order the server asks for them, each note's key.
    public static let conditionParts = ["case", "dial", "bezel", "crystal", "bracelet", "clasp", "caseback", "overall"]

    /// The form's values, under the site's `SellListingValues` names.
    public struct Values: Equatable, Sendable {
        public var brand: String
        public var model: String
        public var referenceNumber: String
        public var sellerSku: String
        public var conditionCase: String
        public var conditionDial: String
        public var conditionBezel: String
        public var conditionCrystal: String
        public var conditionBracelet: String
        public var conditionClasp: String
        public var conditionCaseback: String
        /// The overall grade.
        public var condition: String
        public var conditionNotes: [String: String]
        public var polish: String
        public var originality: String
        public var replacedPartsNote: String
        public var serviceHistory: String
        public var lastServiceYear: String
        /// Four digits, or "unknown".
        public var manufactureYear: String
        public var price: Decimal
        public var notes: String
        public var countryOfOrigin: String
        public var htsCode: String

        public init(
            brand: String, model: String, referenceNumber: String, sellerSku: String = "",
            conditionCase: String, conditionDial: String, conditionBezel: String,
            conditionCrystal: String, conditionBracelet: String, conditionClasp: String,
            conditionCaseback: String, condition: String, conditionNotes: [String: String] = [:],
            polish: String = "", originality: String = "", replacedPartsNote: String = "",
            serviceHistory: String = "", lastServiceYear: String = "", manufactureYear: String,
            price: Decimal, notes: String = "", countryOfOrigin: String = "", htsCode: String = ""
        ) {
            self.brand = brand
            self.model = model
            self.referenceNumber = referenceNumber
            self.sellerSku = sellerSku
            self.conditionCase = conditionCase
            self.conditionDial = conditionDial
            self.conditionBezel = conditionBezel
            self.conditionCrystal = conditionCrystal
            self.conditionBracelet = conditionBracelet
            self.conditionClasp = conditionClasp
            self.conditionCaseback = conditionCaseback
            self.condition = condition
            self.conditionNotes = conditionNotes
            self.polish = polish
            self.originality = originality
            self.replacedPartsNote = replacedPartsNote
            self.serviceHistory = serviceHistory
            self.lastServiceYear = lastServiceYear
            self.manufactureYear = manufactureYear
            self.price = price
            self.notes = notes
            self.countryOfOrigin = countryOfOrigin
            self.htsCode = htsCode
        }
    }

    /// The site's `SellListingContext`.
    public struct Context: Equatable, Sendable {
        public var box: Bool
        public var papers: Bool
        public var booklets: Bool
        public var returnsAccepted: Bool
        /// 24, 48 or 72. Sent only when returns are accepted.
        public var returnWindowHours: Int
        /// The seller's yes to "is this the watch from your Vault?", or nil.
        public var vaultWatchID: String?
        /// A dealer outside the US: country of origin and HTS code travel too.
        public var needsCustomsFields: Bool

        public init(
            box: Bool, papers: Bool, booklets: Bool,
            returnsAccepted: Bool, returnWindowHours: Int,
            vaultWatchID: String?, needsCustomsFields: Bool
        ) {
            self.box = box
            self.papers = papers
            self.booklets = booklets
            self.returnsAccepted = returnsAccepted
            self.returnWindowHours = returnWindowHours
            self.vaultWatchID = vaultWatchID
            self.needsCustomsFields = needsCustomsFields
        }
    }

    public var title: String
    public var brand: String
    public var model: String
    public var reference: String
    public var description: String
    public var price: Decimal
    public var currency: String
    public var conditionCase: String
    public var conditionDial: String
    public var conditionBezel: String
    public var conditionCrystal: String
    public var conditionBracelet: String
    public var conditionClasp: String
    public var conditionCaseback: String
    public var conditionOverall: String
    public var conditionNotes: [String: String]
    public var sellerSku: String?
    public var boxPapers: Bool
    public var boxIncluded: Bool
    public var papersIncluded: Bool
    public var bookletsIncluded: Bool
    /// Present only when answered with a word the server knows.
    public var polish: String?
    public var originality: String?
    /// Sent whenever `originality` is: the note beside `replaced`, else null.
    public var replacedPartsNote: String?
    public var serviceHistory: String?
    /// Sent whenever `serviceHistory` is: the year beside `serviced`, else null.
    public var lastServiceYear: Int?
    public var countryOfOrigin: String?
    public var htsCode: String?
    public var productionYear: Int?
    public var returnsAccepted: Bool
    public var returnWindowHours: Int?
    public var vaultWatchID: String?

    /// The site's `sellListingPayload(values, context)`.
    public init(values: Values, context: Context) {
        title = Self.title(brand: values.brand, model: values.model, reference: values.referenceNumber)
        brand = Self.trim(values.brand)
        model = Self.trim(values.model)
        reference = Self.trim(values.referenceNumber)
        description = Self.trim(values.notes)
        price = values.price
        currency = "USD"
        conditionCase = values.conditionCase
        conditionDial = values.conditionDial
        conditionBezel = values.conditionBezel
        conditionCrystal = values.conditionCrystal
        conditionBracelet = values.conditionBracelet
        conditionClasp = values.conditionClasp
        conditionCaseback = values.conditionCaseback
        conditionOverall = values.condition
        conditionNotes = Self.conditionNotesPayload(values.conditionNotes)
        let sku = Self.trim(values.sellerSku)
        sellerSku = sku.isEmpty ? nil : sku
        boxPapers = context.box && context.papers
        boxIncluded = context.box
        papersIncluded = context.papers
        bookletsIncluded = context.booklets

        // `historyWritePayload`: only answered questions, follow-ups beside them.
        if ListingHistory.polishValues.contains(values.polish) {
            polish = values.polish
        }
        if ListingHistory.originalityValues.contains(values.originality) {
            originality = values.originality
            let note = Self.collapse(values.replacedPartsNote)
            replacedPartsNote = values.originality == "replaced" && !note.isEmpty ? note : nil
        }
        if ListingHistory.serviceValues.contains(values.serviceHistory) {
            serviceHistory = values.serviceHistory
            let year = Self.trim(values.lastServiceYear)
            lastServiceYear = values.serviceHistory == "serviced" && Self.isFourDigits(year) ? Int(year) : nil
        }

        if context.needsCustomsFields {
            let country = Self.trim(values.countryOfOrigin).uppercased()
            countryOfOrigin = country.isEmpty ? nil : country
            let hts = Self.trim(values.htsCode)
            htsCode = hts.isEmpty ? nil : hts
        }
        productionYear = values.manufactureYear == "unknown" ? nil : Int(Self.trim(values.manufactureYear))
        returnsAccepted = context.returnsAccepted
        returnWindowHours = context.returnsAccepted ? context.returnWindowHours : nil
        vaultWatchID = context.vaultWatchID
    }

    /// `"{brand} {model} {reference}"`, every run of whitespace one space.
    public static func title(brand: String, model: String, reference: String) -> String {
        collapse("\(brand) \(model) \(reference)")
    }

    /// The whole notes map as the server takes it: each note trimmed with its
    /// whitespace collapsed, blank ones left out.
    public static func conditionNotesPayload(_ notes: [String: String]) -> [String: String] {
        var payload: [String: String] = [:]
        for part in conditionParts {
            let note = collapse(notes[part] ?? "")
            if !note.isEmpty { payload[part] = note }
        }
        return payload
    }

    static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trimmed, every run of whitespace (a line break included) one space.
    static func collapse(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isFourDigits(_ value: String) -> Bool {
        value.count == 4 && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: Encoding

    /// Snake-case keys spelled out, so the body is the same whichever key
    /// strategy the encoder carries (`Endpoint.json` converts camelCase; these
    /// have none to convert).
    enum CodingKeys: String, CodingKey {
        case title, brand, model, reference, description, price, currency
        case conditionCase = "condition_case"
        case conditionDial = "condition_dial"
        case conditionBezel = "condition_bezel"
        case conditionCrystal = "condition_crystal"
        case conditionBracelet = "condition_bracelet"
        case conditionClasp = "condition_clasp"
        case conditionCaseback = "condition_caseback"
        case conditionOverall = "condition_overall"
        case conditionNotes = "condition_notes"
        case sellerSku = "seller_sku"
        case boxPapers = "box_papers"
        case boxIncluded = "box_included"
        case papersIncluded = "papers_included"
        case bookletsIncluded = "booklets_included"
        case polish, originality
        case replacedPartsNote = "replaced_parts_note"
        case serviceHistory = "service_history"
        case lastServiceYear = "last_service_year"
        case countryOfOrigin = "country_of_origin"
        case htsCode = "hts_code"
        case productionYear = "production_year"
        case returnsAccepted = "returns_accepted"
        case returnWindowHours = "return_window_hours"
        case vaultWatchID = "vault_watch_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(brand, forKey: .brand)
        try container.encode(model, forKey: .model)
        try container.encode(reference, forKey: .reference)
        try container.encode(description, forKey: .description)
        try container.encode(price, forKey: .price)
        try container.encode(currency, forKey: .currency)
        try container.encode(conditionCase, forKey: .conditionCase)
        try container.encode(conditionDial, forKey: .conditionDial)
        try container.encode(conditionBezel, forKey: .conditionBezel)
        try container.encode(conditionCrystal, forKey: .conditionCrystal)
        try container.encode(conditionBracelet, forKey: .conditionBracelet)
        try container.encode(conditionClasp, forKey: .conditionClasp)
        try container.encode(conditionCaseback, forKey: .conditionCaseback)
        try container.encode(conditionOverall, forKey: .conditionOverall)
        // The notes map is a nested keyed container of its own so its part
        // names ("case", "dial") are written exactly as they are.
        var notes = container.nestedContainer(keyedBy: AnyKey.self, forKey: .conditionNotes)
        for (part, note) in conditionNotes.sorted(by: { $0.key < $1.key }) {
            try notes.encode(note, forKey: AnyKey(part))
        }
        try container.encodeIfPresent(sellerSku, forKey: .sellerSku)
        try container.encode(boxPapers, forKey: .boxPapers)
        try container.encode(boxIncluded, forKey: .boxIncluded)
        try container.encode(papersIncluded, forKey: .papersIncluded)
        try container.encode(bookletsIncluded, forKey: .bookletsIncluded)
        if let polish {
            try container.encode(polish, forKey: .polish)
        }
        if let originality {
            try container.encode(originality, forKey: .originality)
            if let replacedPartsNote {
                try container.encode(replacedPartsNote, forKey: .replacedPartsNote)
            } else {
                try container.encodeNil(forKey: .replacedPartsNote)
            }
        }
        if let serviceHistory {
            try container.encode(serviceHistory, forKey: .serviceHistory)
            if let lastServiceYear {
                try container.encode(lastServiceYear, forKey: .lastServiceYear)
            } else {
                try container.encodeNil(forKey: .lastServiceYear)
            }
        }
        try container.encodeIfPresent(countryOfOrigin, forKey: .countryOfOrigin)
        try container.encodeIfPresent(htsCode, forKey: .htsCode)
        try container.encodeIfPresent(productionYear, forKey: .productionYear)
        try container.encode(returnsAccepted, forKey: .returnsAccepted)
        try container.encodeIfPresent(returnWindowHours, forKey: .returnWindowHours)
        try container.encodeIfPresent(vaultWatchID, forKey: .vaultWatchID)
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// The move to review, on its own, after the body: `{"status": "pending_review"}`.
public struct ListingStatusPatch: Encodable, Sendable {
    public let status: String
    public init(_ status: ListingStatus) { self.status = status.rawValue }
}
