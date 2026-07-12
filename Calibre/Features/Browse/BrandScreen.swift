import CalibreDesign
import CalibreKit
import SwiftUI

/// One brand's corner of the market: serif hero, the locked-brand grid with
/// the same filter/sort controls (minus brand), and a rail into other brands.
struct BrandScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.browsePush) private var push

    let brand: String

    @State private var model: ResultsModel?

    private var brandGroup: BrandGroup? {
        services.catalog.metadata?.options.byBrand.first { $0.brand == brand }
    }

    private var otherBrands: [BrandGroup] {
        (services.catalog.metadata?.options.byBrand ?? [])
            .filter { $0.brand != brand }
            .sorted { ($0.liveTotal ?? 0) > ($1.liveTotal ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        Group {
            if let model {
                ResultsContent(model: model, lockedBrand: brand, header: AnyView(hero))
            } else {
                ResultsGridSkeleton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle(brand)
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
        .task {
            if model == nil {
                model = ResultsModel(catalog: services.catalog, filters: BrowseFilters(brand: brand))
            }
            await model?.loadFirstPageIfNeeded()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            exploreRail
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow("Brand")
            Text(brand)
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
            if let count = brandGroup?.liveTotal ?? model?.total {
                Text(count == 1 ? "1 watch live on Calibre." : "\(count.formatted()) watches live on Calibre.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.l)
    }

    @ViewBuilder
    private var exploreRail: some View {
        if !otherBrands.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow("Explore other brands")
                    .padding(.horizontal, Space.margin)
                ChipRail {
                    ForEach(otherBrands, id: \.brand) { group in
                        FilterChip(group.brand, isSelected: false) {
                            push(.brand(group.brand))
                        }
                    }
                }
            }
            .padding(.vertical, Space.m)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.calibre.border).frame(height: 1)
            }
        }
    }
}
