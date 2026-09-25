import RewoundKit

/// One slot on the Home page as drawn: a section from `HomeRunningOrder`, or
/// the request band, which is the app's own furniture rather than a feed
/// module and so has no `HomeSection` of its own.
enum HomePageSlot: Hashable {
    case section(HomeSection)
    case requestWatch

    /// The running order with the request band set into it: directly above
    /// the end-of-feed module when the server sent one, and last when it did
    /// not, so the band never depends on the feed's terminator arriving.
    ///
    /// It waits for a page to exist. While the feed is in flight the running
    /// order is the skeleton alone, and a feed that failed with nothing else
    /// on the page is the retry alone; the band is added to neither, because
    /// "can't find it?" under a page that has not loaded is a question about
    /// nothing.
    static func arrange(_ sections: [HomeSection]) -> [HomePageSlot] {
        var slots = sections.map(HomePageSlot.section)
        let hasPage = sections.contains { $0 != .feedLoading && $0 != .feedUnavailable }
        guard hasPage else { return slots }
        let index = slots.firstIndex(of: .section(.endOfFeed)) ?? slots.endIndex
        slots.insert(.requestWatch, at: index)
        return slots
    }
}
