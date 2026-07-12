import Foundation

/// Tiny JSON file cache in Caches/ for stale-while-revalidate payloads
/// (market metadata, home feed). The OS may purge Caches at will — every read
/// tolerates a missing or corrupt file.
struct DiskCache<Value: Codable & Sendable>: Sendable {
    struct Entry: Sendable {
        let value: Value
        let savedAt: Date
        func isFresh(ttl: TimeInterval, now: Date = Date()) -> Bool {
            now.timeIntervalSince(savedAt) < ttl
        }
    }

    private struct Envelope: Codable {
        let savedAt: Date
        let value: Value
    }

    let fileURL: URL

    init(filename: String, directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appending(path: "CalibreKit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appending(path: filename)
    }

    func load() -> Entry? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return nil }
        return Entry(value: envelope.value, savedAt: envelope.savedAt)
    }

    func save(_ value: Value) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Envelope(savedAt: Date(), value: value)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
