import CalibreDesign
import CalibreKit
import Foundation
import Observation
import SwiftUI

// MARK: - Wizard context (presentation identity)

/// What the wizard opens onto — a fresh listing (optionally prefilled from a
/// buyer request), a draft to finish, or a listed watch to edit.
struct WizardContext: Identifiable {
    enum Kind {
        case new(prefill: WatchRequest?)
        case finishDraft(Listing)
        case edit(Listing)
    }

    let id = UUID()
    let kind: Kind
}

// MARK: - Condition vocabulary

enum ConditionPart: String, CaseIterable, Identifiable {
    case crystal, bezel, bracelet, clasp, caseback, overall

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crystal: "Crystal"
        case .bezel: "Bezel"
        case .bracelet: "Bracelet"
        case .clasp: "Clasp"
        case .caseback: "Caseback"
        case .overall: "Overall"
        }
    }

    static let grades = ["New", "Like New", "Very Good", "Good", "Worn"]
}

// MARK: - Photo slots

/// One photo slot's local truth. Upload progress lives on the shared
/// `UploadProgressBoard`, keyed by `jobID`.
struct WizardPhotoSlot {
    var localURL: URL?
    var remoteURL: URL?
    var serverImageID: String?
    var jobID: UUID?
}

extension ListingImageCategory {
    var label: String {
        switch self {
        case .front: "Front"
        case .caseback: "Caseback"
        case .leftProfile: "Left profile"
        case .rightProfile: "Right profile"
        case .clasp: "Clasp"
        case .fullSet: "Everything included"
        }
    }

    /// One-line capture instruction shown in the camera overlay.
    var instruction: String {
        switch self {
        case .front: "Dial straight-on — fill the circle"
        case .caseback: "Flip it over, fill the circle"
        case .leftProfile: "Crown side straight-on"
        case .rightProfile: "Opposite side straight-on"
        case .clasp: "Clasp closed, centered"
        case .fullSet: "Watch, box, and papers together"
        }
    }
}

// MARK: - Draft snapshot (force-quit resume)

/// Wizard state mirrored to Application Support as JSON so a force-quit
/// resumes exactly where the seller stopped.
struct WizardSnapshot: Codable {
    var listingID: String
    var isEdit: Bool
    var step: Int
    var brand: String
    var model: String
    var reference: String
    var yearText: String
    var yearUnknown: Bool
    /// ConditionPart.rawValue → grade.
    var conditions: [String: String]
    var priceText: String
    var notes: String
    /// Category rawValue → local photo file name (inside the listing's
    /// photo folder).
    var slotFiles: [String: String]
    var extraFiles: [String]
    var fulfillRequestID: String?
    var updatedAt: Date
}

@MainActor
enum DraftStore {
    private static var draftsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appending(path: "Calibre/SellDrafts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func photosDirectory(listingID: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appending(path: "Calibre/SellPhotos/\(listingID)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func fileURL(listingID: String) -> URL {
        draftsDirectory.appending(path: "\(listingID).json")
    }

    static func save(_ snapshot: WizardSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL(listingID: snapshot.listingID), options: .atomic)
    }

    static func load(listingID: String) -> WizardSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(listingID: listingID)) else { return nil }
        return try? JSONDecoder().decode(WizardSnapshot.self, from: data)
    }

    /// The most recently touched in-progress draft, for the resume offer.
    static func activeSnapshot() -> WizardSnapshot? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: draftsDirectory,
            includingPropertiesForKeys: nil
        ) else { return nil }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> WizardSnapshot? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(WizardSnapshot.self, from: data)
            }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }

    static func clear(listingID: String) {
        try? FileManager.default.removeItem(at: fileURL(listingID: listingID))
    }
}

// MARK: - Wizard model

/// Draft-first listing state machine: creates the server draft on entry,
/// PATCHes field changes debounced, mirrors everything to `DraftStore`, and
/// tracks the six-slot photo pipeline.
@MainActor
@Observable
final class WizardModel {
    enum Bootstrap: Equatable {
        case working
        case ready
        case failed(String)
    }

    let kind: WizardContext.Kind
    @ObservationIgnored private let seller: SellerStore
    @ObservationIgnored private let sell: SellSession
    /// Seller commission percent, from the dashboard's dealer payload.
    let feePercent: Decimal

    private(set) var bootstrap: Bootstrap = .working
    private(set) var listing: Listing?

    var step = 0
    static let stepTitles = ["Details", "Photos", "Price", "Review"]

    // Details
    var brand = ""
    var model = ""
    var reference = ""
    var yearText = ""
    var yearUnknown = false
    var conditions: [ConditionPart: String] = [:]

    // Price
    var priceText = ""
    var notes = ""

    // Photos
    var slots: [ListingImageCategory: WizardPhotoSlot] = [:]
    var extraPhotos: [WizardPhotoSlot] = []

    // Payout
    private(set) var estimate: ShippingEstimate?
    private(set) var estimating = false

    // Sync + submit
    private(set) var saveError: String?
    private(set) var submitting = false
    var submitError: String?
    var submitted = false

    var fulfillRequestID: String?

    @ObservationIgnored private var patchTask: Task<Void, Never>?
    @ObservationIgnored private var estimateTask: Task<Void, Never>?

    init(kind: WizardContext.Kind, seller: SellerStore, sell: SellSession, feePercent: Decimal) {
        self.kind = kind
        self.seller = seller
        self.sell = sell
        self.feePercent = feePercent
    }

    var isEdit: Bool {
        if case .edit = kind { return true }
        return false
    }

    /// "{Brand} {Model} {Reference}" — the serif title everywhere.
    var composedTitle: String {
        let joined = [brand, model, reference]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? "Untitled watch" : joined
    }

    // MARK: Bootstrap

    func start() async {
        guard bootstrap != .ready else { return }
        bootstrap = .working
        switch kind {
        case .new(let prefill):
            if let prefill {
                brand = prefill.brand
                model = prefill.model ?? ""
                reference = prefill.reference ?? ""
                if let year = prefill.productionYear {
                    yearText = String(year)
                }
                fulfillRequestID = prefill.id
            }
            do {
                // Draft-first: the listing exists before the first photo.
                let created = try await seller.createListing(ListingDraftPayload(
                    title: composedTitle,
                    brand: brand.isEmpty ? nil : brand,
                    model: model.isEmpty ? nil : model,
                    reference: reference.isEmpty ? nil : reference,
                    status: .draft
                ))
                listing = created
                persistSnapshot()
                bootstrap = .ready
            } catch {
                bootstrap = .failed(sellErrorMessage(error))
            }
        case .finishDraft(let existing), .edit(let existing):
            listing = existing
            populate(from: existing)
            if let snapshot = DraftStore.load(listingID: existing.id) {
                restore(from: snapshot)
            }
            bootstrap = .ready
            await loadServerImages()
        }
    }

    private func populate(from listing: Listing) {
        brand = listing.brand ?? ""
        model = listing.model ?? ""
        reference = listing.referenceNumber ?? ""
        if let year = listing.productionYear {
            yearText = String(year)
        } else {
            yearUnknown = true
        }
        if listing.price.value > 0 {
            priceText = "\(listing.price.value)"
        }
        notes = listing.description ?? ""
        if let condition = listing.condition {
            conditions[.crystal] = condition.crystal
            conditions[.bezel] = condition.bezel
            conditions[.bracelet] = condition.bracelet
            conditions[.clasp] = condition.clasp
            conditions[.caseback] = condition.caseback
            conditions[.overall] = condition.overall
            for part in ConditionPart.allCases where conditions[part]?.isEmpty == true {
                conditions[part] = nil
            }
        }
    }

    private func restore(from snapshot: WizardSnapshot) {
        brand = snapshot.brand
        model = snapshot.model
        reference = snapshot.reference
        yearText = snapshot.yearText
        yearUnknown = snapshot.yearUnknown
        priceText = snapshot.priceText
        notes = snapshot.notes
        step = min(max(snapshot.step, 0), 3)
        fulfillRequestID = snapshot.fulfillRequestID
        for (key, grade) in snapshot.conditions {
            if let part = ConditionPart(rawValue: key) {
                conditions[part] = grade
            }
        }
        guard let listingID = listing?.id else { return }
        let photoDir = DraftStore.photosDirectory(listingID: listingID)
        for (raw, fileName) in snapshot.slotFiles {
            guard let category = ListingImageCategory(rawValue: raw) else { continue }
            let url = photoDir.appending(path: fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                slots[category, default: WizardPhotoSlot()].localURL = url
            }
        }
        for fileName in snapshot.extraFiles {
            let url = photoDir.appending(path: fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                extraPhotos.append(WizardPhotoSlot(localURL: url))
            }
        }
    }

    /// Marks slots whose photos already live on the server (edit / resume).
    func loadServerImages() async {
        guard let listing else { return }
        guard let images = try? await seller.images(listingID: listing.id) else { return }
        for image in images {
            guard let raw = image.category, let category = ListingImageCategory(rawValue: raw) else { continue }
            var slot = slots[category] ?? WizardPhotoSlot()
            slot.serverImageID = image.id
            slot.remoteURL = image.url.url
            slots[category] = slot
        }
    }

    // MARK: Field sync

    /// Call after any field edit: mirrors to disk now, PATCHes soon.
    func fieldChanged() {
        persistSnapshot()
        schedulePatch()
    }

    private func schedulePatch() {
        patchTask?.cancel()
        patchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self?.pushPatch()
        }
    }

    private var currentPayload: ListingDraftPayload {
        ListingDraftPayload(
            title: composedTitle,
            description: notes.isEmpty ? nil : String(notes.prefix(2000)),
            brand: brand.isEmpty ? nil : brand,
            model: model.isEmpty ? nil : model,
            reference: reference.isEmpty ? nil : reference,
            price: price,
            conditionOverall: conditions[.overall],
            conditionBracelet: conditions[.bracelet],
            conditionBezel: conditions[.bezel],
            conditionCrystal: conditions[.crystal],
            conditionClasp: conditions[.clasp],
            conditionCaseback: conditions[.caseback],
            productionYear: yearUnknown ? nil : Int(yearText.trimmingCharacters(in: .whitespaces))
        )
    }

    func pushPatch() async {
        guard let listing else { return }
        do {
            self.listing = try await seller.updateListing(id: listing.id, currentPayload)
            saveError = nil
        } catch {
            saveError = sellErrorMessage(error)
        }
    }

    func persistSnapshot() {
        guard let listing else { return }
        var slotFiles: [String: String] = [:]
        for (category, slot) in slots {
            if let url = slot.localURL {
                slotFiles[category.rawValue] = url.lastPathComponent
            }
        }
        DraftStore.save(WizardSnapshot(
            listingID: listing.id,
            isEdit: isEdit,
            step: step,
            brand: brand,
            model: model,
            reference: reference,
            yearText: yearText,
            yearUnknown: yearUnknown,
            conditions: Dictionary(uniqueKeysWithValues: conditions.map { ($0.key.rawValue, $0.value) }),
            priceText: priceText,
            notes: notes,
            slotFiles: slotFiles,
            extraFiles: extraPhotos.compactMap { $0.localURL?.lastPathComponent },
            fulfillRequestID: fulfillRequestID,
            updatedAt: .now
        ))
    }

    // MARK: Photos

    /// Stores the processed photo and queues its upload immediately.
    func attach(image: UIImage, to category: ListingImageCategory?) async {
        guard let listing else { return }
        let label = category?.rawValue ?? "extra-\(UUID().uuidString.prefix(8))"
        guard let url = PhotoPipeline.store(image, listingID: listing.id, label: String(label)) else {
            submitError = "That photo couldn't be processed. Please try another shot."
            return
        }
        let jobID = await sell.uploads.enqueue(
            draftID: listing.id,
            listingID: listing.id,
            category: category?.rawValue,
            fileURL: url
        )
        if let category {
            slots[category] = WizardPhotoSlot(localURL: url, jobID: jobID)
        } else {
            extraPhotos.append(WizardPhotoSlot(localURL: url, jobID: jobID))
        }
        persistSnapshot()
    }

    /// Re-queues a failed upload from the file already on disk.
    func retryUpload(category: ListingImageCategory) async {
        guard let listing, let slot = slots[category], let url = slot.localURL else { return }
        let jobID = await sell.uploads.enqueue(
            draftID: listing.id,
            listingID: listing.id,
            category: category.rawValue,
            fileURL: url
        )
        slots[category]?.jobID = jobID
    }

    func phase(for category: ListingImageCategory) -> PhotoSlotPhase {
        guard let slot = slots[category] else { return .empty }
        if let jobID = slot.jobID, let entry = sell.board.entry(for: jobID) {
            switch entry.state {
            case .queued: return .uploading(0)
            case .uploading: return .uploading(entry.fraction)
            case .done: return .done
            case .failed: return .failed
            }
        }
        if slot.serverImageID != nil { return .done }
        if slot.localURL != nil { return .uploading(0) }
        return .empty
    }

    func phase(forExtra index: Int) -> PhotoSlotPhase {
        guard extraPhotos.indices.contains(index) else { return .empty }
        let slot = extraPhotos[index]
        if let jobID = slot.jobID, let entry = sell.board.entry(for: jobID) {
            switch entry.state {
            case .queued: return .uploading(0)
            case .uploading: return .uploading(entry.fraction)
            case .done: return .done
            case .failed: return .failed
            }
        }
        return slot.localURL == nil ? .empty : .uploading(0)
    }

    var allRequiredPhotosDone: Bool {
        ListingImageCategory.allCases.allSatisfy { phase(for: $0) == .done }
    }

    // MARK: Price & payout

    var price: Decimal? {
        Decimal.fromMoneyText(priceText)
    }

    var commission: Decimal? {
        guard let price else { return nil }
        var result = Decimal()
        var raw = price * feePercent / 100
        NSDecimalRound(&result, &raw, 2, .plain)
        return result
    }

    var payout: Decimal? {
        guard let price, let commission else { return nil }
        return price - commission - (estimate?.amount.value ?? 0)
    }

    /// Debounced shipping estimate — fires as the price settles.
    func priceChanged() {
        fieldChanged()
        estimateTask?.cancel()
        guard let price, price > 0 else {
            estimate = nil
            estimating = false
            return
        }
        estimating = true
        estimateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            do {
                let quote = try await self.seller.shippingEstimate(listingPrice: price)
                if !Task.isCancelled {
                    self.estimate = quote
                }
            } catch {
                self.estimate = nil
            }
            self.estimating = false
        }
    }

    // MARK: Submit

    /// Flushes fields, then flips the draft to pending review.
    func submit() async -> Bool {
        guard let listing, !submitting else { return false }
        submitError = nil
        submitting = true
        defer { submitting = false }

        patchTask?.cancel()
        await pushPatch()
        if let saveError {
            submitError = saveError
            return false
        }
        do {
            _ = try await seller.submitForReview(listingID: listing.id)
            if let fulfillRequestID {
                // Best effort — the listing is submitted either way.
                _ = try? await seller.fulfillWatchRequest(id: fulfillRequestID, listingID: listing.id)
            }
            DraftStore.clear(listingID: listing.id)
            submitted = true
            return true
        } catch {
            submitError = sellErrorMessage(error)
            return false
        }
    }
}
