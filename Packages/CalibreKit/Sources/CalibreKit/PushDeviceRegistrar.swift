import Foundation

/// Serializes this device's backend association. Account switches, token
/// rotation, and sign-out all share one queue, so a late DELETE cannot remove
/// a newer account's registration.
@MainActor
public final class PushDeviceRegistrar {
    public struct Target: Hashable, Sendable {
        public let userID: String
        public let token: String
        public let environment: String
    }
    private struct Cleanup {
        let userID: String
        let fallback: Target?
        let unregister: @MainActor @Sendable (Target) async throws -> Void
        let completion: CheckedContinuation<Void, Never>
    }
    private let register: @MainActor @Sendable (Target) async throws -> Void
    private var userID: String?
    private var token: String?
    private var environment: String?
    private var registered: Target?
    private var attempted: Set<Target> = []
    private var cleanups: [Cleanup] = []
    private var generation = 0
    private var work: Task<Void, Never>?

    public init(register: @escaping @MainActor @Sendable (Target) async throws -> Void) {
        self.register = register
    }
    public func setUser(_ userID: String?) {
        guard self.userID != userID else { return }
        self.userID = userID
        registered = nil
        generation += 1
        schedule()
    }
    public func setToken(_ token: String, environment: String) {
        self.token = token
        self.environment = environment
        schedule()
    }
    public func refresh() {
        registered = nil
        generation += 1
        schedule()
    }
    /// Cleanup runs after an already-started POST and before any new account's
    /// POST. Keep every attempted token: a callback may rotate the current
    /// token while its predecessor's request is still on the wire.
    public func unregister(
        userID: String,
        fallbackToken: String?,
        environment: String,
        using unregister: @escaping @MainActor @Sendable (Target) async throws -> Void
    ) async {
        if self.userID == userID { setUser(nil) }
        await withCheckedContinuation { completion in
            cleanups.append(Cleanup(
                userID: userID,
                fallback: fallbackToken.map { Target(userID: userID, token: $0, environment: environment) },
                unregister: unregister,
                completion: completion
            ))
            schedule()
        }
    }
    public func waitUntilIdle() async { await work?.value }

    private var target: Target? {
        guard let userID, let token, let environment else { return nil }
        return Target(userID: userID, token: token, environment: environment)
    }
    private func schedule() {
        guard work == nil, !cleanups.isEmpty || (target != nil && target != registered) else { return }
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.work = nil }
            while true {
                if !self.cleanups.isEmpty {
                    let cleanup = self.cleanups.removeFirst()
                    var targets = self.attempted.filter { $0.userID == cleanup.userID }
                    if let fallback = cleanup.fallback { targets.insert(fallback) }
                    for target in targets.sorted(by: { $0.token < $1.token }) {
                        try? await cleanup.unregister(target)
                    }
                    self.attempted.subtract(targets)
                    // A DELETE may have retried during an auth switch. Always
                    // restore the current account after the cleanup completes.
                    self.registered = nil
                    cleanup.completion.resume()
                    continue
                }
                guard let target = self.target, target != self.registered else { return }
                let startedGeneration = self.generation
                self.attempted.insert(target)
                do {
                    try await self.register(target)
                    guard self.generation == startedGeneration, self.target == target else { continue }
                    self.registered = target
                } catch {
                    if !self.cleanups.isEmpty || self.generation != startedGeneration || self.target != target { continue }
                    return // Retry on the next foreground/permission/token event.
                }
            }
        }
    }
}
