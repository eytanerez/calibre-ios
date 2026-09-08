import CalibreDesign
import CalibreKit
import SwiftUI

/// One Bite: the claim, its date, its sources, and the way on.
///
/// A Bite is one short, sourced, dated paragraph the desk stands behind — not
/// a short Journal article, and nothing here reads the Journal. The two things
/// this screen will not do are the two the format was designed around: it
/// never presents an archive Bite as today's, and it never puts a corrected
/// Bite under a new date. A correction is shown *beside* the original.
struct BiteScreen: View {
    let slug: String
    /// The copy the caller already had — today's Bite arrives inside the Home
    /// feed, so opening it should not wait on a round trip.
    var preloaded: Bite?

    @Environment(AppServices.self) private var services
    @Environment(\.browsePush) private var browsePush
    @Environment(\.openURL) private var openURL

    @State private var bite: Bite?
    @State private var nextBite: BiteRoute?
    @State private var store: BitesStore?
    @State private var isLoading = false
    /// True once a fetch has settled, so a missing Bite reads as a failure
    /// rather than as a page with nothing on it.
    @State private var hasSettled = false

    var body: some View {
        Group {
            if let bite {
                reader(bite)
            } else if !hasSettled {
                openingSkeleton
            } else {
                EmptyState(
                    icon: "wifi.slash",
                    title: "We couldn't open this bite",
                    message: "It didn't come through just now. Try again in a moment.",
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
        .navigationDestination(item: $nextBite) { route in
            BiteScreen(slug: route.slug, preloaded: route.preloaded)
        }
        .toolbar {
            if let bite {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: bite.webURL, message: Text("\(bite.title) — from Calibre.")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share this bite")
                }
            }
        }
        .task(id: slug) {
            if store == nil {
                store = BitesStore(client: services.client)
            }
            hasSettled = false
            bite = preloaded
            await load()
        }
    }

    private func load() async {
        guard !isLoading, let store else { return }
        isLoading = true
        if let loaded = try? await store.bite(slug: slug) {
            bite = loaded
        }
        hasSettled = true
        isLoading = false
    }

    // MARK: - The reader

    private func reader(_ bite: Bite) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Eyebrow(bite.topic, color: Color.calibre.primary)

                    Text(bite.title)
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)

                    // The archive label and the piece's own date, together.
                    // Nothing here re-dates an old Bite to look like today's.
                    if bite.isArchive {
                        BiteArchiveLabel(date: bite.date)
                    }

                    Text("\(bite.author) · \(bite.date)")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)

                    if bite.archived {
                        Text("This bite has been retired. It stays here because the link was published.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, Space.l)

                if let url = bite.image?.url {
                    ListingImageWell(url: url, targetWidth: 1_200)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                        .accessibilityLabel(bite.imageAlt ?? "")
                        .accessibilityHidden(bite.imageAlt == nil)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(Self.paragraphs(bite.body), id: \.self) { paragraph in
                        Text(paragraph)
                            .font(CalibreType.body)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                            .lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let note = bite.correctionNote {
                    correction(note: note, on: bite.correctedOn)
                }

                if !bite.sources.isEmpty {
                    sources(bite.sources)
                }

                readOn(bite)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl * 2)
        }
    }

    /// A correction sits beside the original date rather than replacing it, so
    /// the record of what changed survives.
    private func correction(note: String, on day: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(day.map { "Corrected \($0)" } ?? "Corrected")
            Text(note)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.accentForeground)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
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

    private func sources(_ items: [Bite.Source]) -> some View {
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
                        .frame(minHeight: Space.touchTarget, alignment: .leading)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.top, Space.s)
    }

    /// Where to go next: the Journal piece this came out of, the desk's own
    /// next step, and the rest of the bank.
    @ViewBuilder
    private func readOn(_ bite: Bite) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let article = bite.article {
                Button {
                    Haptics.shared.play(.press)
                    services.router.push(.journalArticle(article.id))
                } label: {
                    BiteReadOnRow(label: "The long version", detail: article.title)
                }
                .buttonStyle(PressableStyle())
            }

            if let next = bite.next {
                Button {
                    Haptics.shared.play(.press)
                    follow(next)
                } label: {
                    BiteReadOnRow(label: next.label, detail: "Suggested by the desk")
                }
                .buttonStyle(PressableStyle())
            }

            NavigationLink {
                BitesArchiveScreen()
            } label: {
                BiteReadOnRow(label: "Every bite", detail: "The archive, newest first")
            }
            .buttonStyle(PressableStyle())
        }
    }

    /// Follows the desk's own "one place to go next".
    ///
    /// `href` is a **web path**, not a feed route, so it is resolved against
    /// the one route vocabulary this app already speaks rather than a second
    /// one invented here. A path that vocabulary cannot place opens the page
    /// on the web: the desk chose that destination, and dropping it silently
    /// would lose the only pointer they attached.
    private func follow(_ next: Bite.NextLink) {
        let path = next.href.hasPrefix("/") ? String(next.href.dropFirst()) : next.href
        guard let target = feedActionTarget(path) else {
            openWeb(next.href)
            return
        }
        switch target {
        case .browse(let destination):
            browsePush(destination)
        case .route(let route):
            services.router.push(route)
        case .tab(let tab):
            services.router.selectedTab = tab
        case .bite(let slug):
            nextBite = BiteRoute(slug: slug, preloaded: nil)
        }
    }

    private func openWeb(_ href: String) {
        let absolute = href.hasPrefix("http")
            ? href
            : "https://buycalibre.com\(href.hasPrefix("/") ? "" : "/")\(href)"
        if let url = URL(string: absolute) {
            openURL(url)
        }
    }

    /// Blank-line-separated paragraphs, as the desk wrote them. A body with no
    /// break is one paragraph, which is the usual case.
    static func paragraphs(_ body: String) -> [String] {
        body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var openingSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .frame(width: 90, height: 11)
                        .shimmer()
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .frame(height: 28)
                        .shimmer()
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .frame(width: 180, height: 11)
                        .shimmer()
                }
                .padding(.top, Space.l)

                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .frame(maxWidth: index == 3 ? 200 : .infinity)
                        .frame(height: 13)
                        .shimmer()
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl * 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading this bite")
        }
    }
}

/// "From the archive · June 18, 2026" — the label and the piece's own original
/// date, never today's.
struct BiteArchiveLabel: View {
    let date: String

    var body: some View {
        Text("From the archive · \(date)")
            .font(CalibreType.label)
            .foregroundStyle(Color.calibre.accentForeground)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 5)
            .background(Color.calibre.accent.opacity(0.7), in: Capsule())
            .accessibilityLabel("From the archive, \(date)")
    }
}

/// One "read on" row.
struct BiteReadOnRow: View {
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, minHeight: Space.touchTarget + Space.m, alignment: .leading)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}

