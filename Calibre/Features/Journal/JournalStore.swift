import SwiftUI
import UIKit

/// One bundled Journal article, as Calibre/Resources/Journal/articles.json
/// encodes it (camelCase keys, no wire conversion needed).
struct JournalArticle: Codable, Identifiable, Hashable {
    struct Section: Codable, Hashable {
        let heading: String
        let paragraphs: [String]
    }

    struct Source: Codable, Hashable {
        let label: String
        let href: String
    }

    let id: String
    let category: String
    let title: String
    let excerpt: String
    let author: String
    let date: String
    let readTime: String
    let image: String
    let takeaways: [String]
    let sections: [Section]
    let sources: [Source]
}

/// Loads the bundled Journal once and hands out articles and their images.
/// Bundle-only on purpose — the Journal ships with the app.
@MainActor
@Observable
final class JournalStore {
    static let shared = JournalStore()

    private(set) var articles: [JournalArticle] = []

    var latest: JournalArticle? { articles.first }

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "articles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([JournalArticle].self, from: data) else {
            return
        }
        articles = decoded
    }

    func article(id: String) -> JournalArticle? {
        articles.first { $0.id == id }
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
