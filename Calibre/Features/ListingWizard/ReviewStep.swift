import CalibreDesign
import CalibreKit
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
                    .font(CalibreType.title)
                    .foregroundStyle(Color.calibre.foreground)
            }

            conditionGrid

            priceCard

            photoChecklist

            // A disabled Submit never calls `onSubmit()`, so `submitError`
            // (set only inside the model's `submit()`) would otherwise never
            // populate — show what's missing directly instead of leaving a
            // silently inert button.
            if let error = model.submitError {
                Text(error)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if !canSubmitMissing.isEmpty {
                Text("Missing: \(canSubmitMissing.joined(separator: ", "))")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            VStack(spacing: Space.s) {
                Button {
                    onSubmit()
                } label: {
                    if model.submitting {
                        ProgressView().tint(Color.calibre.primaryForeground)
                    } else {
                        Text(model.isEdit ? "Resubmit for approval" : "Submit for review")
                    }
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(!canSubmit || model.submitting)

                // Net proceeds and the buyer-facing price are ours to put on
                // screen before a seller publishes, so their absence is worth
                // saying out loud rather than leaving an inert button.
                if !model.payoutDisclosed, model.price != nil {
                    Text("Your net proceeds and the price buyers will see need to be on screen before this goes to review.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if model.isEdit {
                    Text("Resubmit for approval — your watch leaves the market until re-approved.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if !model.detailsComplete {
                    Text("Finish the watch details and grade each condition item before review.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if !model.priceDetailsComplete {
                    Text("Add an asking price and notes for buyers before review.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if !model.allRequiredPhotosDone {
                    Text("All six photos need to finish uploading before review.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
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
                        Color.calibre.secondary.opacity(0.5)
                    }
                }
            } else {
                VStack(spacing: Space.s) {
                    Image(systemName: "camera")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.calibre.placeholder)
                    Text("The front shot becomes your hero photo.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Color.calibre.secondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Condition

    private var conditionGrid: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Condition")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            SpecList(ConditionPart.allCases.map { part in
                (part.label, model.conditions[part] ?? "Not graded")
            })
        }
    }

    // MARK: Price

    /// Net proceeds and the buyer-facing price, both straight from the
    /// server's publish preview — a seller sees exactly these two figures
    /// before anything goes to review.
    private var priceCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Price")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            SellCard {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(model.price.map { PriceFormatter.format($0) } ?? "No price yet")
                        .font(CalibreType.priceLarge)
                        .foregroundStyle(
                            model.price == nil ? Color.calibre.placeholder : Color.calibre.foreground
                        )

                    if let preview = model.preview {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("You'll receive \(PriceFormatter.format(preview.netProceeds.value, currency: preview.currency))")
                                .font(CalibreType.bodyMedium)
                                .foregroundStyle(Color.calibre.foreground)
                            Text("Buyers see \(PriceFormatter.format(preview.buyerDisplay.standard.price.value, currency: preview.currency))")
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        .accessibilityElement(children: .combine)

                        if preview.commission.minimumApplied {
                            Text("Every sale carries a minimum commission of \(PriceFormatter.format(preview.commission.minimum.value, currency: preview.currency)), and on this price that minimum is what applies.")
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if model.previewing {
                        HStack(spacing: Space.s) {
                            ProgressView().controlSize(.small).tint(Color.calibre.primary)
                            Text("Working out what you'll receive")
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                    } else if model.price != nil {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("We couldn't work out your net proceeds just now, and we won't guess at them. Try again before this goes to review.")
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Try again") {
                                Task { await model.refreshPreview() }
                            }
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.primary)
                            .buttonStyle(PressableStyle())
                            .frame(minHeight: Space.touchTarget, alignment: .leading)
                        }
                    }

                    Rectangle().fill(Color.calibre.border).frame(height: 1)

                    Text(returnTermsText)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
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
        return "Returns accepted, with a \(hours)-hour window. Your payout releases when that window closes."
    }

    // MARK: Photo checklist

    private var photoChecklist: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Photos")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            SellCard {
                VStack(spacing: 0) {
                    ForEach(Array(ListingImageCategory.allCases.enumerated()), id: \.element) { index, category in
                        checklistRow(category)
                        if index < ListingImageCategory.allCases.count - 1 {
                            Rectangle().fill(Color.calibre.border).frame(height: 1)
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
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.foreground)
            Spacer()
            Text(statusText(phase))
                .font(CalibreType.caption)
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
                .foregroundStyle(Color.calibre.success)
        case .uploading:
            ProgressView().controlSize(.small).tint(Color.calibre.primary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.calibre.destructive)
        case .empty:
            Image(systemName: "circle.dashed")
                .foregroundStyle(Color.calibre.placeholder)
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
        case .done: Color.calibre.success
        case .uploading: Color.calibre.mutedForeground
        case .failed: Color.calibre.destructive
        case .empty: Color.calibre.mutedForeground
        }
    }
}
