import CalibreDesign
import CalibreKit
import SwiftUI

/// One imported listing at a time: shows exactly what's missing (photos,
/// condition, year, description), saves, and moves to the next. Skip leaves
/// the draft for later.
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

    // Editors for the current item.
    @State private var conditions: [ConditionPart: String] = [:]
    @State private var yearText = ""
    @State private var descriptionText = ""
    @State private var captureTarget: CaptureTarget?
    /// Upload jobs started for the current listing, keyed by category.
    @State private var photoJobs: [String: UUID] = [:]

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
                    itemEditor(queue[index], position: index + 1, total: queue.count)
                } else {
                    EmptyState(
                        icon: "checkmark.circle",
                        title: "That's the queue",
                        message: "Every draft you finished is ready to submit from your shop.",
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
        .background(Color.calibre.background.ignoresSafeArea())
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

    private func load() async {
        loadError = nil
        do {
            queue = try await services.seller.importCompletionQueue(jobID: jobID)
            index = 0
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
        guard let item = current else { return }
        yearText = item.productionYear.map(String.init) ?? ""
        descriptionText = item.description ?? ""
        // Prefill known grades from the cached inventory copy, if present.
        if let listing = services.seller.myListings.first(where: { $0.id == item.id }),
           let condition = listing.condition {
            conditions[.crystal] = condition.crystal
            conditions[.bezel] = condition.bezel
            conditions[.bracelet] = condition.bracelet
            conditions[.clasp] = condition.clasp
            conditions[.caseback] = condition.caseback
            conditions[.overall] = condition.overall
        }
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
                    missingChips(item)
                }

                if item.missing.contains("photos") {
                    photoSection
                }

                if missingConditionParts(item).isEmpty == false {
                    conditionSection(missingConditionParts(item))
                }

                if item.missing.contains("production_year") {
                    CalibreTextField("Year", text: $yearText, placeholder: "2019")
                        .keyboardType(.numberPad)
                }

                if item.missing.contains("description") {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Description")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        TextEditor(text: $descriptionText)
                            .font(CalibreType.body)
                            .foregroundStyle(Color.calibre.foreground)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                            .padding(Space.m)
                            .background(
                                Color.calibre.card,
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .strokeBorder(Color.calibre.border, lineWidth: 1)
                            )
                    }
                }

                HStack(spacing: Space.m) {
                    Button("Skip for now") {
                        advance()
                    }
                    .buttonStyle(.calibreGhost)

                    Button {
                        Task { await saveAndNext(item) }
                    } label: {
                        if saving {
                            ProgressView().tint(Color.calibre.primaryForeground)
                        } else {
                            Text("Save & next")
                        }
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(saving)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
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

    /// The condition parts this item still needs, in wizard order.
    private func missingConditionParts(_ item: ImportCompletionItem) -> [ConditionPart] {
        var parts: [ConditionPart] = []
        for key in item.missing {
            switch key {
            case "condition_crystal", "condition_dial": parts.append(.crystal)
            case "condition_bezel": parts.append(.bezel)
            case "condition_bracelet": parts.append(.bracelet)
            case "condition_clasp": parts.append(.clasp)
            case "condition_caseback", "condition_case": parts.append(.caseback)
            case "condition_overall": parts.append(.overall)
            default: break
            }
        }
        return ConditionPart.allCases.filter { parts.contains($0) }
    }

    // MARK: Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Photos")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
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

    private func photoPhase(_ category: ListingImageCategory) -> PhotoSlotPhase {
        guard let jobID = photoJobs[category.rawValue], let entry = sell.board.entry(for: jobID) else {
            return .empty
        }
        switch entry.state {
        case .queued: return .uploading(0)
        case .uploading: return .uploading(entry.fraction)
        case .done: return .done
        case .failed: return .failed
        }
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

    private func saveAndNext(_ item: ImportCompletionItem) async {
        saving = true
        defer { saving = false }
        let payload = ListingDraftPayload(
            description: descriptionText.isEmpty ? nil : descriptionText,
            conditionOverall: conditions[.overall],
            conditionBracelet: conditions[.bracelet],
            conditionBezel: conditions[.bezel],
            conditionCrystal: conditions[.crystal],
            conditionClasp: conditions[.clasp],
            conditionCaseback: conditions[.caseback],
            productionYear: Int(yearText.trimmingCharacters(in: .whitespaces))
        )
        do {
            _ = try await services.seller.updateListing(id: item.id, payload)
            Haptics.shared.play(.save)
            advance()
        } catch {
            toasts.show(title: "Couldn't save", message: sellErrorMessage(error), tone: .error)
        }
    }

    /// The "Save & next" rhythm — skip leaves the draft untouched.
    private func advance() {
        withAnimation(Motion.easeMedium) {
            index += 1
        }
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
