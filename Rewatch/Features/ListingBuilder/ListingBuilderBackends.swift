import Foundation
import Observation
import RewatchKit
import UIKit

// MARK: - Live

/// The real thing: the same endpoints the site's builder calls.
@MainActor
final class LiveListingBuilderBackend: ListingBuilderBackend {
    let mode: BuilderMode = .live
    private let services: AppServices
    private let sell: SellSession

    init(services: AppServices, sell: SellSession) {
        self.services = services
        self.sell = sell
    }

    func cascade(_ query: CatalogCascadeQuery) async throws -> CatalogCascadeResponse {
        try await services.catalog.cascade(query)
    }

    func catalogReferences(term: String, brand: String, model: String) async throws -> CatalogReferenceSearch {
        try await services.catalog.references(matching: term, brand: brand, model: model)
    }

    func vaultMatches(reference: String) async throws -> [VaultMatch] {
        try await services.vault.matches(reference: reference)
    }

    func needsCustomsFields() async -> Bool {
        let country: String?
        if let known = services.seller.dashboard?.dealerApplication?.country {
            country = known
        } else {
            country = (try? await services.seller.dealerApplication())?.country
        }
        guard let country, !country.isEmpty else { return false }
        return country.uppercased() != "US"
    }

    func publishPreview(price: Decimal) async throws -> ListingPublishPreview {
        try await services.seller.publishPreview(price: price)
    }

    func shippingEstimate(price: Decimal) async throws -> ShippingEstimate {
        try await services.seller.shippingEstimate(listingPrice: price)
    }

    func createDraft(_ body: SellListingBody) async throws -> String {
        try await withBackgroundTime("Create listing draft") {
            try await self.services.seller.createListing(body: body).id
        }
    }

    func updateListing(id: String, body: SellListingBody) async throws {
        try await withBackgroundTime("Save listing") {
            _ = try await self.services.seller.updateListing(id: id, body: body)
        }
    }

    func moveToReview(id: String) async throws {
        let reviewed = try await withBackgroundTime("Submit listing") {
            try await self.services.seller.moveToReview(listingID: id)
        }
        Analytics.listingSubmitted(.init(reviewed), source: Analytics.listingSource(for: reviewed.id))
    }

    func fulfillWatchRequest(id: String, listingID: String) async {
        // Best effort: the listing is submitted either way.
        _ = try? await services.seller.fulfillWatchRequest(id: id, listingID: listingID)
    }

    func listingImages(listingID: String) async throws -> [ListingImage] {
        try await services.seller.images(listingID: listingID)
    }

    func enqueueUpload(listingID: String, fileURL: URL, category: ListingImageCategory?, sortIndex: Int) async -> UUID {
        await sell.uploads.enqueue(
            draftID: listingID,
            listingID: listingID,
            category: category?.rawValue,
            fileURL: fileURL,
            sortIndex: sortIndex
        )
    }

    func cancelUpload(_ jobID: UUID) async {
        await sell.uploads.cancel(jobID)
    }

    func deleteImage(listingID: String, imageID: String) async throws {
        try await services.seller.deleteImage(listingID: listingID, imageID: imageID)
    }

    func uploadStatus(_ jobID: UUID) -> BuilderUploadStatus? {
        guard let entry = sell.board.entry(for: jobID) else { return nil }
        let phase: BuilderUploadStatus.Phase = switch entry.state {
        case .queued: .queued
        case .uploading: .uploading(entry.fraction)
        case .done: .done
        case .failed: .failed(final: entry.gaveUp)
        }
        return BuilderUploadStatus(phase: phase, serverImageID: entry.serverImageID)
    }

    /// A request the seller just asked for keeps running for the half minute
    /// iOS allows after they switch away. The photos themselves need none of
    /// this: they go through the background session.
    private func withBackgroundTime<T>(_ name: String, _ work: () async throws -> T) async throws -> T {
        let id = UIApplication.shared.beginBackgroundTask(withName: name)
        defer {
            if id != .invalid { UIApplication.shared.endBackgroundTask(id) }
        }
        return try await work()
    }
}

// MARK: - Demo

/// The DEBUG preview harness's backend: the same screens, nothing written, a
/// small catalog and the published commission rule standing in for the
/// server. Uploads "progress" on a timer.
@MainActor
@Observable
final class DemoListingBuilderBackend: ListingBuilderBackend {
    let mode: BuilderMode = .demo
    private var uploads: [UUID: BuilderUploadStatus] = [:]
    @ObservationIgnored private var nextListing = 0
    /// Calls the harness can show.
    private(set) var createdDrafts = 0

    private static let catalog: [(brand: String, model: String, reference: String, specs: String)] = [
        ("Rolex", "Submariner Date", "126610LN", #"{"diameter_mm": 41, "material": "Oystersteel", "movement": "Automatic", "calibre": "3235", "dial": "Black", "bracelet": "Oyster", "water_resistance_m": 300, "bezel": "Unidirectional, Cerachrom", "glass": "Sapphire", "back": "Screw-down", "shape": "Round", "lug_width_mm": 21}"#),
        ("Rolex", "Datejust 41", "126300", #"{"diameter_mm": 41, "material": "Oystersteel", "movement": "Automatic", "dial": "Blue", "bracelet": "Jubilee", "water_resistance_m": 100}"#),
        ("Omega", "Speedmaster Professional", "310.30.42.50.01.001", #"{"diameter_mm": 42, "material": "Stainless steel", "movement": "Manual", "calibre": "3861", "dial": "Black", "bracelet": "Steel", "water_resistance_m": 50}"#),
        ("Tudor", "Black Bay 58", "79030N", #"{"diameter_mm": 39, "material": "Stainless steel", "movement": "Automatic", "dial": "Black", "bracelet": "Riveted steel", "water_resistance_m": 200}"#),
    ]

    func cascade(_ query: CatalogCascadeQuery) async throws -> CatalogCascadeResponse {
        try await Task.sleep(for: .milliseconds(120))
        let key = BuilderRules.catalogKey
        let rows = Self.catalog
        let values: [String]
        switch query.level {
        case .brands:
            values = Array(Set(rows.map(\.brand))).sorted()
        case .models:
            values = rows.filter { key($0.brand) == key(query.brand) }.map(\.model)
        case .references:
            values = rows.filter { key($0.brand) == key(query.brand) && key($0.model) == key(query.model) }.map(\.reference)
        }
        let needle = key(query.text)
        let matching = values.filter { needle.isEmpty || key($0).contains(needle) }
        let json: [String: Any] = [
            "values": matching.map { ["value": $0] },
            "total": matching.count,
            "truncated": false,
            "omitted": 0,
        ]
        return try Self.decode(json)
    }

    func catalogReferences(term: String, brand: String, model: String) async throws -> CatalogReferenceSearch {
        try await Task.sleep(for: .milliseconds(150))
        let results = Self.catalog.enumerated().map { index, row -> CatalogReference in
            let specs = (try? APIClient.makeDecoder(origin: nil).decode(ListingSpecs.self, from: Data(row.specs.utf8)))
            return CatalogReference(
                id: "demo-ref-\(index)",
                brand: row.brand,
                model: row.model,
                reference: row.reference,
                displayName: "\(row.brand) \(row.model) \(row.reference)",
                specs: specs
            )
        }
        return CatalogReferenceSearch(results: results, total: results.count, truncated: false)
    }

    func vaultMatches(reference: String) async throws -> [VaultMatch] { [] }

    func needsCustomsFields() async -> Bool { false }

    func publishPreview(price: Decimal) async throws -> ListingPublishPreview {
        try await Task.sleep(for: .milliseconds(250))
        // The published member rule (6%, $250 minimum), standing in for the
        // server in the harness only.
        let percent = price * Decimal(string: "0.06")!
        let minimumApplied = percent < 250
        let commission = minimumApplied ? Decimal(250) : percent
        let wire = (price * Decimal(string: "0.97")!).rounded(2)
        let json: [String: Any] = [
            "price": "\(price)",
            "currency": "USD",
            "commission": ["percent": "6.00", "amount": "\(commission.rounded(2))", "minimum_applied": minimumApplied, "minimum": "250.00"],
            "net_proceeds": "\((price - commission).rounded(2))",
            "buyer_display": [
                "standard": ["price": "\(price)"],
                "discount_states": ["price": "\(price)", "wire_price": "\(wire)", "states": ["CT", "MA"]],
            ],
        ]
        return try Self.decode(json)
    }

    func shippingEstimate(price: Decimal) async throws -> ShippingEstimate {
        try await Task.sleep(for: .milliseconds(400))
        return try Self.decode(["amount": "38.40", "currency": "USD", "provider": "demo"])
    }

    func createDraft(_ body: SellListingBody) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        nextListing += 1
        createdDrafts += 1
        return "demo-listing-\(nextListing)"
    }

    func updateListing(id: String, body: SellListingBody) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    func moveToReview(id: String) async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    func fulfillWatchRequest(id: String, listingID: String) async {}

    func listingImages(listingID: String) async throws -> [ListingImage] { [] }

    func enqueueUpload(listingID: String, fileURL: URL, category: ListingImageCategory?, sortIndex: Int) async -> UUID {
        let id = UUID()
        uploads[id] = BuilderUploadStatus(phase: .queued)
        let offset = Double(uploads.count % 6) * 0.25
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.3 + offset))
            for step in 1...8 {
                guard self?.uploads[id] != nil else { return }
                self?.uploads[id] = BuilderUploadStatus(phase: .uploading(Double(step) / 8))
                try? await Task.sleep(for: .milliseconds(320))
            }
            guard self?.uploads[id] != nil else { return }
            self?.uploads[id] = BuilderUploadStatus(phase: .done, serverImageID: "demo-image-\(id.uuidString.prefix(6))")
        }
        return id
    }

    func cancelUpload(_ jobID: UUID) async {
        uploads[jobID] = nil
    }

    func deleteImage(listingID: String, imageID: String) async throws {}

    func uploadStatus(_ jobID: UUID) -> BuilderUploadStatus? {
        uploads[jobID]
    }

    private static func decode<T: Decodable>(_ object: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try APIClient.makeDecoder(origin: nil).decode(T.self, from: data)
    }
}

extension Decimal {
    /// Rounded to `scale` decimal places, half up.
    func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
