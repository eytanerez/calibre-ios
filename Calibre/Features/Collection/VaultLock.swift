import CalibreDesign
import Foundation
import LocalAuthentication
import Observation
import SwiftUI

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

/// The gate itself, applied to the Vault tab's whole navigation stack rather
/// than to the list screen inside it.
///
/// The lock protects what the member owns, and a watch's own page is as much
/// "what they own" as the list is. A gate around only the root screen leaves
/// every pushed vault destination outside it — silently, the moment one is
/// added — so it sits above the stack instead, where a new route can't escape
/// it. The stack's path is untouched by locking, so unlocking returns the
/// member to the watch they were reading.
private struct VaultGateModifier: ViewModifier {
    let lock: VaultLock
    let signedIn: Bool

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let locked = signedIn && lock.isLocked

        return content
            // An overlay stacks pixels; it does not take what is under it out of
            // the accessibility tree. Without this, VoiceOver reads "Your vault
            // is locked" and then swipes straight into the collection it is
            // supposed to be hiding — every watch and every acquisition price.
            // Face ID has to guard the accessibility API too, not just the glass.
            .a11yCoveredBy(locked)
            .overlay {
                if locked {
                    VaultLockedView(lock: lock)
                        .accessibilityAddTraits(.isModal)
                }
            }
            .task(id: signedIn) {
                guard signedIn else { return }
                await lock.unlockIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                // Re-lock the moment the app leaves the screen, so handing
                // over an unlocked phone doesn't hand over the vault.
                if phase != .active { lock.lock() }
            }
    }
}

extension View {
    func vaultGate(_ lock: VaultLock, signedIn: Bool) -> some View {
        modifier(VaultGateModifier(lock: lock, signedIn: signedIn))
    }
}

/// Shown while the vault is waiting on Face ID. Opaque and edge-to-edge: it
/// covers the tab's navigation bar too, which would otherwise still name the
/// watch that is supposed to be hidden.
struct VaultLockedView: View {
    let lock: VaultLock

    var body: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.calibre.primary)
            Text("Your vault is locked")
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
            Text("Only you should see what's in the drawer.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
            if let error = lock.lastError {
                Text(error)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.destructive)
            }
            Button("Unlock with \(lock.methodLabel)") {
                Task { await lock.authenticate() }
            }
            .buttonStyle(.calibre(.primary))
            .disabled(lock.authenticating)
        }
        .multilineTextAlignment(.center)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calibrePageBackground()
        .ignoresSafeArea()
    }
}
