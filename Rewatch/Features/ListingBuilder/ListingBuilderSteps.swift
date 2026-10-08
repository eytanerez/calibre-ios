import RewatchDesign
import RewatchKit
import SwiftUI

/// What every step view gets: the model, the screen's focus, and the screen's
/// way of moving on (which plays the haptic and the transition).
struct BuilderStepContext {
    let model: ListingBuilderModel
    let focus: FocusState<BuilderField?>.Binding
    let advance: () -> Void
    /// Moves on after a beat (long enough to see the answer land), and only
    /// if the seller is still on `step`: a tap on Continue in that beat must
    /// not move them twice.
    let advanceLater: (_ step: BuilderStep, _ milliseconds: Int) -> Void
    /// The first visit to the first step, centred and on its own.
    var alone = false
}

// MARK: - 1 · The watch

struct BuilderWatchStep: View {
    let context: BuilderStepContext
    private var model: ListingBuilderModel { context.model }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if model.mode == .live {
                // A beta tester's sample watch; nothing outside a beta.
                BetaFillButton(label: "Fill this in with a sample watch") { person in
                    model.applySample(person.listing)
                }
            }
            VStack(alignment: .leading, spacing: context.alone ? Space.m : Space.s) {
                BuilderCatalogField(context: context, field: .brand)
                BuilderCatalogField(context: context, field: .model)
                BuilderCatalogField(context: context, field: .reference)
            }

            catalogResult
                .animation(Motion.easeMedium, value: model.watch?.id)
                .animation(Motion.easeMedium, value: model.catalogIsNew)

            vaultQuestion
                .animation(Motion.easeMedium, value: model.vaultMatches.map(\.id))
                .animation(Motion.easeMedium, value: model.answers.vaultWatchID)
        }
    }

    @ViewBuilder
    private var catalogResult: some View {
        if let watch = model.watch {
            VStack(alignment: .leading, spacing: Space.m) {
                BuilderNote {
                    (Text("Matched to the Rewatch catalog").font(RewatchType.bodySemiBold)
                        + Text(": \(watch.displayName).").font(RewatchType.body))
                        .foregroundStyle(Color.rewatch.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .inkUnderline(watch.id)
                }
                if !watch.specChips.isEmpty {
                    WrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(watch.specChips.enumerated()), id: \.element) { index, chip in
                            BuilderSpecChip(text: chip, index: index)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
            .accessibilityElement(children: .combine)
        } else if model.catalogIsNew {
            BuilderNote(emphasized: false) {
                (Text("New to our catalog").font(RewatchType.bodySemiBold)
                    + Text(". Double-check the spelling of brand, model, and reference.").font(RewatchType.body))
                    .foregroundStyle(Color.rewatch.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
        } else {
            Text("Pick from each list or type it in full.")
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.mutedForeground)
        }
    }

    /// "Is this the watch from your Vault?", asked only when the seller's own
    /// collection holds one at this reference; their yes is the only thing
    /// that links the listing to it.
    @ViewBuilder
    private var vaultQuestion: some View {
        if model.answers.vaultWatchID != nil {
            BuilderNote {
                VStack(alignment: .leading, spacing: Space.s) {
                    (Text("From your Vault").font(RewatchType.bodySemiBold)
                        + Text(": \(model.answers.vaultWatchTitle ?? "the watch in your Vault"). This sale continues its passport.").font(RewatchType.body))
                        .foregroundStyle(Color.rewatch.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Not this watch") {
                        Haptics.shared.play(.selection)
                        model.declineVault()
                    }
                    .font(RewatchType.bodySemiBold)
                    .foregroundStyle(Color.rewatch.primaryDeep)
                    .frame(minHeight: Space.touchTarget)
                }
            }
            .transition(.opacity)
        } else if !model.vaultMatches.isEmpty {
            let many = model.vaultMatches.count > 1
            BuilderNote {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(many ? "Is one of these the watch you are listing?" : "Is this the watch you are listing?")
                        .font(RewatchType.bodySemiBold)
                        .foregroundStyle(Color.rewatch.foreground)
                    Text("\(many ? "They are" : "It is") in your Vault at this reference. Say yes and this sale continues that watch\u{2019}s passport; say no and the listing starts its own.")
                        .font(RewatchType.label)
                        .foregroundStyle(Color.rewatch.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(model.vaultMatches) { match in
                        Button {
                            Haptics.shared.play(.selection)
                            model.linkVault(match)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.displayTitle)
                                        .font(RewatchType.bodySemiBold)
                                        .foregroundStyle(Color.rewatch.foreground)
                                    if let detail = vaultDetail(match) {
                                        Text(detail)
                                            .font(RewatchType.caption)
                                            .foregroundStyle(Color.rewatch.mutedForeground)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(many ? "Yes, this one" : "Yes, that is it")
                                    .font(RewatchType.bodySemiBold)
                                    .foregroundStyle(Color.rewatch.primaryDeep)
                            }
                            .padding(Space.m)
                            .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.rewatch.border))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    Button(many ? "No, none of these" : "No, this is a different watch") {
                        Haptics.shared.play(.selection)
                        model.declineVault()
                    }
                    .font(RewatchType.bodySemiBold)
                    .foregroundStyle(Color.rewatch.primaryDeep)
                    .frame(minHeight: Space.touchTarget)
                }
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    private func vaultDetail(_ match: VaultMatch) -> String? {
        var parts: [String] = []
        if let reference = match.reference, !reference.isEmpty, reference != match.displayTitle { parts.append(reference) }
        if let day = MarketFormat.day(iso: match.acquiredDate) { parts.append("acquired \(day)") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}

/// One of Brand, Model and Reference: free text, with the catalog's list for
/// that level (scoped by the fields above) under it while it has the cursor.
/// Picking fills only this field and moves on (the site's cascade).
private struct BuilderCatalogField: View {
    let context: BuilderStepContext
    let field: IdentityField

    @State private var response: CatalogCascadeResponse?
    @State private var failed = false
    @State private var loading = false

    private var model: ListingBuilderModel { context.model }
    private var focusKey: BuilderField {
        switch field {
        case .brand: .brand
        case .model: .model
        case .reference: .reference
        }
    }

    private var isFocused: Bool { context.focus.wrappedValue == focusKey }

    private var label: String {
        switch field {
        case .brand: "Brand"
        case .model: "Model"
        case .reference: "Reference number"
        }
    }

    private var placeholder: String {
        switch field {
        case .brand: "Enter brand"
        case .model: "Enter model"
        case .reference: "Enter reference"
        }
    }

    private var text: Binding<String> {
        switch field {
        case .brand: Binding(get: { model.answers.brand }, set: { model.answers.brand = $0 })
        case .model: Binding(get: { model.answers.model }, set: { model.answers.model = $0 })
        case .reference: Binding(get: { model.answers.reference }, set: { model.answers.reference = $0 })
        }
    }

    /// Model needs a brand above it and Reference needs a model.
    private var enabled: Bool {
        switch field {
        case .brand: true
        case .model: !model.answers.brand.isEmpty
        case .reference: !model.answers.brand.isEmpty && !model.answers.model.isEmpty
        }
    }

    private var query: CatalogCascadeQuery {
        let level: CatalogCascadeQuery.Level = switch field {
        case .brand: .brands
        case .model: .models
        case .reference: .references
        }
        return CatalogCascadeQuery(level: level, brand: model.answers.brand, model: model.answers.model, text: text.wrappedValue)
    }

    private var requestKey: CatalogCascadeQuery? { isFocused && enabled ? query : nil }

    private var suggestions: [String] {
        guard let response else { return [] }
        let needle = BuilderRules.catalogKey(text.wrappedValue)
        var seen = Set<String>()
        var out: [String] = []
        for value in response.values.map(\.value) {
            let key = BuilderRules.catalogKey(value)
            guard !key.isEmpty, key.contains(needle) || needle.isEmpty, !seen.contains(key) else { continue }
            // The exact text already typed is not a suggestion.
            if key == needle { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    private var helper: String {
        switch field {
        case .model where model.answers.brand.isEmpty:
            "Enter the brand first and this offers its models."
        case .reference where !model.answers.brand.isEmpty && model.answers.model.isEmpty:
            "Enter the model and this offers its reference numbers."
        case .reference:
            (SellFieldHelp.reference.components(separatedBy: ". ").first ?? "") + "."
        default:
            ""
        }
    }

    private var submitLabel: SubmitLabel {
        BuilderRules.nextEmptyIdentityField(after: field, in: model.answers) == nil ? .continue : .next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            BuilderFieldLabel(text: label)
            BuilderTextBox(
                placeholder: placeholder,
                text: text,
                keyboard: field == .reference ? .asciiCapable : .default,
                capitalization: field == .reference ? .characters : .words,
                submitLabel: submitLabel,
                focused: isFocused,
                onSubmit: submit
            )
            .focused(context.focus, equals: focusKey)
            .accessibilityIdentifier("builder.\(field.rawValue)")

            if isFocused, enabled {
                list
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }

            if !helper.isEmpty {
                Text(helper)
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Motion.easeFast, value: isFocused)
        .task(id: requestKey) {
            response = nil
            failed = false
            guard let key = requestKey, key.canSearch else { return }
            loading = true
            defer { loading = false }
            do {
                try await Task.sleep(for: .milliseconds(180))
                let result = try await model.backend.cascade(key)
                guard !Task.isCancelled, requestKey == key else { return }
                response = result
            } catch {
                guard !Task.isCancelled, requestKey == key else { return }
                failed = true
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let rows = suggestions
        if !rows.isEmpty || failed || response != nil {
            VStack(alignment: .leading, spacing: 0) {
                if failed {
                    note("We could not reach the Rewatch catalog just now. Type it in full and carry on. Your listing is still matched when it goes to review.")
                } else if rows.isEmpty {
                    if response?.truncated == true {
                        note("More of the catalog than fits here came back: type a little more and this narrows to it.")
                    } else if !text.wrappedValue.isEmpty {
                        note("\(emptyCopy) Type it in full and carry on.")
                    }
                } else {
                    ForEach(Array(rows.prefix(8).enumerated()), id: \.element) { index, value in
                        Button {
                            pick(value)
                        } label: {
                            Text(value)
                                .font(RewatchType.body)
                                .foregroundStyle(Color.rewatch.foreground)
                                .frame(maxWidth: .infinity, minHeight: Space.touchTarget, alignment: .leading)
                                .padding(.horizontal, Space.l)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < min(rows.count, 8) - 1 {
                            Rectangle().fill(Color.rewatch.border.opacity(0.6)).frame(height: 1)
                        }
                    }
                    if rows.count > 8 || response?.truncated == true {
                        Rectangle().fill(Color.rewatch.border).frame(height: 1)
                        note("The catalog holds more than fits here: keep typing to narrow it.")
                    }
                }
            }
            .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.rewatch.border))
            .shadow(color: Color.rewatch.shadowTint.opacity(0.08), radius: 10, y: 4)
        }
    }

    private var emptyCopy: String {
        switch field {
        case .brand: "No brand in the Rewatch catalog matches that yet."
        case .model: "No \(model.answers.brand) model in the catalog matches that yet."
        case .reference: "No \(model.answers.model) reference in the catalog matches that yet."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(RewatchType.caption)
            .foregroundStyle(Color.rewatch.secondaryForeground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
    }

    private func pick(_ value: String) {
        Haptics.shared.play(.selection)
        text.wrappedValue = value
        response = nil
        switch field {
        case .brand: context.focus.wrappedValue = .model
        case .model: context.focus.wrappedValue = .reference
        case .reference: context.focus.wrappedValue = nil
        }
    }

    /// Next goes to the next required field still empty; with all three
    /// filled, it is Continue.
    private func submit() {
        if let next = BuilderRules.nextEmptyIdentityField(after: field, in: model.answers) {
            context.focus.wrappedValue = switch next {
            case .brand: .brand
            case .model: .model
            case .reference: .reference
            }
        } else {
            context.focus.wrappedValue = nil
            context.advance()
        }
    }
}

// MARK: - 2 · The year

struct BuilderYearStep: View {
    let context: BuilderStepContext
    private var model: ListingBuilderModel { context.model }

    private var recent: [String] {
        (0..<5).map { String(model.currentYear - $0) } + ["unknown"]
    }

    private var problem: String? {
        BuilderRules.yearProblem(model.answers.year, currentYear: model.currentYear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                BuilderFieldLabel(text: "Year of manufacture")
                HStack(alignment: .top, spacing: Space.m) {
                    BuilderTextBox(
                        placeholder: String(model.currentYear - 4),
                        text: Binding(
                            get: { model.answers.year == "unknown" ? "" : model.answers.year },
                            set: { typed in
                                let digits = String(typed.filter { $0.isASCII && $0.isNumber }.prefix(4))
                                if digits.isEmpty, model.answers.year == "unknown" { return }
                                model.answers.year = digits
                            }
                        ),
                        keyboard: .numberPad,
                        invalid: problem != nil,
                        focused: context.focus.wrappedValue == .year
                    )
                    .monospacedDigit()
                    .frame(width: 112)
                    .focused(context.focus, equals: .year)
                    .accessibilityIdentifier("builder.year")
                }
                WrapLayout(spacing: Space.s, lineSpacing: Space.s) {
                    ForEach(Array(recent.enumerated()), id: \.element) { index, year in
                        yearChip(year).builderRise(index)
                    }
                }
                Text(problem ?? " ")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.destructive)
                    .opacity(problem == nil ? 0 : 1)
                    .accessibilityHidden(problem == nil)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    BuilderFieldLabel(text: "Stock number", optional: true)
                    Label("Only you see this", systemImage: "lock.fill")
                        .labelStyle(.titleAndIcon)
                        .font(RewatchType.label)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                }
                BuilderTextBox(
                    placeholder: "e.g. A-1042",
                    text: Binding(
                        get: { model.answers.sku },
                        set: { model.answers.sku = String($0.prefix(BuilderRules.skuMax)) }
                    ),
                    capitalization: .characters,
                    submitLabel: .continue,
                    focused: context.focus.wrappedValue == .sku,
                    onSubmit: {
                        // Optional, so Next here continues, unless the year
                        // (required) is still missing.
                        if BuilderRules.yearIsValid(model.answers.year, currentYear: model.currentYear) {
                            context.focus.wrappedValue = nil
                            context.advance()
                        } else {
                            context.focus.wrappedValue = .year
                        }
                    }
                )
                .focused(context.focus, equals: .sku)
                Text(SellFieldHelp.stockNumber)
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func yearChip(_ year: String) -> some View {
        let selected = model.answers.year == year
        return Button {
            Haptics.shared.play(.selection)
            model.answers.year = year
            context.focus.wrappedValue = nil
            context.advanceLater(.year, 280)
        } label: {
            Text(year == "unknown" ? "Unknown" : year)
                .font(RewatchType.bodySemiBold)
                .monospacedDigit()
                .foregroundStyle(Color.rewatch.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(selected ? Color.rewatch.accent.opacity(0.7) : Color.rewatch.card, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.rewatch.primary : Color.rewatch.border, lineWidth: selected ? 1.5 : 1))
                .frame(minHeight: Space.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 3 · Condition

struct BuilderConditionStep: View {
    let context: BuilderStepContext
    @State private var askMatch: Bool
    @State private var showsScale = false
    @State private var openNotes: Set<String> = []

    init(context: BuilderStepContext) {
        self.context = context
        _askMatch = State(initialValue: context.model.answers.grade != nil)
    }

    private var model: ListingBuilderModel { context.model }

    private enum Phase { case grade, match, parts }

    private var phase: Phase {
        guard model.answers.grade != nil, askMatch else { return .grade }
        return model.answers.partsMatch == false ? .parts : .match
    }

    var body: some View {
        Group {
            switch phase {
            case .grade: gradeList
            case .match: matchQuestion
            case .parts: partsGrid
            }
        }
        .animation(.builderRise, value: phase)
        .sheet(isPresented: $showsScale) { GradeScaleSheet() }
    }

    private var gradeList: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(ConditionGrades.definitions.enumerated()), id: \.element.grade) { index, definition in
                BuilderChoiceRow(
                    label: definition.grade,
                    detail: definition.description,
                    selected: model.answers.grade == definition.grade,
                    index: index
                ) {
                    model.chooseGrade(definition.grade)
                    Task {
                        try? await Task.sleep(for: .milliseconds(320))
                        withAnimation(.builderRise) { askMatch = true }
                    }
                }
            }
            scaleButton
        }
        .transition(.opacity)
    }

    private var scaleButton: some View {
        Button {
            showsScale = true
        } label: {
            Label("Grading scale", systemImage: "info.circle")
                .font(RewatchType.bodySemiBold)
                .foregroundStyle(Color.rewatch.primaryDeep)
                .frame(minHeight: Space.touchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what each condition grade means.")
    }

    private var matchQuestion: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            (Text("Do all the parts look ").font(RewatchType.body)
                + Text(model.answers.grade ?? "").font(RewatchType.bodySemiBold)
                + Text("?").font(RewatchType.body))
                .foregroundStyle(Color.rewatch.foreground)
            VStack(spacing: Space.s) {
                BuilderChoiceRow(
                    label: "Yes, they all match",
                    detail: "Case, dial, bezel, crystal, bracelet, clasp and caseback.",
                    selected: model.answers.partsMatch == true
                ) {
                    model.answers.partsMatch = true
                    context.advanceLater(.condition, 320)
                }
                BuilderChoiceRow(label: "Some parts differ", detail: "Set those parts on their own.", selected: false, index: 1) {
                    model.partsDiffer()
                }
            }
            noteField(key: "overall", label: "A few words on why", example: ConditionPart.overall.noteExample, compact: false)
            HStack {
                changeGradeButton
                Spacer()
                scaleButton
            }
        }
        .transition(.opacity.combined(with: .offset(y: 10)))
    }

    private var changeGradeButton: some View {
        Button("Change the overall grade") {
            Haptics.shared.play(.selection)
            withAnimation(.builderRise) { askMatch = false }
        }
        .font(RewatchType.bodySemiBold)
        .foregroundStyle(Color.rewatch.primaryDeep)
        .frame(minHeight: Space.touchTarget)
    }

    /// Seven parts by five grades in one grid: a row per part, a column per
    /// grade, so the whole editor reads at a glance. A part that differs opens
    /// its note; any other part can open one.
    private var partsGrid: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            (Text("Everything starts at ").font(RewatchType.label)
                + Text(model.answers.grade ?? "").font(RewatchType.label.weight(.semibold))
                + Text(". Change only the parts that look different.").font(RewatchType.label))
                .foregroundStyle(Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                gridHeader
                ForEach(Array(BuilderRules.parts.enumerated()), id: \.element) { index, part in
                    Rectangle().fill(Color.rewatch.border.opacity(0.7)).frame(height: 1)
                    partRow(part).builderRise(index)
                }
                Rectangle().fill(Color.rewatch.border).frame(height: 1)
                HStack(alignment: .center, spacing: Space.m) {
                    Text("Overall")
                        .font(RewatchType.bodySemiBold)
                        .foregroundStyle(Color.rewatch.foreground)
                        .frame(width: 74, alignment: .leading)
                    noteField(key: "overall", label: "Overall: why \(model.answers.grade ?? "")", example: ConditionPart.overall.noteExample, compact: true)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
            }
            .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.rewatch.border))

            HStack {
                changeGradeButton
                Spacer()
                scaleButton
            }
        }
        .transition(.opacity.combined(with: .offset(y: 10)))
    }

    private var gridHeader: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Part")
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .frame(width: 74, alignment: .leading)
            ForEach(ConditionPart.grades, id: \.self) { grade in
                Text(grade)
                    .font(RewatchType.sans(.semiBold, 10, relativeTo: .caption2))
                    .foregroundStyle(grade == model.answers.grade ? Color.rewatch.foreground : Color.rewatch.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            Color.clear.frame(width: 32)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .accessibilityHidden(true)
    }

    private func partRow(_ part: ConditionPart) -> some View {
        let current = model.answers.parts[part.rawValue]
        let differs = current != nil && current != model.answers.grade
        let note = model.answers.conditionNotes[part.rawValue] ?? ""
        let trayOpen = differs || openNotes.contains(part.rawValue) || !note.isEmpty
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(part.label)
                    .font(differs ? RewatchType.bodySemiBold : RewatchType.body)
                    .foregroundStyle(differs ? Color.rewatch.foreground : Color.rewatch.secondaryForeground)
                    .frame(width: 74, alignment: .leading)
                ForEach(ConditionPart.grades, id: \.self) { grade in
                    let on = current == grade
                    Button {
                        Haptics.shared.play(.selection)
                        model.setPart(part, grade)
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(on ? Color.clear : Color.rewatch.borderBright, lineWidth: 1)
                            if on {
                                Circle().fill(Color.rewatch.primary)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Color.rewatch.primaryForeground)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(part.label): \(grade)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
                }
                Button {
                    withAnimation(.builderRise) {
                        if openNotes.contains(part.rawValue) { openNotes.remove(part.rawValue) } else { openNotes.insert(part.rawValue) }
                    }
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(trayOpen ? Color.rewatch.primary : Color.rewatch.mutedForeground)
                        .frame(width: 32, height: Space.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a note on the \(part.label.lowercased())")
            }
            if trayOpen {
                noteField(key: part.rawValue, label: "\(part.label): why this grade", example: part.noteExample, compact: true)
                    .padding(.bottom, Space.s)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.horizontal, Space.m)
    }

    private func noteField(key: String, label: String, example: String, compact: Bool) -> some View {
        let text = model.answers.conditionNotes[key] ?? ""
        let length = ConditionNote.length(text)
        let showCount = length >= BuilderRules.conditionNoteMax - 16
        let focusKey = BuilderField.note(key)
        return VStack(alignment: .leading, spacing: Space.xs) {
            if !compact {
                BuilderFieldLabel(text: label, optional: true)
            }
            BuilderTextBox(
                placeholder: "Why? e.g. \(example)",
                text: Binding(get: { model.answers.conditionNotes[key] ?? "" }, set: { model.setNote(key, $0) }),
                submitLabel: .done,
                invalid: length > BuilderRules.conditionNoteMax,
                focused: context.focus.wrappedValue == focusKey,
                onSubmit: { context.focus.wrappedValue = nil }
            ) {
                EmptyView()
            }
            .overlay(alignment: .trailing) {
                if showCount {
                    Text("\(length)/\(BuilderRules.conditionNoteMax)")
                        .font(RewatchType.caption)
                        .monospacedDigit()
                        .foregroundStyle(length > BuilderRules.conditionNoteMax ? Color.rewatch.destructive : Color.rewatch.mutedForeground)
                        .padding(.trailing, Space.m)
                }
            }
            .focused(context.focus, equals: focusKey)
            .accessibilityLabel("\(label), optional")
            if length > BuilderRules.conditionNoteMax {
                Text("Keep it to \(BuilderRules.conditionNoteMax) characters.")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.destructive)
            }
        }
    }
}

// MARK: - 4 · What comes with it

struct BuilderBoxStep: View {
    let context: BuilderStepContext
    private var model: ListingBuilderModel { context.model }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    BuilderToggleTile(label: "Box", on: model.answers.box, index: 0) { model.answers.box.toggle() }
                    BuilderToggleTile(label: "Papers", on: model.answers.papers, index: 1) { model.answers.papers.toggle() }
                    BuilderToggleTile(label: "Booklets", on: model.answers.booklets, index: 2) { model.answers.booklets.toggle() }
                }
                Text(model.answers.box && model.answers.papers && model.answers.booklets
                    ? "Full set."
                    : "Nothing extra? Leave them off and continue.")
                    .font(RewatchType.label)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .contentTransition(.opacity)
                    .animation(Motion.easeFast, value: model.answers.box && model.answers.papers && model.answers.booklets)
            }

            // The site's "Notes (optional)": the seller's own words, which are
            // the listing's description and nothing else.
            VStack(alignment: .leading, spacing: Space.s) {
                BuilderFieldLabel(text: "Anything else buyers should know?", optional: true)
                ZStack(alignment: .topLeading) {
                    if model.answers.notes.isEmpty {
                        Text("Accessories, and anything about this watch that is not as the catalog describes: a replacement bracelet, a refinished dial, an engraved caseback.")
                            .font(RewatchType.body)
                            .foregroundStyle(Color.rewatch.placeholder)
                            .padding(.horizontal, Space.l)
                            .padding(.vertical, Space.m + 2)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(
                        get: { model.answers.notes },
                        set: { model.answers.notes = String($0.prefix(BuilderRules.sellerNotesMax)) }
                    ))
                    .font(RewatchType.body)
                    .foregroundStyle(Color.rewatch.foreground)
                    .tint(Color.rewatch.primary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .focused(context.focus, equals: .sellerNotes)
                    .accessibilityLabel("Anything else buyers should know, optional")
                }
                .frame(minHeight: 132)
                .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(context.focus.wrappedValue == .sellerNotes ? Color.rewatch.primary : Color.rewatch.border,
                                      lineWidth: context.focus.wrappedValue == .sellerNotes ? 1.5 : 1)
                )
                Text("Shows on your listing.")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
            }
            .builderRise(3)
        }
    }
}

// MARK: - 5 · History

struct BuilderHistoryStep: View {
    let context: BuilderStepContext
    @State private var index: Int

    init(context: BuilderStepContext) {
        self.context = context
        let firstOpen = HistoryQuestion.allCases.firstIndex { context.model.answers.historyAnswer($0) == nil }
        _index = State(initialValue: firstOpen ?? HistoryQuestion.allCases.count - 1)
    }

    private var model: ListingBuilderModel { context.model }
    private var question: HistoryQuestion { HistoryQuestion.allCases[index] }

    private var needsFollowUp: Bool {
        (question == .originality && model.answers.originality == "replaced")
            || (question == .service && model.answers.serviceHistory == "serviced")
    }

    private var yearIssue: String? {
        guard question == .service, needsFollowUp else { return nil }
        return BuilderRules.serviceYearProblem(model.answers.serviceYear, currentYear: model.currentYear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            dots
            VStack(alignment: .leading, spacing: Space.m) {
                Text(question.question)
                    .font(RewatchType.serif(.semiBold, 19, relativeTo: .title3))
                    .foregroundStyle(Color.rewatch.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(question.help)
                    .font(RewatchType.label)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Space.s) {
                    ForEach(Array(question.options.enumerated()), id: \.element.value) { optionIndex, option in
                        BuilderChoiceRow(
                            label: option.label,
                            selected: model.answers.historyAnswer(question) == option.value,
                            index: optionIndex
                        ) {
                            choose(option.value)
                        }
                    }
                }
                followUp
            }
            .id(question)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 14)),
                removal: .opacity
            ))
        }
        .animation(.builderRise, value: index)
    }

    private var dots: some View {
        HStack(spacing: Space.s) {
            ForEach(Array(HistoryQuestion.allCases.enumerated()), id: \.element) { dot, item in
                Button {
                    if dot <= index || (dot > 0 && model.answers.historyAnswer(HistoryQuestion.allCases[dot - 1]) != nil) {
                        withAnimation(.builderRise) { index = dot }
                    }
                } label: {
                    Capsule()
                        .fill(dot == index ? Color.rewatch.primary : (dot < index ? Color.rewatch.primary.opacity(0.6) : Color.rewatch.borderBright))
                        .frame(width: dot == index ? 24 : 6, height: 6)
                        .frame(height: Space.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.question)
            }
        }
        .animation(.builderRise, value: index)
    }

    @ViewBuilder
    private var followUp: some View {
        if needsFollowUp {
            let isNote = question == .originality
            VStack(alignment: .leading, spacing: Space.s) {
                BuilderFieldLabel(text: question.followUpLabel ?? "", optional: true)
                BuilderTextBox(
                    placeholder: isNote ? "e.g. the crown and the crystal" : "e.g. \(model.currentYear - 2)",
                    text: isNote
                        ? Binding(get: { model.answers.replaced }, set: { model.answers.replaced = String($0.filter { !$0.isNewline }.prefix(BuilderRules.replacedNoteMax)) })
                        : Binding(get: { model.answers.serviceYear }, set: { model.answers.serviceYear = String($0.filter { $0.isASCII && $0.isNumber }.prefix(4)) }),
                    keyboard: isNote ? .default : .numberPad,
                    submitLabel: index < HistoryQuestion.allCases.count - 1 ? .next : .continue,
                    invalid: yearIssue != nil,
                    focused: context.focus.wrappedValue == (isNote ? .replaced : .serviceYear),
                    onSubmit: next
                )
                .focused(context.focus, equals: isNote ? .replaced : .serviceYear)
                Text(yearIssue ?? " ")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.destructive)
                    .opacity(yearIssue == nil ? 0 : 1)
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
            .onAppear {
                context.focus.wrappedValue = isNote ? .replaced : .serviceYear
            }
        }
    }

    private func choose(_ value: String) {
        model.answers.setHistory(value, for: question)
        let followUp = (question == .originality && value == "replaced") || (question == .service && value == "serviced")
        if !followUp {
            context.focus.wrappedValue = nil
            let asked = index
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                // Only if the seller has not moved on by hand in that beat.
                guard index == asked, model.step == .history else { return }
                next()
            }
        }
    }

    /// The next question, or on past the last one.
    func next() {
        guard yearIssue == nil else { return }
        if index < HistoryQuestion.allCases.count - 1 {
            context.focus.wrappedValue = nil
            withAnimation(.builderRise) { index += 1 }
        } else {
            context.focus.wrappedValue = nil
            context.advance()
        }
    }
}

// MARK: - 7 · Price

struct BuilderPriceStep: View {
    let context: BuilderStepContext
    private var model: ListingBuilderModel { context.model }

    private var problem: String? { BuilderRules.priceProblem(model.answers.priceText) }
    private var customsIssue: String? {
        model.needsCustomsFields ? BuilderRules.customsProblem(country: model.answers.customsCountry, hts: model.answers.customsHTS) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.s) {
                BuilderFieldLabel(text: "Listing price (USD)")
                BuilderTextBox(
                    placeholder: "3,450",
                    text: Binding(
                        get: { model.answers.priceText },
                        set: { model.answers.priceText = BuilderRules.formatMoneyInput($0) }
                    ),
                    keyboard: .decimalPad,
                    invalid: problem != nil,
                    focused: context.focus.wrappedValue == .price
                ) {
                    Text("$")
                        .font(RewatchType.body)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                }
                .font(RewatchType.price)
                .monospacedDigit()
                .focused(context.focus, equals: .price)
                .accessibilityIdentifier("builder.price")
                Text(problem ?? " ")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.destructive)
                    .opacity(problem == nil ? 0 : 1)
            }

            if model.needsCustomsFields {
                // A dealer outside the US: what customs needs, as the site asks it.
                HStack(alignment: .top, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        BuilderFieldLabel(text: "Country of origin")
                        BuilderTextBox(
                            placeholder: "CH",
                            text: Binding(get: { model.answers.customsCountry }, set: { model.answers.customsCountry = String($0.prefix(2)).uppercased() }),
                            capitalization: .characters,
                            focused: context.focus.wrappedValue == .customsCountry,
                            onSubmit: { context.focus.wrappedValue = .customsHTS }
                        )
                        .focused(context.focus, equals: .customsCountry)
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        BuilderFieldLabel(text: "HTS code")
                        BuilderTextBox(
                            placeholder: "9102.11",
                            text: Binding(get: { model.answers.customsHTS }, set: { model.answers.customsHTS = $0 }),
                            keyboard: .numbersAndPunctuation,
                            submitLabel: .done,
                            focused: context.focus.wrappedValue == .customsHTS,
                            onSubmit: { context.focus.wrappedValue = nil }
                        )
                        .focused(context.focus, equals: .customsHTS)
                    }
                }
                if let customsIssue {
                    Text(customsIssue)
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.destructive)
                }
            }

            BuilderPayoutBreakdown(model: model)
        }
    }
}

// MARK: - 8 · Returns

struct BuilderReturnsStep: View {
    let context: BuilderStepContext
    private var model: ListingBuilderModel { context.model }

    var body: some View {
        VStack(spacing: Space.s) {
            ForEach(Array(ReturnsChoice.allCases.enumerated()), id: \.element) { index, choice in
                BuilderChoiceRow(
                    label: choice.label,
                    detail: choice.detail,
                    selected: model.answers.returns == choice,
                    index: index
                ) {
                    model.answers.returns = choice
                    context.advanceLater(.returns, 300)
                }
            }
        }
    }
}
