import Foundation

/// Everything `GET /listings` accepts. Hashable so it doubles as the page
/// cache key in `CatalogStore`.
public struct ListingQuery: Hashable, Sendable {
    public enum Sort: String, Sendable, CaseIterable {
        case priceAsc = "price_asc"
        case priceDesc = "price_desc"
        case createdAsc = "created_asc"
        case createdDesc = "created_desc"
        case mostViewed = "most_viewed"
        case popular
    }

    public enum View: String, Sendable {
        case full
        case card
    }

    public var search: String?
    public var seller: String?
    public var brand: String?
    public var model: String?
    public var reference: String?
    public var priceMin: Decimal?
    public var priceMax: Decimal?
    public var condition: String?
    public var boxPapers: Bool?
    public var year: Int?
    public var material: String?
    public var color: String?
    public var caseSize: String?
    public var movement: String?
    public var bracelet: String?
    public var thickness: String?
    public var lugWidth: String?
    public var waterResistance: String?
    public var caliber: String?
    public var sort: Sort?
    public var page: Int
    public var pageSize: Int
    public var view: View
    public var includeTotal: Bool

    public init(
        search: String? = nil,
        seller: String? = nil,
        brand: String? = nil,
        model: String? = nil,
        reference: String? = nil,
        priceMin: Decimal? = nil,
        priceMax: Decimal? = nil,
        condition: String? = nil,
        boxPapers: Bool? = nil,
        year: Int? = nil,
        material: String? = nil,
        color: String? = nil,
        caseSize: String? = nil,
        movement: String? = nil,
        bracelet: String? = nil,
        thickness: String? = nil,
        lugWidth: String? = nil,
        waterResistance: String? = nil,
        caliber: String? = nil,
        sort: Sort? = nil,
        page: Int = 1,
        pageSize: Int = 24,
        view: View = .card,
        includeTotal: Bool = true
    ) {
        self.search = search
        self.seller = seller
        self.brand = brand
        self.model = model
        self.reference = reference
        self.priceMin = priceMin
        self.priceMax = priceMax
        self.condition = condition
        self.boxPapers = boxPapers
        self.year = year
        self.material = material
        self.color = color
        self.caseSize = caseSize
        self.movement = movement
        self.bracelet = bracelet
        self.thickness = thickness
        self.lugWidth = lugWidth
        self.waterResistance = waterResistance
        self.caliber = caliber
        self.sort = sort
        self.page = page
        self.pageSize = pageSize
        self.view = view
        self.includeTotal = includeTotal
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            if let value, !value.isEmpty {
                items.append(URLQueryItem(name: name, value: value))
            }
        }
        add("search", search)
        add("seller", seller)
        add("brand", brand)
        add("model", model)
        add("reference", reference)
        add("price_min", priceMin.map { "\($0)" })
        add("price_max", priceMax.map { "\($0)" })
        add("condition", condition)
        add("box_papers", boxPapers.map { $0 ? "true" : "false" })
        add("year", year.map(String.init))
        add("material", material)
        add("color", color)
        add("case_size", caseSize)
        add("movement", movement)
        add("bracelet", bracelet)
        add("thickness", thickness)
        add("lug_width", lugWidth)
        add("water_resistance", waterResistance)
        add("caliber", caliber)
        add("sort", sort?.rawValue)
        add("page", String(page))
        add("page_size", String(pageSize))
        add("view", view.rawValue)
        add("include_total", includeTotal ? "true" : "false")
        return items
    }
}

/// A typed search suggestion produced locally from cached market metadata.
public struct SearchSuggestion: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable {
        case brand
        case model(brand: String?)
        case reference(brand: String?, model: String?)
    }

    public let text: String
    public let kind: Kind

    public var id: String { text }

    public static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
        lhs.text == rhs.text
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}
