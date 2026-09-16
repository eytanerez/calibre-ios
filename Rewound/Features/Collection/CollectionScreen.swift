import RewoundDesign
import RewoundKit
import SwiftUI

/// One watch, opened from the Vault list, carrying the photograph's frame.
///
/// It exists because the push has to be a *value* on the tab's own path.
///
/// The row used to be `NavigationLink { VaultWatchDetailScreen(…) }`, a
/// destination view, which SwiftUI holds as navigation state rather than as an
/// element of the path. That is fine until something re-parents the app: a
/// watch Rewound authenticated plays the Vault film the moment it opens, the
/// moment host swaps the whole app into its staging layer, every
/// `NavigationStack` under it is built afresh — and a push the path never knew
/// about is not restored. The screen appeared and was thrown back to the list
/// inside the same second, which reads exactly as the tap having done nothing,
/// and it took the "View Passport" button on that screen with it.
///
/// A path element survives that, because the path lives on the router, above
/// any tree a film could rebuild.
///
/// `MomentPlayer` no longer re-parents the app, which is the root cause and is
/// fixed there. This is the second lock on the same door: what a reader is
/// standing on belongs on the stack's path, not in state that only the current
/// view tree remembers.
struct VaultWatchLink: Hashable {
    let id: String
}

/// The Vault tab: every watch the member owns, led by their own photograph of
/// it. Rewound purchases arrive automatically on delivery — authenticated,
/// with their Passport — and manual adds cover the rest of the drawer.
///
/// A collection is not a shopfront. What a row carries is the picture, what
/// the owner calls it, what it is, what they paid for it, and the way into its
/// records; selling is available and quiet.
struct CollectionScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(\.routePush) private var routePush
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
                    message: "Sign in and every watch you buy on Rewound arrives in your vault authenticated — plus anything else you own.",
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
                    message: "Buy on Rewound and your watch lands in your vault authenticated — or add what you already own to keep the whole drawer in one place.",
                    actionTitle: "Add a watch"
                ) {
                    openAddSheet()
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rewoundPageBackground()
        // Declared here rather than on the tab shell because the zoom needs
        // this screen's namespace: the frame the watch grows out of is the
        // thumbnail in the row that was tapped.
        .navigationDestination(for: VaultWatchLink.self) { link in
            VaultWatchDetailScreen(vaultID: link.id)
                .routeStackNode()
                .navigationTransition(.zoom(sourceID: link.id, in: photoFrames))
        }
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
                    .tint(Color.rewound.primary)
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
                        .tint(Color.rewound.primary)
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
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated else {
                isLoading = false
                return
            }
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

    /// The shape of what is coming, which is now a list of rows rather than a
    /// column of square photographs. A skeleton that draws the old layout is
    /// worse than none: it promises a screen the drawer will not become.
    private var skeleton: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack(alignment: .top, spacing: Space.m) {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Color.rewound.card)
                            .frame(width: 72, height: 72)
                            .shimmer()
                        VStack(alignment: .leading, spacing: Space.s) {
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(Color.rewound.card)
                                .frame(width: 180, height: 18)
                                .shimmer()
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(Color.rewound.card)
                                .frame(width: 120, height: 14)
                                .shimmer()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Space.m)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
        }
    }

    /// The title row: the one line that says what this screen is.
    private var vaultHeader: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Text("Every watch you own, kept in its place.")
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// The drawer, as a list. The website keeps a card grid because a wide
    /// screen can hold one; a phone showed one full-width photograph per watch
    /// and turned a collection of a dozen into a morning's scrolling. A row
    /// carries the same facts in the height of its thumbnail.
    private var list: some View {
        ScrollView {
            // Lazy because a long drawer would otherwise decode every
            // thumbnail before the first row drew.
            LazyVStack(alignment: .leading, spacing: 0) {
                vaultHeader
                    .padding(.bottom, Space.l)

                ForEach(Array(visibleWatches.enumerated()), id: \.element.id) { index, watch in
                    CollectionWatchRow(
                        watch: watch,
                        photoFrames: photoFrames,
                        // The hairline separates rows, so the last one has
                        // nothing under it to separate from.
                        showsHairline: index < visibleWatches.count - 1,
                        onRemove: { confirmRemove = watch },
                        onList: {
                            Haptics.shared.play(.press)
                            services.router.startListing(prefill: ListingPrefill(vaultWatch: watch))
                        },
                        onPassport: { code in
                            // A push, not an `open`: the passport's canonical
                            // tab is Home so a public link never lands behind
                            // the vault lock, and `open` would therefore throw
                            // a member reading their OWN vault out to a
                            // different tab. This lands on the stack they are
                            // standing on.
                            routePush(.passport(code))
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

/// One watch in the collection, as a row: the owner's photograph small enough
/// that the drawer reads as a drawer, what they call it, what it is, what they
/// paid, and the way into its records.
///
/// The website keeps its card grid — a wide screen can hold one. The phone
/// cannot, and a column of full-width photographs made a dozen watches into a
/// scroll nobody finished. That split is deliberate.
private struct CollectionWatchRow: View {
    let watch: VaultWatch
    let photoFrames: Namespace.ID
    let showsHairline: Bool
    let onRemove: () -> Void
    let onList: () -> Void
    let onPassport: (String) -> Void

    /// The thumbnail's side. Square, because the vault's photographs are
    /// framed square everywhere else and a row is not the place to re-crop
    /// somebody's own picture of their watch.
    private let thumbnailSide: CGFloat = 72

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
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Space.m) {
                // Only the reading half is the link. The ⋯ sits outside it,
                // because a button nested inside a NavigationLink's label
                // never gets the tap.
                //
                // A value, and a type of its own rather than a `Route`: the
                // destination it names lifts the photograph's frame into the
                // screen it opens, and only the Vault list can hand it that
                // frame. Reaching the same screen any other way — a passport
                // link, a notification — has none to lift from and gets an
                // ordinary push through `Route`, which is right.
                //
                // It has to be a value and not a destination view. See
                // `VaultWatchLink` for what a view-destination push cost here.
                NavigationLink(value: VaultWatchLink(id: watch.id)) {
                    HStack(alignment: .top, spacing: Space.m) {
                        VaultPhotoFrame(watch: watch, variant: .card, side: thumbnailSide)
                            .matchedTransitionSource(id: watch.id, in: photoFrames)

                        VStack(alignment: .leading, spacing: Space.xs) {
                            // One chip, whichever it is, and the server's flag
                            // is the only thing that decides which. A watch
                            // somebody typed in is a watch nobody at Rewound
                            // has held, however good its photograph looks.
                            if watch.authenticated {
                                AuthenticatedBadge()
                            } else {
                                StatusBadge("Unverified", tone: .neutral)
                            }

                            // A name the owner gave the watch is theirs, and it
                            // is set in their hand. A brand and model is the
                            // catalog talking and keeps the serif.
                            Text(watch.displayTitle)
                                .font(
                                    watch.isNicknamed
                                        ? RewoundType.hand
                                        : RewoundType.serif(.semiBold, 17, relativeTo: .headline)
                                )
                                .foregroundStyle(Color.rewound.foreground)
                                .multilineTextAlignment(.leading)

                            Text(subtitle)
                                .font(RewoundType.caption)
                                .foregroundStyle(Color.rewound.mutedForeground)
                                .multilineTextAlignment(.leading)

                            // What they paid, where they have told us. Nothing
                            // is invented for a watch with no figure on it —
                            // and this is never Rewound's estimate, which is
                            // settled as a number no owner is shown.
                            if let acquired = acquiredText {
                                Text(acquired)
                                    .font(RewoundType.priceSmall)
                                    .foregroundStyle(Color.rewound.foreground)
                                    .accessibilityLabel("Acquired for \(acquired)")
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Open \(watch.displayTitle)")

                Menu {
                    rowActions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .frame(width: Space.touchTarget, height: Space.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(watch.displayTitle)")
            }
            .padding(.vertical, Space.m)

            if showsHairline {
                Rectangle()
                    .fill(Color.rewound.border)
                    .frame(height: 1)
            }
        }
        .contextMenu { rowActions }
    }

    private var acquiredText: String? {
        guard let raw = watch.acquiredPrice, let value = Decimal(string: raw) else { return nil }
        return PriceFormatter.format(value)
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

/// "Authenticated by Rewound" — driven by the server's own flag, never by
/// re-reading `source`.
struct AuthenticatedBadge: View {
    var body: some View {
        Text("AUTHENTICATED BY REWOUND")
            .font(RewoundType.label)
            .foregroundStyle(Color.rewound.primary)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.rewound.primary.opacity(0.1), in: Capsule())
            .accessibilityLabel("Authenticated by Rewound")
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
                    RewoundTextField("Brand", text: $brand, placeholder: "Rolex", kind: .sentence)
                    RewoundTextField("Model", text: $model, placeholder: "Submariner", kind: .sentence)
                    RewoundTextField(
                        "Reference",
                        text: $reference,
                        placeholder: "126610LN",
                        kind: .reference
                    )
                    RewoundTextField("Year", text: $yearText, placeholder: "2022", kind: .integer)
                    RewoundTextField(
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
                        RewoundTextField(
                            "What do you call it?",
                            text: $nickname,
                            placeholder: "The daily",
                            kind: .sentence
                        )
                        Text("Optional. Yours only — buyers never see it.")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        save()
                    } label: {
                        Text(saveTitle)
                            .font(RewoundType.bodyMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.m)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.rewound.primary)
                    .disabled(brand.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
                .padding(Space.l)
            }
            .rewoundPageBackground()
            .navigationTitle("Add a watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.rewound.primary)
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
