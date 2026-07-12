import CalibreDesign
import CalibreKit
import SwiftUI

/// The You tab — account header plus the sections list. Most rows are quiet
/// placeholders until their builds land; sign-in (guest) and sign-out
/// (member) work for real. DEBUG builds get a Developer section.
struct YouScreen: View {
    @Environment(AuthSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @AppStorage("guestChosen") private var guestChosen = false

    @State private var showLogin = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header

                section(title: "Account", rows: [
                    ("person.text.rectangle", "Profile"),
                    ("heart", "Saved"),
                    ("sparkle.magnifyingglass", "Requests"),
                    ("mappin.and.ellipse", "Addresses"),
                    ("creditcard", "Payment method"),
                ])

                section(title: "Preferences", rows: [
                    ("bell.badge", "Notifications"),
                ])

                section(title: "Help", rows: [
                    ("bubble.left.and.bubble.right", "Support"),
                    ("info.circle", "About Calibre"),
                ])

                if session.isAuthenticated {
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
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showLogin) {
            NavigationStack {
                LoginScreen(context: .modal)
            }
        }
        .confirmationDialog(
            "Sign out of Calibre?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can keep browsing as a guest, and sign back in any time.")
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
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                    Text(user.email)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            .padding(.vertical, Space.s)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("You're browsing as a guest")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Sign in to save watches, make offers, and sell from your collection.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                Button {
                    Haptics.shared.play(.press)
                    showLogin = true
                } label: {
                    Text("Sign in or create account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
            }
            .padding(.vertical, Space.s)
        }
    }

    // MARK: - Sections

    private func section(title: String, rows: [(icon: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(title)
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    placeholderRow(icon: rows[index].icon, label: rows[index].label)
                    if index < rows.count - 1 {
                        Divider().overlay(Color.calibre.border)
                    }
                }
            }
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
    }

    /// A quiet disabled row — its feature arrives with a later build.
    private func placeholderRow(icon: String, label: String) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground.opacity(0.6))
                .frame(width: 24)
            Text(label)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.mutedForeground)
            Spacer()
            Text("Soon")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.placeholder)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: Space.touchTarget + 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Available in a later release")
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
                    .font(CalibreType.bodyMedium)
                Spacer()
            }
            .foregroundStyle(Color.calibre.destructive)
            .padding(.horizontal, Space.l)
            .frame(minHeight: Space.touchTarget + 8)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func signOut() async {
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

                Divider().overlay(Color.calibre.border)

                NavigationLink {
                    DebugConsoleView(catalog: services.catalog)
                } label: {
                    developerRow(icon: "antenna.radiowaves.left.and.right", label: "API console")
                }
                .buttonStyle(PressableStyle())
            }
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
    }

    private func developerRow(icon: String, label: String) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.calibre.secondaryForeground)
                .frame(width: 24)
            Text(label)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: Space.touchTarget + 8)
        .contentShape(Rectangle())
    }
    #endif
}
