import CalibreDesign
import CalibreKit
import SwiftUI

/// The Journal index — editorial cards for every published story.
struct JournalScreen: View {
    @Environment(\.browsePush) private var push
    @Environment(AppServices.self) private var services

    private let store = JournalStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("The Journal")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text("Stories from the world of watches, written by the Calibre desk.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .padding(.top, Space.l)

                feed
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .calibrePageBackground()
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
        .task {
            // Hand the store the app's own ContentStore, so the Journal shares
            // one client and one cache with everything else.
            store.configure(content: services.content)
            await store.refresh()
        }
        .browseStackNode()
    }

    /// Four states, and the difference between the last two matters: a
    /// Journal with nothing in it is quiet, not broken.
    @ViewBuilder
    private var feed: some View {
        if store.articles.isEmpty, !store.hasLoaded {
            skeleton
        } else if store.articles.isEmpty, store.loadFailed {
            EmptyState(
                icon: "wifi.slash",
                title: "Couldn't reach the Journal",
                message: "Check your connection and try again.",
                actionTitle: "Try again"
            ) {
                Task { await store.refresh() }
            }
        } else if store.articles.isEmpty {
            EmptyState(
                icon: "text.book.closed",
                title: "The presses are quiet",
                message: "New stories from the Calibre desk will appear here."
            )
        } else {
            ForEach(Array(store.articles.enumerated()), id: \.element.id) { index, article in
                JournalCard(article: article) {
                    push(.journalArticle(article.id))
                }
                .fadeUpEntrance(index: index)
            }
        }
    }

    /// Card-shaped placeholders while the first fetch settles.
    private var skeleton: some View {
        VStack(spacing: Space.xl) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .fill(Color.calibre.card)
                    .frame(height: 300)
                    .shimmer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the Journal")
    }
}

/// One editorial card: hero image, category eyebrow, serif title, excerpt,
/// and the read-time line.
struct JournalCard: View {
    let article: JournalArticle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                if let image = JournalStore.image(named: article.image) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow(article.category, color: Color.calibre.primary)
                    Text(article.title)
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.leading)
                    Text(article.excerpt)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text("\(article.readTime) · \(article.date)")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.placeholder)
                        .padding(.top, 2)
                }
                .padding(Space.l)
            }
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(article.category). \(article.title). \(article.readTime)")
    }
}
