import Foundation
import LocalAuthentication
import Observation

/// Biometric gate for the Vault. What someone owns is the most personal thing
/// in the app, so it sits behind Face ID by default — and re-locks whenever
/// the app leaves the foreground.
@MainActor
@Observable
final class VaultLock {
    static let preferenceKey = "vaultBiometricLock"

    private(set) var unlocked = false
    private(set) var authenticating = false
    private(set) var lastError: String?

    /// On by default. Turning it off unlocks immediately — there's nothing
    /// left to ask for.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.preferenceKey)
            if !newValue {
                unlocked = true
                lastError = nil
            }
        }
    }

    /// A device with neither biometrics nor a passcode can't be asked — the
    /// lock would just strand the owner outside their own vault.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// "Face ID" / "Touch ID" / "your passcode", for buttons and copy.
    var methodLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "your passcode"
        }
    }

    var isLocked: Bool {
        isEnabled && isAvailable && !unlocked
    }

    func unlockIfNeeded() async {
        guard isEnabled, isAvailable else {
            unlocked = true
            return
        }
        guard !unlocked, !authenticating else { return }
        await authenticate()
    }

    func authenticate() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        do {
            // `.deviceOwnerAuthentication` (rather than …WithBiometrics) means
            // the passcode fallback is handled by the system prompt itself.
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your vault"
            )
            unlocked = success
            lastError = success ? nil : "We couldn't verify it was you."
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
            // Cancelling is a choice, not a failure — no scary red text.
            lastError = nil
        } catch {
            lastError = "We couldn't verify it was you."
        }
    }

    /// Called when the app leaves the foreground and on sign-out.
    func lock() {
        guard isEnabled, isAvailable else { return }
        unlocked = false
        lastError = nil
    }
}
