import RewoundDesign
import RewoundKit
import SwiftUI

/// The You tab — account header plus the sections list. Most rows are quiet
/// placeholders until their builds land; sign-in (guest) and sign-out
/// (member) work for real. DEBUG builds get a Developer section.
struct YouScreen: View {
    #if DEBUG
    @State private var tutorialsReplayed = false
    #endif
    @Environment(AuthSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(BetaStore.self) private var beta
    @AppStorage("guestChosen") private var guestChosen = false
    // Same key the app root reads to apply `.preferredColorScheme` — the two
    // `@AppStorage` instances stay in sync automatically.
    @AppStorage("appearancePreference") private var appearancePreference: AppearancePreference = .system

    @State private var showLogin = false
    @State private var confirmSignOut = false
    @State private var showsBetaFeedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                betaFeedbackEntry
                header

                if session.isAuthenticated {
                    // Activity first — offers, orders, and alerts are what a
                    // signed-in member checks most (the old Activity tab).
                    linkedSection(title: "Activity") {
                        NavigationLink { MessagesListScreen() } label: {
                            rowLabel(icon: "bubble.left.and.bubble.right", label: "Messages")
                        }.buttonStyle(PressableStyle())
                        divider
                        NavigationLink { OffersListScreen() } label: {
                            rowLabel(icon: "arrow.left.arrow.right", label: "Offers")
                        }.buttonStyle(PressableStyle())
                        divider
                        NavigationLink { OrdersListScreen().routeStackNode() } label: {
                            rowLabel(icon: "shippingbox", label: "Orders")
                        }.buttonStyle(PressableStyle())
                        divider
                        NavigationLink { AlertsInboxScreen().routeStackNode() } label: {
                            rowLabel(icon: "bell", label: "Alerts", count: services.serverAlerts.remainingCount)
                        }.buttonStyle(PressableStyle())
                    }

                    linkedSection(title: "Account") {
                        row(icon: "person.text.rectangle", label: "Profile", destination: .profile)
                        divider
                        NavigationLink { SavedScreen() } label: {
                            rowLabel(icon: "heart", label: "Saved")
                        }.buttonStyle(PressableStyle())
                        divider
                        NavigationLink { RequestsScreen().routeStackNode() } label: {
                            rowLabel(icon: "sparkle.magnifyingglass", label: "Requests")
                        }.buttonStyle(PressableStyle())
                        divider
                        row(icon: "mappin.and.ellipse", label: "Addresses", destination: .addresses)
                        divider
                        row(icon: "creditcard", label: "Payment method", destination: .paymentMethod)
                    }
                }

                // Always visible — appearance is a device preference, not an
                // account one, so guests can set it too.
                linkedSection(title: "Preferences") {
                    appearanceRow
                    if session.isAuthenticated {
                        divider
                        row(icon: "bell.badge", label: "Notifications", destination: .notifications)
                        divider
                        row(icon: "lock", label: "Change password", destination: .changePassword)
                    }
                }

                linkedSection(title: "Explore") {
                    NavigationLink { BitesArchiveScreen() } label: {
                        rowLabel(icon: "text.book.closed", label: "Bites")
                    }.buttonStyle(PressableStyle())
                    divider
                    NavigationLink { MarketplaceGuideScreen() } label: {
                        rowLabel(icon: "map", label: "How Rewound works")
                    }.buttonStyle(PressableStyle())
                    divider
                    NavigationLink { FeeBreakdownScreen() } label: {
                        rowLabel(icon: "percent", label: "Fees and payments")
                    }.buttonStyle(PressableStyle())
                }

                linkedSection(title: "Help") {
                    NavigationLink { SupportThreadsScreen() } label: {
                        rowLabel(icon: "bubble.left.and.bubble.right", label: "Support")
                    }.buttonStyle(PressableStyle())
                    divider
                    NavigationLink { AboutScreen() } label: {
                        rowLabel(icon: "info.circle", label: "About Rewound")
                    }.buttonStyle(PressableStyle())
                }

                if session.isAuthenticated {
                    linkedSection(title: nil) {
                        row(icon: "trash", label: "Delete account", destination: .deleteAccount, tint: Color.rewound.destructive)
                    }
                    signOutSection
                }

                #if DEBUG
                developerSection
                #endif
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .rewoundPageBackground()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ProfileDestination.self) { destination in
            switch destination {
            case .profile: ProfileScreen()
            case .addresses: AddressesScreen()
            case .paymentMethod: PaymentMethodScreen()
            case .notifications: NotificationSettingsScreen()
            case .changePassword: ChangePasswordScreen()
            case .deleteAccount: DeleteAccountScreen()
            }
        }
        .fullScreenCover(isPresented: $showLogin) {
            NavigationStack {
                LoginScreen(context: .modal)
            }
        }
        .sheet(isPresented: $showsBetaFeedback) {
            BetaFeedbackSheet()
        }
        .alert(
            "Sign out of Rewound?",
            isPresented: $confirmSignOut
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can keep browsing as a guest, and sign back in any time.")
        }
    }

    // MARK: - Beta feedback

    /// The entry point into the beta survey, at the top of the tab so a
    /// tester who came looking for it doesn't have to. Invisible the moment
    /// `beta.isEnabled` goes false, so a build shipped after the beta closes
    /// draws nothing here at all.
    @ViewBuilder
    private var betaFeedbackEntry: some View {
        if beta.isEnabled {
            Button {
                Haptics.shared.play(.press)
                showsBetaFeedback = true
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "flask")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.rewound.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            Color.rewound.accent.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beta feedback")
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
                        Text("Tell us what's broken or confusing. It takes a few minutes.")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.rewound.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        .strokeBorder(Color.rewound.primary.opacity(0.3), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens the beta feedback form")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let user = session.user {
            HStack(spacing: Space.l) {
                AvatarInitial(name: user.username, size: .l)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(user.username)
                        .font(RewoundType.sectionTitle)
                        .foregroundStyle(Color.rewound.foreground)
                    Text(user.email)
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
            }
            .padding(.vertical, Space.s)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("You're browsing as a guest")
                        .font(RewoundType.sectionTitle)
                        .foregroundStyle(Color.rewound.foreground)
                    Text("Sign in to save watches, make offers, and sell from your Vault.")
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }

                Button {
                    Haptics.shared.play(.press)
                    showLogin = true
                } label: {
                    Text("Sign in or create account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.rewound(.primary, fullWidth: true))
            }
            .padding(.vertical, Space.s)
        }
    }

    // MARK: - Sections

    private var divider: some View { Divider().overlay(Color.rewound.border) }

    /// System / Light / Dark — a device preference, so it lives inline
    /// rather than behind its own screen; changes apply immediately via the
    /// `@AppStorage` binding the app root also reads.
    private var appearanceRow: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.rewound.secondaryForeground)
                    .frame(width: 24)
                Text("Appearance")
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Spacer(minLength: 0)
            }
            SegmentedTabs(
                selection: $appearancePreference,
                items: AppearancePreference.allCases.map { ($0, $0.label) }
            )
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
    }

    @ViewBuilder
    private func linkedSection(title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let title { Eyebrow(title) }
            VStack(spacing: 0) { content() }
                .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        .strokeBorder(Color.rewound.border, lineWidth: 1)
                )
        }
    }

    private func row(icon: String, label: String, destination: ProfileDestination, tint: Color? = nil) -> some View {
        NavigationLink(value: destination) {
            rowLabel(icon: icon, label: label, tint: tint)
        }
        .buttonStyle(PressableStyle())
    }

    private func rowLabel(icon: String, label: String, tint: Color? = nil, count: Int? = nil) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint ?? Color.rewound.secondaryForeground)
                .frame(width: 24)
            Text(label)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(tint ?? Color.rewound.foreground)
            if let count {
                Text(count.formatted())
                    .font(RewoundType.label)
                    .monospacedDigit()
                    .foregroundStyle(Color.rewound.primary)
                    .accessibilityLabel("\(count) notifications")
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.rewound.mutedForeground)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: Space.touchTarget + 8)
        .contentShape(Rectangle())
    }

    private var signOutSection: some View {
        Button {
            confirmSignOut = true
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                Text("Sign out")
                    .font(RewoundType.bodyMedium)
                Spacer()
            }
            .foregroundStyle(Color.rewound.foreground)
            .padding(.horizontal, Space.l)
            .frame(minHeight: Space.touchTarget + 8)
            .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func signOut() async {
        // Stop APNs delivery to this device before dropping the session.
        let signingOutUserID = session.user?.id
        await services.push.unregisterOnSignOut()
        guard session.user?.id == signingOutUserID else { return }
        // The one moment a device genuinely changes hands, so the one place
        // the guest support token is dropped. Signing *in* keeps it now — the
        // server merges a guest thread into the account rather than the
        // client throwing its pointer away.
        services.support.forgetGuestToken()
        await session.logout()
        // Keep the shell open — the visitor continues as a guest.
        guestChosen = true
        toasts.show(title: "Signed out", message: "Come back any time.")
    }

    // MARK: - Developer (DEBUG only)

    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Developer")
            VStack(spacing: 0) {
                NavigationLink {
                    GalleryScreen()
                } label: {
                    developerRow(icon: "paintpalette", label: "Design gallery")
                }
                .buttonStyle(PressableStyle())

                Divider().overlay(Color.rewound.border)

                NavigationLink {
                    DebugConsoleView(catalog: services.catalog)
                } label: {
                    developerRow(icon: "antenna.radiowaves.left.and.right", label: "API console")
                }
                .buttonStyle(PressableStyle())

                Divider().overlay(Color.rewound.border)

                // The seller shop's tab strip at the phone widths it has to
                // hold four whole words in. The dashboard it ships on is
                // behind a sign-in and a payouts check, so this is the only
                // way to look at the bar itself in a few seconds.
                NavigationLink {
                    SellerTabStripHarness()
                } label: {
                    developerRow(icon: "rectangle.split.3x1", label: "Seller tab strip")
                }
                .buttonStyle(PressableStyle())

                Divider().overlay(Color.rewound.border)

                // The ledger has always documented a "Replay tips" control;
                // until now there wasn't one, so replaying meant a launch
                // argument (which a sideloaded build cannot pass) or deleting
                // the app. Clears only the tutorial ledger — auth, intro and
                // guest state are untouched.
                Button {
                    TutorialLedger.shared.resetAll()
                    tutorialsReplayed = true
                } label: {
                    developerRow(
                        icon: tutorialsReplayed ? "checkmark" : "arrow.counterclockwise",
                        label: tutorialsReplayed ? "Tips will show again" : "Replay tips",
                        showsChevron: false
                    )
                }
                .buttonStyle(PressableStyle())
                .disabled(tutorialsReplayed)
            }
            .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
        }
    }

    private func developerRow(icon: String, label: String, showsChevron: Bool = true) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.rewound.secondaryForeground)
                .frame(width: 24)
            Text(label)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: Space.touchTarget + 8)
        .contentShape(Rectangle())
    }
    #endif
}
