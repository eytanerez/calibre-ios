import Foundation

// FIXTURE-PENDING: recorded while the backend was mid-migration (login 500 —
// `users.apple_sub` column not yet applied to the dev DB). Shape taken from
// `AccountProfileView.get` in app/api/views/account.py; re-record
// account-profile.json once the backend settles.
/// `/account/profile` — the signed-in user's full profile with counters.
public struct Profile: Codable, Sendable, Identifiable {
    public let id: String
    public let email: String
    public let username: String
    public let firstName: String?
    public let lastName: String?
    public let phone: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let sellerProfile: SellerProfileSummary?
    /// Top-level dealer program state. Replaced the old nested `unlock`
    /// block when dealer status stopped being tied to listing volume.
    public let dealerApplication: DealerApplication?
    public let stats: ProfileStats
}

public struct SellerProfileSummary: Codable, Sendable {
    /// DealerProfile status: pending / approved / downgraded / rejected.
    public let status: String
    public let isVerifiedDealer: Bool
}

public struct ProfileStats: Codable, Sendable {
    public let orders: Int
    public let listings: Int
    public let liveListings: Int
    public let cart: Int
    public let watchlist: Int
    public let addresses: Int
}

// FIXTURE-PENDING: shape from `_serialize_address` in
// app/api/views/account.py.
/// A saved shipping/billing address.
public struct Address: Codable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let label: String?
    public let firstName: String?
    public let lastName: String?
    public let fullName: String?
    public let phone: String?
    public let line1: String
    public let line2: String?
    public let city: String
    public let region: String?
    public let postalCode: String
    /// ISO-2 country code.
    public let country: String
    public let isDefaultShipping: Bool
    public let isDefaultBilling: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
}

/// Create/update body for `/account/addresses`.
public struct AddressPayload: Encodable, Sendable {
    public var label: String?
    public var firstName: String?
    public var lastName: String?
    public var fullName: String?
    public var phone: String?
    public var line1: String
    public var line2: String?
    public var city: String
    public var region: String?
    public var postalCode: String
    public var country: String
    public var isDefaultShipping: Bool?
    public var isDefaultBilling: Bool?

    public init(
        label: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        fullName: String? = nil,
        phone: String? = nil,
        line1: String,
        line2: String? = nil,
        city: String,
        region: String? = nil,
        postalCode: String,
        country: String = "US",
        isDefaultShipping: Bool? = nil,
        isDefaultBilling: Bool? = nil
    ) {
        self.label = label
        self.firstName = firstName
        self.lastName = lastName
        self.fullName = fullName
        self.phone = phone
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.isDefaultShipping = isDefaultShipping
        self.isDefaultBilling = isDefaultBilling
    }
}

// FIXTURE-PENDING: shape from `_serialize_cart_item` in
// app/api/views/account.py.
/// One `/cart` row. The one-watch cart swap semantics live in the UI layer.
public struct CartItem: Codable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let listingId: String
    public let note: String?
    public let listing: ListingSummary?
    public let createdAt: Date?
    public let updatedAt: Date?
}

// FIXTURE-PENDING: shape from `_serialize_watchlist_item` in
// app/api/views/account.py.
/// One `/watchlist` row (a saved listing).
public struct WatchlistItem: Codable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let listingId: String
    public let listing: ListingSummary?
    public let createdAt: Date?
    public let updatedAt: Date?
}

/// `saved_payment_method_payload` in app/services/offers.py — the buyer's
/// current default card. Appears both bare (nested inside
/// `BillingSetupIntent`/`PaymentMethodInfo`) and standalone.
public struct SavedPaymentMethod: Codable, Sendable, Identifiable {
    public let id: String
    public let brand: String?
    public let last4: String?
    public let expMonth: Int?
    public let expYear: Int?
    public let addedAt: Date?
}

/// `GET /account/payment-method` — confirmed against
/// `AccountPaymentMethodView.get` in Backend/app/api/views/offers.py. A
/// wrapper envelope, not a bare `SavedPaymentMethod?`: it also carries
/// whether removal is currently allowed (an active hold or an
/// accepted-unpaid offer locks it) and, when blocked, the backend's own
/// explanation.
public struct PaymentMethodInfo: Decodable, Sendable {
    public let stripeCustomerId: String?
    public let paymentMethod: SavedPaymentMethod?
    public let canRemove: Bool
    public let removeBlockedReason: String?
}

/// One card in the wallet, from `GET /account/payment-methods`.
public struct WalletCard: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let brand: String?
    public let last4: String?
    public let expMonth: Int?
    public let expYear: Int?
    public let isDefault: Bool
    /// This is the seller's guarantee card, not a card for spending.
    ///
    /// One Stripe customer holds both, and a seller who used the same card for
    /// each has two rows that are the same four digits and the same expiry —
    /// so nothing on screen can tell them apart without this. It is not a
    /// payment method: it is what a counterfeit or misrepresentation charge
    /// lands on, and buyer checkout must not offer it.
    public let isSellerCard: Bool
    /// Whether this particular card may be detached right now. False on the
    /// seller's guarantee card, and on the default while a hold is live.
    public let canRemove: Bool
    /// The server's own sentence for why not, when it says no.
    public let removeBlockedReason: String?

    public var displayName: String {
        "\(brand?.capitalized ?? "Card") •••• \(last4 ?? "----")"
    }

    public var expiryLabel: String? {
        guard let expMonth, let expYear else { return nil }
        return String(format: "Expires %02d/%02d", expMonth, expYear % 100)
    }

    /// The date as a card carries it — two digits over two, and no word,
    /// because the card face prints "Expires" itself. Saying it twice is how
    /// "Expires Expires 08/27" reaches a screen.
    public var expiryPrinted: String? {
        guard let expMonth, let expYear else { return nil }
        return String(format: "%02d / %02d", expMonth, expYear % 100)
    }

    enum CodingKeys: String, CodingKey {
        case id, brand, last4, expMonth, expYear, isDefault, isSellerCard, canRemove, removeBlockedReason
    }

    /// Written out rather than synthesized so the three keys added later do
    /// not make this fail to decode against a server that predates them. A
    /// card no one has told us about is an ordinary, removable card.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        last4 = try container.decodeIfPresent(String.self, forKey: .last4)
        expMonth = try container.decodeIfPresent(Int.self, forKey: .expMonth)
        expYear = try container.decodeIfPresent(Int.self, forKey: .expYear)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isSellerCard = try container.decodeIfPresent(Bool.self, forKey: .isSellerCard) ?? false
        canRemove = try container.decodeIfPresent(Bool.self, forKey: .canRemove) ?? true
        removeBlockedReason = try container.decodeIfPresent(String.self, forKey: .removeBlockedReason)
    }
}

/// `GET /account/payment-methods` — every card on the Stripe customer, with
/// which one offers place their hold on.
public struct WalletInfo: Decodable, Sendable {
    public let paymentMethods: [WalletCard]
    public let defaultPaymentMethodId: String?
    /// The seller's guarantee card, when this account has one. Also flagged on
    /// the card itself; carried here so a caller can name it without walking
    /// the list.
    public let sellerCardPaymentMethodId: String?
    public let canRemove: Bool
    public let removeBlockedReason: String?

    /// Every card that may actually be spent from — the guarantee card is a
    /// promise, not a payment method.
    public var spendableCards: [WalletCard] {
        paymentMethods.filter { !$0.isSellerCard && $0.id != sellerCardPaymentMethodId }
    }
}

/// A mobile-only Stripe CustomerSession secret. Distinct from the flat
/// `customer_session` the backend also returns for the web `payment_element`
/// component — that one does not work with PaymentSheet.
public struct CustomerSessionHandle: Decodable, Sendable {
    public let clientSecret: String
    public let expiresAt: Int?
}

/// `POST /billing/setup-intent` — confirmed against
/// Backend/docs/mobile-api.md §"POST /billing/setup-intent (response
/// extended)" and `AccountBillingSetupIntentView` in
/// Backend/app/api/views/offers.py. A SetupIntent for the account Payment
/// Method page's Add/Replace card flow. Confirm `setupIntent.clientSecret`
/// with PaymentSheet's setup mode using `customerSessionMobile`, same as
/// checkout confirms a PaymentIntent with its own CustomerSession.
public struct BillingSetupIntent: Decodable, Sendable {
    public let setupIntent: PaymentIntentHandle
    public let publishableKey: String
    public let customerId: String?
    /// PaymentSheet needs the *mobile* CustomerSession specifically — the
    /// backend's flat `customer_session` only enables the web
    /// `payment_element` component. Nil when Stripe hiccuped; PaymentSheet
    /// still works without it, just without saved-payment-method UI polish.
    public let customerSessionMobile: CustomerSessionHandle?
    /// The buyer's card as of this call — stale until the async webhook
    /// that confirms the SetupIntent updates it, which is why the caller
    /// must poll `paymentMethod()` after PaymentSheet reports `.completed`
    /// rather than trust this snapshot.
    public let paymentMethod: SavedPaymentMethod?
}

/// One thing standing between a customer and account deletion — a live
/// order, an outstanding payout, money in flight, an active return, or an
/// accepted offer. Shown verbatim so the customer knows exactly what's left.
public struct AccountObligation: Codable, Sendable, Identifiable {
    public let kind: String
    public let reference: String?
    public let detail: String?

    enum CodingKeys: String, CodingKey {
        case kind, reference, detail
    }

    public var id: String { kind + "-" + (reference ?? detail ?? "") }
}

// FIXTURE-PENDING: the endpoint 404s until the other agent's notification
// routes land; shape from migration 20260711_0018 / models/notifications.py.
/// Per-user push notification toggles — all on by default.
public struct NotificationPreferences: Codable, Sendable {
    public let offerUpdates: Bool
    public let orderUpdates: Bool
    public let trackingUpdates: Bool
    public let messageUpdates: Bool
    public let watchlistAlerts: Bool
    public let marketUpdates: Bool
    public let securityAlerts: Bool
}
