import CalibreDesign
import CalibreKit
import SwiftUI

/// The bag: Calibre carries one watch at a time, with a saved-for-later
/// shelf underneath. Presented from the home header's bag button.
struct CartSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    /// Parent-provided navigation (the sheet can't push): both dismiss first.
    let openListing: (String) -> Void
    let openSaved: () -> Void

    @State private var isLoading = true
    @State private var confirmRemove = false
    @State private var swapCandidate: WatchlistItem?
    @State private var tutorial = TutorialController(
        id: "cart.bag",
        steps: [
            TutorialStep(
                id: "one-at-a-time",
                anchor: "cart.bagItem",
                title: "One watch at a time",
                message: "Your bag carries a single watch, so every purchase gets our full attention. Add another and we'll tuck this one into Saved — nothing is lost.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.card)
            )
        ]
    )

    private var bagItem: CartItem? { services.commerce.cart.first }

    /// Saved watches, minus anything already in the bag.
    private var savedItems: [WatchlistItem] {
        services.commerce.watchlist.filter { $0.listingId != bagItem?.listingId }
    }

    var body: some View {
        SheetScaffold(title: "Your bag", detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if isLoading, services.commerce.cart.isEmpty, services.commerce.watchlist.isEmpty {
                        loadingRows
                    } else {
                        bagSection

                        if !savedItems.isEmpty {
                            savedSection
                        }
                    }
                }
                .padding(.bottom, Space.xxl)
            }
        }
        .tutorialOverlay(tutorial)
        .task {
            await loadEverything()
            if bagItem != nil { tutorial.startIfNeeded() }
        }
        // Teach the one-watch rule at the moment there's actually a watch to
        // point at — not over an empty bag.
        .onChange(of: bagItem?.listingId) { _, id in
            if id != nil { tutorial.startIfNeeded() }
        }
        .confirmationDialog(
            "Take this watch out of your bag?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove from bag", role: .destructive) {
                Task { await removeBagItem() }
            }
            Button("Keep it", role: .cancel) {}
        }
        .confirmationDialog(
            "Your bag holds one watch at a time.",
            isPresented: swapDialogPresented,
            titleVisibility: .visible,
            presenting: swapCandidate
        ) { candidate in
            Button("Move \(bagItem?.listing?.title ?? "the current watch") to Saved") {
                Task { await performSwap(candidate) }
            }
            Button("Keep my bag as it is", role: .cancel) {}
        } message: { candidate in
            Text("We'll tuck \(bagItem?.listing?.title ?? "your current watch") into Saved and put \(candidate.listing?.title ?? "this one") in your bag.")
        }
    }

    // MARK: - Bag

    @ViewBuilder
    private var bagSection: some View {
        if let item = bagItem {
            VStack(alignment: .leading, spacing: Space.m) {
                bagCard(item)
                    .tutorialAnchor("cart.bagItem")

                Button("Checkout") {
                    Haptics.shared.play(.press)
                    checkout(item)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(!(item.listing?.isAvailable ?? false))

                HStack(spacing: Space.m) {
                    Button("Save for later") {
                        Task { await saveBagItemForLater(item) }
                    }
                    .buttonStyle(.calibre(.ghost, fullWidth: true))

                    Button("Remove") {
                        confirmRemove = true
                    }
                    .buttonStyle(.calibre(.ghost, fullWidth: true))
                    .foregroundStyle(Color.calibre.destructive)
                }

                Text("Your bag holds one watch at a time, so every purchase gets our full attention.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        } else {
            EmptyState(
                icon: "bag",
                title: "Your bag is empty",
                message: "When a watch speaks to you, add it here. One at a time — that's the Calibre way.",
                actionTitle: "Browse the market"
            ) {
                dismiss()
            }
        }
    }

    private func bagCard(_ item: CartItem) -> some View {
        Button {
            dismiss()
            openListing(item.listingId)
        } label: {
            HStack(spacing: Space.m) {
                ListingImageWell(url: item.listing?.image?.url, targetWidth: 180)
                    .frame(width: 88, height: 88)
                    .background(Color.calibre.secondary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(item.listing?.title ?? "Listing")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let listing = item.listing {
                        Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                            .font(CalibreType.price)
                            .foregroundStyle(Color.calibre.foreground)
                        if let badge = listing.unavailableBadge {
                            StatusBadge(badge.text, tone: badge.tone)
                        }
                    }
                }

                Spacer()
            }
            .padding(Space.m)
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Saved for later

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow("Saved for later")
                Spacer()
                Button("View all") {
                    dismiss()
                    openSaved()
                }
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.primary)
                .buttonStyle(PressableStyle())
            }

            VStack(spacing: 0) {
                ForEach(Array(savedItems.enumerated()), id: \.element.id) { index, item in
                    savedRow(item)
                    if index < savedItems.count - 1 {
                        Rectangle().fill(Color.calibre.border).frame(height: 1)
                    }
                }
            }
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
    }

    private func savedRow(_ item: WatchlistItem) -> some View {
        HStack(spacing: Space.m) {
            ListingImageWell(url: item.listing?.image?.url, targetWidth: 120)
                .frame(width: 56, height: 56)
                .background(Color.calibre.secondary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.listing?.title ?? "Listing")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(1)
                HStack(spacing: Space.s) {
                    if let listing = item.listing {
                        Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                            .font(CalibreType.priceSmall)
                            .foregroundStyle(Color.calibre.foreground)
                        if let badge = listing.unavailableBadge {
                            StatusBadge(badge.text, tone: badge.tone)
                        }
                    }
                }
            }

            Spacer()

            Menu {
                if item.listing?.isAvailable ?? false {
                    Button {
                        moveToBag(item)
                    } label: {
                        Label("Move to bag", systemImage: "bag")
                    }
                }
                Button {
                    dismiss()
                    openListing(item.listingId)
                } label: {
                    Label("View", systemImage: "eye")
                }
                Button(role: .destructive) {
                    Task { await removeSaved(item) }
                } label: {
                    Label("Remove", systemImage: "heart.slash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(item.listing?.title ?? "saved watch")")
        }
        .padding(Space.m)
    }

    private var loadingRows: some View {
        VStack(spacing: Space.m) {
            Rectangle().frame(maxWidth: .infinity).frame(height: 112).shimmer()
            Rectangle().frame(maxWidth: .infinity).frame(height: 48).shimmer()
            Rectangle().frame(maxWidth: .infinity).frame(height: 72).shimmer()
            Rectangle().frame(maxWidth: .infinity).frame(height: 72).shimmer()
        }
    }

    // MARK: - Actions

    private var swapDialogPresented: Binding<Bool> {
        Binding(
            get: { swapCandidate != nil },
            set: { if !$0 { swapCandidate = nil } }
        )
    }

    private func loadEverything() async {
        guard session.isAuthenticated else {
            isLoading = false
            return
        }
        let commerce = services.commerce
        async let cart = try? commerce.loadCart()
        async let watchlist = try? commerce.loadWatchlist()
        _ = await (cart, watchlist)
        isLoading = false
    }

    private func checkout(_ item: CartItem) {
        let router = services.router
        dismiss()
        router.open(.checkout(item.listingId, offerID: nil))
    }

    private func saveBagItemForLater(_ item: CartItem) async {
        let commerce = services.commerce
        do {
            if !commerce.isWatching(listingID: item.listingId) {
                try await commerce.toggleWatch(listingID: item.listingId)
            }
            try await commerce.removeCartItem(id: item.id)
            Haptics.shared.play(.save)
            toasts.show(title: "Saved for later", message: "It'll wait for you in Saved.", tone: .success)
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't move it to Saved", message: error.browseMessage, tone: .error)
        }
    }

    private func removeBagItem() async {
        guard let item = bagItem else { return }
        do {
            try await services.commerce.removeCartItem(id: item.id)
            toasts.show(title: "Removed from your bag")
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't remove it", message: error.browseMessage, tone: .error)
        }
    }

    private func removeSaved(_ item: WatchlistItem) async {
        do {
            try await services.commerce.toggleWatch(listingID: item.listingId)
            toasts.show(title: "Removed from Saved")
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't remove it", message: error.browseMessage, tone: .error)
        }
    }

    private func moveToBag(_ item: WatchlistItem) {
        if bagItem != nil {
            swapCandidate = item
        } else {
            Task { await performMove(item) }
        }
    }

    /// Saved → bag when the bag is empty.
    private func performMove(_ item: WatchlistItem) async {
        let commerce = services.commerce
        do {
            try await commerce.addToCart(listingID: item.listingId)
            if commerce.isWatching(listingID: item.listingId) {
                try await commerce.toggleWatch(listingID: item.listingId)
            }
            Haptics.shared.play(.save)
            toasts.show(title: "In your bag", message: "Ready when you are.", tone: .success)
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't move it to your bag", message: error.browseMessage, tone: .error)
        }
    }

    /// Saved → bag when the bag is occupied: the occupant moves to Saved.
    private func performSwap(_ item: WatchlistItem) async {
        let commerce = services.commerce
        guard let existing = bagItem else {
            await performMove(item)
            return
        }
        do {
            if !commerce.isWatching(listingID: existing.listingId) {
                try await commerce.toggleWatch(listingID: existing.listingId)
            }
            try await commerce.removeCartItem(id: existing.id)
            try await commerce.addToCart(listingID: item.listingId)
            if commerce.isWatching(listingID: item.listingId) {
                try await commerce.toggleWatch(listingID: item.listingId)
            }
            Haptics.shared.play(.save)
            toasts.show(
                title: "In your bag",
                message: "We moved \(existing.listing?.title ?? "your other watch") to Saved.",
                tone: .success
            )
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't swap your bag", message: error.browseMessage, tone: .error)
        }
    }
}
