import CalibreDesign
import CalibreKit
import SwiftUI

/// The Community tab: today's question and polls up top, the own-data market
/// overview in the middle, and the Journal below. Guests can read everything;
/// voting funnels through the sign-in gate.
struct CommunityScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var isLoading = true
    @State private var loadFailed = false

    private var today: CommunityToday? { services.community.today }
    private var market: MarketOverview? { services.community.market }
    private var journal: JournalStore { JournalStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if isLoading, today == nil {
                    skeleton
                } else if today == nil, loadFailed {
                    EmptyState(
                        icon: "wifi.slash",
                        title: "Couldn't load the community",
                        message: "Check your connection and try again.",
                        actionTitle: "Try again"
                    ) {
                        Task { await load() }
                    }
                } else {
                    promptsSection
                    marketSection
                    journalSection
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loadFailed = false
        async let todayResult: Void = loadTodaySilently()
        async let marketResult: Void = loadMarketSilently()
        _ = await (todayResult, marketResult)
        isLoading = false
    }

    private func loadTodaySilently() async {
        do {
            _ = try await services.community.loadToday()
        } catch {
            if today == nil { loadFailed = true }
        }
    }

    private func loadMarketSilently() async {
        do {
            _ = try await services.community.loadMarket()
        } catch {
            // The market band just stays hidden; prompts still render.
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.l) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.calibre.card)
                    .frame(height: 150)
                    .shimmer()
            }
        }
    }

    // MARK: - Prompts

    @ViewBuilder
    private var promptsSection: some View {
        if let daily = today?.daily {
            CommunityPromptCard(prompt: daily, featured: true)
        }
        ForEach(today?.polls ?? []) { poll in
            CommunityPromptCard(prompt: poll, featured: false)
        }
        if let recent = today?.recent, !recent.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Recent results")
                    .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
                    .foregroundStyle(Color.calibre.foreground)
                ForEach(recent) { prompt in
                    CommunityPromptCard(prompt: prompt, featured: false)
                }
            }
        }
    }

    // MARK: - Market

    @ViewBuilder
    private var marketSection: some View {
        if let market {
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("The Calibre market")
                        .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Live asking prices and sales, computed from Calibre alone.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                HStack(spacing: Space.m) {
                    marketTile(label: "Live listings", value: "\(market.totals.activeListings)")
                    marketTile(label: "Brands", value: "\(market.totals.brands)")
                    marketTile(label: "Sold, 90 days", value: "\(market.totals.soldLast90Days)")
                }

                VStack(spacing: 0) {
                    ForEach(Array(market.brands.prefix(8).enumerated()), id: \.element.id) { index, brand in
                        if index > 0 {
                            Rectangle().fill(Color.calibre.border).frame(height: 1)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(brand.brand)
                                .font(CalibreType.bodyMedium)
                                .foregroundStyle(Color.calibre.foreground)
                            Text("\(brand.activeCount) live")
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                            Spacer()
                            Text(brand.askMedian.map { PriceFormatter.format(Decimal($0)) } ?? "—")
                                .font(CalibreType.bodyMedium)
                                .foregroundStyle(Color.calibre.foreground)
                        }
                        .padding(.vertical, Space.m)
                        .padding(.horizontal, Space.l)
                    }
                }
                .background(
                    Color.calibre.card,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Color.calibre.border, lineWidth: 1)
                )

                Text("Median asking price per brand · not an external price guide.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
    }

    private func marketTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label.uppercased())
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(value)
                .font(CalibreType.serif(.semiBold, 22, relativeTo: .title2))
                .foregroundStyle(Color.calibre.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(
            Color.calibre.card,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    // MARK: - Journal

    @ViewBuilder
    private var journalSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("The Journal")
                    .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
                    .foregroundStyle(Color.calibre.foreground)
                Spacer()
                NavigationLink(value: Route.journal) {
                    Text("All stories")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.primary)
                }
            }
            ForEach(journal.articles.prefix(3)) { article in
                NavigationLink(value: Route.journalArticle(article.id)) {
                    HStack(alignment: .top, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(article.category.uppercased())
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.primary)
                            Text(article.title)
                                .font(CalibreType.serif(.semiBold, 17, relativeTo: .headline))
                                .foregroundStyle(Color.calibre.foreground)
                                .multilineTextAlignment(.leading)
                            Text(article.readTime)
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        Spacer(minLength: 0)
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
                .buttonStyle(.plain)
            }
        }
    }
}

/// One question/poll card: options while open and unvoted, result bars after.
private struct CommunityPromptCard: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    let prompt: CommunityPrompt
    let featured: Bool

    @State private var voting = false

    private var showResults: Bool { prompt.results != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(prompt.kind == "daily" ? "QUESTION OF THE DAY" : "POLL")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.primary)
            Text(prompt.question)
                .font(CalibreType.serif(.semiBold, featured ? 22 : 18, relativeTo: .title3))
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if showResults {
                resultBars
            } else {
                optionButtons
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
                .strokeBorder(featured ? Color.calibre.primary.opacity(0.35) : Color.calibre.border, lineWidth: 1)
        )
    }

    private var optionButtons: some View {
        VStack(spacing: Space.s) {
            ForEach(prompt.options) { option in
                Button {
                    vote(option.key)
                } label: {
                    Text(option.label)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.m)
                        .background(
                            Color.calibre.background,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Color.calibre.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(voting)
            }
        }
    }

    private var resultBars: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(prompt.results?.options ?? []) { option in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text(option.label + (prompt.myVote == option.key ? " · your pick" : ""))
                            .font(prompt.myVote == option.key ? CalibreType.bodyMedium : CalibreType.body)
                            .foregroundStyle(
                                prompt.myVote == option.key
                                    ? Color.calibre.foreground
                                    : Color.calibre.mutedForeground
                            )
                        Spacer()
                        Text("\(option.percent)%")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.calibre.border.opacity(0.5))
                            Capsule()
                                .fill(
                                    prompt.myVote == option.key
                                        ? Color.calibre.primary
                                        : Color.calibre.primary.opacity(0.35)
                                )
                                .frame(width: max(proxy.size.width * CGFloat(option.percent) / 100, 6))
                        }
                    }
                    .frame(height: 6)
                }
            }
            Text("\(prompt.results?.totalVotes ?? 0) vote\((prompt.results?.totalVotes ?? 0) == 1 ? "" : "s")\(prompt.closed ? " · closed" : "")")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    private func vote(_ optionKey: String) {
        guard session.isAuthenticated else {
            services.auth.require("Sign in to vote and see the results") {}
            return
        }
        voting = true
        Task {
            defer { voting = false }
            do {
                Haptics.shared.play(.selection)
                _ = try await services.community.vote(promptID: prompt.id, option: optionKey)
            } catch {
                services.toasts.show(title: "Couldn't record your vote", message: "Please try again.")
            }
        }
    }
}
