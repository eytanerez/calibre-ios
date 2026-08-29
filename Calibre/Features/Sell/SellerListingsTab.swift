import CalibreDesign
import CalibreKit
import SwiftUI

// MARK: - The filter

/// How a seller sorts their own inventory.
///
/// One case per status the seller can actually be in, rather than the two
/// lumped filters this replaced: `live` used to swallow reserved watches, and
/// `archived` used to swallow rejected ones — so a listing the review team
/// sent back was filed under a word that means the seller put it away. The
/// rail only offers a filter that has rows behind it, so the extra cases cost
/// nothing until they exist.
enum SellerListingFilter: String, CaseIterable, Identifiable {
    case all
    case needsAction
    case live
    case reserved
    case inReview
    case draft
    case sold
    case needsChanges
    case paused
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .needsAction: "Needs action"
        case .live: "Live"
        case .reserved: "Reserved"
        case .inReview: "In review"
        case .draft: "Drafts"
        case .sold: "Sold"
        case .needsChanges: "Needs changes"
        case .paused: "Paused"
        case .archived: "Archived"
        }
    }

    func matches(_ listing: Listing) -> Bool {
        switch self {
        case .all: true
        case .needsAction: SellerStatusDisplay.needsAction(listing)
        case .live: listing.status == .active
        case .reserved: listing.status == .reserved
        case .inReview: listing.status == .pendingReview
        case .draft: listing.status == .draft
        case .sold: listing.status == .sold
        case .needsChanges: listing.status == .rejected
        case .paused: listing.status == .pausedCard
        case .archived: listing.status == .archived
        }
    }

    /// What an empty filter says. Only reachable when inventory changes under
    /// a filter that had rows when the rail was drawn.
    var emptyLine: String {
        switch self {
        case .all: "No listings here yet."
        case .needsAction: "Nothing needs your attention right now."
        case .live: "Nothing is live at the moment."
        case .reserved: "Nothing is reserved."
        case .inReview: "Nothing waiting on review."
        case .draft: "No drafts — everything you started is out the door."
        case .sold: "No sales yet — they'll appear here."
        case .needsChanges: "Nothing came back from review."
        case .paused: "Nothing paused."
        case .archived: "Nothing archived."
        }
    }
}

// MARK: - The tab

/// Inventory: the shop's primary work surface.
///
/// Every listing the seller has, filtered by status, with the same three ways
/// into a row's actions the rest of the app uses — swipe, long press, and the
/// ⋯ menu — all built from one `RowAction` list.
struct SellerListingsTab: View {
    let listings: [Listing]
    /// Imports that left drafts behind, newest first.
    let unfinishedImports: [UnfinishedImport]
    @Binding var filter: SellerListingFilter
    let actions: SellerShopActions

    var body: some View {
        Group {
            if !unfinishedImports.isEmpty {
                continueBulkImport.sellRow()
            }

            if availableFilters.count > 1 {
                filterRail.sellRailRow()
            }

            if visibleListings.isEmpty {
                emptyState.sellRow()
            } else {
                ForEach(visibleListings) { listing in
                    let menu = rowActions(for: listing)
                    SellerListingRow(listing: listing, actions: menu) {
                        actions.openListing(listing)
                    }
                    .sellRow(bottom: Space.m)
                    .rowActions(menu)
                }
            }
        }
    }

    private var visibleListings: [Listing] {
        listings.filter(filter.matches)
    }

    /// `all`, plus every status the seller actually holds something in. A
    /// filter that leads to an empty list is a dead end on a rail people
    /// swipe through, so it isn't offered.
    private var availableFilters: [SellerListingFilter] {
        SellerListingFilter.allCases.filter { candidate in
            candidate == .all || listings.contains(where: candidate.matches)
        }
    }

    // MARK: Filter rail

    private var filterRail: some View {
        ChipRail {
            ForEach(availableFilters) { candidate in
                let count = listings.filter(candidate.matches).count
                FilterChip(
                    "\(candidate.title) · \(count)",
                    isSelected: candidate == filter
                ) {
                    filter = candidate
                }
                // The separator between the word and the figure is a
                // typographic device, not something to read out.
                .accessibilityLabel("\(candidate.title), \(count)")
            }
        }
    }

    // MARK: Rows

    private func rowActions(for listing: Listing) -> [RowAction] {
        var menu: [RowAction] = [
            RowAction("Edit", systemImage: "square.and.pencil") {
                actions.openWizard(listing.status == .draft ? .finishDraft(listing) : .edit(listing))
            }
        ]
        if listing.status == .draft {
            menu.append(
                RowAction("Submit", systemImage: "paperplane", tint: Color.calibre.success) {
                    actions.confirmSubmit(listing)
                }
            )
        }
        // Nothing about the listing changed, so there is nothing to resubmit:
        // the card is the whole of what is wrong with it.
        if listing.status == .pausedCard {
            menu.append(
                RowAction("Card on file", systemImage: "creditcard", tint: Color.calibre.primary) {
                    actions.openCardOnFile()
                }
            )
        }
        // Sold listings are attached to an order and can't be removed.
        if listing.status != .sold {
            menu.append(
                RowAction("Delete", systemImage: "trash", isDestructive: true) {
                    actions.confirmDelete(listing)
                }
            )
        }
        return menu
    }

    // MARK: Empty

    @ViewBuilder
    private var emptyState: some View {
        if listings.isEmpty {
            EmptyState(
                icon: "camera",
                title: "Your shop is ready for its first watch",
                message: "Six photos, one calm flow — most sellers list in under five minutes.",
                aside: "The camera already in your hand is the right one.",
                actionTitle: "List a watch",
                action: { actions.listWatch(nil) }
            )
        } else {
            Text(filter.emptyLine)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Space.xl)
        }
    }

    // MARK: Continue bulk import

    /// An import creates drafts and nothing else, so the drafts it left are
    /// work waiting for a person. This is where that work starts on a phone —
    /// which is where most of it happens, because the photographs need a
    /// camera.
    private var continueBulkImport: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Finish what you imported")

            Text("Each draft goes to review as you finish it. Photos are quickest here \u{2014} the camera is already in your hand.")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Space.m) {
                ForEach(unfinishedImports) { entry in
                    Button {
                        Haptics.shared.play(.press)
                        actions.continueImport(ImportJobRef(id: entry.job.id))
                    } label: {
                        importRow(entry)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func importRow(_ entry: UnfinishedImport) -> some View {
        SellCard {
            HStack(alignment: .top, spacing: Space.m) {
                IconTile(systemName: "camera")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue bulk import \u{2014} \(entry.finished) of \(entry.total) finished")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.remainderLine)
                        .font(CalibreType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.calibre.mutedForeground)
                    if let filename = entry.job.originalFilename, !filename.isEmpty {
                        Text(filename)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .lineLimit(1)
                    }
                    importProgressBar(entry)
                        .padding(.top, Space.xs)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.calibre.primary)
            }
            .padding(Space.l)
        }
        .accessibilityElement(children: .combine)
    }

    private func importProgressBar(_ entry: UnfinishedImport) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.calibre.border)
                Capsule()
                    .fill(Color.calibre.primary)
                    .frame(width: proxy.size.width * entry.fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - One inventory row

/// Thumb, title, status, the figures a seller checks, and the row's actions.
///
/// The ⋯ menu is a sibling of the tap target rather than inside it, so
/// opening the menu can never be read as opening the listing.
struct SellerListingRow: View {
    let listing: Listing
    let actions: [RowAction]
    let open: () -> Void

    var body: some View {
        let badge = SellerStatusDisplay.badge(for: listing)
        let note = attentionNote
        return Button(action: open) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.m) {
                    SellThumb(url: listing.images.first?.url)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(listing.title)
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .lineLimit(1)
                        StatusBadge(badge.text, tone: badge.tone)
                        HStack(spacing: Space.s) {
                            Text("#\(listing.listingNumber) · \(PriceFormatter.format(listing.price.value))")
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                            if let metrics = listing.metrics, metrics.views + metrics.watchers > 0 {
                                Label("\(metrics.views)", systemImage: "eye")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                                    .accessibilityLabel("\(metrics.views) views")
                                Label("\(metrics.watchers)", systemImage: "heart")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                                    .accessibilityLabel("\(metrics.watchers) watching")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    RowActionsMenu(actions: actions, label: "Options for \(listing.title)")
                }
                if let note {
                    CalloutBand(icon: "exclamationmark.bubble", message: note)
                }
            }
            .padding(Space.m)
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// The moderator's words, shown on rejected rows — and, on a paused one,
    /// the reason Calibre took it down and what brings it back.
    private var attentionNote: String? {
        if listing.status == .pausedCard {
            return "We took this off the market because your card on file lapsed. Add a valid credit card and it goes back up automatically — no re-review, nothing to resubmit."
        }
        guard listing.status == .rejected else { return nil }
        let note = listing.reviewEvents?
            .first { $0.toStatus == "rejected" && !($0.notes ?? "").isEmpty }?
            .notes
        return note ?? "Our review team asked for changes. Edit and resubmit when ready."
    }
}
