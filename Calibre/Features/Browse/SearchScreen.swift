import CalibreDesign
import CalibreKit
import SwiftUI

/// Type-ahead search: facet suggestions matched locally against metadata,
/// listing suggestions from a debounced backend query, and recent searches
/// when the field is empty. Submit lands on the results grid.
struct SearchScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.browsePush) private var push

    @State private var query = ""
    @State private var listingHits: [Listing] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var recents = RecentSearchesStore()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [SearchSuggestion] {
        services.catalog.suggestions(matching: trimmedQuery, limit: 6)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowseSearchField(text: $query, autofocus: true) {
                submit(trimmedQuery)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.m)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmedQuery.isEmpty {
                        recentRows
                    } else {
                        facetRows
                        listingRows
                    }
                }
                .padding(.bottom, Space.xxl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color.calibre.background)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
        .task {
            try? await services.catalog.loadMetadata()
        }
        .onChange(of: query) {
            scheduleListingSearch()
        }
    }

    // MARK: Recents

    @ViewBuilder
    private var recentRows: some View {
        if recents.entries.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "Search the market",
                message: "Look for a brand, a model, or a reference number — Submariner, Speedmaster, 116610LN."
            )
        } else {
            HStack {
                Eyebrow("Recent searches")
                Spacer()
                Button("Clear") {
                    recents.clear()
                }
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.primary)
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)

            ForEach(recents.entries, id: \.self) { entry in
                Button {
                    query = entry
                    submit(entry)
                } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Text(entry)
                            .font(CalibreType.body)
                            .foregroundStyle(Color.calibre.foreground)
                        Spacer()
                    }
                    .padding(.horizontal, Space.margin)
                    .frame(minHeight: Space.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Facet suggestions

    @ViewBuilder
    private var facetRows: some View {
        ForEach(suggestions) { suggestion in
            Button {
                open(suggestion)
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: icon(for: suggestion.kind))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.calibre.primary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.text)
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                        Text(subtitle(for: suggestion.kind))
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.calibre.placeholder)
                }
                .padding(.horizontal, Space.margin)
                .frame(minHeight: Space.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: Listing suggestions

    @ViewBuilder
    private var listingRows: some View {
        if !listingHits.isEmpty {
            Eyebrow("Watches")
                .padding(.horizontal, Space.margin)
                .padding(.top, suggestions.isEmpty ? Space.m : Space.l)
                .padding(.bottom, Space.s)

            ForEach(listingHits) { listing in
                Button {
                    push(.listing(listing.id, zoom: nil))
                } label: {
                    HStack(spacing: Space.m) {
                        ListingImageWell(url: listing.images.first?.url, targetWidth: 96)
                            .frame(width: 48, height: 48)
                            .background(Color.calibre.secondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(listing.title)
                                .font(CalibreType.bodyMedium)
                                .foregroundStyle(Color.calibre.foreground)
                                .lineLimit(1)
                            if let reference = listing.referenceNumber {
                                Text("Ref. \(reference)")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                            }
                        }

                        Spacer()

                        Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                            .font(CalibreType.priceSmall)
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .padding(.horizontal, Space.margin)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        } else if !isSearching, !trimmedQuery.isEmpty, suggestions.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "Nothing matches yet",
                message: "No watches answer to \u{201C}\(trimmedQuery)\u{201D} right now. Try a brand, model, or reference."
            )
        }
    }

    // MARK: Actions

    private func icon(for kind: SearchSuggestion.Kind) -> String {
        switch kind {
        case .brand: "crown"
        case .model: "clock"
        case .reference: "number"
        }
    }

    private func subtitle(for kind: SearchSuggestion.Kind) -> String {
        switch kind {
        case .brand:
            return "Brand"
        case .model(let brand):
            return brand.map { "Model · \($0)" } ?? "Model"
        case .reference(let brand, let model):
            let context = [brand, model].compactMap(\.self).joined(separator: " ")
            return context.isEmpty ? "Reference" : "Reference · \(context)"
        }
    }

    private func open(_ suggestion: SearchSuggestion) {
        recents.record(suggestion.text)
        var filters = BrowseFilters()
        switch suggestion.kind {
        case .brand:
            push(.brand(suggestion.text))
            return
        case .model(let brand):
            filters.brand = brand
            filters.model = suggestion.text
        case .reference(let brand, let model):
            filters.brand = brand
            filters.model = model
            filters.reference = suggestion.text
        }
        push(.results(filters, title: suggestion.text))
    }

    private func submit(_ text: String) {
        guard !text.isEmpty else { return }
        recents.record(text)
        push(.results(BrowseFilters(search: text), title: text))
    }

    private func scheduleListingSearch() {
        searchTask?.cancel()
        let text = trimmedQuery
        guard !text.isEmpty else {
            listingHits = []
            isSearching = false
            return
        }
        isSearching = true
        let catalog = services.catalog
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let query = ListingQuery(search: text, pageSize: 6, view: .card, includeTotal: false)
            let page = try? await catalog.browse(query)
            guard !Task.isCancelled else { return }
            listingHits = page?.results ?? []
            isSearching = false
        }
    }
}
