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
                CalibreTextField(
                    "Brand",
                    text: $model.brand,
                    placeholder: "Rolex",
                    error: model.brandError,
                    kind: .sentence
                )
                .id(WizardField.brand)
                .onChange(of: model.brand) { _, _ in model.fieldChanged() }
                CalibreTextField(
                    "Model",
                    text: $model.model,
                    placeholder: "Submariner Date",
                    kind: .sentence
                )
                .onChange(of: model.model) { _, _ in model.fieldChanged() }
                CalibreTextField(
                    "Reference",
                    text: $model.reference,
                    placeholder: "116610LN",
                    kind: .reference
                )
                .onChange(of: model.reference) { _, _ in model.fieldChanged() }
                Text("Unusual brands still go to review.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }

            VStack(alignment: .leading, spacing: Space.m) {
                CalibreTextField(
                    "Year",
                    text: $model.yearText,
                    placeholder: "2019",
                    error: model.yearFieldError,
                    kind: .integer
                )
                    .id(WizardField.year)
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
                                .id(WizardField.condition(part))
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
        let error = model.conditionError(part)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(part.label)
                    .font(CalibreType.body)
                    .foregroundStyle(error == nil ? Color.calibre.mutedForeground : Color.calibre.destructive)
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
                            .lineLimit(1)
                            .fixedSize()
                            // Reserve room for the longest grade so picking a
                            // two-word one ("Like New") doesn't resize the
                            // label. That resize is what made the text blink
                            // out while the menu animated shut.
                            .frame(minWidth: Self.gradeLabelWidth, alignment: .trailing)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                    .frame(minHeight: Space.touchTarget)
                    .contentShape(Rectangle())
                }
                // The menu's dismissal animation must not drag the label
                // through a crossfade.
                .transaction { $0.animation = nil }
            }
            .frame(minHeight: Space.touchTarget)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(part.label): \(model.conditions[part] ?? "not selected")")

            if let error {
                Text(error)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.destructive)
                    .padding(.bottom, Space.s)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.l)
        .animation(Motion.easeFast, value: error)
    }

    /// Width of "Very Good" at the label's font — the widest grade.
    private static let gradeLabelWidth: CGFloat = 84
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
    @State private var previewTarget: PhotoReplaceTarget?
    @State private var tutorial = TutorialController(
        id: "sell.wizard.photos",
        steps: [
            TutorialStep(
                id: "angles",
                anchor: "wizard.photos.header",
                title: "Six angles, one story",
                message: "All six shots are required. Each uploads the instant you take it, and your Front photo becomes the listing's hero. You can submit once every shot finishes uploading.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.card)
            ),
            TutorialStep(
                id: "capture",
                anchor: "wizard.photos.grid",
                title: "Fill a slot",
                message: "Tap any slot to open the camera and capture that angle. Do the Front first — that's your hero.",
                advance: .perform(event: "photo"),
                hint: .tap,
                cutout: .roundedRect(Radius.card),
                actionPrompt: "Tap a slot to add a photo"
            ),
        ]
    )

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
            .tutorialAnchor("wizard.photos.header")

            LazyVGrid(columns: columns, spacing: Space.xl) {
                ForEach(ListingImageCategory.allCases, id: \.self) { category in
                    slotCell(category)
                }
            }
            .tutorialAnchor("wizard.photos.grid")

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
        .tutorialOverlay(tutorial)
        .onAppear { tutorial.startIfNeeded() }
        .fullScreenCover(item: $captureTarget) { target in
            CaptureScreen(target: target) { image in
                Task { await model.attach(image: image, to: target.category) }
                // A real captured photo advances the hands-on step.
                tutorial.fire("photo")
            }
        }
        .fullScreenCover(item: $previewTarget) { target in
            PhotoPreviewScreen(target: target, slot: model.slots[target.category]) { image in
                Task { await model.attach(image: image, to: target.category) }
                tutorial.fire("photo")
            }
        }
    }

    private func slotCell(_ category: ListingImageCategory) -> some View {
        let phase = model.phase(for: category)
        return VStack(spacing: Space.s) {
            Button {
                // A filled slot opens its photo first; an empty one has
                // nothing to show, so go straight to the camera.
                if model.slots[category]?.hasImage == true {
                    previewTarget = PhotoReplaceTarget(category: category)
                } else {
                    captureTarget = CaptureTarget(category: category)
                }
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

            CalibreTextField(
                "Asking price",
                text: $model.priceText,
                placeholder: "12,400",
                error: model.priceFieldError,
                kind: .money
            ) {
                Text("USD")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .id(WizardField.price)
            .onChange(of: model.priceText) { _, _ in model.priceChanged() }

            payoutCard

            // Hidden entirely when the marketplace hasn't told us which
            // windows it offers — a list of hours is not ours to invent.
            if !model.returnWindowChoices.isEmpty {
                returnsSection
            }

            CalibreTextEditor(
                "Notes for buyers (optional)",
                text: $model.notes,
                placeholder: "Service history, how it wears, what's included…",
                characterLimit: 2000
            )
            .onChange(of: model.notes) { _, newValue in
                if newValue.count > 2000 {
                    model.notes = String(newValue.prefix(2000))
                }
                model.fieldChanged()
            }
        }
        // A resumed draft arrives here with a price already typed, and the
        // payout card should be real before the seller touches anything.
        .task { await model.ensurePreview() }
    }

    // MARK: Payout

    /// Every figure here is the server's publish preview — the commission and
    /// its rate, the minimum when it is what applied, net proceeds, and the
    /// price a buyer will actually be shown. Nothing on this card is worked
    /// out on device.
    private var payoutCard: some View {
        SellCard {
            VStack(spacing: 0) {
                payoutRow("Your price", value: yourPriceText, busy: model.previewing)
                rowDivider
                payoutRow(commissionLabel, value: commissionText, busy: model.previewing)
                rowDivider
                payoutRow("Estimated shipping", value: shippingText, busy: shippingBusy)
                rowDivider
                netRow
                rowDivider
                buyerSection
            }
        }
    }

    /// What the buyer will be shown, kept below the seller's own total, plus
    /// the sentences that belong beside a payout figure.
    private var buyerSection: some View {
        VStack(spacing: 0) {
            payoutRow("Buyers see", value: buyerPriceText, busy: model.previewing)

            if !payoutNotes.isEmpty {
                rowDivider
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(payoutNotes, id: \.self) { note in
                        Text(note)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
        }
    }

    private var netRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("You'll receive")
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
            Spacer()
            if model.previewing {
                ProgressView().controlSize(.small).tint(Color.calibre.primary)
            } else {
                Text(netText)
                    .font(CalibreType.price)
                    .foregroundStyle(Color.calibre.foreground)
                    .contentTransition(.numericText())
                    .animation(Motion.easeFast, value: netText)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.calibre.border).frame(height: 1)
    }

    private var yourPriceText: String {
        guard let preview = model.preview else { return "—" }
        return PriceFormatter.format(preview.price.value, currency: preview.currency)
    }

    private var commissionLabel: String {
        guard let preview = model.preview else { return "Calibre commission" }
        return "Calibre commission (\(percentText(preview.commission.percent.value))%)"
    }

    private var commissionText: String {
        guard let preview = model.preview else { return "—" }
        return "− \(PriceFormatter.format(preview.commission.amount.value, currency: preview.currency))"
    }

    private var netText: String {
        guard let preview = model.preview else { return "—" }
        return PriceFormatter.format(preview.netProceeds.value, currency: preview.currency)
    }

    private var buyerPriceText: String {
        guard let preview = model.preview else { return "—" }
        return PriceFormatter.format(preview.buyerDisplay.standard.price.value, currency: preview.currency)
    }

    private var shippingBusy: Bool {
        model.shipping == nil && (model.estimating || model.previewing)
    }

    private var shippingText: String {
        if let shipping = model.shipping {
            return "− \(PriceFormatter.format(shipping.amount.value, currency: shipping.currency))"
        }
        return model.price == nil ? "—" : "included after quote"
    }

    /// The plain sentences that belong beside a payout figure: the minimum
    /// commission when it is what applied, and the display difference in the
    /// states where a surcharge isn't permitted.
    private var payoutNotes: [String] {
        guard let preview = model.preview else { return [] }
        var notes: [String] = []
        if preview.commission.minimumApplied {
            let minimum = PriceFormatter.format(preview.commission.minimum.value, currency: preview.currency)
            notes.append(
                "Every sale carries a minimum commission of \(minimum), and on this price that minimum is what applies."
            )
        }
        if let discount = preview.buyerDisplay.discountStates {
            let named = statesText(discount.states)
            let scope = named.isEmpty ? "In the states where surcharges aren't permitted" : "In \(named)"
            let cardPrice = PriceFormatter.format(discount.price.value, currency: preview.currency)
            let wirePrice = PriceFormatter.format(discount.wirePrice.value, currency: preview.currency)
            notes.append(
                "\(scope) the listed price is shown as the card price, \(cardPrice), and paying by wire receives a discount off it, \(wirePrice). The final total is the same in every state; only the presentation differs."
            )
        }
        return notes
    }

    private func statesText(_ states: [String]) -> String {
        switch states.count {
        case 0: ""
        case 1: states[0]
        case 2: states.joined(separator: " and ")
        default: states.dropLast().joined(separator: ", ") + " and " + (states.last ?? "")
        }
    }

    /// The server's percent, rendered as it was written minus a trailing
    /// ".00" — never rounded to a different number.
    private func percentText(_ value: Decimal) -> String {
        var text = "\(value)"
        guard text.contains(".") else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
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
        .accessibilityElement(children: .combine)
    }

    // MARK: Returns

    /// The seller's return terms, and the payout timing that follows from
    /// them — which is the real substance of the choice.
    private var returnsSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Returns")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            SellCard {
                VStack(alignment: .leading, spacing: Space.l) {
                    Toggle(isOn: $model.returnsAccepted) {
                        Text("Accept returns")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .tint(Color.calibre.primary)
                    .frame(minHeight: Space.touchTarget)
                    .onChange(of: model.returnsAccepted) { _, _ in
                        model.returnsChanged()
                    }

                    if model.returnsAccepted {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("Return window")
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.secondaryForeground)
                            SegmentedTabs(
                                selection: windowBinding,
                                items: model.returnWindowChoices.map { ($0, "\($0) hours") }
                            )
                        }
                        Text("The window starts when the buyer signs for the watch, or two business days after the first delivery attempt, whichever comes first.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("A listing without returns pays out when authentication passes. A listing that accepts them pays out when the return window closes.")
                            .font(CalibreType.body)
                            .foregroundStyle(Color.calibre.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        StatusBadge(payoutTimingText, tone: .neutral)
                    }

                    Text("Return terms are locked onto the order at purchase. Changing them on a listing that hasn't sold sends it back through review.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
            }
            .animation(Motion.easeFast, value: model.returnsAccepted)
        }
    }

    private var payoutTimingText: String {
        model.returnsAccepted
            ? "Yours pays out when the window closes"
            : "Yours pays out when authentication passes"
    }

    /// `SegmentedTabs` needs a definite value; the model keeps the window
    /// optional because a listing without returns doesn't have one.
    private var windowBinding: Binding<Int> {
        Binding(
            get: { model.returnWindowHours ?? model.returnWindowChoices.first ?? 0 },
            set: { newValue in
                model.returnWindowHours = newValue
                model.returnsChanged()
            }
        )
    }
}
