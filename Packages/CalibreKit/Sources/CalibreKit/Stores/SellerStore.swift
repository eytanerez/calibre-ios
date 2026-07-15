import Foundation
import Observation

/// Seller-side tools: readiness gate, dashboard, listing CRUD + photos,
/// shipping quotes, watch requests and bulk-import jobs.
@MainActor
@Observable
public final class SellerStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var readiness: SellerReadiness?
    public private(set) var dashboard: SellerDashboard?
    public private(set) var myListings: [Listing] = []

    /// Bumped by `loadDashboard()`/`loadMyListings()` respectively, guarding
    /// their writes to `dashboard`/`myListings` — the seller dashboard runs
    /// both concurrently and may retry/refresh while an earlier call for the
    /// same data is still in flight; the older response must not overwrite a
    /// newer one that already landed.
    @ObservationIgnored private var dashboardGeneration = 0
    @ObservationIgnored private var listingsGeneration = 0

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Readiness & dashboard

    /// Stripe Connect readiness — gates listing creation (`canList`).
    @discardableResult
    public func loadReadiness() async throws -> SellerReadiness {
        let value: SellerReadiness = try await client.send(Endpoint(path: "/stripe/seller-readiness"))
        readiness = value
        return value
    }

    @discardableResult
    public func loadDashboard() async throws -> SellerDashboard {
        dashboardGeneration += 1
        let generation = dashboardGeneration
        let value: SellerDashboard = try await client.send(Endpoint(path: "/account/dashboard"))
        if generation == dashboardGeneration {
            dashboard = value
        }
        return value
    }

    // MARK: - My listings

    @discardableResult
    public func loadMyListings() async throws -> [Listing] {
        listingsGeneration += 1
        let generation = listingsGeneration
        let rows: [Listing] = try await client.send(Endpoint(path: "/account/listings"))
        if generation == listingsGeneration {
            myListings = rows
        }
        return rows
    }

    /// Create a listing (drafts pass `status: .draft`). Server-side gated on
    /// seller readiness.
    @discardableResult
    public func createListing(_ draft: ListingDraftPayload) async throws -> Listing {
        let listing: Listing = try await client.send(
            try Endpoint.json(method: .post, path: "/account/listings", payload: draft)
        )
        myListings.insert(listing, at: 0)
        return listing
    }

    @discardableResult
    public func updateListing(id: String, _ patch: ListingDraftPayload) async throws -> Listing {
        let listing: Listing = try await client.send(
            try Endpoint.json(method: .patch, path: "/account/listings/\(id)", payload: patch)
        )
        if let index = myListings.firstIndex(where: { $0.id == id }) {
            myListings[index] = listing
        }
        return listing
    }

    public func deleteListing(id: String) async throws {
        let _: EmptyResponse = try await client.send(Endpoint(method: .delete, path: "/account/listings/\(id)"))
        myListings.removeAll { $0.id == id }
    }

    /// Submit a draft for admin review. The backend enforces the six-photo
    /// completeness rule and rejects incomplete submissions.
    @discardableResult
    public func submitForReview(listingID: String) async throws -> Listing {
        try await updateListing(id: listingID, ListingDraftPayload(status: .pendingReview))
    }

    // MARK: - Photos

    public func images(listingID: String) async throws -> [ListingImage] {
        try await client.send(Endpoint(path: "/account/listings/\(listingID)/images"))
    }

    /// Direct (foreground) photo upload. Batch/retry/background uploads go
    /// through `UploadQueue` instead.
    @discardableResult
    public func uploadImage(
        listingID: String,
        data: Data,
        filename: String,
        contentType: String,
        category: String? = nil,
        sortIndex: Int? = nil
    ) async throws -> ListingImage {
        var form = MultipartForm()
        form.addFile("file", filename: filename, contentType: contentType, data: data)
        if let category {
            form.addField("category", value: category)
        }
        if let sortIndex {
            form.addField("sort_index", value: String(sortIndex))
        }
        return try await client.send(
            Endpoint(method: .post, path: "/account/listings/\(listingID)/images", body: .multipart(form))
        )
    }

    /// Update a photo's category or sort position.
    @discardableResult
    public func updateImage(
        listingID: String,
        imageID: String,
        category: String? = nil,
        sortIndex: Int? = nil
    ) async throws -> ListingImage {
        struct Payload: Encodable {
            let category: String?
            let sortIndex: Int?
        }
        return try await client.send(
            try Endpoint.json(
                method: .patch,
                path: "/account/listings/\(listingID)/images/\(imageID)",
                payload: Payload(category: category, sortIndex: sortIndex)
            )
        )
    }

    public func deleteImage(listingID: String, imageID: String) async throws {
        let _: EmptyResponse = try await client.send(
            Endpoint(method: .delete, path: "/account/listings/\(listingID)/images/\(imageID)")
        )
    }

    // MARK: - Shipping

    /// The seller's estimated cost to ship a watch of this price to the
    /// authentication center (uses the seller's default address).
    public func shippingEstimate(listingPrice: Decimal) async throws -> ShippingEstimate {
        struct Payload: Encodable {
            let listingPrice: String
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/account/listings/shipping-estimate",
                payload: Payload(listingPrice: "\(listingPrice)")
            )
        )
    }

    // MARK: - Watch requests

    /// My own sourcing requests.
    public func myWatchRequests() async throws -> [WatchRequest] {
        try await client.send(Endpoint(path: "/account/watch-requests"))
    }

    /// Other members' open requests for dealers to fulfill (latest 100).
    public func openDealerRequests() async throws -> [WatchRequest] {
        try await client.send(Endpoint(path: "/dealer/watch-requests"))
    }

    @discardableResult
    public func createWatchRequest(
        brand: String,
        model: String? = nil,
        reference: String? = nil,
        productionYear: Int? = nil,
        maxBudget: Decimal? = nil,
        notes: String? = nil
    ) async throws -> WatchRequest {
        struct Payload: Encodable {
            let brand: String
            let model: String?
            let reference: String?
            let productionYear: Int?
            let maxBudget: String?
            let notes: String?
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/account/watch-requests",
                payload: Payload(
                    brand: brand,
                    model: model,
                    reference: reference,
                    productionYear: productionYear,
                    maxBudget: maxBudget.map { "\($0)" },
                    notes: notes
                )
            )
        )
    }

    public func deleteWatchRequest(id: String) async throws {
        let _: EmptyResponse = try await client.send(
            Endpoint(method: .delete, path: "/account/watch-requests/\(id)")
        )
    }

    /// Mark an open request fulfilled, optionally linking my listing.
    @discardableResult
    public func fulfillWatchRequest(id: String, listingID: String? = nil) async throws -> WatchRequest {
        struct Payload: Encodable {
            let listingId: String?
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/dealer/watch-requests/\(id)/fulfill",
                payload: Payload(listingId: listingID)
            )
        )
    }

    // MARK: - Bulk imports

    public func importJobs() async throws -> [ListingImportJob] {
        try await client.send(Endpoint(path: "/account/listing-imports"))
    }

    public func importJob(id: String) async throws -> ListingImportJob {
        try await client.send(Endpoint(path: "/account/listing-imports/\(id)"))
    }

    /// Imported listings still missing required fields or photos.
    public func importCompletionQueue(jobID: String) async throws -> [ImportCompletionItem] {
        try await client.send(Endpoint(path: "/account/listing-imports/\(jobID)/completion-queue"))
    }
}
