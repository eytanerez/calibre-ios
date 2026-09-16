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
    /// The rate this seller is actually quoted, resolved the way checkout
    /// resolves it — a negotiated override included. Always prefer this to
    /// picking a published tier rate, which an override would contradict at
    /// the sale.
    public let effectiveFeePercentApplied: APIDecimal?

    enum CodingKeys: String, CodingKey {
        case status, companyName, country, appliedAt, verifiedAt, revokedReason
        case memberFeePercent, dealerFeePercent
        case effectiveFeePercentApplied = "effectiveFeePercent"
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

    /// The rate that applies to this seller today, from the server. The
    /// server's own resolved figure wins; the tier rates only stand in for a
    /// payload written before it existed.
    public var effectiveFeePercent: APIDecimal? {
        effectiveFeePercentApplied ?? (isVerified ? dealerFeePercent : memberFeePercent)
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
        effectiveFeePercentApplied = try? container.decodeIfPresent(
            APIDecimal.self, forKey: .effectiveFeePercentApplied
        )
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

/// Where a verified dealer's storefront line stands.
///
/// `null` on the wire — not a word — when nothing was ever submitted, which
/// is the state almost every dealer is in. It is what keeps them out of the
/// moderation queue, and rendering "pending" for a dealer who has never
/// written one would be the app inventing a state the server does not have.
public enum DealerBioStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// `GET|PUT /account/dealer/bio` — the storefront line as its author sees it.
///
/// `bio` and `live` differ mid-edit and that is the point: the words waiting
/// on a reviewer are the dealer's, and the words a buyer is reading are the
/// last ones that cleared. The editor shows `bio`; a storefront shows `live`.
public struct DealerBio: Decodable, Sendable {
    /// What the dealer last submitted, reviewed or not.
    public let bio: String?
    /// Nil when nothing has ever been submitted.
    public let status: DealerBioStatus?
    /// What a buyer sees right now.
    public let live: String?
    public let submittedAt: Date?
    public let reviewedAt: Date?
    /// The reviewer's own sentence, on a rejection. Never written here.
    public let rejectedReason: String?

    /// One line, and the reviewer reads it before a buyer does.
    public static let characterLimit = 160

    /// A line is with a reviewer and cannot be edited into approval by
    /// resubmitting it.
    public var isAwaitingReview: Bool { status == .pending }

    /// The dealer has written something the storefront is not showing —
    /// either it is still in review, or it came back.
    public var hasUnpublishedEdit: Bool {
        guard let status else { return false }
        return status != .approved
    }
}
