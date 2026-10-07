import RewatchDesign
import RewatchKit
import NukeUI
import SwiftUI

// MARK: - Step 4 · Review & submit

struct ReviewStep: View {
    @Bindable var model: WizardModel
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            hero

            VStack(alignment: .leading, spacing: Space.xs) {
                if !model.brand.isEmpty {
                    Eyebrow([model.brand, model.yearUnknown ? nil : model.yearText]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                }
                Text(model.composedTitle)
                    .font(RewatchType.title)
                    .foregroundStyle(Color.rewatch.foreground)
            }

            conditionGrid

            historyCard

            priceCard

            photoChecklist

            // A disabled Submit never calls `onSubmit()`, so `submitError`
            // (set only inside the model's `submit()`) would otherwise never
            // populate — show what's missing directly instead of leaving a
            // silently inert button.
            if let error = model.submitError {
                Text(error)
                    .font(RewatchType.label)
                    .foregroundStyle(Color.rewatch.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if !canSubmitMissing.isEmpty {
                Text("Missing: \(canSubmitMissing.joined(separator: ", "))")
                    .font(RewatchType.label)
                    .foregroundStyle(Color.rewatch.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            VStack(spacing: Space.s) {
                Button {
                    onSubmit()
                } label: {
                    // The words stay while it submits — a blank button at the
                    // moment a listing goes to review reads as a failure.
                    RewatchBusyLabel(
                        model.isEdit ? "Resubmit for approval" : "Submit for review",
                        busy: model.submitting
                    )
                }
                .buttonStyle(.rewatch(.primary, fullWidth: true))
                .disabled(!canSubmit || model.submitting)
                .accessibilityIdentifier("listing-wizard-submit")

                // Net proceeds and the buyer-facing price are ours to put on
                // screen before a seller publishes, so their absence is worth
                // saying out loud rather than leaving an inert button.
                if !model.payoutDisclosed, model.price != nil {
                    Text("Your net proceeds and the price buyers will see need to be on screen before this goes to review.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if model.isEdit {
                    Text("Resubmit for approval — your watch leaves the market until re-approved.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if !model.detailsComplete {
                    Text("Finish the watch details, grade each condition item and answer the three history questions before review.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if !model.priceDetailsComplete {
                    Text("Add an asking price and notes for buyers before review.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if !model.allRequiredPhotosDone {
                    Text("All six photos need to finish uploading before review.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(Motion.easeFast, value: model.submitError)
    }

    /// `payoutDisclosed` is part of this on purpose: a seller may not submit
    /// without having seen their net proceeds and the buyer-facing price.
    private var canSubmit: Bool {
        model.detailsComplete && model.allRequiredPhotosDone && model.priceDetailsComplete
            && model.payoutDisclosed
    }

    private var canSubmitMissing: [String] {
        var missing = model.detailsMissing + model.priceMissing
        if !model.allRequiredPhotosDone { missing.append("All six photos") }
        return missing
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        let slot = model.slots[.front]
        ZStack {
            if let localURL = slot?.localURL, let image = UIImage(contentsOfFile: localURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = slot?.remoteURL {
                LazyImage(url: remoteURL) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.rewatch.secondary.opacity(0.5)
                    }
                }
            } else {
                VStack(spacing: Space.s) {
                    Image(systemName: "camera")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.rewatch.placeholder)
                    Text("The front shot becomes your hero photo.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Color.rewatch.secondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Condition

    /// The eight grades as `SpecList` draws a row, with each note under its
    /// part exactly as the listing will show it (`ConditionGradeRow`, in the
    /// hand), so the seller reads their own words back before they go out.
    private var conditionGrid: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Condition")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)
            VStack(spacing: 0) {
                ForEach(Array(ConditionPart.allCases.enumerated()), id: \.element) { index, part in
                    let grade = model.conditions[part] ?? "Not graded"
                    ConditionGradeRow(
                        label: part.label,
                        grade: grade,
                        note: conditionNoteText(model.conditionNotes[part].map(ConditionNote.normalized))
                    ) {
                        Text(grade)
                            .font(RewatchType.bodyMedium)
                            .foregroundStyle(Color.rewatch.foreground)
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)

                    if index < ConditionPart.allCases.count - 1 {
                        Rectangle()
                            .fill(Color.rewatch.border)
                            .frame(height: 1)
                    }
                }
            }
            .background(Color.rewatch.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewatch.border, lineWidth: 1)
            )
        }
    }

    // MARK: History

    /// The three history answers in the words the listing will print them
    /// in, so the seller reads back exactly what a buyer will.
    private var historyCard: some View {
        let rows = model.history.reviewRows(currentYear: model.currentYear)
        return VStack(alignment: .leading, spacing: Space.m) {
            Text("History")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    ConditionGradeRow(label: row.label, grade: row.value, note: nil) {
                        Text(row.value)
                            .font(RewatchType.bodyMedium)
                            .foregroundStyle(Color.rewatch.foreground)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)

                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Color.rewatch.border)
                            .frame(height: 1)
                    }
                }
            }
            .background(Color.rewatch.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewatch.border, lineWidth: 1)
            )
        }
    }

    // MARK: Price

    /// Net proceeds and the buyer-facing price, both straight from the
    /// server's publish preview — a seller sees exactly these two figures
    /// before anything goes to review.
    private var priceCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Price")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)
            SellCard {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(model.price.map { PriceFormatter.listing($0) } ?? "No price yet")
                        .font(RewatchType.priceLarge)
                        .foregroundStyle(
                            model.price == nil ? Color.rewatch.placeholder : Color.rewatch.foreground
                        )

                    if let preview = model.preview {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("You'll receive \(PriceFormatter.format(preview.netProceeds.value, currency: preview.currency))")
                                .font(RewatchType.bodyMedium)
                                .foregroundStyle(Color.rewatch.foreground)
                            Text("Buyers see \(PriceFormatter.format(preview.buyerDisplay.standard.price.value, currency: preview.currency))")
                                .font(RewatchType.label)
                                .foregroundStyle(Color.rewatch.mutedForeground)
                        }
                        .accessibilityElement(children: .combine)

                        if preview.commission.minimumApplied {
                            Text("Every sale carries a minimum commission of \(PriceFormatter.format(preview.commission.minimum.value, currency: preview.currency)), and on this price that minimum is what applies.")
                                .font(RewatchType.caption)
                                .foregroundStyle(Color.rewatch.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if model.previewing {
                        HStack(spacing: Space.s) {
                            RewatchInlineLoading(size: 18)
                            Text("Working out what you'll receive")
                                .font(RewatchType.label)
                                .foregroundStyle(Color.rewatch.mutedForeground)
                        }
                    } else if model.price != nil {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("We couldn't work out your net proceeds just now, and we won't guess at them. Try again before this goes to review.")
                                .font(RewatchType.label)
                                .foregroundStyle(Color.rewatch.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                            RetryButton(variant: .ghost) {
                                await model.refreshPreview()
                            }
                            .frame(minHeight: Space.touchTarget, alignment: .leading)
                        }
                    }

                    Rectangle().fill(Color.rewatch.border).frame(height: 1)

                    Text(returnTermsText)
                        .font(RewatchType.label)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
            }
        }
        .task { await model.ensurePreview() }
    }

    /// The terms the seller chose, and the payout timing that follows.
    private var returnTermsText: String {
        guard model.returnsAccepted else {
            return "No returns. Your payout releases when authentication passes."
        }
        guard let hours = model.returnWindowHours else {
            return "Returns accepted. Your payout releases when the return window closes."
        }
        return "\(hours)-hour returns. Your payout releases when that window closes."
    }

    // MARK: Photo checklist

    private var photoChecklist: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Photos")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)
            SellCard {
                VStack(spacing: 0) {
                    ForEach(Array(ListingImageCategory.allCases.enumerated()), id: \.element) { index, category in
                        checklistRow(category)
                        if index < ListingImageCategory.allCases.count - 1 {
                            Rectangle().fill(Color.rewatch.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func checklistRow(_ category: ListingImageCategory) -> some View {
        let phase = model.phase(for: category)
        return HStack(spacing: Space.m) {
            statusIcon(phase)
            Text(category.label)
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.foreground)
            Spacer()
            Text(statusText(phase))
                .font(RewatchType.caption)
                .foregroundStyle(statusColor(phase))
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusIcon(_ phase: PhotoSlotPhase) -> some View {
        switch phase {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.rewatch.success)
        case .uploading:
            // Deliberately not the balance wheel. Every photo slot draws one
            // of these, so a batch upload would put a row of looping marks on
            // one screen, and the marks budget allows one.
            ProgressView().controlSize(.small).tint(Color.rewatch.primary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.rewatch.destructive)
        case .empty:
            Image(systemName: "circle.dashed")
                .foregroundStyle(Color.rewatch.placeholder)
        }
    }

    private func statusText(_ phase: PhotoSlotPhase) -> String {
        switch phase {
        case .done: "Uploaded"
        case .uploading(let fraction): fraction > 0 ? "Uploading \(Int(fraction * 100))%" : "Uploading"
        case .failed: "Upload failed"
        case .empty: "Still needed"
        }
    }

    private func statusColor(_ phase: PhotoSlotPhase) -> Color {
        switch phase {
        case .done: Color.rewatch.success
        case .uploading: Color.rewatch.mutedForeground
        case .failed: Color.rewatch.destructive
        case .empty: Color.rewatch.mutedForeground
        }
    }
}
