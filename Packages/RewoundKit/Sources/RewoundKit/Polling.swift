import Foundation

/// The result of `poll(...)`: either a result that satisfied `isReady`, or
/// the last fetched value (if any) once the attempt budget ran out.
public enum PollOutcome<T: Sendable>: Sendable {
    case ready(T)
    case timedOut(T?)
}

/// Repeatedly calls `fetch` until `isReady` accepts a result or `maxAttempts`
/// is exhausted, sleeping `delay(attempt)` between calls (`attempt` is
/// 0-based). Built for values a backend job updates asynchronously after an
/// endpoint already returned 200 — e.g. a Stripe webhook that hasn't landed
/// yet when PaymentSheet reports `.completed`. `sleep` is injected so callers
/// can substitute a no-op in tests.
public func poll<T: Sendable>(
    maxAttempts: Int,
    delay: @Sendable (Int) -> Duration,
    fetch: @Sendable () async throws -> T,
    isReady: @Sendable (T) -> Bool,
    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
) async -> PollOutcome<T> {
    let attempts = max(maxAttempts, 1)
    var lastResult: T?
    for attempt in 0..<attempts {
        if let result = try? await fetch() {
            lastResult = result
            if isReady(result) {
                return .ready(result)
            }
        }
        if attempt < attempts - 1 {
            try? await sleep(delay(attempt))
        }
    }
    return .timedOut(lastResult)
}
