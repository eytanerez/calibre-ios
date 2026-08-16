import CalibreKit
import SwiftUI
import UIKit

/// The Journal as the rest of the app reaches for it.
///
/// The stories used to ship inside the bundle; they now come from
/// `/content/journal` by way of `CalibreKit`'s `ContentStore`, which keeps the
/// disk cache — a reader without a connection still has yesterday's Journal.
/// This stays a singleton because Home and Community read it directly, and it
/// mirrors the feed into an observable array of its own so those views update
/// when the fetch lands, whichever store fed it.
///
/// Hero images stay bundled. `article.image` still names a file that ships
/// with the app; only the words come from the API.
@MainActor
@Observable
final class JournalStore {
    static let shared = JournalStore()

    /// The feed, newest first, in the order the server sent it.
    private(set) var articles: [JournalArticle] = []

    /// True while a fetch of the feed is in flight.
    private(set) var isLoading = false

    /// True once a load has settled, from the network or from the cache.
    private(set) var hasLoaded = false

    /// True only when a fetch failed and there is nothing at all to read. A
    /// Journal that loaded cleanly and happens to be empty is not a failure.
    private(set) var loadFailed = false

    @ObservationIgnored private var content: ContentStore

    private init() {
        // A stand-in until a Journal screen hands over the app's own store.
        // Home and Community read `shared` long before either screen appears,
        // and they should not find an empty Journal. `/content/journal` is a
        // public endpoint, so this client needs no session.
        let standIn = ContentStore(
            client: APIClient(configuration: .fromInfoPlist(), auth: nil)
        )
        content = standIn
        adopt(standIn)
        Task { [weak self] in await self?.refresh() }
    }

    /// Points the store at the app's shared `ContentStore`, so the Journal and
    /// the rest of the app share one client and one cache. `JournalScreen` and
    /// `JournalArticleScreen` call this on first appearance.
    ///
    /// Safe to call at any point: views observe `articles` on this object
    /// rather than the store underneath, so changing the source never strands
    /// a reader mid-screen.
    func configure(content: ContentStore) {
        guard content !== self.content else { return }
        self.content = content
        adopt(content)
    }

    /// The most recent story — the Journal teaser on Home.
    var latest: JournalArticle? { articles.first }

    /// Whatever we can show for this id right now, without waiting. Feed rows
    /// carry no body, so check `hasBody` before rendering a reader.
    func article(id: String) -> JournalArticle? {
        content.cachedArticle(id: id) ?? articles.first { $0.id == id }
    }

    /// Fetches the feed. Whatever is already on screen stays there when the
    /// network is out — yesterday's Journal reads better than none.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            articles = try await content.loadJournal()
            loadFailed = false
        } catch {
            loadFailed = articles.isEmpty
        }
        hasLoaded = true
        isLoading = false
    }

    /// The whole story, sections and sources included — the feed omits both,
    /// so the reader always asks for this. Returns the feed row when the body
    /// cannot be fetched, and nil when there is nothing to show at all.
    @discardableResult
    func loadArticle(id: String) async -> JournalArticle? {
        do {
            return try await content.article(id: id)
        } catch {
            return article(id: id)
        }
    }

    /// Takes on whatever a newly adopted store already holds, so a swap never
    /// blanks the screen and a warm disk cache shows immediately.
    private func adopt(_ store: ContentStore) {
        if !store.journal.isEmpty {
            articles = store.journal
        }
        if store.journalLoaded {
            hasLoaded = true
            loadFailed = false
        }
    }

    /// The bundled hero image for an article ("name.jpg" → bundle resource).
    nonisolated static func image(named filename: String) -> UIImage? {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? "jpg" : ext) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}
