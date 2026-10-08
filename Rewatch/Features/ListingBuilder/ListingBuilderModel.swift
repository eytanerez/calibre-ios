import Foundation
import Observation
import RewatchDesign
import RewatchKit
import SwiftUI
import UIKit

/// What the builder opens onto: a fresh listing (from a buyer's request, a
/// Vault watch or an Insights suggestion, or nothing), or a draft to finish.
/// Editing a listed watch is not here: that stays on the edit form.
enum BuilderKind {
    case new(prefill: ListingPrefill?)
    case finishDraft(Listing)
}

/// The listing builder's state and everything it does to the outside world.
///
/// The questions run one per screen, the site's nine steps in the site's
/// order. Nothing is written while the seller answers, except the photos,
/// which go up when the seller leaves the photo step: the draft is created
/// then if it does not exist yet, and the photos upload in the background
/// while the seller carries on to the price. The final Approve only sends the
/// remaining answers and moves the listing to review, so it lands at once; if
/// photos are still on their way it waits for them with the count on screen.
@MainActor
@Observable
final class ListingBuilderModel {
    enum SubmitPhase: Equatable {
        case preparing
        case uploading(done: Int, total: Int)
        case sending
    }

    struct SendError: Equatable {
        let message: String
        let step: BuilderStep
    }

    let kind: BuilderKind
    @ObservationIgnored let backend: ListingBuilderBackend

    // MARK: Answers and place

    var answers = BuilderAnswers() {
        didSet { answersChanged(from: oldValue) }
    }

    private(set) var step: BuilderStep = .watch
    /// The furthest step reached: the review can jump back to any step up to it.
    private(set) var reached = 0
    /// Set when a step was opened from the review: Continue goes back there.
    private(set) var returnTo: BuilderStep?
    /// The encouraging line over the question. Chosen when the step opens.
    private(set) var line = ""
    /// The step whose answer was just written, for the copper ink line.
    private(set) var justWrote: BuilderStep?
    /// Which way the last move went, for the transition.
    private(set) var movingForward = true

    // MARK: The watch

    /// The catalog row the three fields name, once the catalog answered.
    private(set) var watch: CatalogReference?
    /// The catalog answered completely and holds no such watch.
    private(set) var catalogIsNew = false
    private(set) var vaultMatches: [VaultMatch] = []
    private(set) var needsCustomsFields = false

    // MARK: Money

    private(set) var preview: ListingPublishPreview?
    private(set) var previewLoading = false
    private(set) var shipping: ShippingEstimate?
    private(set) var shippingLoading = false
    private(set) var shippingError: String?

    // MARK: Photos

    var slots: [ListingImageCategory: BuilderPhotoSlot] = [:]
    var extras: [BuilderExtraPhoto] = []
    @ObservationIgnored private var removedExtras: [BuilderExtraPhoto] = []
    @ObservationIgnored private var nextExtraSortIndex = BuilderRules.firstExtraSortIndex
    let photoFolder: URL
    /// The server draft, once there is one.
    private(set) var listingID: String?
    /// Why the last attempt to put the photos on the server failed, if it did.
    private(set) var photoSyncError: String?
    private(set) var photoError: String?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var syncAgain = false

    // MARK: Submit

    private(set) var submitPhase: SubmitPhase?
    private(set) var sendError: SendError?
    private(set) var submitted = false
    private(set) var fulfillRequestID: String?

    @ObservationIgnored private let sessionID: UUID
    @ObservationIgnored private var catalogTask: Task<Void, Never>?
    @ObservationIgnored private var vaultTask: Task<Void, Never>?
    @ObservationIgnored private var moneyTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var inkTask: Task<Void, Never>?
    @ObservationIgnored private var catalogGeneration = 0
    @ObservationIgnored private var moneyGeneration = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored let currentYear = Calendar.current.component(.year, from: .now)

    init(kind: BuilderKind, backend: ListingBuilderBackend, sessionID: UUID = UUID(), photoRoot: URL? = nil) {
        self.kind = kind
        self.backend = backend
        self.sessionID = sessionID
        let root = photoRoot ?? BuilderDraftStore.photosRoot
        self.photoFolder = root.appending(path: "builder-\(sessionID.uuidString)", directoryHint: .isDirectory)
        line = BuilderRules.encouragement(.watch, answers, watch: nil)
    }

    var mode: BuilderMode { backend.mode }

    var options: BuilderRules.Options {
        BuilderRules.Options(mode: mode, needsCustomsFields: needsCustomsFields, currentYear: currentYear)
    }

    var photosFilled: Set<ListingImageCategory> {
        Set(slots.filter { $0.value.hasImage }.map(\.key))
    }

    func canContinue(_ step: BuilderStep) -> Bool {
        BuilderRules.canContinue(step, answers, photosFilled: photosFilled, options: options)
    }

    var canContinueHere: Bool { canContinue(step) }

    var identity: (brand: String, model: String, reference: String) {
        BuilderRules.identity(answers, watch: watch)
    }

    var body: SellListingBody {
        BuilderRules.body(answers, needsCustomsFields: needsCustomsFields)
    }

    /// Whether closing now has something worth keeping as a draft.
    var canSaveDraft: Bool { canContinue(.watch) }

    // MARK: - Start

    func start() async {
        guard !started else { return }
        started = true
        if mode == .live {
            Task { [weak self] in
                guard let self else { return }
                let needs = await self.backend.needsCustomsFields()
                self.needsCustomsFields = needs
            }
        }
        switch kind {
        case .new(let prefill):
            if let prefill {
                var next = answers
                next.brand = prefill.brand
                next.model = prefill.model ?? ""
                next.reference = prefill.reference ?? ""
                if let year = prefill.productionYear, BuilderRules.isFourDigits(String(year)) {
                    next.year = String(year)
                }
                answers = next
                fulfillRequestID = prefill.fulfillRequestID
            }
        case .finishDraft(let listing):
            await hydrate(from: listing)
        }
        line = BuilderRules.encouragement(step, answers, watch: watch)
    }

    /// A draft made earlier, here or on the site: the listing's answers, then
    /// whatever this phone remembers on top (photos not yet sent, answers not
    /// yet saved), then the first question still open.
    private func hydrate(from listing: Listing) async {
        listingID = listing.id
        var next = BuilderAnswers()
        next.brand = listing.brand ?? ""
        next.model = listing.model ?? ""
        next.reference = listing.referenceNumber ?? ""
        next.sku = listing.sellerSku ?? ""
        next.year = listing.productionYear.map(String.init) ?? ""
        if let condition = listing.condition, let overall = condition.overall, !overall.isEmpty {
            next.grade = overall
            let parts: [ConditionPart: String?] = [
                .watchCase: condition.caseCondition, .dial: condition.dial, .bezel: condition.bezel,
                .crystal: condition.crystal, .bracelet: condition.bracelet, .clasp: condition.clasp,
                .caseback: condition.caseback,
            ]
            let differing = parts.contains { ($0.value ?? overall) != overall }
            next.partsMatch = !differing
            if differing {
                for (part, grade) in parts { next.parts[part.rawValue] = grade ?? overall }
            }
        }
        next.conditionNotes = listing.conditionNotes ?? [:]
        next.box = listing.boxIncluded ?? (listing.boxPapers ?? false)
        next.papers = listing.papersIncluded ?? (listing.boxPapers ?? false)
        next.booklets = listing.bookletsIncluded ?? false
        next.notes = SellerNotes(listing.description).text
        next.polish = listing.history?.polish
        next.originality = listing.history?.originality
        next.replaced = listing.history?.replacedPartsNote ?? ""
        next.serviceHistory = listing.history?.serviceHistory
        next.serviceYear = listing.history?.lastServiceYear.map(String.init) ?? ""
        if listing.price.value > 0 {
            next.priceText = BuilderRules.formatMoneyInput("\(listing.price.value)")
        }
        // A draft's `returns_accepted: false` may be the default rather than an
        // answer, so only a yes is taken as one.
        if let terms = listing.returns, terms.accepted, let hours = terms.windowHours {
            next.returns = ReturnsChoice(rawValue: String(hours))
        }
        next.vaultWatchID = listing.vaultWatchId

        if let images = try? await backend.listingImages(listingID: listing.id) {
            for image in images {
                if let raw = image.category, let category = ListingImageCategory(rawValue: raw) {
                    slots[category] = BuilderPhotoSlot(remoteURL: image.url.url, serverImageID: image.id)
                } else {
                    let sortIndex = image.sortIndex ?? nextExtraSortIndex
                    extras.append(BuilderExtraPhoto(remoteURL: image.url.url, serverImageID: image.id, sortIndex: sortIndex))
                    nextExtraSortIndex = max(nextExtraSortIndex, sortIndex + 1)
                }
            }
        }

        if let snapshot = BuilderDraftStore.load(listingID: listing.id) {
            next = snapshot.answers
            fulfillRequestID = snapshot.fulfillRequestID
            for (raw, saved) in snapshot.slots {
                guard let category = ListingImageCategory(rawValue: raw) else { continue }
                var slot = saved
                if let name = slot.fileName, !FileManager.default.fileExists(atPath: snapshot.photoFolderURL.appending(path: name).path) {
                    slot.fileName = nil
                }
                if slot.fileName != nil || slot.remoteURL == nil {
                    slot.remoteURL = slot.remoteURL ?? slots[category]?.remoteURL
                    slots[category] = slot
                }
            }
            if !snapshot.extras.isEmpty {
                extras = snapshot.extras
            }
            removedExtras = snapshot.removedExtras
            nextExtraSortIndex = max(nextExtraSortIndex, snapshot.nextExtraSortIndex)
            adoptPhotoFolder(snapshot.photoFolderURL)
        }

        answers = next
        let open = BuilderRules.firstOpenStep(answers, photosFilled: photosFilled, options: options)
        step = open
        reached = open.index
        scheduleCatalogMatch(immediately: true)
        if answers.price != nil { scheduleMoney(immediately: true) }
    }

    /// A resumed draft keeps its photos where they already are.
    @ObservationIgnored private var adoptedFolder: URL?
    private func adoptPhotoFolder(_ folder: URL) { adoptedFolder = folder }
    var activePhotoFolder: URL { adoptedFolder ?? photoFolder }

    func photoURL(_ fileName: String) -> URL {
        activePhotoFolder.appending(path: fileName)
    }

    // MARK: - Moving between steps

    /// Continue. False (and nothing moves) when the step is not answered yet.
    @discardableResult
    func advance() -> Bool {
        guard canContinueHere else { return false }
        let current = step
        let target = returnTo ?? current.next
        returnTo = nil
        if sendError?.step == current { sendError = nil }
        markWritten(current)
        reached = max(reached, target.index)
        go(to: target, forward: true)
        return true
    }

    func back() {
        guard step != .watch else { return }
        go(to: step.previous, forward: false)
    }

    /// From the review (or any step already reached): change one answer and
    /// come straight back.
    func edit(_ target: BuilderStep) {
        guard submitPhase == nil, target.index <= reached, target != step else { return }
        returnTo = (step == .review || returnTo == .review) ? .review : nil
        go(to: target, forward: target.index > step.index)
    }

    private func go(to target: BuilderStep, forward: Bool) {
        let leaving = step
        movingForward = forward
        step = target
        line = BuilderRules.encouragement(target, answers, watch: watch)
        if leaving == .photos, target != .photos {
            // Eytan, 2026-10-07: the photos go up when the seller leaves this
            // step, while they carry on.
            Task { await syncPhotos() }
        }
        if target == .price || target == .review, answers.price != nil, preview == nil {
            scheduleMoney(immediately: true)
        }
        scheduleSnapshot()
    }

    private func markWritten(_ step: BuilderStep) {
        justWrote = step
        inkTask?.cancel()
        inkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.justWrote = nil
        }
    }

    // MARK: - Answers

    private func answersChanged(from old: BuilderAnswers) {
        let identityChanged = old.brand != answers.brand || old.model != answers.model || old.reference != answers.reference
        if identityChanged { scheduleCatalogMatch() }
        if old.reference != answers.reference {
            // An answer to a question that changed is not an answer.
            if answers.vaultWatchID != nil,
               BuilderRules.catalogKey(old.reference) != BuilderRules.catalogKey(answers.reference) {
                answers.vaultWatchID = nil
                answers.vaultWatchTitle = nil
            }
            scheduleVaultLookup()
        }
        if old.priceText != answers.priceText { scheduleMoney() }
        if old != answers { scheduleSnapshot() }
    }

    func chooseGrade(_ grade: String) {
        var next = answers
        next.grade = grade
        next.partsMatch = nil
        next.parts = [:]
        answers = next
    }

    /// "Some parts differ": every part starts at the overall grade.
    func partsDiffer() {
        var next = answers
        next.partsMatch = false
        for part in BuilderRules.parts { next.parts[part.rawValue] = answers.grade }
        answers = next
    }

    func setPart(_ part: ConditionPart, _ grade: String) {
        answers.parts[part.rawValue] = grade
    }

    func setNote(_ key: String, _ text: String) {
        // One line of prose: a pasted line break comes out.
        let line = text.filter { !$0.isNewline }
        if line.isEmpty {
            answers.conditionNotes[key] = nil
        } else {
            answers.conditionNotes[key] = line
        }
    }

    // MARK: - The catalog

    private func scheduleCatalogMatch(immediately: Bool = false) {
        catalogTask?.cancel()
        catalogGeneration += 1
        let generation = catalogGeneration
        let brand = answers.brand, model = answers.model, reference = answers.reference
        let complete = !BuilderRules.trimmed(brand).isEmpty && !BuilderRules.trimmed(model).isEmpty
            && !BuilderRules.trimmed(reference).isEmpty
        guard complete else {
            watch = nil
            catalogIsNew = false
            return
        }
        // Keep what matched while the seller is still typing the same watch.
        if let watch, !watch.matches(brand: brand, model: model, reference: reference) {
            self.watch = nil
        }
        catalogIsNew = false
        catalogTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled, let self else { return }
            let term = [brand, model, reference].joined(separator: " ")
            guard term.count >= 2 else { return }
            do {
                let found = try await self.backend.catalogReferences(term: term, brand: brand, model: model)
                guard generation == self.catalogGeneration else { return }
                let matched = found.results.first { $0.matches(brand: brand, model: model, reference: reference) }
                withAnimation(Motion.easeMedium) {
                    self.watch = matched
                    // "New" is only claimed off a complete answer.
                    self.catalogIsNew = matched == nil && !found.isPartial
                }
            } catch {
                guard generation == self.catalogGeneration else { return }
                self.catalogIsNew = false
            }
        }
    }

    // MARK: - The Vault question

    private func scheduleVaultLookup() {
        vaultTask?.cancel()
        let reference = BuilderRules.trimmed(answers.reference)
        guard mode == .live, answers.vaultWatchID == nil, !answers.vaultDeclined, reference.count >= 2 else {
            vaultMatches = []
            return
        }
        vaultTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            let found = (try? await self.backend.vaultMatches(reference: reference)) ?? []
            guard reference == BuilderRules.trimmed(self.answers.reference),
                  self.answers.vaultWatchID == nil, !self.answers.vaultDeclined else { return }
            withAnimation(Motion.easeMedium) { self.vaultMatches = found }
        }
    }

    func linkVault(_ match: VaultMatch) {
        vaultTask?.cancel()
        var next = answers
        next.vaultWatchID = match.vaultWatchId
        next.vaultWatchTitle = match.displayTitle
        answers = next
        withAnimation(Motion.easeMedium) { vaultMatches = [] }
    }

    func declineVault() {
        vaultTask?.cancel()
        var next = answers
        next.vaultWatchID = nil
        next.vaultWatchTitle = nil
        next.vaultDeclined = true
        answers = next
        withAnimation(Motion.easeMedium) { vaultMatches = [] }
    }

    // MARK: - Money

    private func scheduleMoney(immediately: Bool = false) {
        moneyTask?.cancel()
        moneyGeneration += 1
        let generation = moneyGeneration
        guard let price = answers.price, price >= 1 else {
            preview = nil
            shipping = nil
            shippingError = nil
            previewLoading = false
            shippingLoading = false
            return
        }
        previewLoading = true
        shippingLoading = true
        moneyTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled, let self else { return }
            let previewCall = Task { try await self.backend.publishPreview(price: price) }
            let shippingCall = Task { try await self.backend.shippingEstimate(price: price) }
            let previewResult = await previewCall.result
            let shippingResult = await shippingCall.result
            guard generation == self.moneyGeneration else { return }
            switch previewResult {
            case .success(let value): self.preview = value
            case .failure: self.preview = nil
            }
            self.previewLoading = false
            switch shippingResult {
            case .success(let value):
                self.shipping = value
                self.shippingError = nil
            case .failure(let error):
                self.shipping = nil
                self.shippingError = (error as? APIError).flatMap { error -> String? in
                    if case .server(let message, _, _, _) = error { return message }
                    return nil
                } ?? "Unavailable"
            }
            self.shippingLoading = false
        }
    }

    func refreshMoney() {
        scheduleMoney(immediately: true)
    }

    /// The figures, fetched now and waited for.
    private func loadMoneyNow() async {
        scheduleMoney(immediately: true)
        await moneyTask?.value
    }

    /// The beta tester's sample watch: everything but the photos and the
    /// history, then on to what is left (the site's `fillSample`).
    func applySample(_ listing: [String: String]) {
        func grade(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespaces)
            return ConditionPart.grades.first { $0 == trimmed }
        }
        var next = answers
        next.brand = listing["brand"] ?? ""
        next.model = listing["model"] ?? ""
        next.reference = listing["reference_number"] ?? ""
        let year = (listing["manufacture_year"] ?? "").trimmingCharacters(in: .whitespaces)
        next.year = BuilderRules.yearIsValid(year, currentYear: currentYear) ? year : "unknown"
        let overall = grade(listing["condition"])
        next.grade = overall
        var parts: [String: String] = [:]
        for part in BuilderRules.parts {
            parts[part.rawValue] = grade(listing["condition_\(part.rawValue)"]) ?? overall
        }
        let allMatch = BuilderRules.parts.allSatisfy { parts[$0.rawValue] == overall }
        next.partsMatch = overall == nil ? nil : allMatch
        next.parts = overall != nil && !allMatch ? parts : [:]
        next.notes = listing["notes"] ?? ""
        next.priceText = BuilderRules.formatMoneyInput(listing["price"] ?? "")
        answers = next
        let target = BuilderRules.firstOpenStep(answers, photosFilled: photosFilled, options: options)
        reached = max(reached, target.index)
        go(to: target, forward: true)
    }

    /// The server's figures for the price on screen, or nil while they are
    /// for another price (or not in yet).
    var currentPreview: ListingPublishPreview? {
        guard let preview, let price = answers.price, preview.price.value == price else { return nil }
        return preview
    }

    /// What the seller keeps after commission, per the server.
    var keep: Decimal? { currentPreview?.netProceeds.value }

    /// After the estimated label too: the figure on the approve bar.
    var estimatedPayout: Decimal? {
        guard let keep, let shipping, currentPreview != nil else { return nil }
        return keep - shipping.amount.value
    }

    // MARK: - Photos

    func slot(_ category: ListingImageCategory) -> BuilderPhotoSlot? { slots[category] }

    /// A picked or captured photo, prepared and kept on the phone. Nothing is
    /// sent until the seller leaves the step.
    func setPhoto(_ jpeg: Data, for category: ListingImageCategory) {
        do {
            let url = try ListingPhotoPrep.store(jpeg, in: activePhotoFolder, label: category.rawValue)
            var slot = slots[category] ?? BuilderPhotoSlot()
            if let old = slot.fileName, old != slot.sentFileName {
                try? FileManager.default.removeItem(at: photoURL(old))
            }
            slot.fileName = url.lastPathComponent
            slot.remoteURL = nil
            withAnimation(Motion.easeMedium) { slots[category] = slot }
            photoError = nil
            scheduleSnapshot()
        } catch {
            photoError = "\(category.label): \(error.localizedDescription)"
        }
    }

    func removePhoto(_ category: ListingImageCategory) {
        guard var slot = slots[category] else { return }
        if let old = slot.fileName, old != slot.sentFileName {
            try? FileManager.default.removeItem(at: photoURL(old))
        }
        slot.fileName = nil
        slot.remoteURL = nil
        // What the server holds stays until a replacement goes up: an angle is
        // never left empty on the server, and the next photo replaces it.
        withAnimation(Motion.easeMedium) { slots[category] = slot.serverImageID == nil && slot.jobID == nil ? nil : slot }
        scheduleSnapshot()
    }

    func addExtra(_ jpeg: Data) {
        do {
            let url = try ListingPhotoPrep.store(jpeg, in: activePhotoFolder, label: "extra")
            let extra = BuilderExtraPhoto(fileName: url.lastPathComponent, sortIndex: nextExtraSortIndex)
            nextExtraSortIndex += 1
            withAnimation(Motion.easeMedium) { extras.append(extra) }
            scheduleSnapshot()
        } catch {
            photoError = error.localizedDescription
        }
    }

    func removeExtra(_ id: UUID) {
        guard let index = extras.firstIndex(where: { $0.id == id }) else { return }
        let extra = extras[index]
        withAnimation(Motion.easeMedium) { _ = extras.remove(at: index) }
        if extra.serverImageID != nil || extra.jobID != nil {
            removedExtras.append(extra)
        } else if let name = extra.fileName {
            try? FileManager.default.removeItem(at: photoURL(name))
        }
        scheduleSnapshot()
    }

    /// Several at once, from the library: the empty angles fill in layout
    /// order, and anything beyond them joins the extras (the site's
    /// `fillFromFiles`).
    func fill(with photos: [Data]) {
        var remaining = photos[...]
        for category in BuilderRules.photoLayout where slots[category]?.hasImage != true {
            guard let next = remaining.popFirst() else { break }
            setPhoto(next, for: category)
        }
        for leftover in remaining { addExtra(leftover) }
    }

    func reportPhotoProblem(_ message: String) {
        photoError = message
    }

    /// The upload state of one angle, for its tile.
    func uploadStatus(_ category: ListingImageCategory) -> BuilderUploadStatus? {
        guard let slot = slots[category], let jobID = slot.jobID, slot.sentFileName == slot.fileName else { return nil }
        return backend.uploadStatus(jobID)
    }

    func uploadStatus(extra: BuilderExtraPhoto) -> BuilderUploadStatus? {
        guard let jobID = extra.jobID, extra.sentFileName == extra.fileName else { return nil }
        return backend.uploadStatus(jobID)
    }

    /// Every upload that is the current photo of its slot, with its state.
    private var currentJobs: [UUID] {
        slots.values.compactMap { $0.fileName != nil && $0.fileName == $0.sentFileName ? $0.jobID : nil }
            + extras.compactMap { $0.fileName != nil && $0.fileName == $0.sentFileName ? $0.jobID : nil }
    }

    /// Photos on their way, done of total, or nil when none are.
    var uploadProgress: (done: Int, total: Int, failed: Int)? {
        let jobs = currentJobs
        guard !jobs.isEmpty else { return nil }
        var done = 0, failed = 0
        for job in jobs {
            switch backend.uploadStatus(job)?.phase {
            case .done, nil: done += 1
            case .failed(final: true): failed += 1
            default: break
            }
        }
        return (done, jobs.count, failed)
    }

    var photosStillUploading: Bool {
        guard let progress = uploadProgress else { return false }
        return progress.done + progress.failed < progress.total
    }

    /// Put the phone's photos on the server: create the draft if there is
    /// none, then send every photo whose file is not the one already sent,
    /// delete removed extras, withdraw uploads that were overtaken. Runs on
    /// leaving the photo step, on closing with a draft, and before Approve.
    func syncPhotos() async {
        if syncing {
            syncAgain = true
            return
        }
        syncing = true
        defer { syncing = false }
        repeat {
            syncAgain = false
            await syncOnce()
        } while syncAgain
    }

    private func syncOnce() async {
        absorbFinishedUploads()
        let active = Set(currentJobsIncludingOvertaken.filter { !(backend.uploadStatus($0)?.isSettled ?? true) })
        let actions = PhotoSyncPlan.actions(slots: slots, extras: extras, removedExtras: removedExtras, activeJobs: active)
        guard !actions.isEmpty else { return }
        guard let listingID = await ensureDraft() else { return }
        photoSyncError = nil
        for action in actions {
            switch action {
            case let .upload(category, extraID, fileName, sortIndex, cancelling):
                if let cancelling { await backend.cancelUpload(cancelling) }
                let jobID = await backend.enqueueUpload(
                    listingID: listingID,
                    fileURL: photoURL(fileName),
                    category: category,
                    sortIndex: sortIndex
                )
                if let category, var slot = slots[category], slot.fileName == fileName {
                    slot.sentFileName = fileName
                    slot.jobID = jobID
                    slot.serverImageID = nil
                    slots[category] = slot
                } else if let extraID, let index = extras.firstIndex(where: { $0.id == extraID }),
                          extras[index].fileName == fileName {
                    extras[index].sentFileName = fileName
                    extras[index].jobID = jobID
                    extras[index].serverImageID = nil
                }
            case .delete(let imageID):
                do {
                    try await backend.deleteImage(listingID: listingID, imageID: imageID)
                    removedExtras.removeAll { $0.serverImageID == imageID }
                } catch {
                    photoSyncError = sellErrorMessage(error)
                }
            case .cancel(let jobID):
                await backend.cancelUpload(jobID)
                removedExtras.removeAll { $0.jobID == jobID && $0.serverImageID == nil }
            }
        }
        persistSnapshotNow()
    }

    /// Every job any slot still points at, the overtaken ones included.
    private var currentJobsIncludingOvertaken: [UUID] {
        slots.values.compactMap(\.jobID) + extras.compactMap(\.jobID)
    }

    /// Carry what finished uploads learned onto the slots: the server's image
    /// id (so a removed extra can be deleted), and a photo that gave up is
    /// marked unsent so the next sync tries it again.
    private func absorbFinishedUploads(retryingFailures: Bool = true) {
        for (category, slot) in slots {
            guard let jobID = slot.jobID, let status = backend.uploadStatus(jobID) else { continue }
            var updated = slot
            if status.phase == .done, let id = status.serverImageID { updated.serverImageID = id }
            if retryingFailures, status.phase == .failed(final: true) { updated.sentFileName = nil }
            if updated != slot { slots[category] = updated }
        }
        for index in extras.indices {
            guard let jobID = extras[index].jobID, let status = backend.uploadStatus(jobID) else { continue }
            if status.phase == .done, let id = status.serverImageID { extras[index].serverImageID = id }
            if retryingFailures, status.phase == .failed(final: true) { extras[index].sentFileName = nil }
        }
        for index in removedExtras.indices {
            guard let jobID = removedExtras[index].jobID, let status = backend.uploadStatus(jobID),
                  status.phase == .done, let id = status.serverImageID else { continue }
            removedExtras[index].serverImageID = id
        }
    }

    /// The draft the photos belong to, created from the answers so far if it
    /// does not exist yet. Nil (with the reason kept) when it could not be.
    @discardableResult
    func ensureDraft() async -> String? {
        if let listingID { return listingID }
        do {
            let id = try await backend.createDraft(body)
            listingID = id
            photoSyncError = nil
            persistSnapshotNow()
            return id
        } catch {
            photoSyncError = sellErrorMessage(error)
            // A link the server refused would ride on every retry.
            if sellErrorCode(error, is: "vault_watch_already_listed") {
                declineVault()
            }
            return nil
        }
    }

    // MARK: - Submit

    var isSubmitting: Bool { submitPhase != nil }

    /// Approve and submit: the photos are (nearly) all up already, so this is
    /// the remaining answers and the move to review. Waits, with the count on
    /// screen, if photos are still going.
    @discardableResult
    func submit() async -> Bool {
        guard submitPhase == nil, !submitted else { return false }
        sendError = nil
        submitPhase = .preparing
        defer { submitPhase = nil }

        // What the seller takes home and what a buyer sees are ours to show
        // before the listing goes in, not after.
        if mode == .live, currentPreview == nil {
            await loadMoneyNow()
            guard currentPreview != nil else {
                fail("We're still working out your payout and the price buyers will see. Both need to be on screen before this goes to review. Try again in a moment.", step: .review)
                return false
            }
        }

        await syncPhotos()
        guard let listingID else {
            fail(photoSyncError ?? "Something went wrong while submitting. Your answers are still here. Please try again.", step: .review)
            return false
        }

        while true {
            absorbFinishedUploads(retryingFailures: false)
            guard let progress = uploadProgress else { break }
            if progress.failed > 0 {
                fail("\(progress.failed == 1 ? "One photo" : "\(progress.failed) photos") didn\u{2019}t upload. Check your connection and tap Approve again: only \(progress.failed == 1 ? "that photo is" : "those photos are") sent again.", step: .review)
                return false
            }
            if progress.done >= progress.total { break }
            submitPhase = .uploading(done: progress.done, total: progress.total)
            try? await Task.sleep(for: .milliseconds(250))
        }

        submitPhase = .sending
        do {
            try await backend.updateListing(id: listingID, body: body)
            // Photos are on the server before this: the move to review checks them.
            try await backend.moveToReview(id: listingID)
        } catch {
            fail(sellErrorMessage(error), step: BuilderRules.serverErrorStep(error))
            return false
        }
        if let fulfillRequestID {
            await backend.fulfillWatchRequest(id: fulfillRequestID, listingID: listingID)
        }
        BuilderDraftStore.clear(listingID: listingID)
        submitted = true
        return true
    }

    private func fail(_ message: String, step target: BuilderStep) {
        sendError = SendError(message: message, step: target)
        if target != .review, target != step {
            returnTo = .review
            go(to: target, forward: false)
        }
    }

    // MARK: - Closing

    /// Closing with a draft worth keeping: create it if needed, send the photos
    /// and the answers so far, and remember the rest on the phone.
    func saveDraft() async -> Bool {
        guard let id = await ensureDraft() else { return false }
        await syncPhotos()
        try? await backend.updateListing(id: id, body: body)
        persistSnapshotNow()
        return true
    }

    #if DEBUG
    /// The preview harness: open on a step as if every one before it had
    /// been answered.
    func previewJump(to target: BuilderStep) {
        reached = max(reached, target.index)
        step = target
        line = BuilderRules.encouragement(target, answers, watch: watch)
        if answers.price != nil { scheduleMoney(immediately: true) }
    }
    #endif

    // MARK: - Remembering

    private func scheduleSnapshot() {
        guard listingID != nil else { return }
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistSnapshotNow()
        }
    }

    func persistSnapshotNow() {
        guard let listingID, mode == .live, !submitted else { return }
        BuilderDraftStore.save(BuilderSnapshot(
            listingID: listingID,
            photoFolder: activePhotoFolder.lastPathComponent,
            answers: answers,
            slots: Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) }),
            extras: extras,
            removedExtras: removedExtras,
            nextExtraSortIndex: nextExtraSortIndex,
            fulfillRequestID: fulfillRequestID,
            updatedAt: .now
        ))
    }
}

// MARK: - Draft memory

/// What the phone remembers about a builder draft beyond what the server
/// holds: photos not yet sent, and answers not yet saved. Written once the
/// draft exists, so a force-quit picks up where the seller stopped.
struct BuilderSnapshot: Codable {
    var listingID: String
    var photoFolder: String
    var answers: BuilderAnswers
    var slots: [String: BuilderPhotoSlot]
    var extras: [BuilderExtraPhoto]
    var removedExtras: [BuilderExtraPhoto]
    var nextExtraSortIndex: Int
    var fulfillRequestID: String?
    var updatedAt: Date

    var photoFolderURL: URL {
        BuilderDraftStore.photosRoot.appending(path: photoFolder, directoryHint: .isDirectory)
    }
}

enum BuilderDraftStore {
    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static var photosRoot: URL {
        base.appending(path: "Rewatch/SellPhotos", directoryHint: .isDirectory)
    }

    private static var folder: URL {
        let folder = base.appending(path: "Rewatch/SellBuilder", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func file(_ listingID: String) -> URL {
        folder.appending(path: "\(listingID).json")
    }

    static func save(_ snapshot: BuilderSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file(snapshot.listingID), options: .atomic)
    }

    static func load(listingID: String) -> BuilderSnapshot? {
        guard let data = try? Data(contentsOf: file(listingID)) else { return nil }
        return try? JSONDecoder().decode(BuilderSnapshot.self, from: data)
    }

    static func clear(listingID: String) {
        if let snapshot = load(listingID: listingID) {
            try? FileManager.default.removeItem(at: snapshot.photoFolderURL)
        }
        try? FileManager.default.removeItem(at: file(listingID))
    }
}
