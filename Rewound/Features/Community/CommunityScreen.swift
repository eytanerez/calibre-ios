import RewoundDesign
import RewoundKit
import SwiftUI

/// The Community tab's quiet rooms: Today (the day's two questions — one about
/// watches, one about Rewound), Market (reference-level pricing), and Bites
/// (the desk's short, sourced notes). Guests can read everything; voting
/// funnels through the sign-in gate.
///
/// Bites is the editorial room. The Journal room that used to stand here is
/// gone: Bites replaced it as the thing the desk publishes, and a room holding
/// a second, older editorial feed beside it is a choice a reader should not
/// have to make.
struct CommunityScreen: View {
    enum Section: Hashable {
        case today, market, bites
    }

    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var section: Section = .today
    @State private var isLoading = true
    @State private var loadFailed = false

    private var today: CommunityToday? { services.community.today }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabs(
                selection: $section,
                items: [
                    (value: .today, label: "Today"),
                    (value: .market, label: "Market"),
                    (value: .bites, label: "Bites"),
                ]
            )
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s)

            ScrollView {
                Group {
                    switch section {
                    case .today: todaySection
                    case .market: marketSection
                    case .bites: bitesSection
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rewoundPageSwipe(selection: $section, values: [.today, .market, .bites])
        .rewoundPageBackground()
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
        do {
            _ = try await services.community.loadToday(authenticated: session.isAuthenticated)
        } catch {
            if today == nil { loadFailed = true }
        }
        isLoading = false
    }

    /// Today's two questions, drawn as the real cards with stand-in words.
    /// Three 140pt boxes stood in for two cards twice that height, and the
    /// page jumped when they landed.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            ForEach([CommunityPromptKind.watch, .siteFeedback], id: \.self) { kind in
                CommunityPromptCard(prompt: .skeleton(kind: kind), featured: true)
            }
        }
        .skeleton()
    }

    // MARK: - Today

    @ViewBuilder
    private var todaySection: some View {
        if isLoading, today == nil {
            skeleton
        } else if today == nil, loadFailed {
            EmptyState(
                icon: "wifi.slash",
                title: "Couldn't load today's questions",
                message: "Check your connection and try again.",
                actionTitle: "Try again"
            ) {
                await load()
            }
        } else {
            VStack(alignment: .leading, spacing: Space.xxl) {
                // Both lanes, in asking order. A lane with nothing in it says
                // so in its own words rather than being left out — a reader
                // who came back for the watch question should be told it is
                // the watch question that ran dry.
                let live = today?.liveLanes ?? []
                if live.isEmpty {
                    Text("Today's questions are being wound. Check back soon.")
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Space.xxl)
                } else {
                    ForEach(live) { lane in
                        if let prompt = lane.prompt {
                            CommunityPromptCard(prompt: prompt, featured: true)
                        }
                    }
                    ForEach(today?.dryLanes ?? []) { lane in
                        Text(lane.voice.emptyLane)
                            .font(RewoundType.body)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let recent = today?.recent, !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Space.m) {
                        sectionHeader("How the community answered")
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, prompt in
                                if index > 0 {
                                    Rectangle().fill(Color.rewound.border).frame(height: 1)
                                }
                                NavigationLink(value: Route.poll(prompt)) {
                                    RecentResultRow(prompt: prompt)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .background(
                            Color.rewound.card,
                            in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                                .strokeBorder(Color.rewound.border, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Market

    private var marketSection: some View {
        MarketBoardView()
    }

    // MARK: - Bites

    /// The whole record, newest first, drawn by the same list the Bites screen
    /// draws — not a trimmed copy of it that would drift.
    private var bitesSection: some View {
        BitesArchiveList()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(RewoundType.serif(.semiBold, 20, relativeTo: .title3))
            .foregroundStyle(Color.rewound.foreground)
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
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
                .multilineTextAlignment(.leading)
            if let winner, let results = prompt.results, results.totalVotes > 0 {
                Text("\u{201C}\(winner.label)\u{201D} · \(winner.percent)% of \(results.totalVotes) vote\(results.totalVotes == 1 ? "" : "s")")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
            } else {
                Text("No votes were cast.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.l)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rewound.mutedForeground)
                .padding(.trailing, Space.l)
        }
    }
}

/// A live question: options while unanswered, refined result bars after. The
/// eyebrow names which lane it belongs to, because the day asks two and they
/// are two different invitations.
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
                HStack(alignment: .firstTextBaseline) {
                    Text((prompt.closed ? prompt.voice.closedEyebrow : prompt.voice.eyebrow).uppercased())
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.primary)
                    Spacer()
                    ShareLink(item: prompt.shareURL, message: Text(prompt.shareText)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.rewound.mutedForeground)
                    }
                    .accessibilityLabel("Share this question")
                }
                Text(prompt.question)
                    .font(RewoundType.serif(.semiBold, featured ? 24 : 18, relativeTo: featured ? .title2 : .title3))
                    .foregroundStyle(Color.rewound.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if !prompt.closed, !prompt.voice.invitation.isEmpty {
                    Text(prompt.voice.invitation)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            Color.rewound.card,
            in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
    }

    private var optionButtons: some View {
        VStack(spacing: Space.s) {
            ForEach(prompt.options) { option in
                Button {
                    vote(option.key)
                } label: {
                    Text(option.label)
                        .font(RewoundType.bodyMedium)
                        .foregroundStyle(Color.rewound.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.l)
                        .padding(.vertical, Space.m)
                        .background(
                            Color.rewound.background,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Color.rewound.border, lineWidth: 1)
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
                            .font(prompt.myVote == option.key ? RewoundType.bodyMedium : RewoundType.body)
                            .foregroundStyle(
                                prompt.myVote == option.key
                                    ? Color.rewound.foreground
                                    : Color.rewound.mutedForeground
                            )
                        if prompt.myVote == option.key {
                            Text("Your pick")
                                .font(RewoundType.label)
                                .foregroundStyle(Color.rewound.primary)
                        }
                        Spacer()
                        Text("\(option.percent)%")
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.rewound.border.opacity(0.45))
                            Capsule()
                                .fill(
                                    prompt.myVote == option.key
                                        ? Color.rewound.primary
                                        : Color.rewound.primary.opacity(0.3)
                                )
                                .frame(width: max(proxy.size.width * CGFloat(option.percent) / 100, 6))
                        }
                    }
                    .frame(height: 5)
                }
            }
            Text("\(prompt.results?.totalVotes ?? 0) vote\((prompt.results?.totalVotes ?? 0) == 1 ? "" : "s")\(prompt.closed ? " · closed" : "")")
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
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
