import CalibreDesign
import CalibreKit
import SwiftUI

/// Every published Bite, newest first, as its own screen.
///
/// The list itself is `BitesArchiveList`, because the Community tab's Bites
/// room shows the same record inside its own scroll view. One implementation:
/// a reader who opens Bites from Community and a reader who opens it from a
/// link must not be reading two different lists.
struct BitesArchiveScreen: View {
    var body: some View {
        ScrollView {
            BitesArchiveList()
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.l)
        }
        .calibrePageBackground()
        .navigationTitle("Bites")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The record, newest first, with no scroll view and no page chrome of its own
/// so it can sit inside either host.
///
/// Paged backwards on the editorial date rather than on an offset, so a Bite
/// published while somebody is reading cannot shift the page under them. Each
/// row carries its own original date; nothing here is re-dated to look recent,
/// and there is no topic filter — every published Bite is in the one list.
struct BitesArchiveList: View {
    @Environment(AppServices.self) private var services

    @State private var store: BitesStore?
    @State private var bites: [Bite] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    /// True once the first fetch settles, so an empty bank reads as an empty
    /// bank rather than as a page still loading.
    @State private var hasSettled = false
    @State private var failed = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Space.m) {
            if !hasSettled {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        .frame(height: 96)
                        .shimmer()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading the archive")
            } else if failed, bites.isEmpty {
                EmptyState(
                    icon: "wifi.slash",
                    title: "The archive is out of reach",
                    message: "It didn't come through just now. Try again in a moment.",
                    actionTitle: "Try again"
                ) {
                    Task { await loadFirstPage() }
                }
            } else if bites.isEmpty {
                EmptyState(
                    icon: "text.book.closed",
                    title: "Nothing published yet",
                    message: "The desk publishes one short, sourced note at a time. The first one will land here."
                )
            } else {
                ForEach(bites) { bite in
                    NavigationLink {
                        BiteScreen(slug: bite.id, preloaded: bite)
                            .routeStackNode()
                    } label: {
                        BiteArchiveRow(bite: bite)
                    }
                    .buttonStyle(PressableStyle())
                }

                if nextBefore != nil {
                    Button("Show earlier bites") {
                        Task { await loadNextPage() }
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))
                    .disabled(isLoading)
                    .padding(.top, Space.s)
                }
            }
        }
        .task {
            if store == nil {
                store = BitesStore(client: services.client)
            }
            if bites.isEmpty {
                await loadFirstPage()
            }
        }
    }

    private func loadFirstPage() async {
        guard let store, !isLoading else { return }
        isLoading = true
        failed = false
        do {
            let page = try await store.archive()
            bites = page.results
            nextBefore = page.nextBefore
        } catch {
            failed = true
        }
        hasSettled = true
        isLoading = false
    }

    private func loadNextPage() async {
        guard let store, let before = nextBefore, !isLoading else { return }
        isLoading = true
        if let page = try? await store.archive(before: before) {
            // Keyed by slug so a Bite that appears on both sides of a page
            // boundary is not listed twice.
            let known = Set(bites.map(\.id))
            bites += page.results.filter { !known.contains($0.id) }
            nextBefore = page.nextBefore
        }
        isLoading = false
    }
}

/// One row in the archive: topic, claim, and the date it was actually
/// published. A Bite the desk has retired says so, rather than sitting in the
/// record as though it still stood.
private struct BiteArchiveRow: View {
    let bite: Bite

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Eyebrow(bite.topic, color: Color.calibre.primary)
                Spacer(minLength: 0)
                Text(bite.date)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }

            Text(bite.title)
                .font(CalibreType.serif(.semiBold, 17, relativeTo: .body))
                .foregroundStyle(Color.calibre.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(bite.author) · \(bite.sources.count == 1 ? "1 source" : "\(bite.sources.count) sources")")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)

            if bite.archived {
                Text("Retired from rotation.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this bite")
    }

    private var accessibilityLabel: String {
        let base = "\(bite.title). \(bite.author), \(bite.date)"
        return bite.archived ? base + ". Retired from rotation." : base
    }
}
