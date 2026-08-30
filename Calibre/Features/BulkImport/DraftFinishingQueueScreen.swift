import CalibreDesign
import CalibreKit
import SwiftUI

/// One imported draft at a time: its own title and the facts that identify
/// it, the six photo slots shot with the camera, the eight grades, and then
/// the ordinary listing PATCH that sends it to review. Skip leaves the draft
/// exactly as it was.
///
/// An import creates drafts and nothing else — it never promotes a row — so
/// every draft here is waiting for a person, and finishing one is what puts
/// it in front of buyers. This is the primary place that work happens: the
/// photographs need a camera, and the camera is on the phone.
struct DraftFinishingQueueScreen: View {
    let jobID: String

    @Environment(AppServices.self) private var services
    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [ImportCompletionItem]?
    @State private var loadError: String?
    @State private var index = 0
    @State private var saving = false
    /// Drafts passed over with "Skip for now". Reaching the end with any of
    /// these left offers a second lap over just those, rather than making the
    /// dealer leave and re-enter the queue to find them again.
    @State private var skipped: Set<String> = []

    // Editors for the current item.
    @State private var conditions: [ConditionPart: String] = [:]
    @State private var yearText = ""
    @State private var descriptionText = ""
    @State private var captureTarget: CaptureTarget?
    /// Upload jobs started for the current listing, keyed by category.
    @State private var photoJobs: [String: UUID] = [:]
    /// Photos the listing already carries, keyed by category — a draft that
    /// was part-finished on an earlier visit opens with those slots filled.
    @State private var existingPhotoCategories: Set<String> = []
    /// Photos the CSV brought as bare URLs, which carry no angle. They are
    /// what lets an imported draft go to review without six camera shots —
    /// right up until the first camera shot lands.
    @State private var existingUncategorizedPhotos = 0
    /// How many drafts this pass sent to review, for the closing screen.
    @State private var sentForReview = 0
    /// The server's own refusal when a submit is turned down — the
    /// missing-grades sentence is shown exactly as it was written.
    @State private var submitNote: String?

    var body: some View {
        Group {
            if let queue {
                if queue.isEmpty {
                    EmptyState(
                        icon: "checkmark.circle",
                        title: "Every draft is complete",
                        message: "Nothing from this import needs attention — submit them from your shop whenever you're ready."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if index < queue.count {
                    // Keyed on the item so each draft opens at the top of its
                    // own form — the scroll offset used to carry over from the
                    // draft before it, landing the next watch mid-page.
                    itemEditor(queue[index], position: index + 1, total: queue.count)
                        .id(queue[index].id)
                } else if !skipped.isEmpty {
                    EmptyState(
                        icon: "arrow.uturn.backward",
                        title: "\(skipped.count) draft\(skipped.count == 1 ? "" : "s") still waiting",
                        message: "You skipped \(skipped.count == 1 ? "one" : "\(skipped.count)"). Take another lap through just those, or come back to them from your shop.",
                        actionTitle: "Finish the skipped \(skipped.count == 1 ? "one" : "ones")",
                        action: { replaySkipped() }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(
                        icon: "checkmark.circle",
                        title: "That's the queue",
                        message: closingMessage,
                        actionTitle: "Done",
                        action: { dismiss() }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let loadError {
                EmptyState(
                    icon: "tray.and.arrow.down",
                    title: "The queue didn't load",
                    message: loadError,
                    actionTitle: "Try again",
                    action: { Task { await load() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: Space.l) {
                    Rectangle().frame(maxWidth: .infinity).frame(height: 140).shimmer()
                    Rectangle().frame(maxWidth: .infinity).frame(height: 240).shimmer()
                    Spacer()
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calibrePageBackground()
        .navigationTitle("Finish drafts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .fullScreenCover(item: $captureTarget) { target in
            CaptureScreen(target: target) { image in
                Task { await attach(image: image, category: target.category) }
            }
        }
    }

    /// What this pass actually did. Anything skipped is still a draft and is
    /// still reachable — an import never sends a listing to review on its own.
    private var closingMessage: String {
        if sentForReview > 0 {
            return "\(sentForReview) listing\(sentForReview == 1 ? "" : "s") went to review. Anything you skipped is still a draft — pick it up from Continue bulk import whenever you like."
        }
        return "Anything you skipped is still a draft — pick it up from Continue bulk import whenever you like."
    }

    private func load() async {
        loadError = nil
        do {
            let loaded = try await services.seller.importCompletionQueue(jobID: jobID)
            // These drafts are provably bulk-imported. Nothing on the wire says
            // so later, and they are submitted from the shop, so record them
            // now for `listing_submitted.source`.
            Analytics.noteBulkImportedDrafts(loaded.map(\.id))
            queue = loaded
            index = 0
            skipped = []
            prepareEditors()
        } catch {
            loadError = sellErrorMessage(error)
        }
    }

    private var current: ImportCompletionItem? {
        guard let queue, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    private func prepareEditors() {
        conditions = [:]
        yearText = ""
        descriptionText = ""
        photoJobs = [:]
        existingPhotoCategories = []
        existingUncategorizedPhotos = 0
        submitNote = nil
        guard let item = current else { return }
        yearText = item.productionYear.map(String.init) ?? ""
        descriptionText = item.description ?? ""
        // Whatever the CSV carried, exactly as it carried it. Nothing is
        // derived from anything else — a blank grade stays blank until the
        // seller grades it.
        conditions[.watchCase] = item.conditionCase
        conditions[.dial] = item.conditionDial
        conditions[.bezel] = item.conditionBezel
        conditions[.crystal] = item.conditionCrystal
        conditions[.bracelet] = item.conditionBracelet
        conditions[.clasp] = item.conditionClasp
        conditions[.caseback] = item.conditionCaseback
        conditions[.overall] = item.conditionOverall
        for part in ConditionPart.allCases where conditions[part]?.isEmpty == true {
            conditions[part] = nil
        }
        Task { await loadExistingPhotos(listingID: item.id) }
    }

    /// Which of the six slots already have a photo on the server. A draft
    /// part-finished on an earlier visit should not ask for those again.
    private func loadExistingPhotos(listingID: String) async {
        guard let images = try? await services.seller.images(listingID: listingID) else { return }
        guard current?.id == listingID else { return }
        existingPhotoCategories = Set(images.compactMap(\.category))
        existingUncategorizedPhotos = images.filter { ($0.category ?? "").isEmpty }.count
    }

    // MARK: - Editor

    private func itemEditor(_ item: ImportCompletionItem, position: Int, total: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow("Draft \(position) of \(total)")
                    Text(item.title ?? "Imported listing")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s) {
                        if let number = item.listingNumber {
                            Text("#\(number)")
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        if let price = item.price {
                            Text(PriceFormatter.format(price.value))
                                .font(CalibreType.priceSmall)
                                .foregroundStyle(Color.calibre.foreground)
                        }
                    }
                    if !identityLine(item).isEmpty {
                        Text(identityLine(item))
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    missingChips(item)
                }

                // A CSV cannot carry photographs, so the six slots are always
                // on screen here. Every one of them is a camera shot.
                photoSection

                conditionSection(ConditionPart.allCases)

                if item.missing.contains("production_year") {
                    CalibreTextField(
                        "Year",
                        text: $yearText,
                        placeholder: "2019",
                        error: yearText.isEmpty || InputValidation.productionYear(yearText) != nil
                            ? nil
                            : "Enter a valid 4-digit year.",
                        kind: .integer
                    )
                }

                if item.missing.contains("description") {
                    CalibreTextEditor(
                        "Description",
                        text: $descriptionText,
                        placeholder: "How it wears, what's included…",
                        minHeight: 100,
                        characterLimit: 2_000
                    )
                    .onChange(of: descriptionText) { _, value in
                        if value.count > 2_000 {
                            descriptionText = String(value.prefix(2_000))
                        }
                    }
                }

                if let message = incompleteMessage {
                    Text(message)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                HStack(spacing: Space.m) {
                    Button("Skip for now") {
                        skipped.insert(item.id)
                        advance()
                    }
                    .buttonStyle(.calibreGhost)

                    Button {
                        Task { await saveAndNext(item) }
                    } label: {
                        if saving {
                            ProgressView().tint(Color.calibre.primaryForeground)
                        } else {
                            Text(willSubmit ? "Send to review" : "Save & next")
                        }
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(saving || !canSave)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// SKU first: it is the seller's own name for the watch and the only key
    /// the import ever matched on. The reference is descriptive and follows.
    private func identityLine(_ item: ImportCompletionItem) -> String {
        var parts: [String] = []
        if let sku = item.sellerSku, !sku.isEmpty { parts.append("SKU \(sku)") }
        if let reference = item.reference, !reference.isEmpty { parts.append("Ref. \(reference)") }
        if let brand = item.brand, !brand.isEmpty, item.title == nil { parts.append(brand) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func missingChips(_ item: ImportCompletionItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(item.missing, id: \.self) { key in
                    StatusBadge(missingLabel(key), tone: .warning)
                }
            }
        }
    }

    private func missingLabel(_ key: String) -> String {
        switch key {
        case "photos": "Photos"
        case "production_year": "Year"
        case "description": "Description"
        case "condition_overall": "Overall condition"
        case "condition_case": "Case condition"
        case "condition_bracelet": "Bracelet condition"
        case "condition_dial": "Dial condition"
        case "condition_bezel": "Bezel condition"
        case "condition_crystal": "Crystal condition"
        case "condition_clasp": "Clasp condition"
        case "condition_caseback": "Caseback condition"
        default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Photos")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
            Text("A spreadsheet can\u{2019}t carry pictures, so all six are taken here. Tap a slot and shoot it \u{2014} the same six angles every Calibre listing carries.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.l) {
                    ForEach(ListingImageCategory.allCases, id: \.self) { category in
                        VStack(spacing: Space.s) {
                            Button {
                                captureTarget = CaptureTarget(category: category)
                            } label: {
                                PhotoSlotRing(phase: photoPhase(category), size: 60)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("\(category.label) photo")
                            // Naming the angle here replaces the ring's own
                            // label, which is the only thing that said whether
                            // the slot was shot — the phase has to come back
                            // as the value. Same shape as ReturnFlow.
                            .accessibilityValue(photoPhaseValue(category))
                            Text(category.label)
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// The slot's phase, spoken as the button's value — see the call site.
    private func photoPhaseValue(_ category: ListingImageCategory) -> String {
        switch photoPhase(category) {
        case .empty: "not taken"
        case .uploading(let progress): "uploading, \(Int((progress * 100).rounded())) percent"
        case .done: "taken"
        case .failed: "upload failed"
        }
    }

    private func photoPhase(_ category: ListingImageCategory) -> PhotoSlotPhase {
        guard let jobID = photoJobs[category.rawValue], let entry = sell.board.entry(for: jobID) else {
            // Nothing shot this visit — the slot is filled only if the server
            // already holds a photo for that angle.
            return existingPhotoCategories.contains(category.rawValue) ? .done : .empty
        }
        switch entry.state {
        case .queued: return .uploading(0)
        case .uploading: return .uploading(entry.fraction)
        case .done: return .done
        case .failed: return .failed
        }
    }

    /// Exactly the rule the server applies, and no stricter.
    ///
    /// A draft whose only pictures came from the CSV carries no angles at
    /// all, and may go to review on those alone. The moment one categorized
    /// shot lands, the listing is a wizard-graded listing and all six are
    /// required — which is why shooting three would be refused, and why this
    /// asks for six as soon as the seller takes the first.
    private var photosSatisfyTheGate: Bool {
        let shot = ListingImageCategory.allCases.filter { photoPhase($0) == .done }
        if shot.isEmpty {
            return existingUncategorizedPhotos > 0
        }
        return shot.count == ListingImageCategory.allCases.count
    }


    private var allGradesPresent: Bool {
        ConditionPart.allCases.allSatisfy { conditions[$0] != nil }
    }

    private func attach(image: UIImage, category: ListingImageCategory?) async {
        guard let item = current else { return }
        let label = category?.rawValue ?? "extra"
        guard let url = PhotoPipeline.store(image, listingID: item.id, label: label) else {
            toasts.show(title: "That photo couldn't be processed", tone: .error)
            return
        }
        let jobID = await sell.uploads.enqueue(
            draftID: item.id,
            listingID: item.id,
            category: category?.rawValue,
            fileURL: url
        )
        photoJobs[label] = jobID
    }

    // MARK: Save & advance

    /// Saving is always allowed: a partly-finished draft is still worth
    /// keeping, and skipping one costs the seller nothing. The only thing
    /// that can block it is a year that has been typed wrong. What
    /// completeness decides is whether the save also submits.
    private var canSave: Bool {
        yearText.isEmpty || InputValidation.productionYear(yearText) != nil
    }

    /// Whether this save will also send the draft to review. The server has
    /// the last word — this only decides which sentence to show and whether
    /// to ask.
    private var willSubmit: Bool {
        allGradesPresent && photosSatisfyTheGate
    }

    /// The one sentence under the button: what this save will actually do,
    /// or — after a refusal — the server's own words for why it didn't.
    private var incompleteMessage: String? {
        if let submitNote { return submitNote }
        if willSubmit {
            return "Everything\u{2019}s here \u{2014} saving sends this listing to review."
        }
        var waiting: [String] = []
        if !photosSatisfyTheGate {
            let missing = ListingImageCategory.allCases.filter { photoPhase($0) != .done }
            waiting.append("\(missing.count) photo\(missing.count == 1 ? "" : "s")")
        }
        if !allGradesPresent {
            let missing = ConditionPart.allCases.filter { conditions[$0] == nil }
            waiting.append("\(missing.count) grade\(missing.count == 1 ? "" : "s")")
        }
        if waiting.isEmpty { return "Saving updates this listing." }
        return "Still waiting on \(waiting.joined(separator: " and ")) \u{2014} saving keeps this one a draft."
    }

    private func saveAndNext(_ item: ImportCompletionItem) async {
        guard canSave, !saving else { return }
        saving = true
        submitNote = nil
        defer { saving = false }
        let payload = ListingDraftPayload(
            description: InputValidation.isNonBlank(descriptionText)
                ? InputValidation.trimmed(descriptionText)
                : nil,
            // Exactly as graded, all eight, nothing derived from anything.
            conditionOverall: conditions[.overall],
            conditionCase: conditions[.watchCase],
            conditionBracelet: conditions[.bracelet],
            conditionDial: conditions[.dial],
            conditionBezel: conditions[.bezel],
            conditionCrystal: conditions[.crystal],
            conditionClasp: conditions[.clasp],
            conditionCaseback: conditions[.caseback],
            productionYear: InputValidation.productionYear(yearText)
        )
        do {
            _ = try await services.seller.updateListing(id: item.id, payload)
        } catch {
            toasts.show(title: "Couldn\u{2019}t save", message: sellErrorMessage(error), tone: .error)
            return
        }

        if willSubmit {
            do {
                // The ordinary listing PATCH, which is where the submit gate
                // lives. A refusal is the server's own sentence — it names
                // the grades or the angles that are still missing — and it is
                // shown as written rather than translated.
                let submitted = try await services.seller.submitForReview(listingID: item.id)
                sentForReview += 1
                Analytics.listingSubmitted(
                    .init(submitted),
                    source: Analytics.listingSource(for: submitted.id)
                )
            } catch {
                submitNote = sellErrorMessage(error)
                toasts.show(
                    title: "Saved as a draft",
                    message: sellErrorMessage(error),
                    tone: .neutral
                )
                return
            }
        }

        skipped.remove(item.id)
        Haptics.shared.play(.save)
        advance()
    }

    /// The "Save & next" rhythm — skip leaves the draft untouched.
    private func advance() {
        withAnimation(Motion.easeMedium) {
            index += 1
        }
        prepareEditors()
    }

    /// A second lap over only what was skipped, in place — no re-fetch, no
    /// trip back to the job list.
    private func replaySkipped() {
        guard let queue else { return }
        let remaining = queue.filter { skipped.contains($0.id) }
        guard !remaining.isEmpty else {
            skipped = []
            return
        }
        withAnimation(Motion.easeMedium) {
            self.queue = remaining
            index = 0
        }
        skipped = []
        prepareEditors()
    }

    // MARK: Condition editor

    private func conditionSection(_ parts: [ConditionPart]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Condition")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
            SellCard {
                VStack(spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.element) { partIndex, part in
                        HStack {
                            Text(part.label)
                                .font(CalibreType.body)
                                .foregroundStyle(Color.calibre.mutedForeground)
                            Spacer()
                            Menu {
                                ForEach(ConditionPart.grades, id: \.self) { grade in
                                    Button(grade) {
                                        conditions[part] = grade
                                        Haptics.shared.play(.selection)
                                    }
                                }
                            } label: {
                                HStack(spacing: Space.s) {
                                    Text(conditions[part] ?? "Select")
                                        .font(CalibreType.bodyMedium)
                                        .foregroundStyle(
                                            conditions[part] == nil
                                                ? Color.calibre.placeholder
                                                : Color.calibre.foreground
                                        )
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.calibre.mutedForeground)
                                }
                                .frame(minHeight: Space.touchTarget)
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: Space.touchTarget)
                        if partIndex < parts.count - 1 {
                            Rectangle().fill(Color.calibre.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}
