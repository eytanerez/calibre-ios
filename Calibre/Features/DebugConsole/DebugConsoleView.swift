import CalibreKit
import SwiftUI

/// Dev-only smoke screen: proves the CalibreKit pipeline (client → envelope →
/// models → store) against the configured backend by listing page 1.
struct DebugConsoleView: View {
    let catalog: CatalogStore

    @State private var listings: [Listing] = []
    @State private var status = "Loading…"
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(listings) { listing in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(listing.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                                .font(.footnote)
                            Text(listing.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("API Console")
            .toolbar {
                Button("Reload") {
                    Task { await load(refresh: true) }
                }
                .disabled(isLoading)
            }
            .task { await load(refresh: false) }
        }
    }

    private func load(refresh: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        status = "Loading…"
        do {
            if refresh {
                catalog.invalidateBrowseCache()
            }
            let page = try await catalog.browse(ListingQuery(page: 1, pageSize: 25))
            listings = page.results
            let total = page.pagination.total.map(String.init) ?? "?"
            status = "Loaded \(page.results.count) of \(total) listings"
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }
}
