import CalibreDesign
import CalibreKit
import SwiftUI

/// The complete brand directory. Home intentionally shows only a concise
/// preview; this page makes the full market visible in a familiar vertical
/// list with search instead of hiding it in a horizontal rail.
struct AllBrandsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.browsePush) private var push

    @State private var searchText = ""
    @State private var isLoading = true
    @State private var loadFailed = false

    private var brands: [BrandGroup] {
        let all = (services.catalog.metadata?.options.byBrand ?? [])
            .sorted { left, right in
                let leftCount = left.liveTotal ?? 0
                let rightCount = right.liveTotal ?? 0
                if leftCount == rightCount {
                    return left.brand.localizedCaseInsensitiveCompare(right.brand) == .orderedAscending
                }
                return leftCount > rightCount
            }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.brand.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if isLoading, brands.isEmpty {
                loadingState
            } else if loadFailed, brands.isEmpty {
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: "The brand directory is out of reach",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again",
                    action: { Task { await load(forceRefresh: true) } }
                )
            } else if brands.isEmpty {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "No brands match that search",
                    message: "Try a shorter name or clear the search field."
                )
            } else {
                brandList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("All brands")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search brands")
        .browseStackNode()
        .task { await load() }
    }

    private var brandList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(brands, id: \.brand) { group in
                    Button {
                        push(.brand(group.brand))
                    } label: {
                        HStack(spacing: Space.m) {
                            Text(group.brand)
                                .font(CalibreType.bodyMedium)
                                .foregroundStyle(Color.calibre.foreground)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: Space.m)

                            if let count = group.liveTotal {
                                Text(count == 1 ? "1 watch" : "\(count.formatted()) watches")
                                    .font(CalibreType.label)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: Space.touchTarget + 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Shows watches from \(group.brand)")

                    if group.brand != brands.last?.brand {
                        Divider()
                            .overlay(Color.calibre.border)
                            .padding(.leading, Space.l)
                    }
                }
            }
            .background(
                Color.calibre.card,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
            .padding(Space.margin)
        }
        .refreshable { await load(forceRefresh: true) }
    }

    private var loadingState: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
                HStack {
                    Rectangle().frame(width: 120, height: 15).shimmer()
                    Spacer()
                    Rectangle().frame(width: 72, height: 12).shimmer()
                }
                .frame(minHeight: Space.touchTarget + 8)
                if index < 7 {
                    Divider().overlay(Color.calibre.border)
                }
            }
        }
        .padding(.horizontal, Space.l)
        .background(
            Color.calibre.card,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .padding(Space.margin)
        .disabled(true)
        .accessibilityLabel("Loading brands")
    }

    private func load(forceRefresh: Bool = false) async {
        if services.catalog.metadata == nil { isLoading = true }
        loadFailed = false
        do {
            _ = try await services.catalog.loadMetadata(forceRefresh: forceRefresh)
        } catch {
            loadFailed = services.catalog.metadata == nil
        }
        isLoading = false
    }
}
