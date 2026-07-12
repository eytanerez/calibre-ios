import CalibreDesign
import SwiftUI

/// The reader: large serif title, hero image, a quiet takeaways card, serif
/// section headings, sources as links. Generous line-height, no chrome.
struct JournalArticleScreen: View {
    let articleID: String

    private var article: JournalArticle? {
        JournalStore.shared.article(id: articleID)
    }

    var body: some View {
        Group {
            if let article {
                reader(article)
            } else {
                EmptyState(
                    icon: "text.book.closed",
                    title: "That story has moved",
                    message: "We couldn't find this article in the Journal."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.calibre.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
    }

    private func reader(_ article: JournalArticle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Eyebrow(article.category, color: Color.calibre.primary)
                    Text(article.title)
                        .font(CalibreType.display)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("\(article.author) · \(article.date) · \(article.readTime)")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .padding(.top, Space.l)

                if let image = JournalStore.image(named: article.image) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }

                if !article.takeaways.isEmpty {
                    takeaways(article.takeaways)
                }

                ForEach(article.sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text(section.heading)
                            .font(CalibreType.sectionTitle)
                            .foregroundStyle(Color.calibre.foreground)
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(CalibreType.body)
                                .foregroundStyle(Color.calibre.secondaryForeground)
                                .lineSpacing(7)
                        }
                    }
                }

                if !article.sources.isEmpty {
                    sources(article.sources)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl * 2)
        }
    }

    private func takeaways(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("The takeaway")
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    Circle()
                        .fill(Color.calibre.primary)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(item)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.accentForeground)
                        .lineSpacing(5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(
            Color.calibre.accent.opacity(0.4),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    private func sources(_ items: [JournalArticle.Source]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow("Sources")
            ForEach(items, id: \.self) { source in
                if let url = URL(string: source.href) {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            Text(source.label)
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.primary)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.calibre.primary)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.top, Space.s)
    }
}
