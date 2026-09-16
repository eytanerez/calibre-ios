import CalibreKit
import Foundation

/// "Somebody is here" — one beat every 30 seconds while the app is in front.
///
/// Deliberately not part of `Analytics`. Both phone apps switch PostHog's
/// lifecycle and screen-view capture off (see `Analytics.start()`), so a
/// person reading listings on the phone is invisible to it until they tap one
/// of the schema's own events. This answers a different question — how many
/// people are on Calibre right now — for the admin overview alone, and it
/// emits nothing PostHog would recognise.
///
/// Three rules, all of them the endpoint's
/// (`Backend/app/api/views/presence.py`):
///
/// * **The id is opaque and says nothing.** The server keeps only a salted
///   digest of it, so the store cannot be turned back into a list of
///   visitors. No account, no device identifier, nothing else in the body.
/// * **A beat is fire-and-forget.** The endpoint answers 204 in every case
///   that isn't a client error, *including when its Redis is down*, precisely
///   so no client has to handle a failure — and a client that started
///   retrying failed beats would make an outage worse. Failures die here.
/// * **Foreground only.** A beat from the background would claim a presence
///   that isn't there.
@MainActor
final class PresenceHeartbeat {
    /// The backend counts a client for two minutes after its last beat, so
    /// this rhythm lets a flaky connection miss three in a row before the
    /// person blinks out of the figure.
    private static let interval: Duration = .seconds(30)

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// Beats until the calling task is cancelled — which is what leaving the
    /// foreground does, because the app root drives this from `scenePhase`
    /// through `.task(id:)`.
    func beatWhileForeground() async {
        while !Task.isCancelled {
            await beat()
            do {
                try await Task.sleep(for: Self.interval)
            } catch {
                // Cancelled mid-wait: the app is no longer in front.
                return
            }
        }
    }

    private func beat() async {
        guard let endpoint = try? Endpoint<EmptyResponse>.json(
            method: .post,
            path: "/presence/ping",
            payload: ["id": clientID, "surface": "ios"],
            // Unauthenticated on purpose: most people on a watch marketplace
            // at any moment are not signed in, and a figure that counted only
            // members would answer a question nobody asked.
            requiresAuth: false
        ) else { return }
        _ = try? await client.send(endpoint)
    }

    /// An opaque id for this install, minted once and kept.
    ///
    /// `UserDefaults` rather than the Keychain on purpose. The Keychain
    /// survives deleting the app, and an id that outlived the install it
    /// describes would quietly stitch two of them into one visitor. It is not
    /// a credential — it identifies nobody, and losing it costs at most one
    /// duplicate inside a two-minute window.
    private var clientID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.clientIDKey), !existing.isEmpty {
            return existing
        }
        let minted = UUID().uuidString
        defaults.set(minted, forKey: Self.clientIDKey)
        return minted
    }

    private static let clientIDKey = "presence.clientID.v1"
}
