import Foundation

/// Shared validation for user-entered form values. Views should still show
/// field-specific copy, but submission guards use these rules so a disabled
/// button can never be bypassed by a rapid tap or direct action call.
public enum InputValidation {
    public static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isNonBlank(_ value: String) -> Bool {
        !trimmed(value).isEmpty
    }

    /// A deliberately practical email check: one `@`, a non-empty local
    /// part, and a dotted DNS-style host with no whitespace or empty labels.
    /// The server remains authoritative for delivery and uniqueness.
    public static func isValidEmail(_ value: String) -> Bool {
        let candidate = trimmed(value)
        guard candidate.count <= 254,
              !candidate.contains(where: { $0.isWhitespace }),
              !candidate.hasPrefix("."),
              !candidate.contains("..") else { return false }

        let pieces = candidate.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              !pieces[0].isEmpty,
              pieces[0].count <= 64,
              !pieces[0].hasSuffix(".") else { return false }

        let labels = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-" else { return false }
            return label.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-")
            }
        }
    }

    /// E.164 permits at most 15 digits. Formatting punctuation is ignored.
    public static func isValidPhone(_ value: String, required: Bool = true) -> Bool {
        let candidate = trimmed(value)
        if candidate.isEmpty { return !required }
        guard candidate.allSatisfy({ $0.isNumber || $0.isWhitespace || "+-().".contains($0) }) else {
            return false
        }
        return (7...15).contains(candidate.filter(\.isNumber).count)
    }

    public static func isISO2CountryCode(_ value: String) -> Bool {
        let candidate = trimmed(value)
        return candidate.count == 2 && candidate.allSatisfy { $0.isASCII && $0.isLetter }
    }

    /// Parses ordinary positive currency input and rejects signs, exponent
    /// notation, multiple separators, zero, and excess fractional precision.
    public static func positiveMoney(_ value: String, maximumFractionDigits: Int = 2) -> Decimal? {
        let candidate = trimmed(value)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
        guard !candidate.isEmpty else { return nil }

        var decimalSeparators = 0
        var fractionalDigits = 0
        var afterSeparator = false
        for character in candidate {
            if character == "." {
                decimalSeparators += 1
                afterSeparator = true
            } else if character.isASCII && character.isNumber {
                if afterSeparator { fractionalDigits += 1 }
            } else {
                return nil
            }
        }
        guard decimalSeparators <= 1,
              fractionalDigits <= maximumFractionDigits,
              let amount = Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX")),
              amount > 0 else { return nil }
        return amount
    }

    public static func productionYear(_ value: String, currentYear: Int = Calendar.current.component(.year, from: Date())) -> Int? {
        let candidate = trimmed(value)
        guard candidate.count == 4,
              candidate.allSatisfy({ $0.isASCII && $0.isNumber }),
              let year = Int(candidate),
              (1600...(currentYear + 1)).contains(year) else { return nil }
        return year
    }

    public static func passwordMeetsRules(_ value: String) -> Bool {
        value.count >= 8
            && value.contains(where: \.isUppercase)
            && value.contains(where: \.isNumber)
    }
}

/// A media URL as the backend sends it — absolute, or relative like
/// "/media/listing_images/…". Resolved against the API origin at decode time
/// so no view ever handles a relative path. Development-only absolute media
/// hosts (for example `localhost:5173`) are also rebased to the API origin;
/// those URLs otherwise work on the laptop but can never work on a device.
public struct MediaURL: Decodable, Sendable, Hashable {
    public let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            url = nil
            return
        }

        let origin = decoder.userInfo[.apiOrigin] as? URL
        guard let parsed = URL(string: raw), parsed.scheme != nil else {
            url = origin.flatMap { URL(string: raw, relativeTo: $0)?.absoluteURL }
                ?? URL(string: raw)
            return
        }

        if let origin,
           parsed.path.hasPrefix("/media/"),
           (parsed.scheme?.lowercased() != "https" || Self.isInternalHost(parsed.host)) {
            var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
            components?.path = parsed.path
            components?.query = parsed.query
            components?.fragment = parsed.fragment
            url = components?.url
            return
        }
        url = parsed
    }

    private static func isInternalHost(_ hostname: String?) -> Bool {
        guard let host = hostname?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "0.0.0.0"
            || host == "backend"
            || host == "host.docker.internal"
            || host.hasSuffix(".internal")
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
