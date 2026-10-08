import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import Rewatch
@testable import RewatchKit

/// Every call the builder makes, recorded, with the uploads' progress in the
/// test's hands.
@MainActor
final class RecordingBuilderBackend: ListingBuilderBackend {
    enum Call: Equatable {
        case createDraft
        case update(String)
        case moveToReview(String)
        case upload(category: String?, sortIndex: Int, file: String)
        case cancel(UUID)
        case delete(String)
    }

    let mode: BuilderMode = .live
    private(set) var calls: [Call] = []
    var statuses: [UUID: BuilderUploadStatus] = [:]
    var jobs: [UUID] = []
    var moveToReviewError: Error?
    var createError: Error?
    var lastBody: SellListingBody?

    var uploads: [Call] { calls.filter { if case .upload = $0 { true } else { false } } }

    func finishAll() {
        for (id, status) in statuses where status.phase != .done {
            statuses[id] = BuilderUploadStatus(phase: .done, serverImageID: "img-\(id.uuidString.prefix(4))")
        }
    }

    func cascade(_ query: CatalogCascadeQuery) async throws -> CatalogCascadeResponse { throw APIError.invalidResponse }
    func catalogReferences(term: String, brand: String, model: String) async throws -> CatalogReferenceSearch {
        CatalogReferenceSearch(results: [], total: 0, truncated: false)
    }
    func vaultMatches(reference: String) async throws -> [VaultMatch] { [] }
    func needsCustomsFields() async -> Bool { false }
    func publishPreview(price: Decimal) async throws -> ListingPublishPreview {
        let json = """
        {"price": "\(price)", "currency": "USD",
         "commission": {"percent": "6.00", "amount": "747.00", "minimum_applied": false, "minimum": "250.00"},
         "net_proceeds": "\(price - 747)",
         "buyer_display": {"standard": {"price": "\(price)"}, "discount_states": {"price": "\(price)", "wire_price": "\(price - 100)", "states": ["CT", "MA"]}}}
        """
        return try APIClient.makeDecoder(origin: nil).decode(ListingPublishPreview.self, from: Data(json.utf8))
    }
    func shippingEstimate(price: Decimal) async throws -> ShippingEstimate {
        try APIClient.makeDecoder(origin: nil).decode(ShippingEstimate.self, from: Data(#"{"amount": "38.40", "currency": "USD"}"#.utf8))
    }

    func createDraft(_ body: SellListingBody) async throws -> String {
        if let createError { throw createError }
        calls.append(.createDraft)
        lastBody = body
        return "listing-1"
    }

    func updateListing(id: String, body: SellListingBody) async throws {
        calls.append(.update(id))
        lastBody = body
    }

    func moveToReview(id: String) async throws {
        if let moveToReviewError { throw moveToReviewError }
        calls.append(.moveToReview(id))
    }

    func fulfillWatchRequest(id: String, listingID: String) async {}
    func listingImages(listingID: String) async throws -> [ListingImage] { [] }

    func enqueueUpload(listingID: String, fileURL: URL, category: ListingImageCategory?, sortIndex: Int) async -> UUID {
        let id = UUID()
        calls.append(.upload(category: category?.rawValue, sortIndex: sortIndex, file: fileURL.lastPathComponent))
        statuses[id] = BuilderUploadStatus(phase: .queued)
        jobs.append(id)
        return id
    }

    func cancelUpload(_ jobID: UUID) async {
        calls.append(.cancel(jobID))
        statuses[jobID] = nil
    }

    func deleteImage(listingID: String, imageID: String) async throws {
        calls.append(.delete(imageID))
    }

    func uploadStatus(_ jobID: UUID) -> BuilderUploadStatus? { statuses[jobID] }
}

@MainActor
final class ListingBuilderTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "builder-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        BuilderDraftStore.clear(listingID: "listing-1")
    }

    private func jpeg(_ shade: CGFloat = 0.4) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).image { context in
            UIColor(white: shade, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
        return try ListingPhotoPrep.jpeg(from: image)
    }

    /// A builder answered up to the photo step, standing on it.
    private func builder() throws -> (ListingBuilderModel, RecordingBuilderBackend) {
        let backend = RecordingBuilderBackend()
        let model = ListingBuilderModel(kind: .new(prefill: nil), backend: backend, photoRoot: root)
        var answers = BuilderAnswers()
        answers.brand = "Rolex"
        answers.model = "Submariner Date"
        answers.reference = "126610LN"
        answers.year = "2021"
        answers.grade = "Very Good"
        answers.partsMatch = true
        answers.polish = "unpolished"
        answers.originality = "all_original"
        answers.serviceHistory = "never"
        model.answers = answers
        model.previewJump(to: .photos)
        return (model, backend)
    }

    private func fillAllSix(_ model: ListingBuilderModel) throws {
        for (index, category) in BuilderRules.photoLayout.enumerated() {
            model.setPhoto(try jpeg(CGFloat(index) / 10), for: category)
        }
    }

    // MARK: Upload when leaving the photo step

    func testPickingPhotosSendsNothing() throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        XCTAssertEqual(model.photosFilled.count, 6)
        XCTAssertTrue(backend.calls.isEmpty, "Nothing goes up on a pick")
        XCTAssertNil(model.listingID)
    }

    func testLeavingThePhotoStepCreatesTheDraftThenUploadsAllSixInGalleryOrder() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        XCTAssertTrue(model.advance())
        XCTAssertEqual(model.step, .price)
        await model.syncPhotos()

        XCTAssertEqual(backend.calls.first, .createDraft, "The draft exists before any photo is sent")
        XCTAssertEqual(model.listingID, "listing-1")
        let sent = backend.uploads.compactMap { call -> String? in
            if case let .upload(category, sortIndex, _) = call { return "\(category ?? "-"):\(sortIndex)" }
            return nil
        }
        XCTAssertEqual(sent, ["front:0", "caseback:1", "left_profile:2", "right_profile:3", "clasp:4", "full_set:5"])
        XCTAssertEqual(backend.calls.filter { $0 == .createDraft }.count, 1)
        // The draft carries the answers so far, under the site's names.
        XCTAssertEqual(backend.lastBody?.brand, "Rolex")
        XCTAssertEqual(backend.lastBody?.conditionOverall, "Very Good")
    }

    func testGoingBackAndChangingOnePhotoChangesOnlyThatPhoto() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        model.advance()
        await model.syncPhotos()
        backend.finishAll()
        let before = backend.calls.count

        model.edit(.photos)
        XCTAssertEqual(model.step, .photos)
        model.setPhoto(try jpeg(0.9), for: .clasp)
        model.advance()
        XCTAssertEqual(model.step, .price)
        await model.syncPhotos()

        let after = Array(backend.calls[before...])
        XCTAssertEqual(after.count, 1, "One changed photo is one upload: \(after)")
        guard case let .upload(category, sortIndex, _) = after.first else {
            return XCTFail("Expected one upload, got \(after)")
        }
        XCTAssertEqual(category, "clasp")
        XCTAssertEqual(sortIndex, 4)
        XCTAssertFalse(after.contains(.createDraft), "The draft is made once")
    }

    func testAPhotoReplacedWhileItsFirstVersionIsStillGoingWithdrawsTheFirst() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        model.advance()
        await model.syncPhotos()
        let firstFront = try XCTUnwrap(backend.jobs.first)

        model.edit(.photos)
        model.setPhoto(try jpeg(0.8), for: .front)
        model.advance()
        await model.syncPhotos()

        XCTAssertTrue(backend.calls.contains(.cancel(firstFront)), "The older front must not land after the newer one")
        XCTAssertEqual(backend.uploads.count, 7)
    }

    func testARemovedExtraIsDeletedFromTheServer() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        model.addExtra(try jpeg(0.2))
        model.advance()
        await model.syncPhotos()
        guard case let .upload(category, sortIndex, _)? = backend.uploads.last else { return XCTFail("No extra upload") }
        XCTAssertNil(category)
        XCTAssertEqual(sortIndex, BuilderRules.firstExtraSortIndex)
        backend.finishAll()

        model.edit(.photos)
        let extra = try XCTUnwrap(model.extras.first)
        model.removeExtra(extra.id)
        model.advance()
        await model.syncPhotos()
        XCTAssertTrue(backend.calls.contains { if case .delete = $0 { true } else { false } })
        XCTAssertEqual(backend.uploads.count, 7, "Removing sends nothing new")
    }

    func testADraftThatCouldNotBeCreatedIsTriedAgainLater() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        backend.createError = APIError.network(underlying: URLError(.notConnectedToInternet))
        model.advance()
        await model.syncPhotos()
        XCTAssertNil(model.listingID)
        XCTAssertNotNil(model.photoSyncError)
        XCTAssertTrue(backend.uploads.isEmpty)

        backend.createError = nil
        await model.syncPhotos()
        XCTAssertEqual(model.listingID, "listing-1")
        XCTAssertEqual(backend.uploads.count, 6)
        XCTAssertNil(model.photoSyncError)
    }

    // MARK: The instant submit

    private func answeredThroughReturns(_ model: ListingBuilderModel) {
        model.answers.priceText = "12,450"
        model.answers.returns = .hours48
        model.previewJump(to: .review)
    }

    func testApproveOnlyPatchesTheAnswersAndMovesToReview() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        model.advance()
        await model.syncPhotos()
        backend.finishAll()
        answeredThroughReturns(model)
        let before = backend.calls.count

        let done = await model.submit()

        XCTAssertTrue(done)
        XCTAssertTrue(model.submitted)
        XCTAssertEqual(Array(backend.calls[before...]), [.update("listing-1"), .moveToReview("listing-1")])
        XCTAssertEqual(backend.lastBody?.price, Decimal(12450))
        XCTAssertEqual(backend.lastBody?.returnWindowHours, 48)
        // The payout was on screen before it went in.
        XCTAssertEqual(model.keep, Decimal(12450 - 747))
        XCTAssertEqual(model.estimatedPayout, Decimal(string: "11664.6"))
    }

    func testApproveWaitsForPhotosStillGoingThenSends() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        model.advance()
        await model.syncPhotos()
        answeredThroughReturns(model)

        let submit = Task { await model.submit() }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.submitPhase, .uploading(done: 0, total: 6))
        XCTAssertFalse(backend.calls.contains(.moveToReview("listing-1")), "Nothing is sent while photos are going")

        backend.finishAll()
        let done = await submit.value
        XCTAssertTrue(done)
        XCTAssertEqual(backend.calls.suffix(2), [.update("listing-1"), .moveToReview("listing-1")])
    }

    func testAFailedPhotoIsSentAgainAtApproveAndStopsTheSubmitIfItFailsAgain() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        model.advance()
        await model.syncPhotos()
        backend.finishAll()
        let failed = try XCTUnwrap(model.slot(.clasp)?.jobID)
        backend.statuses[failed] = BuilderUploadStatus(phase: .failed(final: true))
        answeredThroughReturns(model)
        let uploadsBefore = backend.uploads.count

        let first = Task { await model.submit() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(backend.uploads.count, uploadsBefore + 1, "Only the photo that failed goes again")
        XCTAssertEqual(model.submitPhase, .uploading(done: 5, total: 6))
        // It fails a second time: the submit stops and says so.
        let retry = try XCTUnwrap(backend.jobs.last)
        backend.statuses[retry] = BuilderUploadStatus(phase: .failed(final: true))
        let firstDone = await first.value
        XCTAssertFalse(firstDone)
        XCTAssertEqual(model.sendError?.step, .review)
        XCTAssertFalse(backend.calls.contains(.moveToReview("listing-1")), "Never sent for review with a photo missing")

        let second = Task { await model.submit() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(backend.uploads.count, uploadsBefore + 2)
        backend.finishAll()
        let done = await second.value
        XCTAssertTrue(done)
    }

    func testARefusalLandsOnTheStepItIsAbout() async throws {
        let (model, backend) = try builder()
        try fillAllSix(model)
        model.advance()
        await model.syncPhotos()
        backend.finishAll()
        answeredThroughReturns(model)
        backend.moveToReviewError = APIError.server(
            message: "Required condition grades missing: Clasp.", code: nil, status: 400, details: nil
        )

        let done = await model.submit()

        XCTAssertFalse(done)
        XCTAssertEqual(model.step, .condition)
        XCTAssertEqual(model.returnTo, .review, "Continue goes straight back to the review")
        XCTAssertEqual(model.sendError?.message, "Required condition grades missing: Clasp.")
    }

    // MARK: The plan, on its own

    func testThePlanSendsOnlyFilesNotAlreadySent() {
        let sent = BuilderPhotoSlot(fileName: "a.jpg", sentFileName: "a.jpg", jobID: UUID())
        let changed = BuilderPhotoSlot(fileName: "b2.jpg", sentFileName: "b.jpg", jobID: UUID())
        let actions = PhotoSyncPlan.actions(
            slots: [.front: sent, .caseback: changed],
            extras: [],
            removedExtras: [],
            activeJobs: []
        )
        XCTAssertEqual(actions, [.upload(category: .caseback, extraID: nil, fileName: "b2.jpg", sortIndex: 1, cancelling: nil)])
    }

    // MARK: Rules

    func testNextGoesToTheNextEmptyWatchField() {
        var answers = BuilderAnswers()
        answers.brand = "Rolex"
        XCTAssertEqual(BuilderRules.nextEmptyIdentityField(after: .brand, in: answers), .model)
        answers.reference = "126610LN"
        XCTAssertEqual(BuilderRules.nextEmptyIdentityField(after: .reference, in: answers), .model)
        answers.model = "Submariner"
        XCTAssertNil(BuilderRules.nextEmptyIdentityField(after: .model, in: answers), "All three filled: Next is Continue")
    }

    func testRefusalsMapToTheirSteps() {
        func step(_ message: String, code: String? = nil, details: [String: String]? = nil) -> BuilderStep {
            BuilderRules.serverErrorStep(APIError.server(message: message, code: code, status: 400, details: details))
        }
        XCTAssertEqual(step("Required photos missing: Clasp."), .photos)
        XCTAssertEqual(step("That stock number is taken.", code: "duplicate_sku"), .year)
        XCTAssertEqual(step("Already listed.", code: "vault_watch_already_listed"), .watch)
        XCTAssertEqual(step("Invalid.", details: ["return_window_hours": "Pick 24, 48 or 72."]), .returns)
        XCTAssertEqual(step("Enter a price."), .price)
        XCTAssertEqual(step("Seller setup is not finished."), .review)
        XCTAssertEqual(BuilderRules.serverErrorStep(URLError(.timedOut)), .review)
    }

    func testPricesAreTypedAsTheSiteTypesThem() {
        XCTAssertEqual(BuilderRules.formatMoneyInput("12450.505"), "12,450.50")
        XCTAssertEqual(BuilderRules.formatMoneyInput("$1,2a34"), "1,234")
        XCTAssertEqual(BuilderRules.parsePrice("12,450.5"), Decimal(string: "12450.5"))
        XCTAssertNil(BuilderRules.parsePrice("12.345"))
        XCTAssertEqual(BuilderRules.priceProblem("99"), "Listings start at $100.")
        XCTAssertNil(BuilderRules.priceProblem("100"))
    }

    // MARK: The photo itself

    func testAPhotoGoesUpAt2400PixelsAsAJPEGWithNoLocation() throws {
        // A 3000 x 1500 JPEG carrying GPS and camera details, stored on its
        // side (orientation 6: rotate to read).
        let side = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let original = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(side.cgImage), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 26.7153, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 80.0534, kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone 17"],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let prepared = try ListingPhotoPrep.jpeg(from: original as Data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        // Turned upright, and the long side brought down to 2400.
        XCTAssertEqual(width, 1200)
        XCTAssertEqual(height, 2400)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary], "The location must not leave the phone")
        XCTAssertNil((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel])
        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1
        XCTAssertEqual(orientation, 1, "The rotation is in the pixels, not a flag")
    }

    func testASmallPhotoIsNotEnlarged() {
        XCTAssertEqual(ListingPhotoPrep.scaledSize(width: 1200, height: 800).resized, false)
        let big = ListingPhotoPrep.scaledSize(width: 4032, height: 3024)
        XCTAssertEqual(big.width, 2400)
        XCTAssertEqual(big.height, 1800)
    }
}
