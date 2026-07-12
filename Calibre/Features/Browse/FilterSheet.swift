import CalibreDesign
import CalibreKit
import SwiftUI

/// The full facet editor: cascading brand → model → reference, condition,
/// year, price range, box & papers, and the secondary facet selects — with a
/// live "Show N watches" count debounced against the backend.
struct FilterSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let metadata: MarketMetadata?
    /// Non-nil hides the brand cascade (BrandScreen locks it).
    let lockedBrand: String?
    let onApply: (BrowseFilters) -> Void

    @State private var draft: BrowseFilters
    @State private var yearText: String
    @State private var priceLower: Double
    @State private var priceUpper: Double
    @State private var liveCount: Int?
    @State private var countTask: Task<Void, Never>?

    private let priceBounds: ClosedRange<Double>

    private static let conditions = ["New", "Like New", "Very Good", "Good", "Worn"]

    init(
        metadata: MarketMetadata?,
        filters: BrowseFilters,
        lockedBrand: String? = nil,
        onApply: @escaping (BrowseFilters) -> Void
    ) {
        self.metadata = metadata
        self.lockedBrand = lockedBrand
        self.onApply = onApply
        _draft = State(initialValue: filters)
        _yearText = State(initialValue: filters.year.map(String.init) ?? "")

        let lower = (metadata?.price.min.value as NSDecimalNumber?)?.doubleValue ?? 0
        let upper = (metadata?.price.max.value as NSDecimalNumber?)?.doubleValue ?? 100_000
        let bounds = lower < upper ? lower...upper : 0...100_000
        priceBounds = bounds
        _priceLower = State(
            initialValue: (filters.priceMin as NSDecimalNumber?)?.doubleValue ?? bounds.lowerBound
        )
        _priceUpper = State(
            initialValue: (filters.priceMax as NSDecimalNumber?)?.doubleValue ?? bounds.upperBound
        )
    }

    var body: some View {
        SheetScaffold(title: "Refine the market", detents: [.large]) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        if lockedBrand == nil {
                            watchSection
                        }
                        conditionSection
                        priceSection
                        yearAndPapersSection
                        detailsSection
                    }
                    .padding(.bottom, Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)

                footer
            }
        }
        .onChange(of: draft) {
            scheduleCount()
        }
        .task {
            scheduleCount(immediately: true)
        }
    }

    // MARK: Sections

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("The watch")
            FacetSelect(label: "Brand", options: brandOptions, selection: brandBinding)
            if draft.brand != nil {
                FacetSelect(label: "Model", options: modelOptions, selection: modelBinding)
            }
            if draft.brand != nil, draft.model != nil, !referenceOptions.isEmpty {
                FacetSelect(label: "Reference", options: referenceOptions, selection: referenceBinding)
            }
        }
    }

    private var conditionSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Condition")
            ChipRail {
                FilterChip("Any", isSelected: draft.condition == nil) {
                    draft.condition = nil
                }
                ForEach(Self.conditions, id: \.self) { condition in
                    FilterChip(condition, isSelected: draft.condition == condition) {
                        draft.condition = draft.condition == condition ? nil : condition
                    }
                }
            }
            .padding(.horizontal, -Space.l)
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Price")
            PriceRangeSlider(
                lowerValue: $priceLower,
                upperValue: $priceUpper,
                in: priceBounds,
                step: priceStep
            )
            .onChange(of: priceLower) { syncPriceIntoDraft() }
            .onChange(of: priceUpper) { syncPriceIntoDraft() }
        }
    }

    private var yearAndPapersSection: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            CalibreTextField("Year", text: $yearText, placeholder: "Any year") {
                EmptyView()
            }
            .onChange(of: yearText) {
                let digits = yearText.filter(\.isNumber)
                if digits != yearText { yearText = digits }
                draft.year = digits.count == 4 ? Int(digits) : nil
            }

            Toggle(isOn: boxPapersBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Box & papers")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Only full sets with original box and papers.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            .tint(Color.calibre.primary)
            .frame(minHeight: Space.touchTarget)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Details")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.m),
                    GridItem(.flexible(), spacing: Space.m),
                ],
                spacing: Space.m
            ) {
                FacetSelect(label: "Material", options: options(\.materials), selection: $draft.material)
                FacetSelect(label: "Dial color", options: options(\.colors), selection: $draft.color)
                FacetSelect(label: "Case size", options: options(\.caseSizes), selection: $draft.caseSize)
                FacetSelect(label: "Movement", options: options(\.movements), selection: $draft.movement)
                FacetSelect(label: "Bracelet", options: options(\.bracelets), selection: $draft.bracelet)
                FacetSelect(label: "Thickness", options: options(\.thicknesses), selection: $draft.thickness)
                FacetSelect(label: "Lug width", options: options(\.lugWidths), selection: $draft.lugWidth)
                FacetSelect(label: "Water resistance", options: options(\.waterResistances), selection: $draft.waterResistance)
                FacetSelect(label: "Caliber", options: options(\.calibers), selection: $draft.caliber)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Space.s) {
            Button {
                Haptics.shared.play(.press)
                onApply(draft)
                dismiss()
            } label: {
                Text(showTitle)
                    .contentTransition(.numericText())
                    .animation(Motion.easeMedium, value: liveCount)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))

            Button("Clear all") {
                draft = draft.cleared(keepBrand: lockedBrand != nil)
                yearText = ""
                priceLower = priceBounds.lowerBound
                priceUpper = priceBounds.upperBound
            }
            .buttonStyle(.calibre(.ghost, fullWidth: true))
        }
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .background(Color.calibre.card)
    }

    // MARK: Live count

    private var showTitle: String {
        guard let liveCount else { return "Show the watches" }
        return liveCount == 1 ? "Show 1 watch" : "Show \(liveCount.formatted()) watches"
    }

    private func scheduleCount(immediately: Bool = false) {
        countTask?.cancel()
        let query = draft.query(page: 1, pageSize: 1, includeTotal: true)
        let catalog = services.catalog
        countTask = Task {
            if !immediately {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            if let page = try? await catalog.browse(query), !Task.isCancelled {
                liveCount = page.pagination.total
            }
        }
    }

    // MARK: Cascade plumbing

    private var brandOptions: [String] {
        metadata?.options.brands ?? []
    }

    private var currentBrandGroup: BrandGroup? {
        metadata?.options.byBrand.first { $0.brand == draft.brand }
    }

    private var modelOptions: [String] {
        currentBrandGroup?.models.map(\.model) ?? []
    }

    private var referenceOptions: [String] {
        currentBrandGroup?.models.first { $0.model == draft.model }?.references ?? []
    }

    private var brandBinding: Binding<String?> {
        Binding(
            get: { draft.brand },
            set: { newValue in
                draft.brand = newValue
                draft.model = nil
                draft.reference = nil
            }
        )
    }

    private var modelBinding: Binding<String?> {
        Binding(
            get: { draft.model },
            set: { newValue in
                draft.model = newValue
                draft.reference = nil
            }
        )
    }

    private var referenceBinding: Binding<String?> {
        Binding(get: { draft.reference }, set: { draft.reference = $0 })
    }

    private var boxPapersBinding: Binding<Bool> {
        Binding(
            get: { draft.boxPapers == true },
            set: { draft.boxPapers = $0 ? true : nil }
        )
    }

    private func options(_ keyPath: KeyPath<FacetOptions, [String]>) -> [String] {
        metadata?.options[keyPath: keyPath] ?? []
    }

    private var priceStep: Double {
        max((priceBounds.upperBound - priceBounds.lowerBound) / 400, 1).rounded()
    }

    private func syncPriceIntoDraft() {
        draft.priceMin = priceLower > priceBounds.lowerBound ? Decimal(Int(priceLower)) : nil
        draft.priceMax = priceUpper < priceBounds.upperBound ? Decimal(Int(priceUpper)) : nil
    }
}

// MARK: - Compact select

/// A quiet labeled select: card fill, hairline border, current value, and a
/// menu picker behind it. "Any" clears the facet.
private struct FacetSelect: View {
    let label: String
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                Text("Any").tag(String?.none)
                ForEach(options, id: \.self) { option in
                    Text(option).tag(String?.some(option))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                HStack(spacing: Space.s) {
                    Text(selection ?? "Any")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(
                            selection == nil ? Color.calibre.mutedForeground : Color.calibre.foreground
                        )
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(minHeight: Space.touchTarget)
            .background(
                Color.calibre.card,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(
                        selection == nil ? Color.calibre.border : Color.calibre.borderBright,
                        lineWidth: 1
                    )
            )
        }
        .accessibilityLabel("\(label), \(selection ?? "any")")
    }
}
