import RewatchDesign
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
    ///
    /// Stored, not asked for on each read. `LAContext()` is a synchronous
    /// round trip to the system's authentication daemon, and SwiftUI reads
    /// `isLocked` on every redraw of the Vault tab's gate: Sentry caught the
    /// main thread parked in that call for over two seconds (issue
    /// 7750159367). True until the device answers — a lock that has not
    /// heard back yet stays shut rather than open.
    private(set) var isAvailable = true

    /// "Face ID" / "Touch ID" / "your passcode", for buttons and copy.
    private(set) var methodLabel = "Face ID"

    @ObservationIgnored private var capabilityCheck: Task<Void, Never>?

    /// Asks the device, off the main thread. First when the gate wants to
    /// unlock (not in `init`: `@State` builds and throws away an instance on
    /// every rebuild of the tab view), then each time the app comes back,
    /// since Face ID or a passcode can be set up in Settings in between.
    func refreshCapability() {
        capabilityCheck = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                VaultLock.askDevice()
            }.value
            self?.isAvailable = found.available
            self?.methodLabel = found.label
        }
    }

    nonisolated private static func askDevice() -> (available: Bool, label: String) {
        let context = LAContext()
        let available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        let label = switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "your passcode"
        }
        return (available, label)
    }

    var isLocked: Bool {
        isEnabled && isAvailable && !unlocked
    }

    func unlockIfNeeded() async {
        // Not before the device has answered: a phone with no passcode
        // would otherwise get a prompt that can only fail.
        if capabilityCheck == nil { refreshCapability() }
        await capabilityCheck?.value
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

        do {
            // The context is made off the main thread for the same reason
            // as `askDevice()`: creating one blocks on the daemon.
            let success = try await Task.detached(priority: .userInitiated) {
                let context = LAContext()
                context.localizedFallbackTitle = "Use passcode"
                // `.deviceOwnerAuthentication` (rather than …WithBiometrics)
                // means the passcode fallback is handled by the system
                // prompt itself.
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock your vault"
                )
            }.value
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
                if phase != .active {
                    lock.lock()
                } else {
                    lock.refreshCapability()
                }
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
                .foregroundStyle(Color.rewatch.primary)
            Text("Your vault is locked")
                .font(RewatchType.title)
                .foregroundStyle(Color.rewatch.foreground)
            Text("Only you should see what's in the drawer.")
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.mutedForeground)
            if let error = lock.lastError {
                Text(error)
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.destructive)
            }
            Button("Unlock with \(lock.methodLabel)") {
                Task { await lock.authenticate() }
            }
            .buttonStyle(.rewatch(.primary))
            .disabled(lock.authenticating)
        }
        .multilineTextAlignment(.center)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rewatchPageBackground()
        .ignoresSafeArea()
    }
}
