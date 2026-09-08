import CalibreDesign
import CalibreKit
import SwiftUI

// MARK: - Where a module's action goes

/// The three navigation mechanisms this app has, as a feed action can reach
/// them. `HomeFeedRoute` decides which routes resolve at all and why.
enum FeedActionTarget {
    /// A push onto Home's own stack.
    case browse(BrowseDestination)
    /// A push through the shared router, which owns the tab that route lives in.
    case route(Route)
    /// A tab with no route of its own — the feed points at the room, not a row.
    case tab(AppTab)
    /// One Bite, opened from Home.
    case bite(String)
}

/// Resolves the feed's deep-link vocabulary against this app's screens.
///
/// The parsing — including which routes this build cannot place at all — lives
/// in `HomeFeedRoute`, where it is unit-tested. This is only the mapping onto
/// the three navigation mechanisms the app has.
func feedActionTarget(_ route: String) -> FeedActionTarget? {
    guard let parsed = HomeFeedRoute(route) else { return nil }
    switch parsed {
    case .buy:
        return .browse(.results(BrowseFilters(), title: "All Watches"))
    case .buyNewest:
        return .browse(.results(BrowseFilters(sort: .createdDesc), title: "Fresh Arrivals"))
    case .alerts:
        return .route(.alerts)
    case .support:
        return .route(.supportChat)
    case .community:
        return .tab(.community)
    case .vault:
        return .tab(.collection)
    case .listing(let id):
        return .route(.listing(id))
    case .offer(let id):
        return .route(.offer(id))
    case .order(let id):
        return .route(.order(id))
    case .journalArticle(let id):
        return .route(.journalArticle(id))
    case .bite(let slug):
        return .bite(slug)
    case .seller(let username):
        return .route(.seller(username))
    }
}

// MARK: - Card projection

extension HomeFeedCard {
    /// The shared card projection, carrying the server's selection reason.
    ///
    /// The reason is printed exactly as it was sent and is never composed
    /// here. `nil` means the server could not justify one, and the card says
    /// nothing rather than saying something plausible.
    var cardModel: ListingCardModel {
        let base = listing.cardModel
        return ListingCardModel(
            id: base.id,
            brand: base.brand,
            year: base.year,
            title: base.title,
            reference: base.reference,
            priceText: base.priceText,
            condition: base.condition,
            watcherCount: base.watcherCount,
            imageURL: base.imageURL,
            isVerifiedDealer: base.isVerifiedDealer,
            reason: reason?.text
        )
    }

    /// The same card for a lane that draws the signal chip itself.
    ///
    /// The chip and the watcher count want the same corner of the photograph,
    /// so a card carrying a signal gives the corner to the chip. Nothing else
    /// about the card changes.
    var laneCardModel: ListingCardModel {
        let base = cardModel
        guard signal != nil else { return base }
        return ListingCardModel(
            id: base.id,
            brand: base.brand,
            year: base.year,
            title: base.title,
            reference: base.reference,
            priceText: base.priceText,
            condition: base.condition,
            watcherCount: nil,
            imageURL: base.imageURL,
            isVerifiedDealer: base.isVerifiedDealer,
            reason: base.reason
        )
    }
}

/// One high-signal chip, as the server tinted it.
///
/// Neutral is the default and `drop` is the exception, so a tone named on the
/// server that this build has never heard of paints a readable chip instead of
/// an unpainted one.
struct FeedSignalChip: View {
    let signal: HomeFeedSignal

    private var tint: Color {
        signal.tone == "drop" ? Color.calibre.success : Color.calibre.primary
    }

    var body: some View {
        Text(signal.label)
            .font(CalibreType.label)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 4)
            .background(Color.calibre.background.opacity(0.95), in: Capsule())
    }
}

// MARK: - your_next_step

/// The one thing this member owes, worded by the server. A note, not a shelf:
/// no photograph, because the subject is a deadline rather than a watch.
struct FeedNextStepCard: View {
    let module: HomeFeedModule
    let step: HomeFeedStep
    let onAction: (FeedActionTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Eyebrow("Your next step", color: Color.calibre.primary)
                Spacer(minLength: 0)
                if let label = step.referenceLabel {
                    Text(label)
                        .font(CalibreType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }

            Text(module.title)
                .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = module.subtitle {
                Text(subtitle)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let due = step.dueAt {
                Text(Self.dueLine(due))
                    .font(CalibreType.label)
                    .foregroundStyle(due < .now ? Color.calibre.destructive : Color.calibre.mutedForeground)
            }

            if let action = module.action, let target = feedActionTarget(action.route) {
                Button(action.label) {
                    Haptics.shared.play(.press)
                    onAction(target)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.borderBright, lineWidth: 1)
        )
        .padding(.horizontal, Space.margin)
    }

    /// The server sends the deadline as-is, past or future, because an overdue
    /// wire is more urgent rather than less. Wording it is this side's job.
    ///
    /// The same ladder the web (`lib/homeFeed.ts`) and Android
    /// (`HomeFeedDue.kt`) read, in the same words. A calendar day cannot tell a
    /// wire due in twenty minutes from one due in eleven hours, and both of
    /// those used to read "Due today" here; the hours are the point.
    ///
    /// Clock-injectable so the wording can be reasoned about off a live clock.
    static func dueLine(_ due: Date, now: Date = .now) -> String {
        let hours = due.timeIntervalSince(now) / 3600
        if hours < 0 { return "Overdue" }
        if hours < 1 { return "Due within the hour" }
        if hours < 24 {
            let rounded = Int(hours.rounded())
            return "Due in \(rounded) \(rounded == 1 ? "hour" : "hours")"
        }
        let days = Int((hours / 24).rounded())
        return "Due in \(days) \(days == 1 ? "day" : "days")"
    }
}

// MARK: - saved_search_matches

/// New matches, as a compact stack. Deliberately not a lane of big cards: the
/// claim here is "this is the search you asked us to watch", and the reason
/// line under each row is the part worth reading.
struct FeedSavedSearchModule: View {
    let module: HomeFeedModule
    let onAction: (FeedActionTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            FeedModuleHeader(module: module, onAction: onAction)

            VStack(spacing: Space.s) {
                ForEach(module.cards) { card in
                    FeedCompactCardRow(card: card)
                }
            }
        }
        .padding(.horizontal, Space.margin)
    }
}

/// One match: a small square, the watch's identity, its price, and the
/// server's sentence about why it is here.
private struct FeedCompactCardRow: View {
    @Environment(\.browsePush) private var push

    let card: HomeFeedCard

    @ScaledMetric(relativeTo: .body) private var thumbSide: CGFloat = 64

    var body: some View {
        Button {
            push(.listing(card.listing.id, zoom: nil))
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                ListingImageWell(url: card.cardModel.imageURL, targetWidth: thumbSide * 3)
                    .frame(width: thumbSide, height: thumbSide)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(card.cardModel.brand)
                    Text(card.cardModel.title)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.leading)
                    Text(card.cardModel.priceText)
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)
                    if let reason = card.reason {
                        Text(reason.text)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                if let signal = card.signal {
                    FeedSignalChip(signal: signal)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this watch")
    }

    private var accessibilityLabel: String {
        [card.cardModel.brand, card.cardModel.title, card.cardModel.priceText, card.reason?.text]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

// MARK: - worth_a_look

/// The ranked shop window: every card the same size, in the server's order.
///
/// The lead card this module used to open with was a second card format for
/// the same watches — one more layout to keep honest, and a first row that read
/// as an advert rather than as the top of a ranking. Rank one is simply first
/// now, and nothing about a card says which rank it holds.
///
/// The title and the action are the server's, which is what fixed the shelf
/// this replaced: it labelled itself personally while being filled from popular
/// inventory, and its "View all" always asked for popular results. Home draws
/// this one under its own greeting, so the heading it arrives with is the one
/// thing the screen replaces.
struct FeedShopWindowModule: View {
    let module: HomeFeedModule
    let zoomNamespace: Namespace.ID
    let onAction: (FeedActionTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            FeedModuleHeader(module: module, onAction: onAction)
                .padding(.horizontal, Space.margin)

            FeedCardLane(cards: module.cards, laneKey: module.type, zoomNamespace: zoomNamespace)
        }
    }
}

/// A listing module's cards, in the lane footprint the app already uses. Every
/// card is the same card at the same size, and the order is the one it arrived
/// in.
private struct FeedCardLane: View {
    @Environment(\.browsePush) private var push

    let cards: [HomeFeedCard]
    let laneKey: String
    let zoomNamespace: Namespace.ID

    @ScaledMetric(relativeTo: .body) private var scaledCardWidth: CGFloat = 168
    private var cardWidth: CGFloat { calibreLaneCardWidth(scaledCardWidth) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Space.l) {
                ForEach(cards) { card in
                    let sourceID = "\(laneKey)-\(card.listing.id)"
                    Button {
                        push(.listing(
                            card.listing.id,
                            zoom: ListingZoomSource(id: sourceID, namespace: zoomNamespace)
                        ))
                    } label: {
                        ListingCard(model: card.laneCardModel) { url in
                            ListingImageWell(url: url)
                        }
                        // The chip lands in the photograph's top-right corner,
                        // which is where the watcher count sits — so
                        // `laneCardModel` takes the count off any card that has
                        // one. Two badges stacked in one corner is not a
                        // composition, and a price cut is the sharper claim.
                        .overlay(alignment: .topTrailing) {
                            if let signal = card.signal {
                                FeedSignalChip(signal: signal)
                                    .padding(Space.s)
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .matchedTransitionSource(id: sourceID, in: zoomNamespace)
                    .frame(width: cardWidth)
                    .accessibilityLabel(
                        [
                            card.signal?.label,
                            card.cardModel.brand,
                            card.cardModel.title,
                            card.cardModel.priceText,
                            card.reason?.text,
                        ]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                    )
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - todays_bite

/// The day's read, whole: the claim, the paragraph the desk wrote, who wrote
/// it, and what it was published against.
///
/// A Bite is one short paragraph by construction, so this prints the paragraph
/// rather than an excerpt and a promise. The sources travel with it — a claim
/// about the market that cannot be checked is an opinion — and they are real
/// links, which is why the card is not one large button: a tap target inside
/// another tap target is not reachable. The reading block opens the Bite, the
/// sources open themselves, and "Read it" is its own control.
///
/// An archive-slot Bite says so, beside its own original date, and the date is
/// stated once. Nothing here re-dates an old piece to look like today's.
struct FeedBiteModule: View {
    let module: HomeFeedModule
    let slot: String
    let bite: Bite
    let onOpen: (Bite) -> Void

    private var fromArchive: Bool { bite.isArchive || slot == "archive" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button {
                Haptics.shared.play(.press)
                onOpen(bite)
            } label: {
                reading
            }
            .buttonStyle(PressableStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens the full Bite")

            VStack(alignment: .leading, spacing: Space.s) {
                Text(byline)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)

                Button {
                    Haptics.shared.play(.press)
                    onOpen(bite)
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(module.action?.label ?? "Read it")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.primary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.calibre.primary)
                    }
                    .frame(minHeight: Space.touchTarget, alignment: .leading)
                }
                .buttonStyle(PressableStyle())

                if !bite.sources.isEmpty {
                    FeedBiteSources(sources: bite.sources)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .padding(.horizontal, Space.margin)
    }

    /// The part that opens the Bite. The phone's column is the reading measure
    /// — the app is drawn for one hand — so the paragraph needs no width of its
    /// own beyond the card's.
    private var reading: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let url = bite.image?.url {
                ListingImageWell(url: url, targetWidth: 1_200)
                    .frame(height: 120)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: Radius.box,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: Radius.box,
                            style: .continuous
                        )
                    )
                    .accessibilityLabel(bite.imageAlt ?? "")
                    .accessibilityHidden(bite.imageAlt == nil)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(module.title, color: Color.calibre.primary)

                if fromArchive {
                    BiteArchiveLabel(date: bite.date)
                }

                Text(bite.title)
                    .font(CalibreType.serif(.semiBold, 19, relativeTo: .title3))
                    .foregroundStyle(Color.calibre.foreground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Whole, not teased. Cutting it at three lines would put an
                // ellipsis through the only sentence the desk wrote, and leave
                // the card claiming less than it is holding.
                Text(bite.body)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.l)
            .padding(.top, bite.image?.url == nil ? Space.l : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The desk's name, and the piece's date when the archive label has not
    /// already given it.
    private var byline: String {
        fromArchive ? bite.author : "\(bite.author) · \(bite.date)"
    }

    /// The paragraph is in here because it is the Bite. Reading out a headline
    /// and a date and then stopping would hand a VoiceOver reader the promise
    /// of the piece and none of it.
    private var accessibilityLabel: String {
        let opening = fromArchive ? "From the archive, \(bite.date)" : bite.date
        return "\(module.title). \(opening). \(bite.title). \(bite.body)"
    }
}

/// What the claim was published against, as links a reader can actually
/// follow. Same shape as the Bite's own page, so a source reached from Home
/// behaves the way it does everywhere else.
private struct FeedBiteSources: View {
    let sources: [Bite.Source]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("Sources")
            ForEach(sources, id: \.self) { source in
                if let url = URL(string: source.href) {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            Text(source.label)
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.primary)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.calibre.primary)
                        }
                        .frame(minHeight: Space.touchTarget, alignment: .leading)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Source, \(source.label)")
                    .accessibilityHint("Opens in your browser")
                }
            }
        }
        .padding(.top, Space.xs)
    }
}

// MARK: - todays_poll

/// The day's question, as a card.
///
/// It is the one module a reader can answer, so it is drawn as a thing to
/// answer: the question in the serif that heads every other section, and under
/// it the options as full-width choice buttons in two columns. After a vote the
/// same two columns stay put and each option becomes a bar in the slot its
/// button held — the eye does not have to find the answer it just picked in a
/// new list.
///
/// Voting goes through the community endpoint and patches this one module. The
/// feed is not refetched: recomputing every other module to redraw a bar chart
/// would be entitled to move a card the reader is looking at. Nothing else is
/// recorded — a vote answers a question, it does not become a standing
/// statement about taste.
struct FeedPollModule: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    let module: HomeFeedModule
    let prompt: CommunityPrompt
    let onVoted: (CommunityPrompt) -> Void

    @State private var voting = false

    /// Two across only while half a phone can still hold an answer. At an
    /// accessibility size it cannot — "None of them — they earned it" in half a
    /// screen is a stack of fragments — so the grid becomes one column, the
    /// same rule the brand rail follows.
    private var columns: [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: Space.s)]
        }
        return [
            GridItem(.flexible(), spacing: Space.s),
            GridItem(.flexible(), spacing: Space.s),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(module.title, color: Color.calibre.primary)
                Text(prompt.question)
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let results = prompt.results {
                resultBars(results)
            } else if !prompt.closed {
                // A closed question is not answerable, so it is not offered as
                // one. With no results to show either, the question stands on
                // its own rather than under buttons that would do nothing.
                options
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .padding(.horizontal, Space.margin)
    }

    private var options: some View {
        LazyVGrid(columns: columns, spacing: Space.s) {
            ForEach(prompt.options) { option in
                Button {
                    vote(option.key)
                } label: {
                    Text(option.label)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                        // A two-word answer beside a two-line one leaves the
                        // short button floating in the middle of the row;
                        // stretching to the row's height puts both boxes on
                        // the same rule.
                        .frame(
                            maxWidth: .infinity,
                            minHeight: Space.touchTarget,
                            maxHeight: .infinity,
                            alignment: .leading
                        )
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
                .accessibilityHint("Answers today's question")
            }
        }
    }

    /// Every option's real count, zero included: an option nobody picked is not
    /// an option with no answer, and blanking it would leave the reader
    /// guessing whether it was even offered.
    private func resultBars(_ results: CommunityPrompt.Results) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            LazyVGrid(columns: columns, spacing: Space.s) {
                ForEach(results.options) { option in
                    FeedPollResultBar(option: option, mine: prompt.myVote == option.key)
                }
            }
            Text(totalLine(results))
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    private func totalLine(_ results: CommunityPrompt.Results) -> String {
        let votes = "\(results.totalVotes) vote\(results.totalVotes == 1 ? "" : "s")"
        return prompt.closed ? "\(votes) · closed" : votes
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
                onVoted(try await services.community.vote(promptID: prompt.id, option: optionKey))
            } catch {
                services.toasts.show(title: "Couldn't record your vote", message: "Please try again.")
            }
        }
    }
}

/// One answered option, in the slot its choice button held.
///
/// The row is drawn for every option and only the fill is the share, so an
/// option nobody picked is an empty row rather than a missing one. The reader's
/// own answer keeps the copper outline it was chosen with.
private struct FeedPollResultBar: View {
    let option: CommunityPrompt.ResultOption
    let mine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.label)
                .font(mine ? CalibreType.bodyMedium : CalibreType.body)
                .foregroundStyle(Color.calibre.foreground)
                .multilineTextAlignment(.leading)
            HStack(spacing: Space.xs) {
                Text("\(option.percent)%")
                    .font(CalibreType.bodyMedium)
                    .monospacedDigit()
                    .foregroundStyle(Color.calibre.foreground)
                Text("\(option.votes)")
                    .font(CalibreType.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.calibre.mutedForeground)
                if mine {
                    Text("Your pick")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(
            maxWidth: .infinity,
            minHeight: Space.touchTarget,
            maxHeight: .infinity,
            alignment: .leading
        )
        // The fill is measured against the row it is drawn in — a background is
        // proposed exactly the size of what it sits behind, which a `ZStack`
        // sibling is not.
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(mine ? Color.calibre.primary.opacity(0.22) : Color.calibre.secondary)
                    .frame(width: proxy.size.width * CGFloat(option.percent) / 100)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(mine ? Color.calibre.primary : Color.calibre.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(option.label), \(option.votes) \(option.votes == 1 ? "vote" : "votes"), \(option.percent) percent\(mine ? ", your pick" : "")"
        )
    }
}

// MARK: - your_collection

/// The member's own watches: a strip of what they own, and only the figures
/// the Vault itself would state for them.
struct FeedCollectionModule: View {
    let module: HomeFeedModule
    let collection: HomeFeedCollection
    let onAction: (FeedActionTarget) -> Void

    @ScaledMetric(relativeTo: .body) private var thumbSide: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            FeedModuleHeader(module: module, onAction: onAction)

            HStack(alignment: .top, spacing: Space.m) {
                ForEach(collection.watches) { watch in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ListingImageWell(
                            url: watch.photoUrl.flatMap { URL(string: $0) },
                            targetWidth: thumbSide * 3
                        )
                        .frame(width: thumbSide, height: thumbSide)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            if watch.authenticated {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.calibre.primary)
                                    .padding(5)
                            }
                        }
                        Text(watch.displayTitle)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                            .frame(width: thumbSide, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        watch.authenticated
                            ? "\(watch.displayTitle), authenticated"
                            : watch.displayTitle
                    )
                }
                Spacer(minLength: 0)
            }

            Text(summary)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.margin)
    }

    /// The valued count is said out loud beside the total, so the figure can
    /// never be read as what the whole collection is worth. With nothing
    /// valued there is no total to print, and the counts stand alone.
    private var summary: String {
        let watches = "\(collection.watchCount) watch\(collection.watchCount == 1 ? "" : "es")"
        let authenticated = "\(collection.authenticatedCount) authenticated"
        guard let total = collection.estimatedTotal,
              let value = Decimal(string: total, locale: Locale(identifier: "en_US_POSIX")),
              collection.valuedCount > 0 else {
            return "\(watches) · \(authenticated)"
        }
        let priced = PriceFormatter.format(value)
        return "\(watches) · \(authenticated) · \(priced) across \(collection.valuedCount) valued"
    }
}

// MARK: - end_of_feed

/// The feed's own ending, in the server's words. Everything below it on this
/// screen is the app's furniture and is not part of the feed.
struct FeedEndModule: View {
    let module: HomeFeedModule
    let state: String
    let onAction: (FeedActionTarget) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Rectangle()
                .fill(Color.calibre.border)
                .frame(height: 1)

            Text(module.title)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            // A degraded feed carries no CTA of its own — the retry is the
            // action, and it belongs to this side.
            if state == "degraded" {
                Button("Try again") {
                    Haptics.shared.play(.press)
                    onRetry()
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
            } else if let action = module.action, let target = feedActionTarget(action.route) {
                Button(action.label) {
                    Haptics.shared.play(.press)
                    onAction(target)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
            }
        }
        .padding(.horizontal, Space.margin)
    }
}

// MARK: - Shared header

/// A module's title and its "view all", both server-composed. The action is
/// dropped when this build cannot place its route.
struct FeedModuleHeader: View {
    let module: HomeFeedModule
    let onAction: (FeedActionTarget) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = module.subtitle {
                    Text(subtitle)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s)
            if let action = module.action, let target = feedActionTarget(action.route) {
                Button(action.label) {
                    onAction(target)
                }
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.primary)
                .buttonStyle(PressableStyle())
                .frame(minHeight: Space.touchTarget)
                .accessibilityLabel(action.label)
            }
        }
    }
}
