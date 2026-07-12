import CalibreDesign
import SwiftUI

/// The Journal index — editorial cards for every bundled story.
struct JournalScreen: View {
    @Environment(\.browsePush) private var push

    private let store = JournalStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("The Journal")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Stories from the world of watches, written by the Calibre desk.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .padding(.top, Space.l)

                if store.articles.isEmpty {
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
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
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
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(article.category). \(article.title). \(article.readTime)")
    }
}
