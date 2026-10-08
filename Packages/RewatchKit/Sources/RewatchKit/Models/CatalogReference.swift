import Foundation

/// A catalog row as `GET /catalog/references` returns it: the reference, a
/// name ready to print, and whatever specs the catalog holds for it.
public struct CatalogReference: Decodable, Sendable, Identifiable, Equatable {
    /// The server's ceiling on `limit` (the site's
    /// `CATALOG_REFERENCE_SEARCH_MAX_LIMIT`).
    public static let searchMaxLimit = 20

    public let id: String
    public let brand: String
    public let model: String?
    public let reference: String?
    public let displayName: String
    /// The reference's own specs, read off the same row. Nil when none of them
    /// could be read.
    public let specs: ListingSpecs?

    enum CodingKeys: String, CodingKey {
        case id, brand, model, reference, displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        brand = try container.decode(String.self, forKey: .brand)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        let named = try container.decodeIfPresent(String.self, forKey: .displayName)
        displayName = named ?? [brand, model, reference].compactMap { $0 }.joined(separator: " ")
        specs = try? ListingSpecs(from: decoder)
    }

    public init(
        id: String,
        brand: String,
        model: String?,
        reference: String?,
        displayName: String,
        specs: ListingSpecs? = nil
    ) {
        self.id = id
        self.brand = brand
        self.model = model
        self.reference = reference
        self.displayName = displayName
        self.specs = specs
    }

    public static func == (lhs: CatalogReference, rhs: CatalogReference) -> Bool {
        lhs.id == rhs.id
    }

    /// The server's matching key (`normalize_key`): trimmed, whitespace
    /// collapsed, casefolded.
    public static func key(_ value: String?) -> String {
        (value ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Whether this row is the watch those three name: all three equal on the
    /// server's key. The site's rule, unchanged.
    public func matches(brand: String, model: String, reference: String) -> Bool {
        Self.key(self.brand) == Self.key(brand)
            && Self.key(self.model) == Self.key(model)
            && Self.key(self.reference) == Self.key(reference)
    }

    /// The short facts the site prints as chips once a watch matched:
    /// diameter, material, movement, dial, bracelet, water resistance.
    public var specChips: [String] {
        guard let specs else { return [] }
        var chips: [String] = []
        if let diameter = specs.diameterMm, diameter > 0 { chips.append("\(diameter) mm") }
        if let material = specs.material, !material.isEmpty { chips.append(material) }
        if let movement = specs.movement, !movement.isEmpty { chips.append(movement) }
        if let dial = specs.dial, !dial.isEmpty { chips.append("\(dial) dial") }
        if let bracelet = specs.bracelet, !bracelet.isEmpty { chips.append(bracelet) }
        if let water = specs.waterResistanceM, water > 0 { chips.append("\(water) m") }
        return chips
    }
}

/// What `GET /catalog/references` answers. `total` and `truncated` are absent
/// on a server that predates them, which says nothing about whether rows were
/// left behind; `isPartial` reads a full page as possibly partial then.
public struct CatalogReferenceSearch: Decodable, Sendable {
    public let results: [CatalogReference]
    public let total: Int?
    public let truncated: Bool?

    public init(results: [CatalogReference], total: Int? = nil, truncated: Bool? = nil) {
        self.results = results
        self.total = total
        self.truncated = truncated
    }

    public var isPartial: Bool {
        truncated ?? (results.count >= CatalogReference.searchMaxLimit)
    }
}
