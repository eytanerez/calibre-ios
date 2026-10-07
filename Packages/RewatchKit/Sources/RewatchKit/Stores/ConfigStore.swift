import Foundation
import Observation

/// The marketplace's own statement of its rates, minimums and windows.
///
/// Screens reach for this only to disclose a figure before the object that
/// would carry it exists — the offer hold before an offer, the return fee
/// before a return. A live breakdown, quote or payload figure always wins.
///
/// Public and cached on disk, because a disclosure that silently disappears
/// offline is worse than a slightly stale one.
@MainActor
@Observable
public final class ConfigStore {
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let cache = DiskCache<MarketplaceConfig>(filename: "marketplace-config.json")

    public private(set) var config: MarketplaceConfig?

    @ObservationIgnored private var loading = false

    public init(client: APIClient) {
        self.client = client
        config = cache.load()?.value
    }

    @discardableResult
    public func load() async throws -> MarketplaceConfig {
        if let config, loading { return config }
        loading = true
        defer { loading = false }
        do {
            let value: MarketplaceConfig = try await client.send(
                Endpoint(path: "/config/marketplace", requiresAuth: false)
            )
            config = value
            cache.save(value)
            return value
        } catch {
            if let config { return config }
            throw error
        }
    }

    /// Fire-and-forget refresh for screens that can render without it.
    public func warm() {
        Task { [weak self] in _ = try? await self?.load() }
    }

    // MARK: - Convenience

    /// The refundable hold an offer authorizes, formatted, or nil when the
    /// server hasn't told us yet — in which case the sentence is written
    /// without a number rather than with a guessed one.
    public var offerHoldText: String? {
        guard let amount = config?.offerHoldAmount else { return nil }
        return PriceFormatter.format(amount.value)
    }

    public var offerExpiryHours: Int? { config?.offerTtlHours }

    public var paymentGraceHours: Int? { config?.offerPaymentGraceHours }

    /// How long a buyer has to pay once an offer is accepted.
    public var paymentDeadlineHours: Int? { config?.offerPaymentDeadlineHours }

    /// The windows a seller may pick from; empty until the config lands.
    public var returnWindowChoices: [Int] { config?.returnWindows ?? [] }
}
