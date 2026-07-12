import CalibreDesign
import CalibreKit
import SwiftUI

/// The watchlist as a 2-column grid. Long-press any watch to remove it, or
/// flip into Edit mode for one-tap removal.
///
/// Price-drop badges were spec'd "if detectable": the watchlist payload
/// carries only the listing's current price — no saved-at price — so drops
/// aren't detectable from the API today. Skipped and noted.
struct SavedScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.browsePush) private var push

    @State private var isLoading = true
    @State private var isEditing = false

    private var items: [WatchlistItem] { services.commerce.watchlist }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "heart",
                    title: "Keep your shortlist here",
                    message: "Sign in and the watches you save will wait for you on any device.",
                    actionTitle: "Sign in"
                ) {
                    services.auth.require("Sign in to see your saved watches") {}
                }
            } else if isLoading, items.isEmpty {
                skeleton
            } else if items.isEmpty {
                EmptyState(
                    icon: "heart",
                    title: "Nothing saved yet",
                    message: "Watches you save appear here so you can compare and act when the moment is right."
                )
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(Motion.easeMedium) {
                            isEditing.toggle()
                        }
                    }
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.primary)
                }
            }
        }
        .task {
            guard session.isAuthenticated else {
                isLoading = false
                return
            }
            _ = try? await services.commerce.loadWatchlist()
            isLoading = false
        }
        .refreshable {
            _ = try? await services.commerce.loadWatchlist()
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.l),
                    GridItem(.flexible(), spacing: Space.l),
                ],
                alignment: .leading,
                spacing: Space.xl
            ) {
                ForEach(items) { item in
                    savedCell(item)
                }
            }
            .padding(Space.margin)
        }
    }

    private func savedCell(_ item: WatchlistItem) -> some View {
        Button {
            guard !isEditing else { return }
            push(.listing(item.listingId, zoom: nil))
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: Space.s) {
                    ZStack(alignment: .bottomLeading) {
                        ListingImageWell(url: item.listing?.image?.url)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .background(Color.calibre.secondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                        if let badge = item.listing?.unavailableBadge {
                            StatusBadge(badge.text, tone: badge.tone)
                                .padding(Space.s)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        if let year = item.listing?.productionYear {
                            Eyebrow(String(year))
                        }
                        Text(item.listing?.title ?? "Listing")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                        if let listing = item.listing {
                            Text(PriceFormatter.format(listing.price.value, currency: listing.currency))
                                .font(CalibreType.price)
                                .foregroundStyle(Color.calibre.foreground)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                if isEditing {
                    Button {
                        Task { await remove(item) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.calibre.destructive)
                            .background(Color.calibre.background, in: Circle())
                            .frame(width: Space.touchTarget, height: Space.touchTarget, alignment: .topTrailing)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(Space.xs)
                    .transition(.opacity)
                    .accessibilityLabel("Remove \(item.listing?.title ?? "watch") from Saved")
                }
            }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(role: .destructive) {
                Task { await remove(item) }
            } label: {
                Label("Remove from Saved", systemImage: "heart.slash")
            }
        }
    }

    private var skeleton: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.l),
                    GridItem(.flexible(), spacing: Space.l),
                ],
                spacing: Space.xl
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    ListingCardSkeleton()
                }
            }
            .padding(Space.margin)
        }
        .disabled(true)
    }

    private func remove(_ item: WatchlistItem) async {
        do {
            try await services.commerce.toggleWatch(listingID: item.listingId)
            Haptics.shared.play(.save)
            toasts.show(title: "Removed from Saved")
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't remove it", message: error.browseMessage, tone: .error)
        }
    }
}
