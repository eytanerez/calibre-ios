import Foundation
import XCTest
@testable import CalibreKit

/// `poll(maxAttempts:delay:fetch:isReady:sleep:)` — the generic backoff loop
/// backing the Payment Method page's "wait for the webhook to land" refresh.
/// `sleep` is injected so these tests run instantly instead of waiting on
/// real timers.
final class PollingTests: XCTestCase {
    private actor Recorder {
        private(set) var sleeps: [Duration] = []
        private(set) var fetchCount = 0

        func recordSleep(_ duration: Duration) {
            sleeps.append(duration)
        }

        func recordFetch() -> Int {
            fetchCount += 1
            return fetchCount
        }
    }

    func testStopsAsSoonAsReadyAndDoesNotOverFetch() async throws {
        let recorder = Recorder()
        let outcome = await poll(
            maxAttempts: 5,
            delay: { _ in .milliseconds(1) },
            fetch: { await recorder.recordFetch() },
            isReady: { $0 == 2 },
            sleep: { await recorder.recordSleep($0) }
        )

        guard case .ready(let value) = outcome else {
            return XCTFail("Expected .ready, got \(outcome)")
        }
        XCTAssertEqual(value, 2)
        let fetchCount = await recorder.fetchCount
        XCTAssertEqual(fetchCount, 2, "must stop polling the instant isReady is true")
        let sleepCount = await recorder.sleeps.count
        XCTAssertEqual(sleepCount, 1, "one sleep between the two fetches, none after success")
    }

    func testTimesOutWithLastValueWhenNeverReady() async throws {
        let recorder = Recorder()
        let outcome = await poll(
            maxAttempts: 3,
            delay: { _ in .milliseconds(1) },
            fetch: { await recorder.recordFetch() },
            isReady: { _ in false },
            sleep: { await recorder.recordSleep($0) }
        )

        guard case .timedOut(let value) = outcome else {
            return XCTFail("Expected .timedOut, got \(outcome)")
        }
        XCTAssertEqual(value, 3, "the last fetched value is preserved for the caller to fall back on")
        let fetchCount = await recorder.fetchCount
        XCTAssertEqual(fetchCount, 3)
        let sleepCount = await recorder.sleeps.count
        XCTAssertEqual(sleepCount, 2, "no trailing sleep after the final attempt")
    }

    func testThrowingFetchIsToleratedAndRetried() async throws {
        struct Boom: Error {}
        let recorder = Recorder()
        let outcome = await poll(
            maxAttempts: 4,
            delay: { _ in .milliseconds(1) },
            fetch: { () async throws -> Int in
                let count = await recorder.recordFetch()
                if count == 1 { throw Boom() }
                return count
            },
            isReady: { $0 == 2 },
            sleep: { await recorder.recordSleep($0) }
        )

        guard case .ready(let value) = outcome else {
            return XCTFail("Expected .ready, got \(outcome)")
        }
        XCTAssertEqual(value, 2, "a failed fetch is swallowed and retried, not fatal")
    }

    func testDelayScheduleIsRespectedPerAttempt() async throws {
        let recorder = Recorder()
        _ = await poll(
            maxAttempts: 3,
            delay: { attempt in .seconds(attempt + 1) },
            fetch: { await recorder.recordFetch() },
            isReady: { _ in false },
            sleep: { await recorder.recordSleep($0) }
        )

        let sleeps = await recorder.sleeps
        XCTAssertEqual(sleeps, [.seconds(1), .seconds(2)], "delay(attempt) is threaded through in order")
    }
}
