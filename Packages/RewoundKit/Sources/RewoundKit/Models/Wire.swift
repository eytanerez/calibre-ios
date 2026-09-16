import Foundation

// MARK: - Encodable conformances for the wire value types
//
// Models are Codable (not just Decodable) so the metadata/home-feed disk cache
// can round-trip them. Encoding is only ever used for that cache — the API
// itself is written with dedicated payload structs.

extension MediaURL: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url?.absoluteString ?? "")
    }
}

extension APIDecimal: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(value)")
    }
}

// MARK: - Status decoding

/// Decodes a lowercase snake_case wire status into `E`, falling back to the
/// given case for values this build doesn't know yet. New server statuses must
/// never crash the app.
func decodeWireStatus<E: RawRepresentable>(from decoder: Decoder, fallback: E) throws -> E where E.RawValue == String {
    let raw = try decoder.singleValueContainer().decode(String.self)
    return E(rawValue: raw) ?? fallback
}

// MARK: - Images

/// A listing's image array. Every recorded capture sends plain URL strings,
/// but the seller image-management endpoint uses object entries — this decodes
/// either shape so a backend-side unification can't break the app.
public struct ListingImageList: Codable, Sendable {
    public let urls: [MediaURL]

    public init(urls: [MediaURL]) {
        self.urls = urls
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var urls: [MediaURL] = []
        while !container.isAtEnd {
            if let media = try? container.decode(MediaURL.self) {
                urls.append(media)
            } else if let object = try? container.decode(ListingImage.self) {
                urls.append(object.url)
            } else {
                // Skip anything unrecognized rather than failing the listing.
                _ = try? container.decode(AnyIgnored.self)
            }
        }
        self.urls = urls
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for media in urls {
            try container.encode(media)
        }
    }
}

/// Consumes one arbitrary JSON value so unkeyed decoding can move past it.
struct AnyIgnored: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if (try? container.decode(Bool.self)) != nil { return }
        if (try? container.decode(Double.self)) != nil { return }
        if (try? container.decode(String.self)) != nil { return }
        if (try? container.decode([AnyIgnored].self)) != nil { return }
        _ = try container.decode([String: AnyIgnored].self)
    }
}
