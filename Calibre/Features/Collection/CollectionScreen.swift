import CalibreDesign
import CalibreKit
import SwiftUI

/// The Vault tab: every watch the member owns. Calibre purchases arrive
/// automatically on delivery — authenticated, with their Passport — and
/// manual adds cover the rest of the drawer.
struct CollectionScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(\.openURL) private var openURL

    @Environment(\.scenePhase) private var scenePhase

    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showAddSheet = false
    @State private var lock = VaultLock()
    @State private var confirmRemove: VaultWatch?

    private var watches: [VaultWatch] { services.vault.watches }

    var body: some View {
        Group {
            if session.isAuthenticated, lock.isLocked {
                lockedState
            } else {
                vaultBody
            }
        }
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated else { return }
            await lock.unlockIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-lock the moment the app leaves the screen, so handing over an
            // unlocked phone doesn't hand over the vault.
            if phase != .active { lock.lock() }
        }
    }

    /// Shown while the vault is waiting on Face ID.
    private var lockedState: some View {
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
        .background(Color.calibre.background)
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var vaultBody: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "latch.2.case",
                    title: "Your vault lives here",
                    message: "Sign in and every watch you buy on Calibre arrives in your vault authenticated — plus anything else you own.",
                    actionTitle: "Sign in"
                ) {
                    services.auth.require("Sign in to see your vault") {}
                }
            } else if isLoading, watches.isEmpty {
                skeleton
            } else if watches.isEmpty, loadFailed {
                EmptyState(
                    icon: "wifi.slash",
                    title: "Couldn't load your vault",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    Task { await load() }
                }
            } else if watches.isEmpty {
                EmptyState(
                    icon: "latch.2.case",
                    title: "No watches yet",
                    message: "Buy on Calibre and your watch lands in your vault authenticated — or add what you already own to keep the whole drawer in one place.",
                    actionTitle: "Add a watch"
                ) {
                    showAddSheet = true
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add a watch", systemImage: "plus")
                        }
                        if lock.isAvailable {
                            Toggle(isOn: Binding(
                                get: { lock.isEnabled },
                                set: { lock.isEnabled = $0 }
                            )) {
                                Label("Require \(lock.methodLabel)", systemImage: "lock")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .tint(Color.calibre.primary)
                    .accessibilityLabel("Vault options")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCollectionWatchSheet()
        }
        .confirmationDialog(
            "Remove this watch?",
            isPresented: Binding(
                get: { confirmRemove != nil },
                set: { if !$0 { confirmRemove = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmRemove
        ) { watch in
            Button("Remove", role: .destructive) {
                Task { await remove(watch) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { watch in
            Text("\"\(watch.displayTitle)\" leaves your vault. You can add it again later.")
        }
        .task {
            guard session.isAuthenticated else { return }
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func remove(_ watch: VaultWatch) async {
        do {
            try await services.vault.remove(id: watch.id)
            Haptics.shared.play(.save)
        } catch {
            services.toasts.show(title: "Couldn't remove that watch", message: "Please try again.")
        }
    }

    private func load() async {
        loadFailed = false
        do {
            _ = try await services.vault.load()
        } catch {
            if watches.isEmpty { loadFailed = true }
        }
        isLoading = false
    }

    private var skeleton: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.calibre.card)
                        .frame(height: 120)
                        .shimmer()
                }
            }
            .padding(Space.l)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header

                ForEach(watches) { watch in
                    CollectionWatchCard(watch: watch) {
                        confirmRemove = watch
                    } onPassport: { code in
                        if let url = URL(string: "https://buycalibre.com/passport/\(code)") {
                            openURL(url)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("YOUR VAULT")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                Text("\(watches.count) watch\(watches.count == 1 ? "" : "es")")
                    .font(CalibreType.serif(.semiBold, 30, relativeTo: .largeTitle))
                    .foregroundStyle(Color.calibre.foreground)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
    }
}

private struct CollectionWatchCard: View {
    let watch: VaultWatch
    let onRemove: () -> Void
    let onPassport: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(watch.displayTitle)
                        .font(CalibreType.serif(.semiBold, 18, relativeTo: .headline))
                        .foregroundStyle(Color.calibre.foreground)
                    Text(subtitle)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                Spacer()
                if watch.isAuthenticated {
                    Text("AUTHENTICATED")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs)
                        .background(
                            Color.calibre.primary.opacity(0.1),
                            in: Capsule()
                        )
                }
            }

            HStack(spacing: Space.xl) {
                metric(label: "Acquired for", value: money(watch.acquiredPrice))
            }

            HStack {
                if let code = watch.passportCode {
                    Button {
                        onPassport(code)
                    } label: {
                        Text("View Passport")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Text("Remove")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.calibre.card,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if watch.nickname != nil {
            let joined = [watch.brand, watch.model].compactMap { $0 }.joined(separator: " ")
            if !joined.isEmpty { parts.append(joined) }
        }
        if let reference = watch.reference, !reference.isEmpty {
            parts.append("Ref. \(reference)")
        }
        if let year = watch.productionYear {
            parts.append(String(year))
        }
        return parts.isEmpty ? "No reference on file" : parts.joined(separator: " · ")
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(value)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .monospacedDigit()
        }
    }

    private func money(_ raw: String?) -> String {
        guard let raw, let value = Decimal(string: raw) else { return "—" }
        return PriceFormatter.format(value)
    }
}

/// Manual add: brand is required, everything else optional.
private struct AddCollectionWatchSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var brand = ""
    @State private var model = ""
    @State private var reference = ""
    @State private var yearText = ""
    @State private var priceText = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    CalibreTextField("Brand", text: $brand, placeholder: "Rolex", kind: .sentence)
                    CalibreTextField("Model", text: $model, placeholder: "Submariner", kind: .sentence)
                    CalibreTextField(
                        "Reference",
                        text: $reference,
                        placeholder: "126610LN",
                        kind: .reference
                    )
                    CalibreTextField("Year", text: $yearText, placeholder: "2022", kind: .integer)
                    CalibreTextField(
                        "What you paid (USD)",
                        text: $priceText,
                        placeholder: "9,500",
                        kind: .money
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.destructive)
                    }

                    Button {
                        save()
                    } label: {
                        Text(saving ? "Adding…" : "Add to vault")
                            .font(CalibreType.bodyMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.m)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.calibre.primary)
                    .disabled(brand.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
                .padding(Space.l)
            }
            .background(Color.calibre.background)
            .navigationTitle("Add a watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.calibre.primary)
                }
            }
        }
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                _ = try await services.vault.add(
                    brand: brand.trimmingCharacters(in: .whitespaces),
                    model: model.trimmingCharacters(in: .whitespaces).isEmpty ? nil : model.trimmingCharacters(in: .whitespaces),
                    reference: reference.trimmingCharacters(in: .whitespaces).isEmpty ? nil : reference.trimmingCharacters(in: .whitespaces),
                    productionYear: Int(yearText.trimmingCharacters(in: .whitespaces)),
                    acquiredPrice: priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil
                        : priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                )
                Haptics.shared.play(.success)
                dismiss()
            } catch {
                errorMessage = "Couldn't add the watch. Check the details and try again."
            }
        }
    }
}
