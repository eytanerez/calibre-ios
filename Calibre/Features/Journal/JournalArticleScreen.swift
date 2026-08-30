import CalibreDesign
import CalibreKit
import SwiftUI

/// The reader: large serif title, hero image, a quiet takeaways card, serif
/// section headings, sources as links. Generous line-height, no chrome.
///
/// The feed carries only the headline, excerpt and hero, so the body is
/// fetched on arrival. Whatever the feed already gave us goes on screen right
/// away rather than making the reader wait on a blank page.
struct JournalArticleScreen: View {
    let articleID: String

    @Environment(AppServices.self) private var services

    private let store = JournalStore.shared

    @State private var article: JournalArticle?
    @State private var isLoading = false
    /// True once a fetch has finished, so a missing body reads as a failure
    /// rather than as a story with nothing in it.
    @State private var hasSettled = false

    var body: some View {
        Group {
            if let article {
                reader(article)
            } else if !hasSettled {
                openingSkeleton
            } else {
                EmptyState(
                    icon: "wifi.slash",
                    title: "We couldn't open this story",
                    message: "The Journal didn't come through just now. Try again in a moment.",
                    actionTitle: "Try again"
                ) {
                    Task { await load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .calibrePageBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let article {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: URL(string: "https://buycalibre.com/journal/\(article.id)")
                            ?? URL(string: "https://buycalibre.com/journal")!,
                        message: Text("\(article.title) — from the Calibre Journal.")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share this story")
                }
            }
        }
        .task(id: articleID) {
            store.configure(content: services.content)
            hasSettled = false
            // The feed row, if we have one, so the headline and hero are on
            // screen while the body is still in the air.
            article = store.article(id: articleID)
            await load()
        }
        .browseStackNode()
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        if let loaded = await store.loadArticle(id: articleID) {
            article = loaded
        }
        hasSettled = true
        isLoading = false
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
                        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                        .accessibilityLabel("Photograph for \(article.title)")
                }

                // Until the body lands, the excerpt is the story. It stands
                // down once the real sections arrive.
                if !article.hasBody {
                    Text(article.excerpt)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                        .lineSpacing(7)
                }

                if !article.takeaways.isEmpty {
                    takeaways(article.takeaways)
                }

                if article.hasBody {
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
                } else if isLoading || !hasSettled {
                    bodySkeleton
                } else {
                    bodyUnavailable
                }

                if !article.sources.isEmpty {
                    sources(article.sources)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl * 2)
        }
    }

    /// Nothing from the feed either — the page shape while the first fetch
    /// settles, so arriving from a deep link is not a blank screen.
    private var openingSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .frame(width: 90, height: 11)
                        .shimmer()
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .frame(height: 30)
                        .shimmer()
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .frame(width: 200, height: 11)
                        .shimmer()
                }
                .padding(.top, Space.l)

                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .frame(height: 220)
                    .shimmer()

                bodySkeleton
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl * 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading this story")
        }
    }

    /// Paragraph-shaped placeholders for the body still in flight.
    private var bodySkeleton: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .frame(width: 170, height: 16)
                .shimmer()
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .frame(maxWidth: skeletonLineWidth(index))
                    .frame(height: 13)
                    .shimmer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the rest of this story")
    }

    /// The last line of a paragraph runs short, the way a real one does.
    private func skeletonLineWidth(_ index: Int) -> CGFloat {
        index == 4 ? 220 : .infinity
    }

    /// We have the opening but not the body. Say so plainly and offer the
    /// only useful thing — another try.
    private var bodyUnavailable: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("The rest of this story hasn't arrived yet.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.secondaryForeground)
            Button("Try again") {
                Task { await load() }
            }
            .buttonStyle(.calibreSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
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
