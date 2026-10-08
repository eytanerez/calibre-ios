import Foundation
import XCTest

@testable import RewatchKit

/// A transport the test answers by hand.
private final class ScriptedTransport: UploadTransport, @unchecked Sendable {
    let lock = NSLock()
    var bodies: [UUID: Data] = [:]
    var cancelled: [UUID] = []
    var inFlight: Set<UUID> = []
    var adopted: [UUID] = []
    var reply: (Int, String) = (201, #"{"ok": true, "data": {"id": "image-7"}}"#)

    func upload(request: URLRequest, bodyFile: URL, jobID: UUID, progress: @escaping @Sendable (Double) -> Void) async throws -> (Data, HTTPURLResponse) {
        let body = try Data(contentsOf: bodyFile)
        let (status, json) = lock.withLock { () -> (Int, String) in
            bodies[jobID] = body
            return reply
        }
        progress(1)
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func adopt(jobID: UUID) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { adopted.append(jobID) }
        let json = #"{"ok": true, "data": {"id": "image-adopted"}}"#
        return (Data(json.utf8), HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
    }

    func cancel(jobID: UUID) { lock.withLock { cancelled.append(jobID) } }
    func inFlightJobIDs() async -> Set<UUID> { lock.withLock { inFlight } }
}

final class UploadQueueTransportTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appending(path: "upload-queue-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func photo() throws -> URL {
        let url = directory.appending(path: "front.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        return url
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out")
    }

    @MainActor
    func testTheBodyCarriesTheCategoryAndSortIndexAndTheImageIDComesBack() async throws {
        let transport = ScriptedTransport()
        let board = UploadProgressBoard()
        let client = APIClient(configuration: APIConfiguration(baseURL: URL(string: "https://api.test")!), auth: nil)
        let queue = UploadQueue(client: client, auth: nil, board: board, persistenceDirectory: directory, transport: transport, minStartInterval: 0)

        let id = await queue.enqueue(draftID: "l1", listingID: "l1", category: "caseback", fileURL: try photo(), sortIndex: 1)
        try await waitUntil { board.entry(for: id)?.state == .done }

        XCTAssertEqual(board.entry(for: id)?.serverImageID, "image-7")
        let body = String(decoding: try XCTUnwrap(transport.lock.withLock { transport.bodies[id] }), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"sort_index\"\r\n\r\n1\r\n"), body)
        XCTAssertTrue(body.contains("name=\"category\"\r\n\r\ncaseback\r\n"), body)
    }

    @MainActor
    func testACancelledJobIsDroppedAndItsTaskCancelled() async throws {
        let transport = ScriptedTransport()
        let board = UploadProgressBoard()
        let client = APIClient(configuration: APIConfiguration(baseURL: URL(string: "https://api.test")!), auth: nil)
        // A long start interval keeps the second job waiting in line.
        let queue = UploadQueue(client: client, auth: nil, board: board, persistenceDirectory: directory, transport: transport, minStartInterval: 30)
        let file = try photo()
        _ = await queue.enqueue(draftID: "l1", listingID: "l1", category: "front", fileURL: file, sortIndex: 0)
        let second = await queue.enqueue(draftID: "l1", listingID: "l1", category: "front", fileURL: file, sortIndex: 0)

        await queue.cancel(second)

        XCTAssertNil(board.entry(for: second))
        XCTAssertTrue(transport.lock.withLock { transport.cancelled.contains(second) })
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(transport.lock.withLock { transport.bodies[second] }, "A withdrawn photo is never sent")
    }

    /// A job iOS was still sending when the app last ended is waited for, not
    /// sent a second time.
    @MainActor
    func testResumeAdoptsAnUploadStillInFlightFromTheLastLaunch() async throws {
        let file = try photo()
        let job = UploadJob(draftID: "l1", listingID: "l1", category: "front", fileURL: file, sortIndex: 0)
        let folder = directory.appending(path: "RewatchKit")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        struct Persisted: Encodable { let jobs: [UploadJob] }
        try JSONEncoder().encode(Persisted(jobs: [job])).write(to: folder.appending(path: "pending-uploads.json"))

        let transport = ScriptedTransport()
        transport.inFlight = [job.id]
        let board = UploadProgressBoard()
        let client = APIClient(configuration: APIConfiguration(baseURL: URL(string: "https://api.test")!), auth: nil)
        let queue = UploadQueue(client: client, auth: nil, board: board, persistenceDirectory: directory, transport: transport, minStartInterval: 0)

        await queue.resumePersisted()
        try await waitUntil { board.entry(for: job.id)?.state == .done }

        XCTAssertEqual(transport.lock.withLock { transport.adopted }, [job.id])
        XCTAssertNil(transport.lock.withLock { transport.bodies[job.id] }, "Adopted, not sent again")
        XCTAssertEqual(board.entry(for: job.id)?.serverImageID, "image-adopted")
    }

    /// A job persisted by the build before `sort_index` existed still decodes.
    func testAJobFromAnEarlierBuildStillDecodes() throws {
        let json = #"{"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "draftID": "d", "listingID": "l", "category": "front", "fileURL": "file:///tmp/a.jpg"}"#
        let job = try JSONDecoder().decode(UploadJob.self, from: Data(json.utf8))
        XCTAssertNil(job.sortIndex)
        XCTAssertEqual(job.category, "front")
    }
}
