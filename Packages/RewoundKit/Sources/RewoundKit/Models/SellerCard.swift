import Foundation

/// `GET /account/seller-card` — the credit card a seller keeps on file.
///
/// Credit only: a non-credit card is detached server-side after the
/// SetupIntent succeeds, and the seller is told a credit card is required.
/// The card is what a counterfeit or misrepresentation charge lands on, and
/// an expiring one is surfaced before it lapses.
public struct SellerCardState: Decodable, Sendable {
    public let present: Bool
    public let brand: String?
    public let last4: String?
    public let expMonth: Int?
    public let expYear: Int?
    /// "credit", "debit" or "prepaid" as the network reports it.
    public let funding: String?
    /// The server's verdict on whether this card is usable today.
    public let valid: Bool?
    public let expiringSoon: Bool?

    enum CodingKeys: String, CodingKey {
        case present, brand, last4, expMonth, expYear, funding, valid, expiringSoon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        present = try container.decodeIfPresent(Bool.self, forKey: .present) ?? false
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        last4 = try container.decodeIfPresent(String.self, forKey: .last4)
        expMonth = try container.decodeIfPresent(Int.self, forKey: .expMonth)
        expYear = try container.decodeIfPresent(Int.self, forKey: .expYear)
        funding = try container.decodeIfPresent(String.self, forKey: .funding)
        valid = try container.decodeIfPresent(Bool.self, forKey: .valid)
        expiringSoon = try container.decodeIfPresent(Bool.self, forKey: .expiringSoon)
    }

    public var displayName: String {
        "\(brand?.capitalized ?? "Card") •••• \(last4 ?? "----")"
    }

    public var expiryLabel: String? {
        guard let expMonth, let expYear else { return nil }
        return String(format: "%02d/%02d", expMonth, expYear % 100)
    }

    /// True when a banner is owed: no card, an invalid one, or one about to
    /// lapse.
    public var needsAttention: Bool {
        !present || valid == false || expiringSoon == true
    }
}

/// `POST /account/seller-card/setup-intent` — confirm `clientSecret` with the
/// SDK's SetupIntent handling, then re-read `GET /account/seller-card`.
public struct SellerCardSetupIntent: Decodable, Sendable {
    public let setupIntentId: String
    public let clientSecret: String
    public let status: String?
    public let creditCardRequired: Bool?
}
