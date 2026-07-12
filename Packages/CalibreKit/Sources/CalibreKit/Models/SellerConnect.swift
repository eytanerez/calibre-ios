import Foundation

// FIXTURE-PENDING: shape from `StripeConnectAccountSessionView.post` in
// app/api/views/stripe.py; verified live against the dev backend 2026-07-12.
/// `POST /stripe/connect/account-session` — the AccountSession the Stripe
/// Connect SDK consumes, plus readiness refreshed as part of the same call.
public struct ConnectAccountSession: Codable, Sendable {
    public let accountId: String?
    public let clientSecret: String
    public let readiness: SellerReadiness
}
