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
            } else if !canSubmit {
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

                if model.isEdit {
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

    private var canSubmit: Bool {
        model.detailsComplete && model.allRequiredPhotosDone && model.priceDetailsComplete
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

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Price")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            SellCard {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(model.price.map { PriceFormatter.format($0) } ?? "No price yet")
                            .font(CalibreType.priceLarge)
                            .foregroundStyle(
                                model.price == nil ? Color.calibre.placeholder : Color.calibre.foreground
                            )
                        if let payout = model.payout {
                            Text("You'll receive ≈ \(PriceFormatter.format(max(payout, 0)))")
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                    }
                    Spacer()
                }
                .padding(Space.l)
            }
        }
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
