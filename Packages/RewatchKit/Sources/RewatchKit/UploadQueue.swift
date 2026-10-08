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
    /// The gallery position the photo is sent with (`sort_index`). Nil leaves
    /// it to the server's default. Optional so a job persisted by an earlier
    /// build still decodes.
    public let sortIndex: Int?

    public init(
        id: UUID = UUID(),
        draftID: String,
        listingID: String,
        category: String?,
        fileURL: URL,
        sortIndex: Int? = nil
    ) {
        self.id = id
        self.draftID = draftID
        self.listingID = listingID
        self.category = category
        self.fileURL = fileURL
        self.sortIndex = sortIndex
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
        /// The listing image the upload became, once the server said so.
        public var serverImageID: String?
        /// Out of retries: nothing more happens until it is queued again.
        public var gaveUp = false
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

    func upsert(job: UploadJob, fraction: Double, state: UploadState, serverImageID: String? = nil, gaveUp: Bool = false) {
        if let index = entries.firstIndex(where: { $0.id == job.id }) {
            entries[index].fraction = fraction
            entries[index].state = state
            entries[index].gaveUp = gaveUp
            if let serverImageID {
                entries[index].serverImageID = serverImageID
            }
        } else {
            entries.append(Entry(id: job.id, job: job, fraction: fraction, state: state, serverImageID: serverImageID, gaveUp: gaveUp))
        }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
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
///
/// Uploads go through an `UploadTransport`. The app hands it the background
/// one (`BackgroundUploadTransport`): each body is written to a file and sent
/// by a background `URLSession`, so a seller who switches apps mid-upload
/// does not lose it. iOS keeps sending while the app is suspended, and wakes
/// it to hear the answer. A job whose task is still in flight from an earlier
/// launch is adopted on resume, not sent twice.
public actor UploadQueue {
    private struct PersistedState: Codable {
        var jobs: [UploadJob]
    }

    private let client: APIClient?
    private let baseURL: URL
    private let auth: AuthProviding?
    private let transport: UploadTransport
    private let persistenceURL: URL
    private let bodiesDirectory: URL
    /// Main-actor mirror the UI observes.
    public nonisolated let board: UploadProgressBoard

    private var pending: [UploadJob] = []
    /// Everything not yet uploaded successfully (queued + active + failed) —
    /// this is what survives to the next launch.
    private var outstanding: [UploadJob] = []
    /// Jobs the caller withdrew. A result that lands for one is dropped.
    private var cancelled: Set<UUID> = []
    private var activeCount = 0
    private let maxConcurrent = 2
    /// Floor between upload starts.
    private let minStartInterval: TimeInterval
    private let retryDelays: [TimeInterval]
    private var lastStartAt: Date?
    private var pumping = false

    public init(
        client: APIClient,
        auth: AuthProviding?,
        board: UploadProgressBoard,
        persistenceDirectory: URL? = nil,
        transport: UploadTransport? = nil,
        retryDelays: [TimeInterval] = [1, 4, 10],
        minStartInterval: TimeInterval = 1.0
    ) {
        self.client = client
        self.baseURL = client.baseURL
        self.auth = auth
        self.board = board
        self.transport = transport ?? ForegroundUploadTransport()
        self.retryDelays = retryDelays
        self.minStartInterval = minStartInterval

        let base = persistenceDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appending(path: "RewatchKit", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.persistenceURL = folder.appending(path: "pending-uploads.json")
        let bodies = folder.appending(path: "upload-bodies", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: bodies, withIntermediateDirectories: true)
        self.bodiesDirectory = bodies
    }

    // MARK: Public API

    /// Queue a photo for upload. Returns the job id the progress board keys
    /// on.
    @discardableResult
    public func enqueue(
        draftID: String,
        listingID: String,
        category: String?,
        fileURL: URL,
        sortIndex: Int? = nil
    ) async -> UUID {
        let job = UploadJob(
            draftID: draftID,
            listingID: listingID,
            category: category,
            fileURL: fileURL,
            sortIndex: sortIndex
        )
        pending.append(job)
        outstanding.append(job)
        persist()
        await publish(job, fraction: 0, state: .queued)
        pump()
        return job.id
    }

    /// Withdraw a job: dropped if it has not started, its task cancelled if it
    /// has, and forgotten either way. Used when the seller replaces a photo
    /// whose earlier version is still on its way, so the older one cannot land
    /// after the newer one and take its slot back.
    public func cancel(_ id: UUID) async {
        cancelled.insert(id)
        pending.removeAll { $0.id == id }
        outstanding.removeAll { $0.id == id }
        persist()
        transport.cancel(jobID: id)
        await MainActor.run { [board] in board.remove(id) }
    }

    /// Reload jobs persisted by a previous launch and start uploading them.
    /// A job iOS is still sending from the previous launch is waited for, not
    /// started again.
    public func resumePersisted() async {
        guard let data = try? Data(contentsOf: persistenceURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        let inFlight = await transport.inFlightJobIDs()
        let known = Set(outstanding.map(\.id))
        for job in state.jobs where !known.contains(job.id) {
            // Files that vanished between launches can never succeed.
            guard FileManager.default.fileExists(atPath: job.fileURL.path) else { continue }
            outstanding.append(job)
            await publish(job, fraction: 0, state: .queued)
            if inFlight.contains(job.id) {
                activeCount += 1
                Task {
                    await self.run(job, adopting: true)
                    self.finish()
                }
            } else {
                pending.append(job)
            }
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
                await self.run(job, adopting: false)
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

    private func run(_ job: UploadJob, adopting: Bool) async {
        var attempt = 0
        var adopt = adopting
        while true {
            guard !cancelled.contains(job.id) else { return }
            do {
                let imageID: String?
                if attempt > 0, let landed = await alreadyLanded(job) {
                    // A lost response is not a lost upload.
                    imageID = landed
                } else {
                    imageID = try await performUpload(job, allowAuthRetry: true, adopting: adopt)
                }
                guard !cancelled.contains(job.id) else { return }
                removePersisted(job)
                await publish(job, fraction: 1, state: .done, serverImageID: imageID)
                return
            } catch {
                adopt = false
                guard !cancelled.contains(job.id) else { return }
                if attempt < retryDelays.count {
                    await publish(job, fraction: 0, state: .failed(retryCount: attempt + 1))
                    try? await Task.sleep(for: .seconds(retryDelays[attempt]))
                    attempt += 1
                    guard !cancelled.contains(job.id) else { return }
                    await publish(job, fraction: 0, state: .uploading)
                } else {
                    // Out of retries: leave the job persisted so a relaunch
                    // (or explicit resume) can try again.
                    await publish(job, fraction: 0, state: .failed(retryCount: attempt), gaveUp: true)
                    return
                }
            }
        }
    }

    /// Before a retry of an UNCATEGORIZED photo, whether the last try reached
    /// the server after all: a photo at this sort index with no category is
    /// that photo, and sending it again would append the same shot twice. The
    /// site asks the same question before each of its retries.
    ///
    /// Not asked for the six angles: the server replaces a category's photo
    /// with each new one, so a retry there is already safe, and an older
    /// photo sitting at the same index would be mistaken for this one.
    private func alreadyLanded(_ job: UploadJob) async -> String? {
        guard job.category == nil, let sortIndex = job.sortIndex, let client else { return nil }
        let images: [ListingImage]? = try? await client.send(
            Endpoint(path: "/account/listings/\(job.listingID)/images")
        )
        return images?.first { $0.category == nil && $0.sortIndex == sortIndex }?.id
    }

    /// Returns the new image's id when the server sent one.
    private func performUpload(_ job: UploadJob, allowAuthRetry: Bool, adopting: Bool) async throws -> String? {
        let (data, http): (Data, HTTPURLResponse)
        if adopting {
            (data, http) = try await transport.adopt(jobID: job.id)
        } else {
            let fileData = try Data(contentsOf: job.fileURL)

            var form = MultipartForm()
            form.addFile(
                "file",
                filename: job.fileURL.lastPathComponent,
                contentType: Self.contentType(for: job.fileURL),
                data: fileData
            )
            if let sortIndex = job.sortIndex {
                form.addField("sort_index", value: String(sortIndex))
            }
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

            // A background session sends from a file, never from memory.
            let bodyURL = bodiesDirectory.appending(path: "\(job.id.uuidString).multipart")
            try form.encoded().write(to: bodyURL, options: .atomic)

            await publish(job, fraction: 0, state: .uploading)
            let board = board
            (data, http) = try await transport.upload(
                request: request,
                bodyFile: bodyURL,
                jobID: job.id
            ) { fraction in
                Task { @MainActor in
                    board.upsert(job: job, fraction: fraction, state: .uploading)
                }
            }
        }

        if http.statusCode == 401, allowAuthRetry, let auth {
            if await auth.refreshAfterUnauthorized() {
                return try await performUpload(job, allowAuthRetry: false, adopting: false)
            }
            throw APIError.sessionExpired
        }
        if http.statusCode == 429 {
            throw APIError.rateLimited(
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            )
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
        return ack?.data?.id
    }

    private struct Ack: Decodable {
        struct Image: Decodable { let id: String? }
        let ok: Bool
        let error: String?
        let data: Image?
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
        try? FileManager.default.removeItem(at: bodiesDirectory.appending(path: "\(job.id.uuidString).multipart"))
    }

    private func publish(
        _ job: UploadJob,
        fraction: Double,
        state: UploadState,
        serverImageID: String? = nil,
        gaveUp: Bool = false
    ) async {
        await MainActor.run { [board] in
            board.upsert(job: job, fraction: fraction, state: state, serverImageID: serverImageID, gaveUp: gaveUp)
        }
    }
}

// MARK: - Transports

/// Sends one multipart body that is already on disk.
public protocol UploadTransport: Sendable {
    func upload(
        request: URLRequest,
        bodyFile: URL,
        jobID: UUID,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse)
    /// Waits for a task started by an earlier launch to finish.
    func adopt(jobID: UUID) async throws -> (Data, HTTPURLResponse)
    func cancel(jobID: UUID)
    /// Jobs whose task is still in flight from an earlier launch.
    func inFlightJobIDs() async -> Set<UUID>
}

/// The in-process transport: an ordinary session, alive only while the app
/// is. Tests use it; so does any caller that does not ask for the background
/// one.
public final class ForegroundUploadTransport: UploadTransport, @unchecked Sendable {
    private let session: URLSession
    private let lock = NSLock()
    private var tasks: [UUID: URLSessionTask] = [:]

    public init(protocolClasses: [AnyClass]? = nil) {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 60
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config)
    }

    public func upload(
        request: URLRequest,
        bodyFile: URL,
        jobID: UUID,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        let relay = UploadProgressRelay(onProgress: progress) { [weak self] task in
            self?.lock.withLock { self?.tasks[jobID] = task }
        }
        defer { lock.withLock { tasks[jobID] = nil } }
        let (data, response) = try await session.upload(for: request, fromFile: bodyFile, delegate: relay)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }

    public func adopt(jobID: UUID) async throws -> (Data, HTTPURLResponse) {
        throw APIError.invalidResponse
    }

    public func cancel(jobID: UUID) {
        lock.withLock { tasks[jobID] }?.cancel()
    }

    public func inFlightJobIDs() async -> Set<UUID> { [] }
}

/// The background transport: uploads iOS carries on with while the app is
/// suspended, and finishes even if iOS ends the app in the meantime.
///
/// One per session identifier for the life of the process (iOS allows only
/// one session per identifier), shared by every queue that asks for it. The
/// app delegate hands iOS's wake-up completion handler to
/// `BackgroundUploadTransport.handleEvents(forSession:completion:)`.
public final class BackgroundUploadTransport: NSObject, UploadTransport, URLSessionDataDelegate, @unchecked Sendable {
    public static let listingPhotosIdentifier = "com.shoprewatch.rewatch.listing-photos"

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: BackgroundUploadTransport] = [:]
    nonisolated(unsafe) private static var wakeHandlers: [String: @Sendable () -> Void] = [:]

    /// The one transport for this identifier.
    public static func shared(identifier: String = listingPhotosIdentifier) -> BackgroundUploadTransport {
        registryLock.withLock {
            if let existing = registry[identifier] { return existing }
            let made = BackgroundUploadTransport(identifier: identifier)
            registry[identifier] = made
            return made
        }
    }

    /// From `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    /// The session is recreated so its delegate hears the events, and the
    /// handler is called once they have all been delivered.
    public static func handleEvents(forSession identifier: String, completion: @escaping @Sendable () -> Void) {
        registryLock.withLock { wakeHandlers[identifier] = completion }
        _ = shared(identifier: identifier).session
    }

    private let identifier: String
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<(Data, HTTPURLResponse), Error>] = [:]
    private var progressHandlers: [UUID: @Sendable (Double) -> Void] = [:]
    private var buffers: [Int: Data] = [:]
    private var bodyFiles: [Int: URL] = [:]
    /// Answers that arrived with nobody waiting (a task from an earlier
    /// launch, finished before `adopt` asked for it).
    private var finished: [UUID: Result<(Data, HTTPURLResponse), Error>] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    private init(identifier: String) {
        self.identifier = identifier
        super.init()
    }

    public func upload(
        request: URLRequest,
        bodyFile: URL,
        jobID: UUID,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        let task = session.uploadTask(with: request, fromFile: bodyFile)
        task.taskDescription = jobID.uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    waiters[jobID] = continuation
                    progressHandlers[jobID] = progress
                    bodyFiles[task.taskIdentifier] = bodyFile
                }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    public func adopt(jobID: UUID) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let done: Result<(Data, HTTPURLResponse), Error>? = lock.withLock {
                if let result = finished.removeValue(forKey: jobID) { return result }
                waiters[jobID] = continuation
                return nil
            }
            if let done { continuation.resume(with: done) }
        }
    }

    public func cancel(jobID: UUID) {
        session.getAllTasks { tasks in
            tasks.first { $0.taskDescription == jobID.uuidString }?.cancel()
        }
    }

    public func inFlightJobIDs() async -> Set<UUID> {
        let tasks = await session.allTasks
        var ids = Set(tasks.filter { $0.state == .running || $0.state == .suspended }
            .compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
        // Finished while the app was away and not yet collected.
        lock.withLock { ids.formUnion(finished.keys) }
        return ids
    }

    // MARK: URLSession delegate

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0, let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let handler = lock.withLock { progressHandlers[id] }
        handler?(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { buffers[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (data, bodyFile) = lock.withLock {
            (buffers.removeValue(forKey: task.taskIdentifier) ?? Data(), bodyFiles.removeValue(forKey: task.taskIdentifier))
        }
        if let bodyFile { try? FileManager.default.removeItem(at: bodyFile) }
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let result: Result<(Data, HTTPURLResponse), Error>
        if let error {
            result = .failure(APIError.network(underlying: error))
        } else if let http = task.response as? HTTPURLResponse {
            result = .success((data, http))
        } else {
            result = .failure(APIError.invalidResponse)
        }
        let waiter: CheckedContinuation<(Data, HTTPURLResponse), Error>? = lock.withLock {
            progressHandlers[id] = nil
            if let waiter = waiters.removeValue(forKey: id) { return waiter }
            finished[id] = result
            return nil
        }
        waiter?.resume(with: result)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = Self.registryLock.withLock { Self.wakeHandlers.removeValue(forKey: identifier) }
        guard let handler else { return }
        DispatchQueue.main.async { handler() }
    }
}

/// Task delegate that forwards byte-level progress as a 0…1 fraction.
private final class UploadProgressRelay: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onCreate: (URLSessionTask) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void, onCreate: @escaping (URLSessionTask) -> Void) {
        self.onProgress = onProgress
        self.onCreate = onCreate
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        onCreate(task)
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
