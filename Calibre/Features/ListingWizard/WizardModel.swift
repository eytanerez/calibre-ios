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
        case new(prefill: ListingPrefill?)
        case finishDraft(Listing)
        case edit(Listing)
    }

    let id = UUID()
    let kind: Kind
}

/// What a fresh listing can start from — a buyer's request, or a watch the
/// seller already owns in their vault. Keeping this separate from
/// `WatchRequest` means the vault route doesn't have to pretend to be one
/// (and doesn't accidentally mark a request fulfilled).
struct ListingPrefill: Equatable {
    var brand: String
    var model: String?
    var reference: String?
    var productionYear: Int?
    /// Set only when listing against an open buyer request.
    var fulfillRequestID: String?

    init(
        brand: String,
        model: String? = nil,
        reference: String? = nil,
        productionYear: Int? = nil,
        fulfillRequestID: String? = nil
    ) {
        self.brand = brand
        self.model = model
        self.reference = reference
        self.productionYear = productionYear
        self.fulfillRequestID = fulfillRequestID
    }

    init(request: WatchRequest) {
        self.init(
            brand: request.brand,
            model: request.model,
            reference: request.reference,
            productionYear: request.productionYear,
            fulfillRequestID: request.id
        )
    }

    init(vaultWatch: VaultWatch) {
        self.init(
            brand: vaultWatch.brand ?? "",
            model: vaultWatch.model,
            reference: vaultWatch.reference,
            productionYear: vaultWatch.productionYear
        )
    }
}

// MARK: - Condition vocabulary

/// Scroll anchors for the wizard's inputs, so pressing Continue can bring the
/// first offending field into view.
enum WizardField: Hashable {
    case brand, year, condition(ConditionPart), price
}

/// The eight grades, in the order the sell form asks for them — the same
/// order and the same words the server's submit gate names when one is
/// missing. Nothing is ever derived from anything else here: a missing clasp
/// is a missing clasp, not the bracelet's grade wearing the clasp's name.
enum ConditionPart: String, CaseIterable, Identifiable, Hashable {
    case watchCase = "case"
    case dial, bezel, crystal, bracelet, clasp, caseback, overall

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watchCase: "Case"
        case .dial: "Dial"
        case .bezel: "Bezel"
        case .crystal: "Crystal"
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

    /// Something the seller can actually look at, locally or on the server.
    var hasImage: Bool {
        localURL != nil || remoteURL != nil
    }
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
    /// Absent on snapshots written before the SKU field existed.
    var sellerSku: String? = nil
    /// Return terms, optional so a snapshot written by an earlier build still
    /// decodes — `DraftStore.load` uses `try?`, and a missing key would
    /// otherwise throw away a seller's whole in-progress draft.
    var returnsAccepted: Bool? = nil
    var returnWindowHours: Int? = nil
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
    @ObservationIgnored private let config: ConfigStore

    private(set) var bootstrap: Bootstrap = .working
    private(set) var listing: Listing?

    var step = 0
    static let stepTitles = ["Details", "Photos", "Price", "Review"]

    // Details
    var brand = ""
    var model = ""
    var reference = ""
    /// The seller's own shelf label. Optional here — a listing made by hand
    /// needs no SKU — but it is the only key a bulk import ever matches on,
    /// so a dealer who keeps one is asked for it.
    var sellerSku = ""
    var yearText = ""
    var yearUnknown = false
    var conditions: [ConditionPart: String] = [:]

    // Price
    var priceText = ""
    var notes = ""

    // Returns — the seller's choice at listing time.
    var returnsAccepted = false
    var returnWindowHours: Int?

    // Photos
    var slots: [ListingImageCategory: WizardPhotoSlot] = [:]
    var extraPhotos: [WizardPhotoSlot] = []

    // Payout
    private(set) var estimate: ShippingEstimate?
    private(set) var estimating = false
    /// The server's own statement of commission, net proceeds and the
    /// buyer-facing price. Every figure on the payout card comes from here —
    /// nothing about a rate, a minimum, or a buyer price is worked out on
    /// device.
    private(set) var preview: ListingPublishPreview?
    private(set) var previewing = false

    // Sync + submit
    private(set) var saveError: String?
    private(set) var submitting = false
    var submitError: String?
    var submitted = false

    var fulfillRequestID: String?

    @ObservationIgnored private var patchTask: Task<Void, Never>?
    @ObservationIgnored private var estimateTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = 0

    init(kind: WizardContext.Kind, seller: SellerStore, sell: SellSession, config: ConfigStore) {
        self.kind = kind
        self.seller = seller
        self.sell = sell
        self.config = config
    }

    var isEdit: Bool {
        if case .edit = kind { return true }
        return false
    }

    /// "{Brand} {Model} {Reference}" — the serif title everywhere.
    var composedTitle: String {
        let joined = [brand, model, reference]
            .map(InputValidation.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? "Untitled watch" : joined
    }

    var yearError: String? {
        guard !yearUnknown else { return nil }
        return InputValidation.productionYear(yearText) == nil
            ? "Enter a 4-digit year, or choose Year unknown."
            : nil
    }

    var detailsComplete: Bool {
        InputValidation.isNonBlank(brand)
            && (yearUnknown || InputValidation.productionYear(yearText) != nil)
            && ConditionPart.allCases.allSatisfy { conditions[$0] != nil }
    }

    /// The grades still to fill, worded the way the server's submit gate
    /// words its own refusal — so the sentence a seller reads before pressing
    /// submit matches the one they would read after.
    var missingGradesSentence: String? {
        let missing = ConditionPart.allCases.filter { conditions[$0] == nil }
        guard !missing.isEmpty else { return nil }
        return "Required condition grades missing: " + missing.map(\.label).joined(separator: ", ") + "."
    }

    /// What Details still needs. Used by the Review step's summary and by the
    /// draft-creation guard — the step itself flags fields inline instead.
    var detailsMissing: [String] {
        var missing: [String] = []
        if !InputValidation.isNonBlank(brand) { missing.append("Brand") }
        if !yearUnknown, InputValidation.productionYear(yearText) == nil { missing.append("Year") }
        for part in ConditionPart.allCases where conditions[part] == nil {
            missing.append(part.label)
        }
        return missing
    }

    /// What Price still needs. Notes are optional, so a price is the whole list.
    var priceMissing: [String] {
        price == nil ? ["Price"] : []
    }

    // MARK: Field-level validation

    /// Steps where Continue has been pressed at least once. Blank-field errors
    /// stay quiet until then — a form that scolds you about fields you haven't
    /// reached yet is just noise.
    private(set) var attemptedSteps: Set<Int> = []

    func markAttempted(_ step: Int) {
        attemptedSteps.insert(step)
    }

    private func attempted(_ step: Int) -> Bool {
        attemptedSteps.contains(step)
    }

    var brandError: String? {
        guard attempted(0), !InputValidation.isNonBlank(brand) else { return nil }
        return "Enter the brand."
    }

    /// A year that's been typed wrong is worth flagging straight away; an
    /// untouched one only after Continue.
    var yearFieldError: String? {
        guard !yearUnknown else { return nil }
        if InputValidation.isNonBlank(yearText) { return yearError }
        return attempted(0) ? "Enter a 4-digit year, or choose Year unknown." : nil
    }

    func conditionError(_ part: ConditionPart) -> String? {
        guard attempted(0), conditions[part] == nil else { return nil }
        return "Pick a grade."
    }

    var priceFieldError: String? {
        if InputValidation.isNonBlank(priceText), price == nil {
            return "Enter an amount greater than zero, with at most two decimals."
        }
        guard attempted(2), price == nil else { return nil }
        return "Enter your asking price."
    }

    /// Where to scroll when Continue is pressed on an incomplete step.
    func firstInvalidField(onStep step: Int) -> WizardField? {
        switch step {
        case 0:
            if brandError != nil { return .brand }
            if yearFieldError != nil { return .year }
            if let part = ConditionPart.allCases.first(where: { conditions[$0] == nil }) {
                return .condition(part)
            }
            return nil
        case 2:
            return priceFieldError != nil ? .price : nil
        default:
            return nil
        }
    }

    // MARK: Bootstrap

    func start() async {
        guard bootstrap != .ready else { return }
        bootstrap = .working
        // The return windows a seller may pick from are the marketplace's to
        // state, not ours — ask for them early so the chooser is ready by the
        // time the Price step is.
        config.warm()
        switch kind {
        case .new(let prefill):
            if let prefill {
                brand = prefill.brand
                model = prefill.model ?? ""
                reference = prefill.reference ?? ""
                if let year = prefill.productionYear {
                    yearText = String(year)
                }
                fulfillRequestID = prefill.fulfillRequestID
            }
            // No server draft yet — one is created only once Details is
            // complete (see `createDraftIfNeeded()`), so glancing at the
            // wizard and backing out never leaves an "Untitled watch"
            // behind on the dashboard.
            bootstrap = .ready
        case .finishDraft(let existing), .edit(let existing):
            listing = existing
            populate(from: existing)
            if let snapshot = DraftStore.load(listingID: existing.id) {
                restore(from: snapshot)
            }
            bootstrap = .ready
            await loadServerImages()
            // A resumed draft usually already has a price, and the seller is
            // entitled to see their net proceeds without touching the field.
            await ensurePreview()
        }
    }

    /// Creates the server draft the moment Details is complete — called when
    /// advancing past step 0. A no-op if the draft already exists (resume,
    /// edit, or a second call after the first succeeded). The draft is named
    /// from the real title from the very first write, since by now brand,
    /// model, and reference are already known.
    func createDraftIfNeeded() async -> Bool {
        guard listing == nil else { return true }
        guard detailsComplete else {
            submitError = "Add \(detailsMissing.joined(separator: ", ")) to continue."
            return false
        }
        var payload = currentPayload
        payload.status = ListingStatus.draft.rawValue
        do {
            let created = try await seller.createListing(payload)
            listing = created
            submitError = nil
            persistSnapshot()
            return true
        } catch {
            submitError = sellErrorMessage(error)
            return false
        }
    }

    private func populate(from listing: Listing) {
        brand = listing.brand ?? ""
        model = listing.model ?? ""
        reference = listing.referenceNumber ?? ""
        sellerSku = listing.sellerSku ?? ""
        if let year = listing.productionYear {
            yearText = String(year)
        } else {
            yearUnknown = true
        }
        if listing.price.value > 0 {
            priceText = "\(listing.price.value)"
        }
        notes = listing.description ?? ""
        if let terms = listing.returns {
            returnsAccepted = terms.accepted
            returnWindowHours = terms.windowHours
        }
        if let condition = listing.condition {
            conditions[.watchCase] = condition.caseCondition
            conditions[.dial] = condition.dial
            conditions[.bezel] = condition.bezel
            conditions[.crystal] = condition.crystal
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
        if let sku = snapshot.sellerSku { sellerSku = sku }
        yearText = snapshot.yearText
        yearUnknown = snapshot.yearUnknown
        priceText = snapshot.priceText
        notes = snapshot.notes
        // Absent on snapshots written before return terms existed — leave
        // whatever the listing itself said in that case.
        if let accepted = snapshot.returnsAccepted {
            returnsAccepted = accepted
            returnWindowHours = snapshot.returnWindowHours
        }
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
            description: InputValidation.isNonBlank(notes)
                ? String(InputValidation.trimmed(notes).prefix(2000))
                : nil,
            brand: InputValidation.isNonBlank(brand) ? InputValidation.trimmed(brand) : nil,
            model: InputValidation.isNonBlank(model) ? InputValidation.trimmed(model) : nil,
            reference: InputValidation.isNonBlank(reference) ? InputValidation.trimmed(reference) : nil,
            sellerSku: InputValidation.isNonBlank(sellerSku) ? InputValidation.trimmed(sellerSku) : nil,
            price: price,
            // Each grade is sent as the seller graded it. There is no
            // back-fill: the case is not the caseback, the dial is not the
            // crystal, and a seller who enters one grade must never produce a
            // listing that displays eight.
            conditionOverall: conditions[.overall],
            conditionCase: conditions[.watchCase],
            conditionBracelet: conditions[.bracelet],
            conditionDial: conditions[.dial],
            conditionBezel: conditions[.bezel],
            conditionCrystal: conditions[.crystal],
            conditionClasp: conditions[.clasp],
            conditionCaseback: conditions[.caseback],
            productionYear: yearUnknown ? nil : InputValidation.productionYear(yearText),
            returnsAccepted: returnsAccepted,
            // The server requires a window when returns are accepted, and
            // refuses one when they aren't.
            returnWindowHours: returnsAccepted ? returnWindowHours : nil
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
            sellerSku: sellerSku,
            returnsAccepted: returnsAccepted,
            returnWindowHours: returnWindowHours,
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
        InputValidation.positiveMoney(priceText)
    }

    /// The seller's inbound label, whichever source we have it from. The
    /// listing-scoped preview carries one; the price-scoped preview used
    /// before a draft exists does not, so the standalone estimate stands in.
    var shipping: ShippingEstimate? {
        preview?.shippingEstimate ?? estimate
    }

    /// Notes are optional — a price is all the Price step really needs.
    var priceDetailsComplete: Bool {
        price != nil
    }

    /// The seller has seen what they take home and what a buyer will be
    /// shown — the two figures that must be on screen before publishing.
    var payoutDisclosed: Bool {
        preview != nil
    }

    /// Debounced shipping estimate and publish preview — both fire as the
    /// price settles.
    func priceChanged() {
        fieldChanged()
        estimateTask?.cancel()
        schedulePreview()
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

    // MARK: Publish preview

    /// Debounced publish preview, on the shipping estimate's timing so the
    /// payout card settles once rather than on every keystroke.
    private func schedulePreview() {
        previewTask?.cancel()
        guard let price, price > 0 else {
            // Clearing the field wins over anything already in flight.
            previewGeneration += 1
            preview = nil
            previewing = false
            return
        }
        previewing = true
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            await self.loadPreview(price: price)
        }
    }

    /// Fetches the preview for the price the seller has typed. Once a draft
    /// exists the listing-scoped call is the right one — it also returns the
    /// shipping estimate and the listing's return terms — but it reads the
    /// price the *server* holds, so the pending debounced PATCH has to land
    /// first or the card would quote the previous price.
    private func loadPreview(price: Decimal) async {
        previewGeneration += 1
        let generation = previewGeneration
        previewing = true
        // Only the newest fetch is allowed to write the card or clear the
        // busy flag; an overtaken one leaves both to its successor.
        defer {
            if generation == previewGeneration {
                previewing = false
            }
        }
        do {
            let fetched: ListingPublishPreview
            if let listing {
                patchTask?.cancel()
                await pushPatch()
                guard generation == previewGeneration else { return }
                // A save that didn't land would leave the preview quoting a
                // price the seller has since changed.
                guard saveError == nil else {
                    preview = nil
                    return
                }
                fetched = try await seller.publishPreview(listingID: listing.id)
            } else {
                fetched = try await seller.publishPreview(price: price)
            }
            guard generation == previewGeneration else { return }
            preview = fetched
        } catch {
            // A payout figure we can't stand behind is worse than none at
            // all, so the card falls back to "—" rather than a stale number.
            guard generation == previewGeneration else { return }
            preview = nil
        }
    }

    /// Fetches a preview only if we don't already have one — for screens that
    /// need the figures on appearing rather than on a price edit.
    func ensurePreview() async {
        guard preview == nil, !previewing, let price, price > 0 else { return }
        await loadPreview(price: price)
    }

    /// Explicit retry, for when the preview didn't come back and the seller
    /// is waiting on it to publish.
    func refreshPreview() async {
        guard let price, price > 0 else { return }
        previewTask?.cancel()
        await loadPreview(price: price)
    }

    // MARK: Return terms

    /// The windows the marketplace offers, e.g. [24, 48, 72]. Empty until the
    /// config lands — in which case the chooser hides rather than inventing
    /// a list.
    var returnWindowChoices: [Int] {
        config.returnWindowChoices
    }

    /// Call after either return field changes: keeps the window and the
    /// toggle consistent, then saves like any other edit.
    func returnsChanged() {
        if returnsAccepted, returnWindowHours == nil {
            returnWindowHours = returnWindowChoices.first
        }
        fieldChanged()
    }

    // MARK: Submit

    /// Flushes fields, then flips the draft to pending review.
    func submit() async -> Bool {
        guard !submitting else { return false }
        submitError = nil
        guard detailsComplete else {
            var parts: [String] = []
            if !InputValidation.isNonBlank(brand) { parts.append("Add the brand.") }
            if !yearUnknown, InputValidation.productionYear(yearText) == nil {
                parts.append("Add a 4-digit year, or mark it unknown.")
            }
            if let grades = missingGradesSentence { parts.append(grades) }
            submitError = parts.joined(separator: " ")
            return false
        }
        guard priceDetailsComplete else {
            submitError = "Enter an asking price greater than zero."
            return false
        }
        // Net proceeds and the buyer-facing price are ours to show before a
        // seller publishes, not after.
        guard payoutDisclosed else {
            submitError = "We're still working out your net proceeds and the price buyers will see. Both need to be on screen before this goes to review."
            return false
        }
        guard allRequiredPhotosDone else {
            submitError = "All six photos need to finish uploading before review."
            return false
        }
        guard let listing else { return false }
        submitting = true
        defer { submitting = false }

        patchTask?.cancel()
        await pushPatch()
        if let saveError {
            submitError = saveError
            return false
        }
        do {
            let reviewed = try await seller.submitForReview(listingID: listing.id)
            Analytics.listingSubmitted(
                .init(reviewed),
                source: Analytics.listingSource(for: reviewed.id)
            )
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
