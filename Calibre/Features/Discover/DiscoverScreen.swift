import CalibreDesign
import CalibreKit
import SwiftUI

/// The Discover tab root — full-screen card-deck browsing, the app's
/// signature surface. Swipe right to save (gated through `session.require`
/// for guests, with intent replay after sign-in), left to pass (always
/// local). Tap opens the listing. The control row mirrors the gestures for
/// accessibility, with a five-second Undo after every action.
struct DiscoverScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var feed: DeckFeed?
    @State private var swipeCommand: SwipeDirection?
    @State private var undoable: UndoRecord?
    @State private var undoExpiry: Task<Void, Never>?
    /// Zoom-transition anchor for the PDP push (P3 wires the destination).
    @Namespace private var deckNamespace

    var body: some View {
        VStack(spacing: Space.l) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.easeMedium, value: feed?.phase)
        .task { await bootstrapFeed() }
        .onDisappear { feed?.stopPrefetching() }
        .onAppear { feed?.updatePrefetch() }
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            Task { await feed?.handleAuthChange() }
        }
    }

    // MARK: - Header

    /// Minimal: a small serif wordline and, once signed in, a saved-count
    /// ticker whose number rolls via `numericText`.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Discover")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            Spacer()
            if session.isAuthenticated {
                savedTicker
            }
        }
        .padding(.top, Space.s)
    }

    private var savedTicker: some View {
        let count = services.commerce.watchedListingIDs.count
        return HStack(spacing: Space.xs) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .medium))
            Text("\(count) saved")
                .font(CalibreType.label)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(Color.calibre.accentForeground)
        .padding(.horizontal, Space.m)
        .padding(.vertical, 6)
        .background(Color.calibre.accent, in: Capsule())
        .animation(Motion.easeMedium, value: count)
        .accessibilityLabel("\(count) watches saved")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let feed {
            switch feed.phase {
            case .loading:
                DeckSkeleton()
            case .failed(let message):
                centered {
                    EmptyState(
                        icon: "wifi.exclamationmark",
                        title: "The deck couldn't load",
                        message: message,
                        actionTitle: "Try again",
                        action: { Task { await feed.restart() } }
                    )
                }
            case .exhausted:
                centered {
                    EmptyState(
                        icon: "rectangle.stack",
                        title: "That's every watch for now",
                        message: "You've seen every watch currently live. Check Fresh Arrivals on Home.",
                        actionTitle: feed.hasPasses ? "Reset passes" : nil,
                        action: feed.hasPasses ? { Task { await feed.resetPassesAndReload() } } : nil
                    )
                }
            case .ready:
                if feed.cards.isEmpty {
                    // A refill is catching up — keep the deck's silhouette.
                    DeckSkeleton()
                } else {
                    DeckView(
                        cards: feed.cards,
                        command: $swipeCommand,
                        namespace: deckNamespace,
                        onCommit: handleCommit,
                        onAdvance: { feed.removeTop() },
                        onTap: openListing
                    )
                }
            }
        } else {
            DeckSkeleton()
        }
    }

    private func centered(@ViewBuilder _ inner: () -> some View) -> some View {
        VStack {
            Spacer(minLength: 0)
            inner()
            Spacer(minLength: 0)
        }
    }

    // MARK: - Controls

    /// Pass and save circles mirror the gestures; the Undo pill sits between
    /// them for five seconds after each action.
    private var controls: some View {
        ZStack {
            HStack {
                circleButton(
                    icon: "xmark",
                    label: "Pass on this watch",
                    tint: Color.calibre.mutedForeground
                ) {
                    swipeCommand = .pass
                }
                Spacer()
                circleButton(
                    icon: "heart.fill",
                    label: "Save this watch",
                    tint: Color.calibre.success
                ) {
                    swipeCommand = .save
                }
            }
            if let undoable {
                undoPill(for: undoable)
            }
        }
        .frame(height: 64)
        .animation(Motion.easeMedium, value: undoable?.id)
    }

    private var deckIsActive: Bool {
        feed?.phase == .ready && feed?.topCard != nil
    }

    private func circleButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .background(Color.calibre.card, in: Circle())
                .overlay(Circle().strokeBorder(Color.calibre.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .calibreShadow(.resting)
        .disabled(!deckIsActive || swipeCommand != nil)
        .opacity(deckIsActive ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func undoPill(for record: UndoRecord) -> some View {
        Button {
            performUndo(record)
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 12, weight: .medium))
                Text("Undo")
                    .font(CalibreType.label)
            }
            .foregroundStyle(Color.calibre.secondaryForeground)
            .padding(.horizontal, Space.l)
            .frame(minHeight: Space.touchTarget)
            .background(Color.calibre.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.calibre.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .calibreShadow(.resting)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
        .accessibilityLabel(record.kind == .save ? "Undo save" : "Undo pass")
    }

    // MARK: - Semantics

    private func handleCommit(_ listing: Listing, _ direction: SwipeDirection) {
        switch direction {
        case .pass:
            services.signals.recordDiscoverPass(listing.id)
            setUndo(UndoRecord(listing: listing, kind: .pass))
        case .save:
            setUndo(UndoRecord(listing: listing, kind: .save))
            session.require("Sign in to save watches you love") {
                [commerce = services.commerce, toasts, feed] in
                guard !commerce.isWatching(listingID: listing.id) else { return }
                do {
                    try await commerce.toggleWatch(listingID: listing.id)
                } catch {
                    toasts.show(
                        title: "Couldn't save that watch",
                        message: error.localizedDescription,
                        tone: .error
                    )
                    feed?.reinsertTop(listing)
                }
            }
        }
    }

    private func setUndo(_ record: UndoRecord) {
        undoable = record
        undoExpiry?.cancel()
        undoExpiry = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            undoable = nil
        }
    }

    private func performUndo(_ record: UndoRecord) {
        undoExpiry?.cancel()
        undoable = nil
        Haptics.shared.play(.press)

        switch record.kind {
        case .pass:
            services.signals.removeDiscoverPass(record.listing.id)
            reinstate(record.listing)
        case .save:
            if services.commerce.isWatching(listingID: record.listing.id) {
                Task {
                    do {
                        try await services.commerce.toggleWatch(listingID: record.listing.id)
                        reinstate(record.listing)
                    } catch {
                        toasts.show(
                            title: "Couldn't undo that save",
                            message: error.localizedDescription,
                            tone: .error
                        )
                    }
                }
            } else {
                // A guest save whose sign-in never completed — nothing was
                // written anywhere; just deal the card back.
                reinstate(record.listing)
            }
        }
    }

    private func reinstate(_ listing: Listing) {
        withAnimation(Motion.easeMedium) {
            feed?.reinsertTop(listing)
        }
    }

    private func openListing(_ listing: Listing) {
        router.discoverPath.append(.listing(listing.id))
    }

    // MARK: - Lifecycle

    private func bootstrapFeed() async {
        guard feed == nil else { return }
        let fresh = DeckFeed(
            catalog: services.catalog,
            commerce: services.commerce,
            signals: services.signals,
            session: services.auth
        )
        fresh.onTransientError = { [toasts, weak fresh] message in
            toasts.show(
                title: "Couldn't load more watches",
                message: message,
                tone: .error,
                action: .init(label: "Retry") { fresh?.refillIfNeeded() }
            )
        }
        feed = fresh
        await fresh.start()
    }
}

/// The last swipe, reversible for five seconds.
private struct UndoRecord: Identifiable {
    enum Kind { case save, pass }

    let listing: Listing
    let kind: Kind

    var id: String { listing.id }
}
