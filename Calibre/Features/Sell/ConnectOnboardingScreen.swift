import CalibreDesign
import StripeConnect
import SwiftUI
import UIKit

/// Stripe Connect embedded onboarding, bridged into SwiftUI. The SDK's
/// `AccountOnboardingController` presents itself full-screen from a host
/// view controller; this cover shows a quiet holding view underneath.
///
/// Two flows share this host: payout setup, and the dealer application's
/// business/EIN step. Only the component's own title differs, so the title
/// is a parameter rather than a second copy of the controller plumbing.
struct ConnectOnboardingScreen: View {
    let clientSecret: String
    let publishableKey: String
    let title: String
    let onExit: () -> Void
    let onLoadFailure: (String) -> Void

    init(
        clientSecret: String,
        publishableKey: String,
        title: String = "Set up payouts",
        onExit: @escaping () -> Void,
        onLoadFailure: @escaping (String) -> Void
    ) {
        self.clientSecret = clientSecret
        self.publishableKey = publishableKey
        self.title = title
        self.onExit = onExit
        self.onLoadFailure = onLoadFailure
    }

    var body: some View {
        ZStack {
            Color.calibre.background.ignoresSafeArea()
            VStack(spacing: Space.l) {
                ProgressView()
                    .tint(Color.calibre.primary)
                Text("Opening secure verification…")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            ConnectOnboardingHost(
                clientSecret: clientSecret,
                publishableKey: publishableKey,
                title: title,
                onExit: onExit,
                onLoadFailure: onLoadFailure
            )
            .allowsHitTesting(false)
        }
    }
}

private struct ConnectOnboardingHost: UIViewControllerRepresentable {
    let clientSecret: String
    let publishableKey: String
    let title: String
    let onExit: () -> Void
    let onLoadFailure: (String) -> Void

    func makeUIViewController(context: Context) -> HostViewController {
        HostViewController(
            clientSecret: clientSecret,
            publishableKey: publishableKey,
            title: title,
            onExit: onExit,
            onLoadFailure: onLoadFailure
        )
    }

    func updateUIViewController(_ uiViewController: HostViewController, context: Context) {}

    /// Presents the Stripe onboarding component once, the first time the
    /// host lands on screen.
    final class HostViewController: UIViewController, @preconcurrency AccountOnboardingControllerDelegate {
        private let clientSecret: String
        private let publishableKey: String
        private let componentTitle: String
        private let onExit: () -> Void
        private let onLoadFailure: (String) -> Void

        private var manager: EmbeddedComponentManager?
        private var controller: AccountOnboardingController?
        private var presented = false
        /// Set when the component failed to load — the exit that follows is
        /// a failure, not a completion.
        private var failed = false

        init(
            clientSecret: String,
            publishableKey: String,
            title: String,
            onExit: @escaping () -> Void,
            onLoadFailure: @escaping (String) -> Void
        ) {
            self.clientSecret = clientSecret
            self.publishableKey = publishableKey
            self.componentTitle = title
            self.onExit = onExit
            self.onLoadFailure = onLoadFailure
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unsupported") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !presented else { return }
            presented = true

            let apiClient = STPAPIClient(publishableKey: publishableKey)
            let secret = clientSecret
            let manager = EmbeddedComponentManager(
                apiClient: apiClient,
                appearance: Self.calibreAppearance(),
                fetchClientSecret: { secret }
            )
            self.manager = manager

            let controller = manager.createAccountOnboardingController()
            controller.title = componentTitle
            controller.delegate = self
            self.controller = controller
            controller.present(from: self)
        }

        // MARK: AccountOnboardingControllerDelegate

        func accountOnboardingDidExit(_ accountOnboarding: AccountOnboardingController) {
            guard !failed else { return }
            onExit()
        }

        func accountOnboarding(
            _ accountOnboarding: AccountOnboardingController,
            didFailLoadWithError error: Error
        ) {
            failed = true
            onLoadFailure(error.localizedDescription)
        }

        /// Brand tokens, where the SDK allows: chocolate primary, warm
        /// surfaces, the control radius.
        static func calibreAppearance() -> EmbeddedComponentManager.Appearance {
            var appearance = EmbeddedComponentManager.Appearance()
            appearance.colors.primary = UIColor(Color.calibre.primary)
            appearance.colors.actionPrimaryText = UIColor(Color.calibre.primary)
            appearance.colors.background = UIColor(Color.calibre.background)
            appearance.colors.text = UIColor(Color.calibre.foreground)
            appearance.colors.secondaryText = UIColor(Color.calibre.mutedForeground)
            appearance.colors.border = UIColor(Color.calibre.borderBright)
            appearance.colors.formAccent = UIColor(Color.calibre.primary)
            appearance.colors.danger = UIColor(Color.calibre.destructive)
            appearance.cornerRadius.base = Radius.control
            appearance.cornerRadius.button = Radius.control
            appearance.buttonPrimary.colorBackground = UIColor(Color.calibre.primary)
            appearance.buttonPrimary.colorText = UIColor(Color.calibre.primaryForeground)
            return appearance
        }
    }
}
