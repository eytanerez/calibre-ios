import CoreGraphics
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

    // MARK: - Photo annotations

    /// Writes the seller's mark on one photo, replacing whatever was on it.
    ///
    /// There is no read here on purpose: the annotations already travel on
    /// every listing detail payload, and a second request for them would give
    /// the gallery a source that can disagree with the listing it is drawing.
    ///
    /// The path arrives simplified and normalised — see `AnnotationPath`.
    /// Refusals come back as `APIError.server` carrying the server's own
    /// sentence (too short a mark, too many points, a photo that no longer
    /// exists, the per-listing limit); show that rather than writing a second
    /// wording for the same rule.
    @discardableResult
    public func saveAnnotation(
        listingID: String,
        imageIndex: Int,
        path: [CGPoint],
        note: String?
    ) async throws -> ListingAnnotation {
        let document = ListingAnnotation(imageIndex: imageIndex, path: path, note: note)
        return try await client.send(
            try Endpoint.json(
                method: .put,
                path: "/account/listings/\(listingID)/annotations/\(imageIndex)",
                payload: document
            )
        )
    }

    public func deleteAnnotation(listingID: String, imageIndex: Int) async throws {
        struct Response: Decodable { let deleted: Bool }
        let _: Response = try await client.send(
            Endpoint(method: .delete, path: "/account/listings/\(listingID)/annotations/\(imageIndex)")
        )
    }

    // MARK: - The storefront line

    /// The dealer's own line, as its author sees it — their submitted words,
    /// what a buyer is currently reading, and where review got to.
    ///
    /// A seller who is not a verified dealer is refused with
    /// `dealer_required`: the line sits beside a verified-business badge, so
    /// there is no version of it for an unverified name.
    public func dealerBio() async throws -> DealerBio {
        struct Response: Decodable { let bio: DealerBio }
        let response: Response = try await client.send(Endpoint(path: "/account/dealer/bio"))
        return response.bio
    }

    /// Submits a line for review. Always returns it to `pending`, an edit of
    /// an already-approved line included — and the previously approved words
    /// stay on the storefront meanwhile, so editing never blanks it.
    @discardableResult
    public func updateDealerBio(_ bio: String) async throws -> DealerBio {
        struct Payload: Encodable { let bio: String }
        struct Response: Decodable { let bio: DealerBio }
        let response: Response = try await client.send(
            try Endpoint.json(method: .put, path: "/account/dealer/bio", payload: Payload(bio: bio))
        )
        return response.bio
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

    // MARK: - Publish preview

    /// What the seller takes home and what the buyer will see, computed
    /// server-side: the commission (with the flat minimum applied when it
    /// bites), net proceeds, and the buyer-facing price in both the standard
    /// and discount-state presentations.
    ///
    /// Every figure on the payout card comes from here. Nothing about a
    /// commission rate, a minimum, or a buyer price is derived on device.
    public func publishPreview(listingID: String) async throws -> ListingPublishPreview {
        try await client.send(Endpoint(path: "/account/listings/\(listingID)/publish-preview"))
    }

    /// The same preview, scoped to a price rather than a listing — so the
    /// wizard can show a real payout figure on the create path, before any
    /// draft exists. Shipping and return terms are absent here; the
    /// listing-scoped call fills those in once there is a draft.
    public func publishPreview(price: Decimal) async throws -> ListingPublishPreview {
        try await client.send(
            Endpoint(
                path: "/account/publish-preview",
                query: [URLQueryItem(name: "price", value: "\(price)")]
            )
        )
    }

    // MARK: - Dealer program

    /// Where this seller stands in the dealer program.
    public func dealerApplication() async throws -> DealerApplication {
        try await client.send(Endpoint(path: "/account/dealer-application"))
    }

    /// Applies to become a verified dealer. The response carries an embedded
    /// onboarding session that collects the business legal name and EIN;
    /// clearing it grants dealer status automatically.
    ///
    /// Throws `APIError.server` with code `connect_required` (409) when the
    /// seller has no payouts account yet — send them through payout
    /// onboarding first.
    public func applyForDealer(companyName: String, country: String) async throws -> DealerApplicationResult {
        struct Payload: Encodable {
            let companyName: String
            let country: String
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/account/dealer-application",
                payload: Payload(companyName: companyName, country: country)
            )
        )
    }

    // MARK: - Card on file

    /// The credit card Calibre keeps on file for sellers, and whether it
    /// still works. Listing readiness fails with `seller_card_required`
    /// until one is present.
    public func sellerCard() async throws -> SellerCardState {
        try await client.send(Endpoint(path: "/account/seller-card"))
    }

    /// A SetupIntent for adding or replacing the seller's card. Credit only:
    /// a non-credit card is detached server-side after confirmation.
    public func sellerCardSetupIntent() async throws -> SellerCardSetupIntent {
        try await client.send(Endpoint(method: .post, path: "/account/seller-card/setup-intent"))
    }

    // MARK: - Pricing guidance

    /// "Watches like this listed at $X–Y and sold in ~N days" — computed from
    /// Calibre's own listings and sales. Returns `available == false` when the
    /// comparable sample is too thin to be honest about.
    public func pricingGuidance(
        brand: String,
        model: String? = nil,
        reference: String? = nil
    ) async throws -> PricingGuidance {
        var query = [URLQueryItem(name: "brand", value: brand)]
        if let model, !model.isEmpty {
            query.append(URLQueryItem(name: "model", value: model))
        }
        if let reference, !reference.isEmpty {
            query.append(URLQueryItem(name: "reference", value: reference))
        }
        return try await client.send(Endpoint(path: "/listings/pricing-guidance", query: query))
    }

    // MARK: - Watch requests

    /// My own sourcing requests.
    public func myWatchRequests() async throws -> [WatchRequest] {
        try await client.send(Endpoint(path: "/account/watch-requests"))
    }

    /// Other members' open requests, for verified dealers to source against.
    ///
    /// Verified dealers only: everyone else gets `APIError.server` with code
    /// `dealer_required` (403). The response is a flat
    /// `{results, page, page_size, total}` page — a buyer request carries a
    /// budget and a username, so it is a lead list, not public browse.
    public func openDealerRequests(
        query: String? = nil,
        brand: String? = nil,
        watchReferenceID: String? = nil,
        sort: DealerRequestSort = .latest,
        openOnly: Bool = true,
        page: Int = 1,
        pageSize: Int = 25
    ) async throws -> DealerWatchRequestPage {
        var items: [URLQueryItem] = []
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let brand, !brand.isEmpty {
            items.append(URLQueryItem(name: "brand", value: brand))
        }
        if let watchReferenceID, !watchReferenceID.isEmpty {
            items.append(URLQueryItem(name: "watch_reference_id", value: watchReferenceID))
        }
        items.append(URLQueryItem(name: "sort", value: sort.rawValue))
        items.append(URLQueryItem(name: "open_only", value: openOnly ? "true" : "false"))
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "page_size", value: String(pageSize)))
        return try await client.send(Endpoint(path: "/dealer/watch-requests", query: items))
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
