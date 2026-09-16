import Foundation

/// One Journal article from `GET /content/journal` (list) or
/// `/content/journal/{id}` (full).
///
/// Keys are camelCase on the wire and stay camelCase through
/// `convertFromSnakeCase`, which leaves underscore-free keys alone. The list
/// response omits `sections` and `sources`, so both default to empty rather
/// than failing the feed.
///
/// `image` still names a bundled hero file — the artwork ships with the app;
/// only the words come from the API.
public struct JournalArticle: Codable, Sendable, Identifiable, Hashable {
    public struct Section: Codable, Sendable, Hashable {
        public let heading: String
        public let paragraphs: [String]

        enum CodingKeys: String, CodingKey {
            case heading, paragraphs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            heading = try container.decodeIfPresent(String.self, forKey: .heading) ?? ""
            paragraphs = try container.decodeIfPresent([String].self, forKey: .paragraphs) ?? []
        }
    }

    public struct Source: Codable, Sendable, Hashable {
        public let label: String
        public let href: String
    }

    public let id: String
    public let category: String
    public let title: String
    public let excerpt: String
    public let author: String
    /// Human date as edited, e.g. "June 18, 2026".
    public let date: String
    /// Machine date, when the CMS has one.
    public let datePublishedISO: String?
    public let readTime: String
    /// Bundled hero image filename.
    public let image: String
    public let takeaways: [String]
    public let sections: [Section]
    public let sources: [Source]

    enum CodingKeys: String, CodingKey {
        case id, category, title, excerpt, author, date, datePublishedISO
        case readTime, image, takeaways, sections, sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "Calibre Desk"
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        datePublishedISO = try container.decodeIfPresent(String.self, forKey: .datePublishedISO)
        readTime = try container.decodeIfPresent(String.self, forKey: .readTime) ?? ""
        image = try container.decodeIfPresent(String.self, forKey: .image) ?? ""
        takeaways = try container.decodeIfPresent([String].self, forKey: .takeaways) ?? []
        sections = try container.decodeIfPresent([Section].self, forKey: .sections) ?? []
        sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
    }

    /// True once the full article (not just the feed row) has been fetched.
    public var hasBody: Bool { !sections.isEmpty }
}
