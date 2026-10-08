import Foundation
import RewatchKit

// MARK: - Photo slots

/// One of the six angles, as the builder holds it.
///
/// Photos are prepared and kept on the phone while the seller is on the photo
/// step. Nothing goes up until they LEAVE the step (Eytan, 2026-10-07): then
/// the draft is created if it does not exist yet, and every photo whose local
/// file is not the one already sent goes up in the background while the
/// seller carries on. Going back and changing one photo changes only that
/// photo on the server, because only its file differs from what was sent.
struct BuilderPhotoSlot: Codable, Equatable {
    /// The prepared JPEG in the builder's folder, by name.
    var fileName: String?
    /// The server's copy when there is no local file (a draft being finished).
    var remoteURL: URL?
    /// The listing image holding this slot's photo, once the server said so.
    var serverImageID: String?
    /// The local file already sent to the server (or on its way there).
    var sentFileName: String?
    /// The upload carrying `sentFileName`.
    var jobID: UUID?

    var hasImage: Bool { fileName != nil || remoteURL != nil }
    /// A local photo the server does not have yet.
    var needsUpload: Bool { fileName != nil && fileName != sentFileName }
}

/// A photo beyond the six angles: the site's "More photos".
struct BuilderExtraPhoto: Codable, Equatable, Identifiable {
    var id = UUID()
    var fileName: String?
    var remoteURL: URL?
    var serverImageID: String?
    var sentFileName: String?
    var jobID: UUID?
    /// Fixed for the photo's life, so a retry can ask the server whether this
    /// exact photo already landed (`UploadQueue.alreadyLanded`).
    var sortIndex: Int

    var needsUpload: Bool { fileName != nil && fileName != sentFileName }
}

/// What leaving the photo step has to do to the server.
enum PhotoSyncAction: Equatable {
    /// Send this file. `cancelling` is an earlier upload for the same slot
    /// still on its way, withdrawn so it cannot land after this one.
    case upload(category: ListingImageCategory?, extraID: UUID?, fileName: String, sortIndex: Int, cancelling: UUID?)
    /// A removed extra the server holds.
    case delete(imageID: String)
    /// A removed extra still on its way.
    case cancel(jobID: UUID)
}

enum PhotoSyncPlan {
    /// Everything the server needs to match the phone, in gallery order.
    ///
    /// - A slot uploads only when its local file is not the one already sent:
    ///   one changed photo is one upload. The server replaces an angle's photo
    ///   with each new one, so nothing is deleted for an angle.
    /// - An extra the seller removed is deleted if it reached the server, or
    ///   withdrawn if it is still going.
    static func actions(
        slots: [ListingImageCategory: BuilderPhotoSlot],
        extras: [BuilderExtraPhoto],
        removedExtras: [BuilderExtraPhoto],
        activeJobs: Set<UUID>
    ) -> [PhotoSyncAction] {
        var actions: [PhotoSyncAction] = []
        for removed in removedExtras {
            if let imageID = removed.serverImageID {
                actions.append(.delete(imageID: imageID))
            } else if let jobID = removed.jobID {
                actions.append(.cancel(jobID: jobID))
            }
        }
        for category in BuilderRules.uploadOrder {
            guard let slot = slots[category], slot.needsUpload, let fileName = slot.fileName else { continue }
            let stillGoing = slot.jobID.flatMap { activeJobs.contains($0) ? $0 : nil }
            actions.append(.upload(
                category: category,
                extraID: nil,
                fileName: fileName,
                sortIndex: BuilderRules.sortIndex(for: category),
                cancelling: stillGoing
            ))
        }
        for extra in extras.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            guard extra.needsUpload, let fileName = extra.fileName else { continue }
            let stillGoing = extra.jobID.flatMap { activeJobs.contains($0) ? $0 : nil }
            actions.append(.upload(
                category: nil,
                extraID: extra.id,
                fileName: fileName,
                sortIndex: extra.sortIndex,
                cancelling: stillGoing
            ))
        }
        return actions
    }
}

// MARK: - Upload status

/// One upload, as the builder reads it.
struct BuilderUploadStatus: Equatable {
    enum Phase: Equatable {
        case queued
        case uploading(Double)
        case done
        /// Out of retries, or between them.
        case failed(final: Bool)
    }

    var phase: Phase
    var serverImageID: String?

    var isSettled: Bool {
        switch phase {
        case .done, .failed(final: true): true
        default: false
        }
    }
}

// MARK: - What the builder talks to

/// Everything the builder asks of the outside world, so the same screens run
/// against the live API, the DEBUG preview harness (nothing written) and the
/// tests (every call recorded).
@MainActor
protocol ListingBuilderBackend: AnyObject {
    var mode: BuilderMode { get }

    // The watch
    func cascade(_ query: CatalogCascadeQuery) async throws -> CatalogCascadeResponse
    func catalogReferences(term: String, brand: String, model: String) async throws -> CatalogReferenceSearch
    func vaultMatches(reference: String) async throws -> [VaultMatch]
    /// A dealer outside the US is asked for customs details.
    func needsCustomsFields() async -> Bool

    // Money
    func publishPreview(price: Decimal) async throws -> ListingPublishPreview
    func shippingEstimate(price: Decimal) async throws -> ShippingEstimate

    // The listing
    func createDraft(_ body: SellListingBody) async throws -> String
    func updateListing(id: String, body: SellListingBody) async throws
    func moveToReview(id: String) async throws
    func fulfillWatchRequest(id: String, listingID: String) async
    func listingImages(listingID: String) async throws -> [ListingImage]

    // Photos
    func enqueueUpload(listingID: String, fileURL: URL, category: ListingImageCategory?, sortIndex: Int) async -> UUID
    func cancelUpload(_ jobID: UUID) async
    func deleteImage(listingID: String, imageID: String) async throws
    func uploadStatus(_ jobID: UUID) -> BuilderUploadStatus?
}
