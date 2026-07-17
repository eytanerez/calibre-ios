import Foundation
import Observation

/// The member's Collection. Calibre purchases land here automatically on
/// delivery; manual adds cover watches bought elsewhere.
@MainActor
@Observable
public final class VaultStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var watches: [VaultWatch] = []

    public init(client: APIClient) {
        self.client = client
    }

    @discardableResult
    public func load() async throws -> [VaultWatch] {
        struct Response: Decodable { let results: [VaultWatch] }
        let response: Response = try await client.send(Endpoint(path: "/vault"))
        watches = response.results
        return response.results
    }

    @discardableResult
    public func add(
        brand: String,
        model: String? = nil,
        reference: String? = nil,
        productionYear: Int? = nil,
        acquiredPrice: String? = nil
    ) async throws -> VaultWatch {
        struct Payload: Encodable {
            let brand: String
            let model: String?
            let reference: String?
            let productionYear: Int?
            let acquiredPrice: String?
        }
        let created: VaultWatch = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/vault",
                payload: Payload(
                    brand: brand,
                    model: model,
                    reference: reference,
                    productionYear: productionYear,
                    acquiredPrice: acquiredPrice
                )
            )
        )
        watches.insert(created, at: 0)
        return created
    }

    public func remove(id: String) async throws {
        struct Response: Decodable { let deleted: Bool }
        let _: Response = try await client.send(Endpoint(method: .delete, path: "/vault/\(id)"))
        watches.removeAll { $0.id == id }
    }

    public func reset() {
        watches = []
    }

    /// Sum of cached estimates, for the header tile.
    public var estimatedTotal: Double {
        watches.reduce(0) { total, watch in
            total + (Double(watch.estimatedValue ?? "") ?? 0)
        }
    }
}
