import CalibreDesign
import CalibreKit
import SwiftUI

/// The Vault tab: every watch the member owns, led by their own photograph of
/// it. Calibre purchases arrive automatically on delivery — authenticated,
/// with their Passport — and manual adds cover the rest of the drawer.
///
/// A collection is not a shopfront. What a card carries is the picture, what
/// the owner calls it, what it is, and the way into its records; selling is
/// available and quiet, and what somebody paid is theirs and stays on the
/// watch's own screen.
struct CollectionScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    /// The tab's gate, owned above this screen so everything pushed on top of
    /// it is locked too. Read here only for the "Require Face ID" toggle.
    @Environment(VaultLock.self) private var lock

    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showAddSheet = false
    @State private var confirmRemove: VaultWatch?
    /// The watch this device just added, once the server had written it.
    ///
    /// Nothing is put on the shelf on the strength of a tap: the row does not
    /// exist until the save comes back. It is then held out of the list until
    /// the sheet that created it has gone, so the settling happens where the
    /// owner can actually see it rather than behind a modal.
    @State private var settlingID: String?

    /// The photograph carries the push. The card hands its frame to the
    /// watch's own screen, and going back puts it down where it was picked up.
    @Namespace private var photoFrames

    private var watches: [VaultWatch] { services.vault.watches }

    private var visibleWatches: [VaultWatch] {
        guard showAddSheet, let settlingID else { return watches }
        return watches.filter { $0.id != settlingID }
    }

    var body: some View {
        vaultBody
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
                    aside: "Even the one you never take off.",
                    actionTitle: "Add a watch"
                ) {
                    openAddSheet()
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calibrePageBackground()
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openAddSheet()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Color.calibre.primary)
                    .accessibilityLabel("Add a watch")
                }
                if lock.isAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle(isOn: Binding(
                                get: { lock.isEnabled },
                                set: { lock.isEnabled = $0 }
                            )) {
                                Label("Require \(lock.methodLabel)", systemImage: "lock")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .tint(Color.calibre.primary)
                        .accessibilityLabel("Vault options")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCollectionWatchSheet { created in
                settlingID = created.id
            }
        }
        .alert(
            "Remove this watch?",
            isPresented: Binding(
                get: { confirmRemove != nil },
                set: { if !$0 { confirmRemove = nil } }
            ),
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

    /// The previous add's settle is spent. Left standing, it would hold that
    /// watch out of the list for as long as the sheet is up and then settle it
    /// in a second time on the way back — a watch putting itself down again
    /// because somebody opened the form and changed their mind.
    private func openAddSheet() {
        settlingID = nil
        showAddSheet = true
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
            VStack(spacing: Space.xl) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Space.m) {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color.calibre.card)
                            .aspectRatio(1, contentMode: .fit)
                            .shimmer()
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Color.calibre.card)
                            .frame(width: 160, height: 18)
                            .shimmer()
                    }
                }
            }
            .padding(Space.l)
        }
    }

    /// The fact the vault mark announces: the drawer is open, past the
    /// biometric gate, and there is something in it. Nil while either is not
    /// so — an empty vault gets no mark, and neither does one still behind
    /// Face ID — and nothing is drawn for nil. Once per session: `lock()` on
    /// the way to the background clears `unlocked`, and unlocking again is
    /// the same fact, not news.
    private var vaultOpenedKey: String? {
        lock.unlocked && !watches.isEmpty ? "vault-opened" : nil
    }

    /// The title row: the ninth mark, lifting a watch out of its slot beside
    /// the one line that says what this screen is. The words carry the
    /// meaning; the mark has no label of its own.
    private var vaultHeader: some View {
        HStack(alignment: .center, spacing: Space.m) {
            CalibreMark.vault(size: 48, trigger: "vault-opened")
                .markAnnounces(vaultOpenedKey)
            Text("Every watch you own, kept in its place.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var list: some View {
        ScrollView {
            // Lazy, because every row is now a full-width photograph: a plain
            // stack would decode the whole drawer before the first one drew.
            LazyVStack(alignment: .leading, spacing: Space.xxl) {
                vaultHeader

                ForEach(visibleWatches) { watch in
                    CollectionWatchCard(
                        watch: watch,
                        photoFrames: photoFrames,
                        onRemove: { confirmRemove = watch },
                        onList: {
                            Haptics.shared.play(.press)
                            services.router.startListing(prefill: ListingPrefill(vaultWatch: watch))
                        },
                        onPassport: { code in
                            // `push`, not `open`: the passport's canonical tab
                            // is Home so a public link never lands behind the
                            // vault lock, and `open` would therefore throw a
                            // member reading their OWN vault out to a different
                            // tab. Push appends to the stack they are on.
                            services.router.push(.passport(code))
                        }
                    )
                    .modifier(SettleIntoPlace(active: settlingID == watch.id))
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
    }
}

/// A watch being put down on a shelf.
///
/// Ease-out, opacity and offset only — the interface's motion rule, not the
/// marks' grammar. Nothing is being announced here, so this is not a mark and
/// does not borrow their anticipation or their weight.
private struct SettleIntoPlace: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool

    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .opacity(active && !settled ? 0 : 1)
            .offset(y: active && !settled && !reduceMotion ? 12 : 0)
            .onAppear {
                guard active, !settled else { return }
                withAnimation(Motion.easeSlow) { settled = true }
            }
    }
}

/// One watch in the collection: the owner's photograph of it, what they call
/// it, what it is, and the two records that belong to it.
private struct CollectionWatchCard: View {
    let watch: VaultWatch
    let photoFrames: Namespace.ID
    let onRemove: () -> Void
    let onList: () -> Void
    let onPassport: (String) -> Void

    /// One definition, shared by the ⋯ menu and the long-press menu, so both
    /// always offer exactly the same things.
    @ViewBuilder
    private var rowActions: some View {
        if let code = watch.passportCode {
            Button {
                onPassport(code)
            } label: {
                Label("View Passport", systemImage: "doc.text")
            }
        }
        Button {
            onList()
        } label: {
            Label("Sell", systemImage: "tag")
        }
        Button(role: .destructive, action: onRemove) {
            Label("Remove from vault", systemImage: "trash")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // Only the card's reading half is the link. The affordances below
            // sit outside it, because a button nested inside a NavigationLink's
            // label never gets the tap.
            //
            // A destination rather than a `Route` value, so the push can carry
            // the photograph's own frame into the screen it opens. Reaching the
            // same screen any other way — a passport link, a notification — has
            // no frame to lift from and gets an ordinary push, which is right.
            NavigationLink {
                VaultWatchDetailScreen(vaultID: watch.id)
                    .navigationTransition(.zoom(sourceID: watch.id, in: photoFrames))
            } label: {
                VStack(alignment: .leading, spacing: Space.m) {
                    GeometryReader { proxy in
                        VaultPhotoFrame(watch: watch, variant: .card, side: proxy.size.width)
                            .matchedTransitionSource(id: watch.id, in: photoFrames)
                    }
                    .aspectRatio(1, contentMode: .fit)

                    HStack(alignment: .top, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            // One chip, whichever it is, and the server's flag
                            // is the only thing that decides which. A watch
                            // somebody typed in is a watch nobody at Calibre
                            // has held, however good its photograph looks.
                            Group {
                                if watch.authenticated {
                                    AuthenticatedBadge()
                                } else {
                                    StatusBadge("Unverified", tone: .neutral)
                                }
                            }
                            .padding(.bottom, Space.xs)

                            // A name the owner gave the watch is theirs, and it
                            // is set in their hand. A brand and model is the
                            // catalog talking and keeps the serif.
                            Text(watch.displayTitle)
                                .font(
                                    watch.isNicknamed
                                        ? CalibreType.hand
                                        : CalibreType.serif(.semiBold, 20, relativeTo: .title3)
                                )
                                .foregroundStyle(Color.calibre.foreground)
                                .multilineTextAlignment(.leading)
                            Text(subtitle)
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .padding(.top, Space.xs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Open \(watch.displayTitle)")

            HStack(spacing: Space.m) {
                // The record Calibre keeps for this watch, in reach. It used
                // to be the third item of an overflow menu, behind a Sell
                // button, on a screen about watches somebody is keeping.
                if let code = watch.passportCode {
                    NavigationLink(value: Route.passport(code)) {
                        HStack(spacing: Space.s) {
                            Image(systemName: "doc.text")
                            Text("Passport")
                        }
                    }
                    .buttonStyle(.calibre(.secondary))
                }

                // Available, and quiet.
                Button("Sell", action: onList)
                    .buttonStyle(.calibre(.ghost))

                Spacer(minLength: 0)

                Menu {
                    rowActions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .frame(width: Space.touchTarget, height: Space.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(watch.displayTitle)")
            }
        }
        .contextMenu { rowActions }
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
}

/// "Authenticated by Calibre" — driven by the server's own flag, never by
/// re-reading `source`.
struct AuthenticatedBadge: View {
    var body: some View {
        Text("AUTHENTICATED BY CALIBRE")
            .font(CalibreType.label)
            .foregroundStyle(Color.calibre.primary)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.calibre.primary.opacity(0.1), in: Capsule())
            .accessibilityLabel("Authenticated by Calibre")
    }
}

/// Manual add: brand is required, everything else optional.
private struct AddCollectionWatchSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    /// Handed the row the server wrote, so the collection can settle it in.
    let onAdded: (VaultWatch) -> Void

    @State private var brand = ""
    @State private var model = ""
    @State private var reference = ""
    @State private var yearText = ""
    @State private var priceText = ""
    @State private var nickname = ""
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
                    .moneyFormatted($priceText)
                    // Optional, and skipped more often than not — it sits
                    // after the facts rather than in front of them. Where an
                    // owner does fill it in, it becomes the vault's primary
                    // line and the reference moves underneath.
                    VStack(alignment: .leading, spacing: Space.xs) {
                        CalibreTextField(
                            "What do you call it?",
                            text: $nickname,
                            placeholder: "The daily",
                            kind: .sentence
                        )
                        Text("Optional. Yours only — buyers never see it.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        save()
                    } label: {
                        Text(saveTitle)
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
            .calibrePageBackground()
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

    /// A failed save leaves the sheet standing on everything that was typed,
    /// and the button says what pressing it again would do.
    private var saveTitle: String {
        if saving { return "Adding…" }
        return errorMessage == nil ? "Add to vault" : "Try again"
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                let created = try await services.vault.add(
                    brand: brand.trimmingCharacters(in: .whitespaces),
                    model: model.trimmingCharacters(in: .whitespaces).isEmpty ? nil : model.trimmingCharacters(in: .whitespaces),
                    reference: reference.trimmingCharacters(in: .whitespaces).isEmpty ? nil : reference.trimmingCharacters(in: .whitespaces),
                    productionYear: Int(yearText.trimmingCharacters(in: .whitespaces)),
                    acquiredPrice: priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil
                        : priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces),
                    nickname: nickname.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil
                        : nickname.trimmingCharacters(in: .whitespaces)
                )
                Haptics.shared.play(.success)
                onAdded(created)
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription
                    ?? "Couldn't add the watch. Check the details and try again."
            }
        }
    }
}
