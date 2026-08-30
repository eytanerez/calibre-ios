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

/// Money as it should look *while it is being typed* — grouping separators
/// appear under the caret, the way CALIBRE_FINAL_PUSH_CONTRACTS.md §6 asks
/// for across the site, the admin and both apps.
///
/// This is deliberately not `PriceFormatter`. `PriceFormatter.format` renders
/// a finished `Decimal` with a currency symbol; a field being typed into holds
/// a half-finished *string* — "12,4", "12400.", "0.5" — and none of those are
/// a `Decimal` yet. Round-tripping through `Decimal` would delete the trailing
/// separator the moment it was typed, so the person could never reach the
/// cents. The rules here therefore work on characters:
///
/// - keep digits and at most one `.`, drop everything else (including the `$`
///   and any separators the person pasted in);
/// - group the integer part in threes;
/// - keep a trailing `.` and up to `maximumFractionDigits` after it, so the
///   caret can sit past the point while the cents are still being typed;
/// - never re-group the fraction.
///
/// The submitted value stays the field's own text: `InputValidation.positiveMoney`
/// already strips `,` and `$` before parsing (Values.swift), so the server sees
/// the same number it always did.
public enum MoneyInputFormatter {
    public static func format(_ raw: String, maximumFractionDigits: Int = 2) -> String {
        var integerDigits = ""
        var fractionDigits = ""
        var sawSeparator = false
        for character in raw {
            if character == "." {
                // A second separator is a typo, not a number.
                if sawSeparator { continue }
                sawSeparator = true
            } else if character.isASCII && character.isNumber {
                if sawSeparator {
                    if fractionDigits.count < maximumFractionDigits {
                        fractionDigits.append(character)
                    }
                } else {
                    integerDigits.append(character)
                }
            }
        }

        // "007" is a keystroke on the way to "700", but "0007" is not a price.
        // One leading zero survives so "0.5" can be typed.
        while integerDigits.count > 1, integerDigits.hasPrefix("0") {
            integerDigits.removeFirst()
        }

        let grouped = groupInThrees(integerDigits)
        if sawSeparator {
            return grouped.isEmpty ? "0.\(fractionDigits)" : "\(grouped).\(fractionDigits)"
        }
        return grouped
    }

    private static func groupInThrees(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var out = ""
        for (offset, character) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 {
                out.append(",")
            }
            out.append(character)
        }
        return out
    }
}

/// US phone numbers as they are typed: `(415) 555-0134`.
///
/// US only, per CALIBRE_FINAL_PUSH_CONTRACTS.md §6 and §7. A leading `+1` or a
/// bare leading `1` on an 11-digit string is the country code and is dropped —
/// a person typing their own number often starts with it, and `(1) 415-555-01`
/// is not a phone number anyone recognises.
///
/// Anything that is not ten US digits is left as the person typed it rather
/// than forced into the shape: a half-typed number formats progressively
/// ("415" → "(415)"), and a number that cannot be American at all (more than
/// ten digits after the country code) is returned untouched so the field never
/// silently deletes what someone entered.
public enum PhoneFormatter {
    /// The digits a US number is stored and submitted as — ten, no country
    /// code, no punctuation. Nil when the input is not a US number.
    public static func nationalDigits(_ raw: String) -> String? {
        var digits = raw.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") {
            digits.removeFirst()
        }
        return digits.count == 10 ? digits : nil
    }

    /// Progressive formatting for a field being typed into.
    ///
    /// No punctuation is added until the digit *after* the one it would
    /// follow has been typed. That is not cosmetic: a formatter that closes
    /// the bracket at three digits renders "(415)", and the backspace that
    /// deletes the ")" leaves "(415", which re-formats straight back to
    /// "(415)" — the field stops accepting deletions and the person is stuck.
    /// Adding each separator one digit late means every backspace removes a
    /// digit and the number unwinds exactly the way it was built.
    public static func format(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        // Only strip the country code once there is a national number behind
        // it, or the "1" of "1-415-…" would vanish as it was typed.
        if digits.count > 10, digits.hasPrefix("1") {
            digits.removeFirst()
        }
        guard digits.count <= 10 else { return raw }

        switch digits.count {
        case 0...3:
            return String(digits)
        case 4...6:
            let area = digits.prefix(3)
            let exchange = digits.dropFirst(3)
            return "(\(area)) \(exchange)"
        default:
            let area = digits.prefix(3)
            let exchange = digits.dropFirst(3).prefix(3)
            let line = digits.dropFirst(6)
            return "(\(area)) \(exchange)-\(line)"
        }
    }

    /// Formatting for a value that arrived from the server and is only being
    /// read. A number that is not a ten-digit US one is shown exactly as
    /// stored — §0.6 forbids hiding data, and a foreign number that predates
    /// the US-only rule is still that member's real number.
    public static func display(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let digits = nationalDigits(raw) else { return raw }
        let area = digits.prefix(3)
        let exchange = digits.dropFirst(3).prefix(3)
        let line = digits.dropFirst(6)
        return "(\(area)) \(exchange)-\(line)"
    }
}
