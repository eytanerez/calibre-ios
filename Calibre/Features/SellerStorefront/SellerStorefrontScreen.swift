import CalibreDesign
import CalibreKit
import SwiftUI

/// A seller's public storefront: header with reputation, recent reviews, and
/// the paged grid of their active listings.
struct SellerStorefrontScreen: View {
    @Environment(AppServices.self) private var services

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
                    Task { await load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                skeleton
            }
        }
        .background(Color.calibre.background)
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
                            .font(CalibreType.sectionTitle)
                            .foregroundStyle(Color.calibre.foreground)
                        if storefront.isVerifiedDealer {
                            StatusBadge("Dealer", tone: .info)
                        }
                    }
                    if let since = storefront.memberSince {
                        Text("Member since \(since.formatted(.dateTime.month(.wide).year()))")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }
            }

            HStack(spacing: Space.xl) {
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
                                .font(CalibreType.priceSmall)
                                .foregroundStyle(Color.calibre.foreground)
                        }
                        Text(storefront.reputation.ratingCount == 1 ? "1 review" : "\(storefront.reputation.ratingCount) reviews")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }
            }

            if let bio = storefront.bio, !bio.isEmpty {
                Text(bio)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .lineSpacing(5)
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(CalibreType.priceSmall)
                .foregroundStyle(Color.calibre.foreground)
            Text(label)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    // MARK: Reviews

    private func reviews(_ storefront: SellerStorefront) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("What buyers say")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            VStack(spacing: 0) {
                ForEach(Array(storefront.reviews.enumerated()), id: \.element.id) { index, review in
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            StarRating(rating: Double(review.rating))
                            if review.verifiedPurchase == true {
                                Text("Verified purchase")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.success)
                            }
                            Spacer()
                            if let date = review.createdAt {
                                Text(date.formatted(.relative(presentation: .named)))
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                            }
                        }
                        if let comment = review.comment, !comment.isEmpty {
                            Text(comment)
                                .font(CalibreType.body)
                                .foregroundStyle(Color.calibre.secondaryForeground)
                                .lineSpacing(4)
                        }
                    }
                    .padding(Space.l)

                    if index < storefront.reviews.count - 1 {
                        Rectangle()
                            .fill(Color.calibre.border)
                            .frame(height: 1)
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

    // MARK: Inventory

    @ViewBuilder
    private func inventorySection(_ storefront: SellerStorefront) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("In the window")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
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
                        columns: [
                            GridItem(.flexible(), spacing: Space.l),
                            GridItem(.flexible(), spacing: Space.l),
                        ],
                        alignment: .leading,
                        spacing: Space.xl
                    ) {
                        ForEach(inventory.listings) { listing in
                            ListingGridCard(
                                listing: listing,
                                laneKey: "storefront",
                                zoomNamespace: zoomNamespace
                            )
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
