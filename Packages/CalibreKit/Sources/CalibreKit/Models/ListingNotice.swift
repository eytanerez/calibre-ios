import Foundation

/// A watch this member had in their cart or on their saved list that has since
/// sold, and the row that promises they are told about it exactly once.
///
/// The listing itself is gone from `/cart` and `/watchlist` the moment the sale
/// lands, and it 404s for them afterwards — so the notice carries its own
/// snapshot of the watch. A row holding only an id would have nothing left to
/// render by the time anybody read it.
///
/// The pairing (member, listing) is unique on the server, which is what makes
/// "exactly once, per person, per listing" a property of the schema rather than
/// a promise the client is trusted to keep. The client's half of the bargain is
/// to acknowledge only what it has actually put on screen.
public struct ListingGoneNotice: Decodable, Sendable, Identifiable, Equatable {
    /// Where the watch was when it sold. `both` is a member who had it saved
    /// and in their cart; it is still one notice.
    public enum Source: String, Decodable, Sendable {
        case cart
        case saved
        case both
        case unknown

        public init(from decoder: Decoder) throws {
            self = try decodeWireStatus(from: decoder, fallback: .unknown)
        }
    }

    public let id: String
    public let listingId: String
    public let listingNumber: Int?
    /// "sold" today. More reasons are possible later, so this is not an enum
    /// with an exhaustive switch behind it.
    public let reason: String
    public let source: Source
    public let title: String?
    public let image: MediaURL?
    /// A decimal as a string, exactly as the server sends money everywhere
    /// else. Nil when the snapshot has no price.
    public let price: String?
    public let currency: String
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, listingId, listingNumber, reason, source, title, image, price, currency, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        listingId = try container.decode(String.self, forKey: .listingId)
        listingNumber = ((try? container.decodeIfPresent(Int.self, forKey: .listingNumber)) ?? nil)
        reason = ((try? container.decodeIfPresent(String.self, forKey: .reason)) ?? nil) ?? "sold"
        source = ((try? container.decodeIfPresent(Source.self, forKey: .source)) ?? nil) ?? .unknown
        title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil)
        image = ((try? container.decodeIfPresent(MediaURL.self, forKey: .image)) ?? nil)
        price = ((try? container.decodeIfPresent(String.self, forKey: .price)) ?? nil)
        currency = ((try? container.decodeIfPresent(String.self, forKey: .currency)) ?? nil) ?? "USD"
        // The one notice this member will ever get about this watch must not
        // be lost to a timestamp the shared ISO-8601 strategy cannot read.
        // Nothing on the banner depends on the stamp; the ordering is the
        // server's and is already applied.
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
    }

    public init(
        id: String,
        listingId: String,
        listingNumber: Int? = nil,
        reason: String = "sold",
        source: Source = .saved,
        title: String? = nil,
        image: MediaURL? = nil,
        price: String? = nil,
        currency: String = "USD",
        createdAt: Date? = nil
    ) {
        self.id = id
        self.listingId = listingId
        self.listingNumber = listingNumber
        self.reason = reason
        self.source = source
        self.title = title
        self.image = image
        self.price = price
        self.currency = currency
        self.createdAt = createdAt
    }

    /// The price as a number, for the one formatter every other price on the
    /// phone goes through.
    public var priceValue: Decimal? {
        price.flatMap { Decimal(string: $0) }
    }
}

/// `GET /listing-notices` — what is pending for this member right now.
public struct ListingGoneNoticePage: Decodable, Sendable {
    public let notices: [ListingGoneNotice]
    /// More pending than this page carried. The remainder is served on the
    /// next read; nothing is dropped.
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case notices, hasMore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notices = ((try? container.decodeIfPresent([ListingGoneNotice].self, forKey: .notices)) ?? nil) ?? []
        hasMore = ((try? container.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? nil) ?? false
    }

    public init(notices: [ListingGoneNotice], hasMore: Bool = false) {
        self.notices = notices
        self.hasMore = hasMore
    }
}
