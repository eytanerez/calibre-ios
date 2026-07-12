import Foundation

/// A media URL as the backend sends it — absolute, or relative like
/// "/media/listing_images/…". Resolved against the API origin at decode time
/// so no view ever handles a relative path.
public struct MediaURL: Decodable, Sendable, Hashable {
    public let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let absolute = URL(string: raw), absolute.scheme != nil {
            url = absolute
        } else if let origin = decoder.userInfo[.apiOrigin] as? URL {
            url = URL(string: raw, relativeTo: origin)?.absoluteURL
        } else {
            url = URL(string: raw)
        }
    }
}

/// Money as the backend sends it — a JSON string ("12400.00") or number.
/// Always `Decimal`; float drift is not acceptable for prices.
public struct APIDecimal: Decodable, Sendable, Hashable {
    public let value: Decimal

    public init(_ value: Decimal) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad decimal string: \(string)")
            }
            value = decimal
        } else if let double = try? container.decode(Double.self) {
            value = Decimal(string: "\(double)") ?? Decimal(double)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected string or number")
        }
    }
}

/// Brand price formatting: whole dollars ("$12,400"), cents only when present
/// ("$12,400.50"). Currency defaults to USD — the marketplace's currency.
public enum PriceFormatter {
    public static func format(_ amount: Decimal, currency: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: "en_US")
        let isWhole = amount == amount.rounded(0)
        formatter.minimumFractionDigits = isWhole ? 0 : 2
        formatter.maximumFractionDigits = isWhole ? 0 : 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
