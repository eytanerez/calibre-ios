import Foundation

/// One Bite — a short, sourced, dated claim the desk stands behind, published
/// at most once a day. `GET /content/bites/today`, `GET /content/bites` and
/// `GET /content/bites/{slug}` all serve this same shape.
///
/// A Bite is not a short Journal article and shares nothing with one: its own
/// tables, its own routes, its own reads. `JournalArticle` stays exactly as it
/// is, and a Bite can never appear in the Journal feed. The two are modeled
/// apart here for the same reason the server keeps them apart — a Bite carries
/// an archive slot, the sources it was published against, and a correction
/// that is added *beside* the original date rather than replacing it.
public struct Bite: Decodable, Sendable, Identifiable, Hashable {
    /// What the claim was published against.
    ///
    /// The list can be empty and nothing stops it: `validate_sources`
    /// (`app/services/content.py`) accepts an empty list, and the column's
    /// CHECK asks only that it be an array. So an empty array means the desk
    /// recorded no sources and nothing more — `BiteScreen` omits the section
    /// rather than saying where an unsourced Bite came from, which the payload
    /// does not know.
    public struct Source: Decodable, Sendable, Hashable {
        public let label: String
        public let href: String
    }

    /// The Journal piece this Bite came out of, when there is one. A one-way
    /// reference: the Bite links to the article, never the other way round.
    public struct ArticleLink: Decodable, Sendable, Hashable {
        public let id: String
        public let title: String
    }

    /// The one place to go next, as the desk chose it.
    public struct NextLink: Decodable, Sendable, Hashable {
        public let label: String
        public let href: String
    }

    public let id: String
    public let title: String
    public let topic: String
    public let body: String
    public let author: String
    /// The human date as the desk edits it, e.g. "September 6, 2026".
    public let date: String
    /// The **original** editorial date, in every context — including a
    /// correction and including the archive slot. Nothing writes a new date
    /// onto an old publication.
    public let datePublishedISO: String?
    /// True when the server filled today's slot from the archive because
    /// there was nothing fresh. The reader is told, and told the real date.
    public let isArchive: Bool
    /// True when the desk retired this Bite. It still resolves: a dated URL
    /// that starts 404ing is worse than one that says it has been retired.
    public let archived: Bool
    public let image: MediaURL?
    public let imageAlt: String?
    public let sources: [Source]
    public let article: ArticleLink?
    public let next: NextLink?
    public let correctedOn: String?
    public let correctionNote: String?

    /// The Bite's page on the web marketplace — used for sharing.
    public var webURL: URL {
        URL(string: "https://shoprewound.com/bites/\(id)")
            ?? URL(string: "https://shoprewound.com/bites")!
    }
}

/// `GET /content/bites` — the archive, newest first.
///
/// Paged on the editorial date rather than on an offset, so a Bite published
/// while somebody is reading cannot shift the page under them.
public struct BiteArchivePage: Decodable, Sendable {
    public let results: [Bite]
    /// The `before=` value for the next page, or nil on the last one.
    public let nextBefore: String?
}
