import Foundation
import Observation

/// Small on-device signals the backend doesn't track: recently-viewed
/// listings (cap 50, most recent first) and the Discover pass-list (cap 500).
/// Persisted as one JSON file in Application Support.
@MainActor
@Observable
public final class LocalSignals {
    private struct Snapshot: Codable {
        var recentlyViewed: [String]
        var discoverPassed: [String]
    }

    public private(set) var recentlyViewed: [String] = []
    public private(set) var discoverPassed: [String] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let recentlyViewedCap = 50
    @ObservationIgnored private let discoverPassCap = 500

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appending(path: "CalibreKit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: "local-signals.json")
        load()
    }

    // MARK: - Recently viewed

    /// Record a listing-detail visit; moves the id to the front.
    public func recordViewed(_ listingID: String) {
        recentlyViewed.removeAll { $0 == listingID }
        recentlyViewed.insert(listingID, at: 0)
        if recentlyViewed.count > recentlyViewedCap {
            recentlyViewed.removeLast(recentlyViewed.count - recentlyViewedCap)
        }
        save()
    }

    // MARK: - Discover pass-list

    /// Record a "not for me" swipe so Discover doesn't resurface the listing.
    public func recordDiscoverPass(_ listingID: String) {
        guard !discoverPassed.contains(listingID) else { return }
        discoverPassed.append(listingID)
        if discoverPassed.count > discoverPassCap {
            discoverPassed.removeFirst(discoverPassed.count - discoverPassCap)
        }
        save()
    }

    public func hasPassed(_ listingID: String) -> Bool {
        discoverPassed.contains(listingID)
    }

    public func resetDiscoverPasses() {
        discoverPassed.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        recentlyViewed = Array(snapshot.recentlyViewed.prefix(recentlyViewedCap))
        discoverPassed = Array(snapshot.discoverPassed.suffix(discoverPassCap))
    }

    private func save() {
        let snapshot = Snapshot(recentlyViewed: recentlyViewed, discoverPassed: discoverPassed)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
