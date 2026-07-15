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
    public let stats: ProfileStats
}

public struct SellerProfileSummary: Codable, Sendable {
    /// DealerProfile status: pending / approved / downgraded / rejected.
    public let status: String
    public let isVerifiedDealer: Bool
    public let dealerActiveUntil: Date?
    public let unlock: DealerUnlock?
}

/// Dealer-tier unlock progress (10 live listings → dealer pricing next month).
public struct DealerUnlock: Codable, Sendable {
    public let status: String
    public let isActive: Bool
    public let activeUntil: Date?
    public let liveListingCount: Int
    public let threshold: Int
    public let remainingToUnlock: Int
    public let nextMonthUnlocked: Bool
    public let currentFeePercent: APIDecimal
    public let memberFeePercent: APIDecimal
    public let dealerFeePercent: APIDecimal
    public let currentMonthLabel: String?
    public let nextMonthLabel: String?
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
