import Foundation

/// Where a seller stands in the dealer program. A dealer is a verified
/// business: the application is a second Stripe verification step, and
/// clearing it grants dealer status automatically — there is no queue.
public enum DealerApplicationStatus: String, Codable, Sendable {
    /// Never applied.
    case none
    /// Verification submitted, still being checked.
    case pending
    /// Verified — the dealer rate, the badge, and bulk tools are live.
    case verified
    /// Revoked for cause; existing listings stay live.
    case revoked
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// Top-level `dealer_application` on the profile and seller dashboard
/// payloads. Replaces the retired ten-listing `unlock` block: dealer status
/// is no longer earned by inventory volume.
///
/// Both fee percentages come from the server — no client may state a rate
/// that isn't in this payload.
public struct DealerApplication: Codable, Sendable {
    public let status: DealerApplicationStatus
    public let companyName: String?
    public let country: String?
    public let appliedAt: Date?
    public let verifiedAt: Date?
    /// Present on `revoked` — the backend's own plain-English explanation.
    public let revokedReason: String?
    /// The private-seller rate, e.g. "6.00".
    public let memberFeePercent: APIDecimal?
    /// The verified-dealer rate, e.g. "4.00".
    public let dealerFeePercent: APIDecimal?

    enum CodingKeys: String, CodingKey {
        case status, companyName, country, appliedAt, verifiedAt, revokedReason
        case memberFeePercent, dealerFeePercent
    }

    /// Whether an application has ever been made.
    ///
    /// Prefer these over comparing `status` through an optional chain: in
    /// `application?.status == .none`, Swift binds the bare `.none` to
    /// `Optional.none`, so the test silently means "is nil" instead of "has
    /// not applied". Both readings are plausible here, which is exactly what
    /// makes the bug quiet.
    public var hasApplied: Bool { status != .none }

    /// Dealer benefits are live: the dealer rate, the badge, and bulk tools.
    public var isVerified: Bool { status == .verified }

    public var isPending: Bool { status == .pending }

    public var isRevoked: Bool { status == .revoked }

    /// The rate that applies to this seller today, from the server.
    public var effectiveFeePercent: APIDecimal? {
        isVerified ? dealerFeePercent : memberFeePercent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(DealerApplicationStatus.self, forKey: .status) ?? .none
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        appliedAt = try container.decodeIfPresent(Date.self, forKey: .appliedAt)
        verifiedAt = try container.decodeIfPresent(Date.self, forKey: .verifiedAt)
        revokedReason = try container.decodeIfPresent(String.self, forKey: .revokedReason)
        memberFeePercent = try container.decodeIfPresent(APIDecimal.self, forKey: .memberFeePercent)
        dealerFeePercent = try container.decodeIfPresent(APIDecimal.self, forKey: .dealerFeePercent)
    }
}

/// `POST /account/dealer-application` — the created application plus the
/// embedded Connect onboarding session that collects the business details and
/// EIN. `409 connect_required` means payout onboarding has to happen first.
public struct DealerApplicationResult: Decodable, Sendable {
    public let application: DealerApplication
    public let stripe: StripeSession?

    /// The embedded-component client secret. Calibre never sees the banking
    /// details behind it; they stay with the processor.
    public struct StripeSession: Decodable, Sendable {
        public let clientSecret: String
    }
}
