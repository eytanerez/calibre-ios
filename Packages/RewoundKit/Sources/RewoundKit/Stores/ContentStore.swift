import Foundation
import Observation

/// Editorial content served by the API. The Journal used to ship inside the
/// bundle; it now comes from `/content/journal`, with a disk cache so a
/// reader on a train still has something to read.
///
/// Hero images stay bundled — `article.image` still names a file that ships
/// with the app.
@MainActor
@Observable
public final class ContentStore {
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let feedCache = DiskCache<[JournalArticle]>(filename: "journal-feed.json")
    @ObservationIgnored private let articleCache = DiskCache<[String: JournalArticle]>(filename: "journal-articles.json")

    /// The feed, newest first, as the server orders it.
    public private(set) var journal: [JournalArticle] = []
    /// Full articles, keyed by id — the feed rows omit body and sources.
    public private(set) var articles: [String: JournalArticle] = [:]
    /// True once a load has settled, whether from the network or the cache.
    public private(set) var journalLoaded = false

    @ObservationIgnored private var loadingFeed = false

    public init(client: APIClient) {
        self.client = client
        if let cached = feedCache.load()?.value {
            journal = cached
            journalLoaded = true
        }
        if let cached = articleCache.load()?.value {
            articles = cached
        }
    }

    public var latest: JournalArticle? { journal.first }

    /// Fetches the feed, keeping whatever is already on screen if the
    /// network is unavailable — an empty Journal is a worse answer than
    /// yesterday's Journal.
    @discardableResult
    public func loadJournal() async throws -> [JournalArticle] {
        guard !loadingFeed else { return journal }
        loadingFeed = true
        defer {
            loadingFeed = false
            journalLoaded = true
        }
        do {
            let page: JournalFeedPage = try await client.send(
                Endpoint(path: "/content/journal", requiresAuth: false)
            )
            let rows = page.results
            journal = rows
            feedCache.save(rows)
            return rows
        } catch {
            if !journal.isEmpty { return journal }
            throw error
        }
    }

    /// The full article. Returns the cached copy immediately when we already
    /// have the body, and refreshes from the API otherwise.
    @discardableResult
    public func article(id: String) async throws -> JournalArticle {
        if let cached = articles[id], cached.hasBody {
            return cached
        }
        do {
            let article: JournalArticle = try await client.send(
                Endpoint(path: "/content/journal/\(id)", requiresAuth: false)
            )
            articles[id] = article
            articleCache.save(articles)
            return article
        } catch {
            // A feed row is still worth showing — headline, excerpt, hero.
            if let fallback = articles[id] ?? journal.first(where: { $0.id == id }) {
                return fallback
            }
            throw error
        }
    }

    /// Whatever we can show for this id right now, without waiting.
    public func cachedArticle(id: String) -> JournalArticle? {
        articles[id] ?? journal.first { $0.id == id }
    }
}

/// `GET /content/journal` wraps its rows in `results`. The article endpoint
/// does not — it answers with the article itself — so only the feed needs
/// unwrapping. A payload without the key decodes as an empty feed rather than
/// throwing, which keeps a cached Journal on screen instead of an error.
private struct JournalFeedPage: Decodable {
    let results: [JournalArticle]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([JournalArticle].self, forKey: .results) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case results
    }
}
