import CalibreDesign
import CalibreKit
import NukeUI
import SwiftUI

// MARK: - Step 1 · Details

struct DetailsStep: View {
    @Bindable var model: WizardModel
    @State private var showGradeGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.l) {
                CalibreTextField("Brand", text: $model.brand, placeholder: "Rolex")
                    .onChange(of: model.brand) { _, _ in model.fieldChanged() }
                CalibreTextField("Model", text: $model.model, placeholder: "Submariner Date")
                    .onChange(of: model.model) { _, _ in model.fieldChanged() }
                CalibreTextField("Reference", text: $model.reference, placeholder: "116610LN")
                    .onChange(of: model.reference) { _, _ in model.fieldChanged() }
                Text("Unusual brands still go to review.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }

            VStack(alignment: .leading, spacing: Space.m) {
                CalibreTextField("Year", text: $model.yearText, placeholder: "2019")
                    .keyboardType(.numberPad)
                    .disabled(model.yearUnknown)
                    .opacity(model.yearUnknown ? 0.5 : 1)
                    .onChange(of: model.yearText) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(4))
                        if digits != newValue {
                            model.yearText = digits
                        }
                        model.fieldChanged()
                    }
                Toggle(isOn: $model.yearUnknown) {
                    Text("Year unknown")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.foreground)
                }
                .tint(Color.calibre.primary)
                .onChange(of: model.yearUnknown) { _, _ in model.fieldChanged() }
            }

            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Condition")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                    Spacer()
                    Button("How we grade") {
                        showGradeGuide = true
                    }
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.primary)
                    .buttonStyle(PressableStyle())
                }

                SellCard {
                    VStack(spacing: 0) {
                        ForEach(Array(ConditionPart.allCases.enumerated()), id: \.element) { index, part in
                            conditionRow(part)
                            if index < ConditionPart.allCases.count - 1 {
                                Rectangle().fill(Color.calibre.border).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showGradeGuide) {
            GradeGuideSheet()
        }
    }

    private func conditionRow(_ part: ConditionPart) -> some View {
        HStack {
            Text(part.label)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
            Spacer()
            Menu {
                ForEach(ConditionPart.grades, id: \.self) { grade in
                    Button(grade) {
                        model.conditions[part] = grade
                        model.fieldChanged()
                        Haptics.shared.play(.selection)
                    }
                }
            } label: {
                HStack(spacing: Space.s) {
                    Text(model.conditions[part] ?? "Select")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(
                            model.conditions[part] == nil
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(part.label): \(model.conditions[part] ?? "not selected")")
    }
}

/// "How we grade" — the five grades, in plain words.
private struct GradeGuideSheet: View {
    private let grades: [(String, String)] = [
        ("New", "Unworn, exactly as it left the boutique — stickers still on."),
        ("Like New", "Worn a handful of times. No marks visible to the naked eye."),
        ("Very Good", "Light hairlines you have to hunt for. Nothing through the finish."),
        ("Good", "Honest wear — visible scratches or a small ding, all cosmetic."),
        ("Worn", "Heavy wear that tells the watch's story. Fully functional."),
    ]

    var body: some View {
        SheetScaffold(title: "How we grade", detents: [.medium, .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Grade each part on its own — buyers trust listings that read honestly, and our watchmakers verify every grade at authentication.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                    ForEach(grades, id: \.0) { grade, meaning in
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            StatusBadge(grade, tone: .neutral)
                                .frame(width: 92, alignment: .leading)
                            Text(meaning)
                                .font(CalibreType.body)
                                .foregroundStyle(Color.calibre.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.bottom, Space.xxl)
            }
        }
    }
}

// MARK: - Step 2 · Photos

struct PhotosStep: View {
    @Bindable var model: WizardModel
    @State private var captureTarget: CaptureTarget?

    private let columns = [
        GridItem(.flexible(), spacing: Space.l),
        GridItem(.flexible(), spacing: Space.l),
        GridItem(.flexible(), spacing: Space.l),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Six shots, one story")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Text("Each photo uploads the moment you take it. Natural light, plain background — the watch does the talking.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: columns, spacing: Space.xl) {
                ForEach(ListingImageCategory.allCases, id: \.self) { category in
                    slotCell(category)
                }
            }

            morePhotos

            #if DEBUG
            Button("Use sample photos") {
                Task {
                    for (category, image) in PhotoPipeline.sampleImages() {
                        await model.attach(image: image, to: category)
                    }
                }
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
            #endif
        }
        .fullScreenCover(item: $captureTarget) { target in
            CaptureScreen(target: target) { image in
                Task { await model.attach(image: image, to: target.category) }
            }
        }
    }

    private func slotCell(_ category: ListingImageCategory) -> some View {
        let phase = model.phase(for: category)
        return VStack(spacing: Space.s) {
            Button {
                captureTarget = CaptureTarget(category: category)
            } label: {
                PhotoSlotRing(phase: phase, size: 76) {
                    slotThumbnail(category)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(category.label) photo")

            Text(category.label)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if phase == .failed {
                Button {
                    Task { await model.retryUpload(category: category) }
                } label: {
                    Text("Try again")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.destructive)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 2)
                        .background(Color.calibre.destructive.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder
    private func slotThumbnail(_ category: ListingImageCategory) -> some View {
        if let slot = model.slots[category] {
            if let localURL = slot.localURL, let image = UIImage(contentsOfFile: localURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = slot.remoteURL {
                LazyImage(url: remoteURL) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.calibre.secondary
                    }
                }
            } else {
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private var morePhotos: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("More photos")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.m) {
                    ForEach(model.extraPhotos.indices, id: \.self) { index in
                        PhotoSlotRing(phase: model.phase(forExtra: index), size: 56) {
                            if let url = model.extraPhotos[index].localURL,
                               let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                EmptyView()
                            }
                        }
                    }
                    Button {
                        captureTarget = CaptureTarget(category: nil)
                    } label: {
                        PhotoSlotRing(phase: .empty, size: 56)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Add another photo")
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Step 3 · Price

struct PriceStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(model.price.map { PriceFormatter.format($0) } ?? "$—")
                    .font(CalibreType.serif(.semiBold, 40, relativeTo: .largeTitle))
                    .foregroundStyle(
                        model.price == nil ? Color.calibre.placeholder : Color.calibre.foreground
                    )
                    .contentTransition(.numericText())
                    .animation(Motion.easeFast, value: model.priceText)
                Text("Your asking price")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }

            CalibreTextField("Asking price", text: $model.priceText, placeholder: "12,400") {
                Text("USD")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .keyboardType(.decimalPad)
            .onChange(of: model.priceText) { _, _ in model.priceChanged() }

            payoutCard

            VStack(alignment: .leading, spacing: Space.s) {
                Text("Notes for buyers")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                TextEditor(text: $model.notes)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(Space.m)
                    .background(
                        Color.calibre.card,
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Color.calibre.border, lineWidth: 1)
                    )
                    .onChange(of: model.notes) { _, newValue in
                        if newValue.count > 2000 {
                            model.notes = String(newValue.prefix(2000))
                        }
                        model.fieldChanged()
                    }
                Text("\(model.notes.count)/2000")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// Price − commission − estimated shipping = payout, live.
    private var payoutCard: some View {
        SellCard {
            VStack(spacing: 0) {
                payoutRow("Your price", value: model.price.map { PriceFormatter.format($0) } ?? "—")
                Rectangle().fill(Color.calibre.border).frame(height: 1)
                payoutRow(
                    "Calibre commission (\(feeText)%)",
                    value: model.commission.map { "− \(PriceFormatter.format($0))" } ?? "—"
                )
                Rectangle().fill(Color.calibre.border).frame(height: 1)
                payoutRow("Estimated shipping", value: shippingText, busy: model.estimating)
                Rectangle().fill(Color.calibre.border).frame(height: 1)
                HStack(alignment: .firstTextBaseline) {
                    Text("You'll receive")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    Spacer()
                    Text(model.payout.map { "≈ \(PriceFormatter.format(max($0, 0)))" } ?? "—")
                        .font(CalibreType.price)
                        .foregroundStyle(Color.calibre.foreground)
                        .contentTransition(.numericText())
                        .animation(Motion.easeFast, value: model.priceText)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
        }
    }

    private var feeText: String {
        var value = model.feePercent
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    private var shippingText: String {
        if model.estimating { return " " }
        if let estimate = model.estimate {
            return "− \(PriceFormatter.format(estimate.amount.value))"
        }
        return model.price == nil ? "—" : "included after quote"
    }

    private func payoutRow(_ label: String, value: String, busy: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
            Spacer()
            if busy {
                ProgressView().controlSize(.small).tint(Color.calibre.primary)
            } else {
                Text(value)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}
