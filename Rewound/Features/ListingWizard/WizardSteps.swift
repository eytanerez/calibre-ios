import RewoundDesign
import RewoundKit
import NukeUI
import SwiftUI

// MARK: - Step 1 · Details

struct DetailsStep: View {
    @Bindable var model: WizardModel
    @State private var showGradeGuide = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Width of "Very Good" at the label's font — the widest grade. Scaled,
    /// because a fixed 84pt column holds about two characters of an
    /// accessibility-size grade and clipped the rest of the word.
    @ScaledMetric(relativeTo: .body) private var gradeLabelWidth: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            // Everything except the photographs, which a tester has to take or
            // choose themselves — there is no invented file to hand them, and a
            // listing with no pictures is one they would rightly report as
            // broken. Renders nothing outside a beta.
            BetaFillButton(label: "Fill this in with a sample watch") { person in
                let listing = person.listing
                model.applyPrefill(
                    brand: listing["brand"] ?? "",
                    model: listing["model"] ?? "",
                    reference: listing["reference_number"] ?? ""
                )
                model.yearText = listing["manufacture_year"] ?? ""
                model.yearUnknown = false
                model.priceText = listing["price"] ?? ""
                model.notes = listing["notes"] ?? ""
                // Keyed off the wire names the server sends, so a part renamed
                // in one place cannot silently stop being filled in the other.
                let byPart: [ConditionPart: String] = [
                    .watchCase: "condition_case",
                    .dial: "condition_dial",
                    .bezel: "condition_bezel",
                    .crystal: "condition_crystal",
                    .bracelet: "condition_bracelet",
                    .clasp: "condition_clasp",
                    .caseback: "condition_caseback",
                    .overall: "condition",
                ]
                for (part, key) in byPart {
                    if let grade = listing[key] { model.conditions[part] = grade }
                }
                model.fieldChanged()
            }

            VStack(alignment: .leading, spacing: Space.l) {
                ListingCatalogField("Brand", text: $model.brand, level: .brands, error: model.brandError)
                    .id(WizardField.brand)
                    .onChange(of: model.brand) { _, _ in model.brandChanged() }
                ListingCatalogField("Model", text: $model.model, level: .models, brand: model.brand, error: model.modelError)
                    .onChange(of: model.model) { _, _ in model.modelChanged() }
                ListingCatalogField("Reference", text: $model.reference, level: .references, brand: model.brand, model: model.model, error: model.referenceError)
                    .onChange(of: model.reference) { _, _ in model.referenceChanged() }
                RewoundTextField(
                    "Seller SKU (optional)",
                    text: $model.sellerSku,
                    placeholder: "CAL-001",
                    kind: .reference
                )
                .onChange(of: model.sellerSku) { _, value in
                    if value.count > 64 { model.sellerSku = String(value.prefix(64)) }
                    model.fieldChanged()
                }
                Text("Your own shelf label, if you keep one. It has to be unique to this watch \u{2014} a bulk import matches on the SKU and nothing else. Buyers never see it.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Unusual brands still go to review.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }

            VaultMatchAsk(model: model)

            VStack(alignment: .leading, spacing: Space.m) {
                RewoundTextField(
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
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.foreground)
                }
                .tint(Color.rewound.primary)
                .onChange(of: model.yearUnknown) { _, _ in model.fieldChanged() }
            }

            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Condition")
                        .font(RewoundType.sectionTitle)
                        .foregroundStyle(Color.rewound.foreground)
                    Spacer()
                    Button("How we grade") {
                        showGradeGuide = true
                    }
                    .font(RewoundType.label)
                    .foregroundStyle(Color.rewound.primary)
                    .buttonStyle(PressableStyle())
                }

                SellCard {
                    VStack(spacing: 0) {
                        ForEach(Array(ConditionPart.allCases.enumerated()), id: \.element) { index, part in
                            conditionRow(part)
                                .id(WizardField.condition(part))
                            if index < ConditionPart.allCases.count - 1 {
                                Rectangle().fill(Color.rewound.border).frame(height: 1)
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
            // The part and its grade share a line right up to the
            // accessibility sizes, where the reserved grade column alone is
            // wider than the card and pushed the part name off the row. Past
            // that point the grade sits under the name it belongs to.
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.s) {
                        partLabel(part, error: error)
                        gradeMenu(part)
                    }
                } else {
                    HStack {
                        partLabel(part, error: error)
                        Spacer()
                        gradeMenu(part)
                    }
                }
            }
            .frame(minHeight: Space.touchTarget)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(part.label): \(model.conditions[part] ?? "not selected")")

            if let error {
                Text(error)
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.destructive)
                    .padding(.bottom, Space.s)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.l)
        .animation(Motion.easeFast, value: error)
    }

    private func partLabel(_ part: ConditionPart, error: String?) -> some View {
        Text(part.label)
            .font(RewoundType.body)
            .foregroundStyle(error == nil ? Color.rewound.mutedForeground : Color.rewound.destructive)
    }

    private func gradeMenu(_ part: ConditionPart) -> some View {
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
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(
                        model.conditions[part] == nil
                            ? Color.rewound.placeholder
                            : Color.rewound.foreground
                    )
                    // The reservation below only works while the grade fits on
                    // one line; at an accessibility size it has to be allowed
                    // to wrap, or "Very Good" is drawn straight off the card.
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                    // Reserve room for the longest grade so picking a
                    // two-word one ("Like New") doesn't resize the
                    // label. That resize is what made the text blink
                    // out while the menu animated shut.
                    .frame(
                        minWidth: typeSize.isAccessibilitySize ? nil : gradeLabelWidth,
                        alignment: .trailing
                    )
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
            .frame(minHeight: Space.touchTarget)
            .contentShape(Rectangle())
        }
        // The menu's dismissal animation must not drag the label
        // through a crossfade.
        .transaction { $0.animation = nil }
    }
}

/// "How we grade" — the five grades, in plain words.
private struct GradeGuideSheet: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Width of the grade column. `StatusBadge` draws in `RewoundType.label`
    /// (13pt relative to .footnote), so the reservation tracks the text it is
    /// holding room for instead of staying 92pt while the badge triples.
    @ScaledMetric(relativeTo: .footnote) private var badgeColumnWidth: CGFloat = 92

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
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.mutedForeground)
                    ForEach(grades, id: \.0) { grade, meaning in
                        // Side by side until the grade column would take most
                        // of the sheet and leave its meaning a word a line —
                        // then the grade simply sits above what it means.
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: Space.s) {
                                StatusBadge(grade, tone: .neutral)
                                meaningLine(meaning)
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                                StatusBadge(grade, tone: .neutral)
                                    .frame(width: badgeColumnWidth, alignment: .leading)
                                meaningLine(meaning)
                            }
                        }
                    }
                }
                .padding(.bottom, Space.xxl)
            }
        }
    }

    private func meaningLine(_ meaning: String) -> some View {
        Text(meaning)
            .font(RewoundType.body)
            .foregroundStyle(Color.rewound.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The vault question

/// "Is this one you already own?" — asked on Details when the reference the
/// seller typed matches a watch in their own collection.
///
/// A reference is a model, not a watch: a collector may own two of the same
/// one, so a match is only ever a question. The seller's yes is the single
/// thing that links this listing to that watch, and the link is what keeps a
/// relisted watch on ONE Passport instead of minting a second for the same
/// object. Silent when there is nothing to ask about, and gone for good once
/// it has been answered.
private struct VaultMatchAsk: View {
    let model: WizardModel

    var body: some View {
        Group {
            if model.linkedVaultWatchID != nil {
                CalloutBand(
                    icon: "checkmark.seal",
                    title: "Linked to your Vault",
                    message: confirmation
                )
            } else if !model.vaultMatches.isEmpty {
                ask
            }
        }
        .animation(Motion.easeMedium, value: model.vaultMatches)
        .animation(Motion.easeMedium, value: model.linkedVaultWatchID)
    }

    /// Named where we can name it. A listing that arrived already linked
    /// carries the id and nothing else — the match lookup excludes a watch
    /// that is already spoken for — so the sentence stands on its own.
    private var confirmation: String {
        let continuity = "When it sells, this listing carries on that watch's Passport instead of starting a second one."
        guard let watch = model.linkedVaultWatch else { return continuity }
        return "\(watch.displayTitle). \(continuity)"
    }

    private var ask: some View {
        SellCard {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Is this one you already own?")
                            .font(RewoundType.sectionTitle)
                            .foregroundStyle(Color.rewound.foreground)
                        Text("That reference matches a watch in your Vault. If it's the same watch, this listing carries on its Passport rather than starting a second one for it.")
                            .font(RewoundType.body)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(model.vaultMatches.enumerated()), id: \.element.id) { index, match in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.rewound.border)
                                    .frame(height: 1)
                                    .padding(.vertical, Space.m)
                            }
                            matchRow(match)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)

                // The decline runs the width of the card, under a rule: it
                // answers the whole question rather than any one watch on it.
                Rectangle().fill(Color.rewound.border).frame(height: 1)
                Button("No, this is a different watch") {
                    Haptics.shared.play(.selection)
                    model.declineVaultMatch()
                }
                .buttonStyle(.rewound(.ghost, fullWidth: true))
            }
        }
    }

    private func matchRow(_ match: VaultMatch) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(match.displayTitle)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if let provenance = provenance(match) {
                Text(provenance)
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Yes, that's it") {
                Haptics.shared.play(.selection)
                Task { await model.linkVaultWatch(match) }
            }
            .buttonStyle(.rewound(.secondary))
            .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Everything the seller needs to recognize their own watch, and nothing
    /// invented: a date that doesn't parse is left out rather than guessed at,
    /// and a reference is skipped when it is already the watch's whole name.
    private func provenance(_ match: VaultMatch) -> String? {
        var parts: [String] = []
        if let reference = match.reference,
           !reference.isEmpty,
           reference != match.displayTitle {
            parts.append("Ref. \(reference)")
        }
        if let acquired = MarketFormat.day(iso: match.acquiredDate) {
            parts.append("Acquired \(acquired)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Step 2 · Photos

struct PhotosStep: View {
    @Bindable var model: WizardModel
    @State private var captureTarget: CaptureTarget?
    @State private var previewTarget: PhotoReplaceTarget?
    @State private var removingPhoto: ListingImageCategory?
    @State private var tutorial = TutorialController(
        id: "sell.wizard.photos",
        steps: [
            TutorialStep(
                id: "angles",
                anchor: "wizard.photos.header",
                title: "Six angles, one story",
                message: "All six shots are required. Each uploads the instant you take it, and your Front photo becomes the listing's hero. You can submit once every shot finishes uploading.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.box)
            ),
            TutorialStep(
                id: "capture",
                anchor: "wizard.photos.grid",
                title: "Fill a slot",
                message: "Tap any slot to open the camera and capture that angle. Do the Front first — that's your hero.",
                advance: .perform(event: "photo"),
                hint: .tap,
                cutout: .roundedRect(Radius.box),
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
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
                Text("Each photo uploads the moment you take it. Natural light, plain background — the watch does the talking.")
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
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

            inclusions

            #if DEBUG
            Button("Use sample photos") {
                Task {
                    for (category, image) in PhotoPipeline.sampleImages() {
                        await model.attach(image: image, to: category)
                    }
                }
            }
            .buttonStyle(.rewound(.secondary, fullWidth: true))
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
            PhotoPreviewScreen(
                target: target,
                slot: model.slots[target.category]
            ) { image in
                Task {
                    await model.attach(image: image, to: target.category)
                }
                tutorial.fire("photo")
            }
        }
    }

    // MARK: What comes with the watch

    /// Three answers, asked beside the photographs because the full-set shot
    /// is where the seller already has the box and the papers on the table.
    ///
    /// Nothing here is required. A watch with no box is an ordinary watch, and
    /// forcing an answer would only teach people to tick to get past the step.
    /// What matters is that the question is asked at all: it never was, so
    /// every listing this wizard has made says "watch only" on the seller's
    /// behalf.
    private var inclusions: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("What comes with it")
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
                Text("Our authentication center checks each of these against what actually arrives.")
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Original box", isOn: $model.boxIncluded)
            Toggle("Papers", isOn: $model.papersIncluded)
            Toggle("Booklets", isOn: $model.bookletsIncluded)
        }
        .font(RewoundType.bodyMedium)
        .foregroundStyle(Color.rewound.foreground)
        .tint(Color.rewound.primary)
        .onChange(of: model.boxIncluded) { _, _ in model.fieldChanged() }
        .onChange(of: model.papersIncluded) { _, _ in model.fieldChanged() }
        .onChange(of: model.bookletsIncluded) { _, _ in model.fieldChanged() }
    }

    private func slotCell(_ category: ListingImageCategory) -> some View {
        let phase = model.phase(for: category)
        return VStack(spacing: Space.s) {
            ZStack(alignment: .topTrailing) {
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
                .accessibilityIdentifier("listing-photo-\(category.rawValue)")

                if canRemove(phase) {
                    Button {
                        removingPhoto = category
                        Task {
                            await model.removePhoto(category: category)
                            removingPhoto = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(white: 1))
                            .frame(width: 20, height: 20)
                            .background(Color.rewound.destructive, in: Circle())
                            .overlay(Circle().strokeBorder(Color.rewound.card, lineWidth: 2))
                            .frame(width: Space.touchTarget, height: Space.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(removingPhoto != nil)
                    .accessibilityLabel("Remove \(category.label) photo")
                    .accessibilityIdentifier("listing-photo-remove-\(category.rawValue)")
                    .offset(x: 10, y: -10)
                }
            }

            Text(category.label)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if phase == .failed {
                Button {
                    Task { await model.retryUpload(category: category) }
                } label: {
                    Text("Try again")
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.destructive)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 2)
                        .background(Color.rewound.destructive.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func canRemove(_ phase: PhotoSlotPhase) -> Bool {
        switch phase {
        case .done, .failed: true
        case .empty, .uploading: false
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
                        Color.rewound.secondary
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
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.secondaryForeground)
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
                Text(model.price.map { PriceFormatter.listing($0) } ?? "$—")
                    .font(RewoundType.serif(.semiBold, 40, relativeTo: .largeTitle))
                    .foregroundStyle(
                        model.price == nil ? Color.rewound.placeholder : Color.rewound.foreground
                    )
                    .contentTransition(.numericText())
                    .animation(Motion.easeFast, value: model.priceText)
                Text("Your asking price")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }

            RewoundTextField(
                "Asking price",
                text: $model.priceText,
                placeholder: "12,400",
                error: model.priceFieldError,
                kind: .money
            ) {
                Text("USD")
                    .font(RewoundType.label)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
            .id(WizardField.price)
            .moneyFormatted($model.priceText)
            .onChange(of: model.priceText) { _, _ in model.priceChanged() }

            payoutCard

            // Hidden entirely when the marketplace hasn't told us which
            // windows it offers — a list of hours is not ours to invent.
            if !model.returnWindowChoices.isEmpty {
                returnsSection
            }

            RewoundTextEditor(
                "Notes for buyers (optional)",
                text: $model.notes,
                // The deviation prompt. A watch that differs from its catalog
                // row — a replacement bracelet, a refinished dial — is a fact
                // only the seller can state, and an admin turns what they write
                // here into a per-listing spec override at review.
                placeholder: "Service history, how it wears, and anything not as the catalog describes…",
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
                payoutRow("Estimated shipping after sale", value: shippingText, busy: shippingBusy)
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
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
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
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
            Spacer()
            if model.previewing {
                // Stays a system spinner on purpose. The marks vocabulary
                // forbids a mark on a price, and this stands exactly where
                // the figure is about to be.
                ProgressView().controlSize(.small).tint(Color.rewound.primary)
            } else {
                Text(netText)
                    .font(RewoundType.price)
                    .foregroundStyle(Color.rewound.foreground)
                    .contentTransition(.numericText())
                    .animation(Motion.easeFast, value: netText)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.rewound.border).frame(height: 1)
    }

    private var yourPriceText: String {
        guard let preview = model.preview else { return "—" }
        return PriceFormatter.format(preview.price.value, currency: preview.currency)
    }

    private var commissionLabel: String {
        guard let preview = model.preview else { return "Rewound commission" }
        return "Rewound commission (\(percentText(preview.commission.percent.value))%)"
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
            return PriceFormatter.format(shipping.amount.value, currency: shipping.currency)
        }
        return model.price == nil ? "—" : "included after quote"
    }

    /// The plain sentences that belong beside a payout figure: the minimum
    /// commission when it is what applied, and the display difference in the
    /// states where a surcharge isn't permitted.
    private var payoutNotes: [String] {
        guard let preview = model.preview else { return [] }
        // The shipping figure is priced from a standard box nobody has
        // measured yet, and it binds nothing: Rewound buys the real label
        // after the sale and the actual cost is what comes off the payout.
        var notes: [String] = [
            "The shipping figure is an estimate, priced from a standard box. It commits you to nothing \u{2014} after the sale you give us the real dimensions, Rewound buys the label, and what it actually costs is what comes off your payout."
        ]
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
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.mutedForeground)
            Spacer()
            if busy {
                // A system spinner, for the same reason as the net-proceeds
                // row above: this is the slot a figure lands in, and no mark
                // goes on a price.
                ProgressView().controlSize(.small).tint(Color.rewound.primary)
            } else {
                Text(value)
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
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
                .font(RewoundType.sectionTitle)
                .foregroundStyle(Color.rewound.foreground)

            SellCard {
                VStack(alignment: .leading, spacing: Space.l) {
                    Toggle(isOn: $model.returnsAccepted) {
                        Text("Accept returns")
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
                    }
                    .tint(Color.rewound.primary)
                    .frame(minHeight: Space.touchTarget)
                    .onChange(of: model.returnsAccepted) { _, _ in
                        model.returnsChanged()
                    }

                    if model.returnsAccepted {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("Return window")
                                .font(RewoundType.label)
                                .foregroundStyle(Color.rewound.secondaryForeground)
                            SegmentedTabs(
                                selection: windowBinding,
                                items: model.returnWindowChoices.map { ($0, "\($0) hours") }
                            )
                        }
                        Text("The window starts when the buyer signs for the watch, or two business days after the first delivery attempt, whichever comes first.")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("A listing without returns pays out when authentication passes. A listing that accepts them pays out when the return window closes.")
                            .font(RewoundType.body)
                            .foregroundStyle(Color.rewound.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        StatusBadge(payoutTimingText, tone: .neutral)
                    }

                    Text("Return terms are locked onto the order at purchase. Changing them on a listing that hasn't sold sends it back through review.")
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
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

/// Typed entries remain valid when no catalog row matches. A full query key
/// and task cancellation prevent an old brand's response replacing a new one.
private struct ListingCatalogField: View {
    @Environment(AppServices.self) private var services
    let label: String
    @Binding var text: String
    let level: CatalogCascadeQuery.Level
    let brand: String
    let model: String
    let error: String?
    @FocusState private var focused: Bool
    @State private var response: CatalogCascadeResponse?
    @State private var failed = false

    init(_ label: String, text: Binding<String>, level: CatalogCascadeQuery.Level,
         brand: String = "", model: String = "", error: String? = nil) {
        self.label = label; self._text = text; self.level = level
        self.brand = brand; self.model = model; self.error = error
    }
    private var query: CatalogCascadeQuery {
        CatalogCascadeQuery(level: level, brand: brand, model: model, text: text)
    }
    private var requestKey: CatalogCascadeQuery? { focused ? query : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label).font(RewoundType.label).foregroundStyle(Color.rewound.secondaryForeground)
                .accessibilityHidden(true)
            TextField(label, text: $text)
                .font(RewoundType.body)
                .textInputAutocapitalization(level == .references ? .characters : .words)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.horizontal, Space.m)
                .frame(minHeight: Space.touchTarget)
                .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Radius.control)
                    .stroke(error != nil ? Color.rewound.destructive : focused ? Color.rewound.primary : Color.rewound.border))
                .accessibilityIdentifier("listing.\(label.lowercased())")
            if let error {
                Text(error).font(RewoundType.caption).foregroundStyle(Color.rewound.destructive)
            }
            if focused {
                if let response {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(response.values.prefix(6)) { suggestion in
                            Button {
                                text = suggestion.value
                                focused = false
                            } label: {
                                Text(suggestion.value)
                                    .font(RewoundType.body)
                                    .frame(maxWidth: .infinity, minHeight: Space.touchTarget, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if response.total > 6 || response.truncated {
                            Text("\(response.total) matches — keep typing to narrow them.")
                                .font(RewoundType.caption).foregroundStyle(Color.rewound.mutedForeground)
                        } else if response.values.isEmpty {
                            Text("No catalog match. You can keep your own entry.")
                                .font(RewoundType.caption).foregroundStyle(Color.rewound.mutedForeground)
                        }
                    }
                } else if failed {
                    Text("Suggestions unavailable. You can still enter the watch details.")
                        .font(RewoundType.caption).foregroundStyle(Color.rewound.mutedForeground)
                }
            }
        }
        .task(id: requestKey) {
            response = nil; failed = false
            guard let key = requestKey, key.canSearch else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let result = try await services.catalog.cascade(key)
                guard !Task.isCancelled, requestKey == key else { return }
                response = result
            } catch {
                guard !Task.isCancelled, requestKey == key else { return }
                failed = true
            }
        }
    }
}
