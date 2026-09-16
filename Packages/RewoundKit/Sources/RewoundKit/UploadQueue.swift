import Foundation
import Observation

// MARK: - Job model

/// One queued photo upload. Persisted to disk so a relaunch resumes pending
/// work.
public struct UploadJob: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// The local draft this photo belongs to (UI bookkeeping).
    public let draftID: String
    /// The server listing the file uploads to.
    public let listingID: String
    /// front / caseback / left_profile / right_profile / clasp / full_set,
    /// or nil for uncategorized (bulk-import) photos.
    public let category: String?
    public let fileURL: URL

    public init(id: UUID = UUID(), draftID: String, listingID: String, category: String?, fileURL: URL) {
        self.id = id
        self.draftID = draftID
        self.listingID = listingID
        self.category = category
        self.fileURL = fileURL
    }
}

public enum UploadState: Sendable, Equatable {
    case queued
    case uploading
    case done
    case failed(retryCount: Int)
}

// MARK: - Progress board

/// Main-actor mirror of queue state for SwiftUI. The queue pushes updates
/// here; views observe `entries`.
@MainActor
@Observable
public final class UploadProgressBoard {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let job: UploadJob
        public var fraction: Double
        public var state: UploadState
    }

    /// Insertion-ordered — the order jobs were enqueued.
    public private(set) var entries: [Entry] = []

    public init() {}

    public func entry(for id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Fraction across every non-done job, for an aggregate progress bar.
    public var overallFraction: Double {
        let active = entries.filter { $0.state != .done }
        guard !active.isEmpty else { return 1 }
        return active.reduce(0) { $0 + $1.fraction } / Double(active.count)
    }

    func upsert(job: UploadJob, fraction: Double, state: UploadState) {
        if let index = entries.firstIndex(where: { $0.id == job.id }) {
            entries[index].fraction = fraction
            entries[index].state = state
        } else {
            entries.append(Entry(id: job.id, job: job, fraction: fraction, state: state))
        }
    }

    func clearFinished() {
        entries.removeAll { $0.state == .done }
    }
}

// MARK: - Queue

/// Serial-ish photo upload pipeline: max 2 concurrent multipart uploads, at
/// most one upload *start* per second (keeps well under the backend's 60/h
/// `listing_upload` throttle bursts), exponential-backoff retry ×3
/// (1 s / 4 s / 10 s), and disk persistence of pending jobs for relaunch
/// resume.
public actor UploadQueue {
    private struct PersistedState: Codable {
        var jobs: [UploadJob]
    }

    private let baseURL: URL
    private let auth: AuthProviding?
    private let session: URLSession
    private let persistenceURL: URL
    /// Main-actor mirror the UI observes.
    public nonisolated let board: UploadProgressBoard

    private var pending: [UploadJob] = []
    /// Everything not yet uploaded successfully (queued + active + failed) —
    /// this is what survives to the next launch.
    private var outstanding: [UploadJob] = []
    private var activeCount = 0
    private let maxConcurrent = 2
    /// Floor between upload starts.
    private let minStartInterval: TimeInterval = 1.0
    private let retryDelays: [TimeInterval] = [1, 4, 10]
    private var lastStartAt: Date?
    private var pumping = false

    public init(
        client: APIClient,
        auth: AuthProviding?,
        board: UploadProgressBoard,
        persistenceDirectory: URL? = nil
    ) {
        self.baseURL = client.baseURL
        self.auth = auth
        self.board = board

        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)

        let base = persistenceDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appending(path: "CalibreKit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.persistenceURL = folder.appending(path: "pending-uploads.json")
    }

    // MARK: Public API

    /// Queue a photo for upload. Returns the job id the progress board keys
    /// on.
    @discardableResult
    public func enqueue(draftID: String, listingID: String, category: String?, fileURL: URL) async -> UUID {
        let job = UploadJob(draftID: draftID, listingID: listingID, category: category, fileURL: fileURL)
        pending.append(job)
        outstanding.append(job)
        persist()
        await publish(job, fraction: 0, state: .queued)
        pump()
        return job.id
    }

    /// Reload jobs persisted by a previous launch and start uploading them.
    public func resumePersisted() async {
        guard let data = try? Data(contentsOf: persistenceURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        let known = Set(outstanding.map(\.id))
        for job in state.jobs where !known.contains(job.id) {
            // Files that vanished between launches can never succeed.
            guard FileManager.default.fileExists(atPath: job.fileURL.path) else { continue }
            pending.append(job)
            outstanding.append(job)
            await publish(job, fraction: 0, state: .queued)
        }
        persist()
        pump()
    }

    public var pendingCount: Int { pending.count + activeCount }

    // MARK: Pump

    private func pump() {
        guard !pumping else { return }
        pumping = true
        Task { await self.drain() }
    }

    private func drain() async {
        while !pending.isEmpty, activeCount < maxConcurrent {
            // Floor of one upload start per second.
            if let last = lastStartAt {
                let elapsed = Date().timeIntervalSince(last)
                if elapsed < minStartInterval {
                    try? await Task.sleep(for: .seconds(minStartInterval - elapsed))
                }
            }
            guard !pending.isEmpty, activeCount < maxConcurrent else { break }
            let job = pending.removeFirst()
            lastStartAt = Date()
            activeCount += 1
            Task {
                await self.run(job)
                self.finish()
            }
        }
        pumping = false
    }

    private func finish() {
        activeCount -= 1
        pump()
    }

    // MARK: Upload with retry

    private func run(_ job: UploadJob) async {
        var attempt = 0
        while true {
            do {
                try await performUpload(job, allowAuthRetry: true)
                removePersisted(job)
                await publish(job, fraction: 1, state: .done)
                return
            } catch {
                if attempt < retryDelays.count {
                    await publish(job, fraction: 0, state: .failed(retryCount: attempt + 1))
                    try? await Task.sleep(for: .seconds(retryDelays[attempt]))
                    attempt += 1
                    await publish(job, fraction: 0, state: .uploading)
                } else {
                    // Out of retries: leave the job persisted so a relaunch
                    // (or explicit resume) can try again.
                    await publish(job, fraction: 0, state: .failed(retryCount: attempt))
                    return
                }
            }
        }
    }

    private func performUpload(_ job: UploadJob, allowAuthRetry: Bool) async throws {
        let fileData = try Data(contentsOf: job.fileURL)

        var form = MultipartForm()
        form.addFile(
            "file",
            filename: job.fileURL.lastPathComponent,
            contentType: Self.contentType(for: job.fileURL),
            data: fileData
        )
        if let category = job.category {
            form.addField("category", value: category)
        }

        var request = URLRequest(url: baseURL.appending(path: "/account/listings/\(job.listingID)/images"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        if let header = await auth?.authHeader() {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        await publish(job, fraction: 0, state: .uploading)
        let relay = UploadProgressRelay { [board, job] fraction in
            Task { @MainActor in
                board.upsert(job: job, fraction: fraction, state: .uploading)
            }
        }

        let (data, response) = try await session.upload(for: request, from: form.encoded(), delegate: relay)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401, allowAuthRetry, let auth {
            if await auth.refreshAfterUnauthorized() {
                try await performUpload(job, allowAuthRetry: false)
                return
            }
            throw APIError.sessionExpired
        }
        if http.statusCode == 429 {
            throw APIError.rateLimited(
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            )
        }

        struct Ack: Decodable {
            let ok: Bool
            let error: String?
        }
        let ack = try? JSONDecoder().decode(Ack.self, from: data)
        guard (200..<300).contains(http.statusCode), ack?.ok == true else {
            throw APIError.server(
                message: ack?.error ?? "Upload failed.",
                code: nil,
                status: http.statusCode,
                details: nil
            )
        }
    }

    /// Explicit content type per part — HEIC parts must never fall back to
    /// application/octet-stream (the backend rejects it).
    static func contentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "heic", "heif": "image/heic"
        case "png": "image/png"
        case "webp": "image/webp"
        default: "image/jpeg"
        }
    }

    // MARK: Persistence

    private func persist() {
        let state = PersistedState(jobs: outstanding)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func removePersisted(_ job: UploadJob) {
        outstanding.removeAll { $0.id == job.id }
        persist()
    }

    private func publish(_ job: UploadJob, fraction: Double, state: UploadState) async {
        await MainActor.run { [board] in
            board.upsert(job: job, fraction: fraction, state: state)
        }
    }
}

/// Task delegate that forwards byte-level progress as a 0…1 fraction.
private final class UploadProgressRelay: NSObject, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
