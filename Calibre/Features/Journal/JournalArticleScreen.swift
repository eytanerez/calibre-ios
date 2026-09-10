import CalibreDesign
import CalibreKit
import SwiftUI

/// The consumer Journal is retired — Bites replaced it.
///
/// An old `/journal/:id` link has to keep resolving, so this looks for the
/// Bite that carries this article as its parent and takes the reader there
/// instead. An article no Bite ever cited — or whose Bite has since been
/// retired from the record — falls back to the library.
///
/// The record is paged backwards on the editorial date, so the search walks
/// pages until it matches or runs out. It is bounded: a stray link against a
/// long-running desk must not page for ever.
struct JournalArticleScreen: View {
    let articleID: String

    /// How many pages of the record one lookup will walk before it gives up.
    private static let maxArchivePages = 10

    @Environment(AppServices.self) private var services

    @State private var bite: Bite?
    /// True once the lookup has finished, whichever way it went.
    @State private var settled = false

    var body: some View {
        Group {
            if let bite {
                BiteScreen(slug: bite.id, preloaded: bite)
                    .routeStackNode()
            } else if settled {
                BitesArchiveScreen()
            } else {
                // Nothing is drawn under the bar while this resolves. It lands
                // either on a particular Bite or on the library, and a screen
                // that shows one and swaps to the other a moment later is
                // worse than one that waits.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .calibrePageBackground()
                    .navigationTitle("Bites")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task(id: articleID) { await resolve() }
    }

    /// Walks the record for the Bite drawn from this article.
    ///
    /// A search that failed is not an article without a Bite, but the two land
    /// in the same place: the library, which is the honest answer to "the
    /// piece you asked for is not here any more".
    private func resolve() async {
        bite = nil
        settled = false

        let store = BitesStore(client: services.client)
        var before: String?
        for _ in 0..<Self.maxArchivePages {
            guard let page = try? await store.archive(before: before) else { break }
            if let match = page.results.first(where: { $0.article?.id == articleID }) {
                bite = match
                break
            }
            guard let next = page.nextBefore else { break }
            before = next
        }

        settled = true
    }
}
