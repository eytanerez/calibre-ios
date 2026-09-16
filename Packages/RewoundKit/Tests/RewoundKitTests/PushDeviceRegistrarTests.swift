import XCTest
@testable import RewoundKit

@MainActor
final class PushDeviceRegistrarTests: XCTestCase {
    func testUnchangedCachedTokenRegistersForNewAccountWithoutAnotherAPNsCallback() async {
        var calls: [PushDeviceRegistrar.Target] = []
        let registrar = PushDeviceRegistrar { calls.append($0) }
        registrar.setToken("device", environment: "production")
        await registrar.waitUntilIdle()
        XCTAssertTrue(calls.isEmpty)
        registrar.setUser("old-account")
        await registrar.waitUntilIdle()
        registrar.setUser("new-account")
        await registrar.waitUntilIdle()
        XCTAssertEqual(calls.map(\.userID), ["old-account", "new-account"])
        XCTAssertEqual(calls.map(\.token), ["device", "device"])
    }

    func testLateOldAccountCompletionIsFollowedByNewAccountRegistration() async {
        var continuation: CheckedContinuation<Void, Never>?
        var calls: [String] = []
        let started = expectation(description: "old registration started")
        let registrar = PushDeviceRegistrar { target in
            calls.append(target.userID)
            if target.userID == "old" {
                started.fulfill()
                await withCheckedContinuation { continuation = $0 }
            }
        }
        registrar.setToken("device", environment: "production")
        registrar.setUser("old")
        await fulfillment(of: [started], timeout: 1)
        registrar.setUser("new")
        continuation?.resume()
        await registrar.waitUntilIdle()
        XCTAssertEqual(calls, ["old", "new"])
    }

    func testSignOutWaitsForInFlightRegistrationAndDoesNotResurrectIt() async {
        var continuation: CheckedContinuation<Void, Never>?
        var calls = 0
        let started = expectation(description: "registration started")
        let registrar = PushDeviceRegistrar { _ in
            calls += 1
            started.fulfill()
            await withCheckedContinuation { continuation = $0 }
        }
        registrar.setToken("device", environment: "production")
        registrar.setUser("old")
        await fulfillment(of: [started], timeout: 1)
        var signOutFinished = false
        var deletedTokens: [String] = []
        let signOut = Task {
            await registrar.unregister(userID: "old", fallbackToken: "device", environment: "production") {
                deletedTokens.append($0.token)
            }
            signOutFinished = true
        }
        await Task.yield()
        XCTAssertFalse(signOutFinished)
        registrar.setToken("rotated-device", environment: "production")
        continuation?.resume()
        await signOut.value
        await registrar.waitUntilIdle()
        XCTAssertTrue(signOutFinished)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(deletedTokens, ["device"], "The token actually posted must be deleted, even after APNs rotates it")
    }


    func testNewAccountPostWaitsUntilOldAccountDeleteFinishes() async {
        var events: [String] = []
        var deleteContinuation: CheckedContinuation<Void, Never>?
        let deleting = expectation(description: "delete in flight")
        let registrar = PushDeviceRegistrar { events.append("POST \($0.userID)") }
        registrar.setToken("device", environment: "production")
        registrar.setUser("old")
        await registrar.waitUntilIdle()
        let signOut = Task {
            await registrar.unregister(userID: "old", fallbackToken: "device", environment: "production") { _ in
                events.append("DELETE start")
                deleting.fulfill()
                await withCheckedContinuation { deleteContinuation = $0 }
                events.append("DELETE end")
            }
        }
        await fulfillment(of: [deleting], timeout: 1)
        registrar.setUser("new")
        await Task.yield()
        XCTAssertEqual(events, ["POST old", "DELETE start"])
        deleteContinuation?.resume()
        await signOut.value
        await registrar.waitUntilIdle()
        XCTAssertEqual(events, ["POST old", "DELETE start", "DELETE end", "POST new"])
    }

    func testFailedRegistrationRetriesOnForeground() async {
        var attempts = 0
        let registrar = PushDeviceRegistrar { _ in
            attempts += 1
            if attempts == 1 { throw CancellationError() }
        }
        registrar.setToken("device", environment: "production")
        registrar.setUser("member")
        await registrar.waitUntilIdle()
        registrar.refresh()
        await registrar.waitUntilIdle()
        XCTAssertEqual(attempts, 2)
    }
}
