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
        if (services.catalog.metadata?.options.byBrand.count ?? 0) > 1 {
            Button {
                push(.brands)
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.calibre.primary)
                    Text("Browse all brands")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .padding(.horizontal, Space.margin)
                .frame(minHeight: Space.touchTarget + 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .background(Color.calibre.background.opacity(0.97))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.calibre.border).frame(height: 1)
            }
            .accessibilityHint("Opens the complete brand directory")
        }
    }
}
