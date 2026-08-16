import Foundation

/// `GET /account/listings/{id}/publish-preview` — the server's answer to
/// "what do I actually take home, and what will a buyer see?".
///
/// Every number here is computed by the backend, including whether the
/// minimum commission applied. Clients render these figures; they never
/// derive them.
public struct ListingPublishPreview: Decodable, Sendable {
    public let price: APIDecimal
    public let currency: String
    public let commission: Commission
    public let netProceeds: APIDecimal
    public let buyerDisplay: BuyerDisplay
    /// The seller's estimated inbound label. Decoded leniently — an
    /// unexpected shape must not cost the seller their payout figure.
    public let shippingEstimate: ShippingEstimate?
    public let returns: ListingReturnTerms?

    public struct Commission: Decodable, Sendable {
        public let percent: APIDecimal
        public let amount: APIDecimal
        /// True when the flat minimum, not the percentage, set the amount.
        public let minimumApplied: Bool
        public let minimum: APIDecimal

        enum CodingKeys: String, CodingKey {
            case percent, amount, minimumApplied, minimum
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            percent = try container.decode(APIDecimal.self, forKey: .percent)
            amount = try container.decode(APIDecimal.self, forKey: .amount)
            minimumApplied = try container.decodeIfPresent(Bool.self, forKey: .minimumApplied) ?? false
            minimum = try container.decode(APIDecimal.self, forKey: .minimum)
        }
    }

    /// What the buyer sees, by presentation mode. In the discount states the
    /// listed price is shown as the card price and wire earns a discount off
    /// it — the final total is identical either way.
    public struct BuyerDisplay: Decodable, Sendable {
        public let standard: Standard
        public let discountStates: DiscountStates?

        public struct Standard: Decodable, Sendable {
            public let price: APIDecimal
        }

        public struct DiscountStates: Decodable, Sendable {
            public let price: APIDecimal
            public let wirePrice: APIDecimal
            public let states: [String]

            enum CodingKeys: String, CodingKey {
                case price, wirePrice, states
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                price = try container.decode(APIDecimal.self, forKey: .price)
                wirePrice = try container.decode(APIDecimal.self, forKey: .wirePrice)
                states = try container.decodeIfPresent([String].self, forKey: .states) ?? []
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case price, currency, commission, netProceeds, buyerDisplay
        case shippingEstimate, returns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        price = try container.decode(APIDecimal.self, forKey: .price)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        commission = try container.decode(Commission.self, forKey: .commission)
        netProceeds = try container.decode(APIDecimal.self, forKey: .netProceeds)
        buyerDisplay = try container.decode(BuyerDisplay.self, forKey: .buyerDisplay)
        shippingEstimate = try? container.decodeIfPresent(ShippingEstimate.self, forKey: .shippingEstimate)
        returns = try? container.decodeIfPresent(ListingReturnTerms.self, forKey: .returns)
    }
}
