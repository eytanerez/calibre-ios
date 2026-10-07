import RewatchDesign
import RewatchKit
import SwiftUI

/// A seller's public storefront: header with reputation, recent reviews, and
/// the paged grid of their active listings.
struct SellerStorefrontScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var typeSize

    let username: String

    @State private var storefront: SellerStorefront?
    @State private var failed = false
    @State private var inventory: ResultsModel?
    @Namespace private var zoomNamespace

    var body: some View {
        Group {
            if let storefront {
                content(storefront)
            } else if failed {
                EmptyState(
                    icon: "person.crop.square",
                    title: "This seller is away",
                    message: "We couldn't load @\(username)'s storefront. Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    failed = false
                    await load()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                skeleton
            }
        }
        .rewatchPageBackground()
        .navigationTitle("@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
        .task {
            await load()
        }
    }

    private func content(_ storefront: SellerStorefront) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xxl) {
                header(storefront)
                    .padding(.horizontal, Space.margin)

                if !storefront.reviews.isEmpty {
                    reviews(storefront)
                        .padding(.horizontal, Space.margin)
                }

                inventorySection(storefront)
            }
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .refreshable {
            await load()
            await inventory?.reload(refresh: true)
        }
    }

    // MARK: Header

    private func header(_ storefront: SellerStorefront) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                AvatarInitial(name: storefront.username, size: .l)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s) {
                        Text("@\(storefront.username)")
                            .font(RewatchType.sectionTitle)
                            .foregroundStyle(Color.rewatch.foreground)
                        if storefront.isVerifiedDealer {
                            StatusBadge("Dealer", tone: .info)
                        }
                    }
                    if let since = storefront.memberSince {
                        Text("Member since \(since.formatted(.dateTime.month(.wide).year()))")
                            .font(RewatchType.caption)
                            .foregroundStyle(Color.rewatch.mutedForeground)
                    }
                }
            }

            if typeSize.isAccessibilitySize {
                // Every stat is fixedSize, so at accessibility sizes the row
                // cannot compress — the review count simply runs off the
                // trailing edge. Above the threshold they stack; at every
                // default size the row below is what ships.
                VStack(alignment: .leading, spacing: Space.m) {
                    statBlocks(storefront)
                }
            } else {
                HStack(alignment: .top, spacing: Space.xl) {
                    statBlocks(storefront)
                    Spacer(minLength: 0)
                }
            }

            storefrontLine(storefront)
        }
    }

    /// The one place on Rewatch where a seller speaks in their own voice
    /// rather than through a listing form, so it is set in their hand.
    ///
    /// The server sends the line a buyer is allowed to read — the last words
    /// that cleared review, not whatever the dealer has typed since — so this
    /// renders what arrives and never reasons about approval itself.
    ///
    /// A verified dealer who has not written one gets a plain sentence in the
    /// sans instead: that is Rewatch describing an absence, not the dealer
    /// talking, and putting it in the hand would put words in their mouth.
    /// A seller who is not a dealer has no line to be missing.
    @ViewBuilder
    private func storefrontLine(_ storefront: SellerStorefront) -> some View {
        if let bio = storefront.bio, !bio.isEmpty {
            Text(bio)
                .font(RewatchType.hand)
                .foregroundStyle(Color.rewatch.secondaryForeground)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Storefront stat: the figure in chocolate, its unit beneath. Serif
    /// numerals sit on varying widths and were wrapping mid-number in the old
    /// equal-spaced row — `monospacedDigit` plus a single unwrapped line keeps
    /// them stable, and the row lays out by content rather than stretching.
    /// Sales, listings, and the rating — the same three blocks whichever way
    /// the header lays them out.
    @ViewBuilder
    private func statBlocks(_ storefront: SellerStorefront) -> some View {
        stat(
            value: "\(storefront.reputation.salesCount)",
            label: storefront.reputation.salesCount == 1 ? "sale" : "sales"
        )
        stat(
            value: "\(storefront.activeListingCount)",
            label: storefront.activeListingCount == 1 ? "listing" : "listings"
        )
        if let average = storefront.reputation.averageRating, storefront.reputation.ratingCount > 0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    StarRating(rating: average)
                    Text(average.formatted(.number.precision(.fractionLength(1))))
                        .font(RewatchType.priceSmall)
                        .foregroundStyle(Color.rewatch.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(storefront.reputation.ratingCount == 1 ? "1 review" : "\(storefront.reputation.ratingCount) reviews")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(RewatchType.priceSmall)
                .foregroundStyle(Color.rewatch.primary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(label)
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: Reviews

    private func reviews(_ storefront: SellerStorefront) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("What buyers say")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)

            VStack(spacing: 0) {
                ForEach(Array(storefront.reviews.enumerated()), id: \.element.id) { index, review in
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            StarRating(rating: Double(review.rating))
                            if review.verifiedPurchase == true {
                                Text("Verified purchase")
                                    .font(RewatchType.caption)
                                    .foregroundStyle(Color.rewatch.success)
                            }
                            Spacer()
                            if let date = review.createdAt {
                                Text(date.formatted(.relative(presentation: .named)))
                                    .font(RewatchType.caption)
                                    .foregroundStyle(Color.rewatch.mutedForeground)
                            }
                        }
                        if let comment = review.comment, !comment.isEmpty {
                            Text(comment)
                                .font(RewatchType.body)
                                .foregroundStyle(Color.rewatch.secondaryForeground)
                                .lineSpacing(4)
                        }
                    }
                    .padding(Space.l)

                    if index < storefront.reviews.count - 1 {
                        Rectangle()
                            .fill(Color.rewatch.border)
                            .frame(height: 1)
                    }
                }
            }
            .background(Color.rewatch.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewatch.border, lineWidth: 1)
            )
        }
    }

    // MARK: Inventory

    @ViewBuilder
    private func inventorySection(_ storefront: SellerStorefront) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("In the window")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)
                .padding(.horizontal, Space.margin)

            if let inventory {
                if inventory.isLoadingFirst, inventory.listings.isEmpty {
                    inventorySkeleton
                } else if inventory.listings.isEmpty {
                    EmptyState(
                        icon: "clock",
                        title: "Nothing in the window",
                        message: "@\(storefront.username) has no live listings at the moment."
                    )
                } else {
                    LazyVGrid(
                        columns: rewatchGridColumns(typeSize, spacing: Space.l),
                        alignment: .leading,
                        spacing: Space.xl
                    ) {
                        ForEach(inventory.listings) { listing in
                            ListingGridCard(
                                listing: listing,
                                laneKey: "storefront",
                                zoomNamespace: zoomNamespace
                            )
                            // Row-tall, so every row of the card stays level
                            // with its neighbour's (see `listingCardPinsPrice`).
                            .frame(maxHeight: .infinity, alignment: .top)
                            .task {
                                await inventory.loadMoreIfNeeded(current: listing)
                            }
                        }
                    }
                    .padding(.horizontal, Space.margin)

                    if inventory.isLoadingMore {
                        HStack(spacing: Space.l) {
                            ListingCardSkeleton()
                            ListingCardSkeleton()
                        }
                        .padding(.horizontal, Space.margin)
                    }
                }
            } else {
                inventorySkeleton
            }
        }
    }

    private var inventorySkeleton: some View {
        LazyVGrid(
            columns: rewatchGridColumns(typeSize, spacing: Space.l),
            spacing: Space.xl
        ) {
            ForEach(0..<4, id: \.self) { _ in
                ListingCardSkeleton()
            }
        }
        .padding(.horizontal, Space.margin)
    }

    private var skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(spacing: Space.l) {
                    Circle().frame(width: 56, height: 56).shimmer()
                    VStack(alignment: .leading, spacing: Space.s) {
                        Rectangle().frame(width: 140, height: 18).shimmer()
                        Rectangle().frame(width: 100, height: 12).shimmer()
                    }
                }
                Rectangle().frame(maxWidth: .infinity).frame(height: 80).shimmer()
                HStack(spacing: Space.l) {
                    ListingCardSkeleton()
                    ListingCardSkeleton()
                }
            }
            .padding(Space.margin)
        }
        .disabled(true)
    }

    // MARK: Loading

    private func load() async {
        do {
            storefront = try await services.catalog.sellerStorefront(username: username)
            failed = false
            if inventory == nil {
                inventory = ResultsModel(
                    catalog: services.catalog,
                    filters: BrowseFilters(seller: username)
                )
                await inventory?.loadFirstPageIfNeeded()
            }
        } catch {
            if storefront == nil {
                failed = true
            }
        }
    }
}
