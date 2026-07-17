import CalibreDesign
import CalibreKit
import SwiftUI

/// The Community tab, split into three quiet rooms: Today (the daily question
/// and polls), Market (reference-level pricing), and the Journal. Guests can
/// read everything; voting funnels through the sign-in gate.
struct CommunityScreen: View {
    enum Section: Hashable {
        case today, market, journal
    }

    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var section: Section = .today
    @State private var isLoading = true
    @State private var loadFailed = false

    private var today: CommunityToday? { services.community.today }
    private var market: MarketOverview? { services.community.market }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabs(
                selection: $section,
                items: [
                    (value: .today, label: "Today"),
                    (value: .market, label: "Market"),
                    (value: .journal, label: "Journal"),
                ]
            )
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s)

            ScrollView {
                Group {
                    switch section {
                    case .today: todaySection
                    case .market: marketSection
                    case .journal: journalSection
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: session.isAuthenticated) {
            // Votes ride the session; refresh so a fresh sign-in sees theirs.
            Task { await load() }
        }
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
            _ = try await services.community.loadToday(authenticated: session.isAuthenticated)
        } catch {
            if today == nil { loadFailed = true }
        }
    }

    private func loadMarketSilently() async {
        do {
            _ = try await services.community.loadMarket()
        } catch {
            // The market section shows its own quiet empty state.
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.l) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.calibre.card)
                    .frame(height: 140)
                    .shimmer()
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todaySection: some View {
        if isLoading, today == nil {
            skeleton
        } else if today == nil, loadFailed {
            EmptyState(
                icon: "wifi.slash",
                title: "Couldn't load today's question",
                message: "Check your connection and try again.",
                actionTitle: "Try again"
            ) {
                Task { await load() }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.xxl) {
                if let daily = today?.daily {
                    CommunityPromptCard(prompt: daily, featured: true)
                } else {
                    Text("Today's question is being wound. Check back soon.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Space.xxl)
                }

                if let polls = today?.polls, !polls.isEmpty {
                    VStack(alignment: .leading, spacing: Space.l) {
                        sectionHeader("Open polls")
                        ForEach(polls) { poll in
                            CommunityPromptCard(prompt: poll, featured: false)
                        }
                    }
                }

                if let recent = today?.recent, !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Space.m) {
                        sectionHeader("How the community answered")
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, prompt in
                                if index > 0 {
                                    Rectangle().fill(Color.calibre.border).frame(height: 1)
                                }
                                RecentResultRow(prompt: prompt)
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
                    }
                }
            }
        }
    }

    // MARK: - Market

    @ViewBuilder
    private var marketSection: some View {
        if let market {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("The market on Calibre")
                        .font(CalibreType.serif(.semiBold, 24, relativeTo: .title2))
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Live listings and completed, authenticated sales.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                HStack(spacing: Space.m) {
                    marketTile(label: "Live", value: market.totals.activeListings.formatted())
                    marketTile(label: "Brands", value: market.totals.brands.formatted())
                    marketTile(label: "Sold · 90d", value: market.totals.soldLast90Days.formatted())
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    sectionHeader("Median asking price")
                    VStack(spacing: 0) {
                        ForEach(Array(market.brands.prefix(10).enumerated()), id: \.element.id) { index, brand in
                            if index > 0 {
                                Rectangle().fill(Color.calibre.border).frame(height: 1)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                Text(brand.brand)
                                    .font(CalibreType.bodyMedium)
                                    .foregroundStyle(Color.calibre.foreground)
                                    .lineLimit(1)
                                Spacer(minLength: Space.m)
                                Text("\(brand.activeCount)")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                                    .monospacedDigit()
                                Text(brand.askMedian.map { PriceFormatter.format(Decimal($0)) } ?? "—")
                                    .font(CalibreType.bodyMedium)
                                    .foregroundStyle(Color.calibre.foreground)
                                    .monospacedDigit()
                                    .frame(minWidth: 84, alignment: .trailing)
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
                }
            }
        } else if isLoading {
            skeleton
        } else {
            EmptyState(
                icon: "chart.line.uptrend.xyaxis",
                title: "Market data is warming up",
                message: "Check back in a moment.",
                actionTitle: "Refresh"
            ) {
                Task { await load() }
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
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
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

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ForEach(JournalStore.shared.articles) { article in
                NavigationLink(value: Route.journalArticle(article.id)) {
                    JournalTeaserRow(article: article)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
            .foregroundStyle(Color.calibre.foreground)
    }
}

/// One Journal article row: thumbnail, category, title, byline — the same
/// quiet editorial voice as the Journal index itself.
private struct JournalTeaserRow: View {
    let article: JournalArticle

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Group {
                if let image = JournalStore.image(named: article.image) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.calibre.border
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(article.category.uppercased())
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.primary)
                Text(article.title)
                    .font(CalibreType.serif(.semiBold, 17, relativeTo: .headline))
                    .foregroundStyle(Color.calibre.foreground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Text(article.readTime)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A closed prompt, condensed to one line of result: the winning answer and
/// the turnout — history without the clutter.
private struct RecentResultRow: View {
    let prompt: CommunityPrompt

    private var winner: CommunityPrompt.ResultOption? {
        prompt.results?.options.max { $0.votes < $1.votes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(prompt.question)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .multilineTextAlignment(.leading)
            if let winner, let results = prompt.results, results.totalVotes > 0 {
                Text("\u{201C}\(winner.label)\u{201D} · \(winner.percent)% of \(results.totalVotes) vote\(results.totalVotes == 1 ? "" : "s")")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            } else {
                Text("No votes were cast.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.l)
    }
}

/// A live question or poll: options while unanswered, refined result bars
/// after. The featured daily gets the serif spotlight.
struct CommunityPromptCard: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    let prompt: CommunityPrompt
    let featured: Bool

    @State private var voting = false

    private var showResults: Bool { prompt.results != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(prompt.kind == "daily" ? "QUESTION OF THE DAY" : "POLL")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.primary)
                Text(prompt.question)
                    .font(CalibreType.serif(.semiBold, featured ? 24 : 18, relativeTo: featured ? .title2 : .title3))
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showResults {
                resultBars
            } else {
                optionButtons
            }
        }
        .padding(featured ? Space.xl : Space.l)
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
                        .padding(.horizontal, Space.l)
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
                .buttonStyle(PressableStyle())
                .disabled(voting)
            }
        }
    }

    private var resultBars: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(prompt.results?.options ?? []) { option in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(option.label)
                            .font(prompt.myVote == option.key ? CalibreType.bodyMedium : CalibreType.body)
                            .foregroundStyle(
                                prompt.myVote == option.key
                                    ? Color.calibre.foreground
                                    : Color.calibre.mutedForeground
                            )
                        if prompt.myVote == option.key {
                            Text("Your pick")
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.primary)
                        }
                        Spacer()
                        Text("\(option.percent)%")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.calibre.border.opacity(0.45))
                            Capsule()
                                .fill(
                                    prompt.myVote == option.key
                                        ? Color.calibre.primary
                                        : Color.calibre.primary.opacity(0.3)
                                )
                                .frame(width: max(proxy.size.width * CGFloat(option.percent) / 100, 6))
                        }
                    }
                    .frame(height: 5)
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
