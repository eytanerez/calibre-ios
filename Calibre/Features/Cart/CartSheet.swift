import CalibreDesign
import CalibreKit
import SwiftUI

/// The bag, with a saved-for-later shelf underneath. Presented from the home
/// header's bag button.
///
/// A checkout covers as many or as few of the watches in the bag as the buyer
/// picks — one payment, one order each — so the bag is a list of selectable
/// rows rather than a single occupant. Everything checkoutable starts
/// selected, because that is what someone opening their bag to buy means.
struct CartSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Parent-provided navigation (the sheet can't push): both dismiss first.
    let openListing: (String) -> Void
    let openSaved: () -> Void

    @State private var isLoading = true
    @State private var removalCandidate: CartItem?
    /// Listing ids the buyer has deliberately deselected. Storing the *out*
    /// set rather than the in set means a watch added while the sheet is open
    /// arrives selected, which is what adding one means.
    @State private var deselected: Set<String> = []
    @State private var tutorial = TutorialController(
        id: "cart.bag.multi",
        steps: [
            TutorialStep(
                id: "as-many-or-few",
                anchor: "cart.bagItems",
                title: "As many or as few",
                message: "Pick the watches you want to buy now and leave the rest for later. Whatever you choose is one payment — and one order per watch, each tracked on its own.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.box)
            )
        ]
    )

    private var bagItems: [CartItem] { services.commerce.cart }

    /// The rows a checkout can actually cover — an unavailable watch is in the
    /// bag but not for sale.
    private var checkoutableItems: [CartItem] {
        bagItems.filter { $0.listing?.isAvailable ?? false }
    }

    private var selectedItems: [CartItem] {
        checkoutableItems.filter { !deselected.contains($0.listingId) }
    }

    private var selectedCount: Int { selectedItems.count }

    /// The API caps a checkout at ten watches; the bag says so before the
    /// button is tapped rather than after the server refuses.
    private var maximumPerCheckout: Int { CheckoutStore.maximumListingsPerCheckout }
    private var isOverLimit: Bool { selectedCount > maximumPerCheckout }

    /// Saved watches, minus anything already in the bag.
    private var savedItems: [WatchlistItem] {
        let inBag = Set(bagItems.map(\.listingId))
        return services.commerce.watchlist.filter { !inBag.contains($0.listingId) }
    }

    var body: some View {
        SheetScaffold(title: "Your bag", detents: [.large]) {
            List {
                if isLoading, bagItems.isEmpty, services.commerce.watchlist.isEmpty {
                    loadingRows.cartRow(bottom: Space.xxl)
                } else {
                    bagSection.cartRow(bottom: savedItems.isEmpty ? Space.xxl : Space.xl)

                    if !savedItems.isEmpty {
                        savedHeader.cartRow(bottom: Space.s)

                        ForEach(Array(savedItems.enumerated()), id: \.element.id) { index, item in
                            savedRow(item)
                                .cartRow(top: 0, bottom: index == savedItems.count - 1 ? Space.xxl : Space.s)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    savedSwipeActions(item)
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
        }
        .tutorialOverlay(tutorial)
        .task {
            await loadEverything()
            if !bagItems.isEmpty { tutorial.startIfNeeded() }
        }
        // Teach the rule at the moment there are watches to point at — not
        // over an empty bag.
        .onChange(of: bagItems.count) { _, count in
            if count > 0 { tutorial.startIfNeeded() }
        }
        .alert(
            "Take this watch out of your bag?",
            isPresented: removalDialogPresented,
            presenting: removalCandidate
        ) { item in
            Button("Remove from bag", role: .destructive) {
                Task { await removeBagItem(item) }
            }
            Button("Keep it", role: .cancel) {}
        } message: { item in
            Text("\(item.listing?.title ?? "This watch") leaves your bag. You can always add it again.")
        }
    }

    // MARK: - Bag

    @ViewBuilder
    private var bagSection: some View {
        if bagItems.isEmpty {
            EmptyState(
                icon: "bag",
                title: "Your bag is empty",
                message: "When a watch speaks to you, add it here. Buy one, or several together — it's one payment either way.",
                actionTitle: "Browse the market"
            ) {
                dismiss()
            }
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                if checkoutableItems.count > 1 {
                    selectionHeader
                }

                VStack(spacing: Space.s) {
                    ForEach(bagItems) { item in
                        bagCard(item)
                    }
                }
                .tutorialAnchor("cart.bagItems")

                Button(checkoutTitle) {
                    Haptics.shared.play(.press)
                    checkoutSelected()
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(selectedCount == 0 || isOverLimit)

                if isOverLimit {
                    Text("One purchase can cover up to \(maximumPerCheckout) watches. Deselect \(selectedCount - maximumPerCheckout) to continue.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The warm one-liner: the bag never insists on all of it.
                Text("Check out with as many or as few as you like — one payment, one order per watch.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "2 of 3 selected", with select-all beside it.
    private var selectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selectionSummary)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            Spacer()
            Button(allSelected ? "Deselect all" : "Select all") {
                Haptics.shared.play(.selection)
                withAnimation(Motion.easeFast) {
                    if allSelected {
                        deselected = Set(checkoutableItems.map(\.listingId))
                    } else {
                        deselected.removeAll()
                    }
                }
            }
            .font(CalibreType.label)
            .foregroundStyle(Color.calibre.primary)
            .buttonStyle(PressableStyle())
        }
        .accessibilityElement(children: .combine)
    }

    private var allSelected: Bool {
        !checkoutableItems.isEmpty && selectedCount == checkoutableItems.count
    }

    private var selectionSummary: String {
        guard selectedCount > 0 else { return "None selected" }
        return "\(selectedCount) of \(checkoutableItems.count) selected"
    }

    private var checkoutTitle: String {
        switch selectedCount {
        case 0: "Select a watch to check out"
        case 1: "Checkout"
        default: "Check out \(selectedCount) watches"
        }
    }

    /// One bag row: a selection control on the left when there is a choice to
    /// make, the watch itself in the middle, and its own overflow menu.
    ///
    /// Three of those four pieces have a fixed width — a 44pt checkbox, a 72pt
    /// image well and a 44pt menu — so the title and price share whatever is
    /// left. At an accessibility size that remainder is not enough to finish
    /// the price, and a bag row that will not say what a watch costs is not a
    /// bag row. Above the threshold the same pieces stack instead; at every
    /// size below it, this is the row that has always shipped.
    private func bagCard(_ item: CartItem) -> some View {
        let available = item.listing?.isAvailable ?? false
        let selected = available && !deselected.contains(item.listingId)

        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.m) {
                        if checkoutableItems.count > 1 {
                            bagSelectionButton(item, selected: selected, available: available)
                        }
                        Spacer(minLength: 0)
                        bagMenu(item)
                    }
                    bagOpenButton(item, stacked: true)
                }
            } else {
                HStack(spacing: Space.m) {
                    if checkoutableItems.count > 1 {
                        bagSelectionButton(item, selected: selected, available: available)
                    }
                    bagOpenButton(item, stacked: false)
                    bagMenu(item)
                }
            }
        }
        .padding(Space.m)
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(
                    selected && checkoutableItems.count > 1
                        ? Color.calibre.primary.opacity(0.45)
                        : Color.calibre.border,
                    lineWidth: 1
                )
        )
        .opacity(available ? 1 : 0.6)
        .animation(Motion.easeFast, value: selected)
    }

    /// Include-in-this-checkout, shown only when there is more than one
    /// checkoutable watch to choose between.
    private func bagSelectionButton(_ item: CartItem, selected: Bool, available: Bool) -> some View {
        Button {
            Haptics.shared.play(.selection)
            toggleSelection(item)
        } label: {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected ? Color.calibre.primary : Color.calibre.borderBright)
                .frame(width: Space.touchTarget, height: Space.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!available)
        .accessibilityLabel(selected ? "Selected for checkout" : "Not selected")
        .accessibilityValue(item.listing?.title ?? "Listing")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The watch itself — tapping it opens the listing. `stacked` puts the
    /// image well above the words rather than beside them, which is the only
    /// arrangement that leaves the price room to be read whole.
    @ViewBuilder
    private func bagOpenButton(_ item: CartItem, stacked: Bool) -> some View {
        Button {
            dismiss()
            openListing(item.listingId)
        } label: {
            if stacked {
                VStack(alignment: .leading, spacing: Space.m) {
                    bagImageWell(item)
                    bagDetails(item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: Space.m) {
                    bagImageWell(item)
                    bagDetails(item)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(PressableStyle())
    }

    private func bagImageWell(_ item: CartItem) -> some View {
        ListingImageWell(url: item.listing?.image?.url, targetWidth: 180)
            .frame(width: 72, height: 72)
            .background(Color.calibre.secondary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func bagDetails(_ item: CartItem) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(item.listing?.title ?? "Listing")
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
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

    private func bagMenu(_ item: CartItem) -> some View {
        Menu {
            Button {
                Task { await saveBagItemForLater(item) }
            } label: {
                Label("Save for later", systemImage: "heart")
            }
            Button(role: .destructive) {
                removalCandidate = item
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
                .frame(width: Space.touchTarget, height: Space.touchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(item.listing?.title ?? "this watch")")
    }

    private func toggleSelection(_ item: CartItem) {
        if deselected.contains(item.listingId) {
            deselected.remove(item.listingId)
        } else {
            deselected.insert(item.listingId)
        }
    }

    // MARK: - Saved for later

    private var savedHeader: some View {
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
    }

    /// The image/title/price area is its own `Button` (tap opens the
    /// listing, matching `bagCard`); the overflow `Menu` is a sibling, not
    /// nested inside that button's label, so the two controls never fight
    /// over the same tap.
    ///
    /// The same squeeze `bagCard` has, one size down: a 56pt image well and a
    /// 44pt menu are fixed, so at an accessibility size the price runs out of
    /// room mid-number, and a shelf that won't say what a watch costs isn't
    /// worth showing. Above the threshold the pieces stack; at every size
    /// below it, this is the row that has always shipped.
    private func savedRow(_ item: WatchlistItem) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.m) {
                        Spacer(minLength: 0)
                        savedMenu(item)
                    }
                    savedOpenButton(item, stacked: true)
                }
            } else {
                HStack(spacing: Space.m) {
                    savedOpenButton(item, stacked: false)
                    savedMenu(item)
                }
            }
        }
        .padding(Space.m)
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    /// The watch itself — tapping it opens the listing. `stacked` puts the
    /// image well above the words rather than beside them, which is the only
    /// arrangement that leaves the price room to be read whole.
    @ViewBuilder
    private func savedOpenButton(_ item: WatchlistItem, stacked: Bool) -> some View {
        Button {
            dismiss()
            openListing(item.listingId)
        } label: {
            if stacked {
                VStack(alignment: .leading, spacing: Space.m) {
                    savedImageWell(item)
                    savedDetails(item, stacked: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: Space.m) {
                    savedImageWell(item)
                    savedDetails(item, stacked: false)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.listing.map { "\($0.title), \(PriceFormatter.format($0.price.value, currency: $0.currency))" } ?? "Listing")
        .accessibilityHint("Opens this listing")
    }

    private func savedImageWell(_ item: WatchlistItem) -> some View {
        ListingImageWell(url: item.listing?.image?.url, targetWidth: 120)
            .frame(width: 56, height: 56)
            .background(Color.calibre.secondary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func savedDetails(_ item: WatchlistItem, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.listing?.title ?? "Listing")
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                // Stacked, the title has the row's full width, so it wraps the
                // way `bagCard`'s does instead of clipping a long name.
                .lineLimit(stacked ? 2 : 1)
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
    }

    private func savedMenu(_ item: WatchlistItem) -> some View {
        Menu {
            if item.listing?.isAvailable ?? false {
                Button {
                    Task { await moveToBag(item) }
                } label: {
                    Label("Move to bag", systemImage: "bag")
                }
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

    /// Native swipe actions mirror the overflow menu: Move to bag when the
    /// watch is still available, Remove always — same underlying calls, no
    /// duplicated logic.
    @ViewBuilder
    private func savedSwipeActions(_ item: WatchlistItem) -> some View {
        if item.listing?.isAvailable ?? false {
            Button {
                Task { await moveToBag(item) }
            } label: {
                Label("Move to bag", systemImage: "bag")
            }
            .tint(Color.calibre.primary)
        }
        Button(role: .destructive) {
            Task { await removeSaved(item) }
        } label: {
            Label("Remove", systemImage: "heart.slash")
        }
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

    private var removalDialogPresented: Binding<Bool> {
        Binding(
            get: { removalCandidate != nil },
            set: { if !$0 { removalCandidate = nil } }
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

    /// The selected set, in the order the bag shows them, straight into one
    /// checkout.
    private func checkoutSelected() {
        let ids = selectedItems.map(\.listingId)
        guard !ids.isEmpty, ids.count <= maximumPerCheckout else { return }
        let router = services.router
        dismiss()
        router.presentCheckout(listingIDs: ids)
    }

    private func saveBagItemForLater(_ item: CartItem) async {
        let commerce = services.commerce
        do {
            if !commerce.isWatching(listingID: item.listingId) {
                try await commerce.toggleWatch(listingID: item.listingId)
                Analytics.watchLiked(analyticsListing(item.listing, id: item.listingId))
            }
            try await commerce.removeCartItem(id: item.id)
            deselected.remove(item.listingId)
            Haptics.shared.play(.save)
            toasts.show(title: "Saved for later", message: "It'll wait for you in Saved.", tone: .success)
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't move it to Saved", message: error.browseMessage, tone: .error)
        }
    }

    private func removeBagItem(_ item: CartItem) async {
        do {
            try await services.commerce.removeCartItem(id: item.id)
            deselected.remove(item.listingId)
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

    /// Listing-shaped analytics properties from a cart/watchlist row. A
    /// `ListingSummary` has no brand or reference, so those go out absent
    /// rather than guessed.
    private func analyticsListing(
        _ summary: ListingSummary?,
        id listingID: String
    ) -> Analytics.ListingInfo {
        summary.map(Analytics.ListingInfo.init) ?? .init(id: listingID)
    }

    /// Saved → bag. The bag holds as many as the buyer wants, so nothing has
    /// to move out to make room.
    private func moveToBag(_ item: WatchlistItem) async {
        let commerce = services.commerce
        do {
            try await commerce.addToCart(listingID: item.listingId)
            Analytics.watchAddedToCart(analyticsListing(item.listing, id: item.listingId))
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
}

// MARK: - List row plumbing

private extension View {
    /// Plain-list row chrome: no separators, quiet background, and no extra
    /// horizontal inset — `SheetScaffold` already applies `Space.margin`.
    func cartRow(top: CGFloat = 0, bottom: CGFloat = Space.xl) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
    }
}
