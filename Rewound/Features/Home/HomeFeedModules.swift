import RewoundDesign
import RewoundKit
import NukeUI
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
    /// here. `nil` means the server could not justify one — or that the card
    /// is a fill-in, which nobody justified — and the card says nothing rather
    /// than saying something plausible.
    ///
    /// `reservesReason` is the lane's answer, not this card's: the reason now
    /// sits above the price, so a card with nothing to say has to hold the
    /// space anyway or its price climbs above its neighbors'. Only the lane
    /// can see all of its cards, so only the lane can decide.
    func cardModel(reservesReason: Bool = false, inCart: Bool = false) -> ListingCardModel {
        let base = listing.cardModel(inCart: inCart)
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
            isInCart: base.isInCart,
            reason: reasonLine,
            reservesReasonLine: reservesReason
        )
    }

    /// The shared card projection, carrying the server's selection reason and
    /// reserving nothing.
    var cardModel: ListingCardModel { cardModel() }

    /// The same card for a lane that draws the signal chip itself.
    ///
    /// The chip and the watcher count want the same corner of the photograph,
    /// so a card carrying a signal gives the corner to the chip. The
    /// condition pill moves out too, not because it competes with the chip
    /// for a corner, but because the two are drawn together by
    /// `FeedCardLane`'s own overlay (`LaneCardBadges`) so their combined
    /// width can be measured — a card that also drew `ConditionPill`
    /// internally, top-leading, would put two condition pills on screen.
    /// Nothing else about the card changes.
    func laneCardModel(reservesReason: Bool, inCart: Bool = false) -> ListingCardModel {
        let base = cardModel(reservesReason: reservesReason, inCart: inCart)
        guard signal != nil else { return base }
        return ListingCardModel(
            id: base.id,
            brand: base.brand,
            year: base.year,
            title: base.title,
            reference: base.reference,
            priceText: base.priceText,
            condition: nil,
            watcherCount: nil,
            imageURL: base.imageURL,
            isVerifiedDealer: base.isVerifiedDealer,
            isInCart: base.isInCart,
            reason: base.reason,
            reservesReasonLine: base.reservesReasonLine
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
        signal.tone == "drop" ? Color.rewound.success : Color.rewound.primary
    }

    var body: some View {
        Text(signal.label)
            .font(RewoundType.label)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 4)
            .background(Color.rewound.background.opacity(0.95), in: Capsule())
    }
}

/// The condition pill and the signal chip, sharing one photograph when both
/// are present.
///
/// Both used to be pinned to their own corner with no idea the other one
/// existed — fine while every condition was one word ("New") and every
/// signal was short, but "Like New" beside "Just listed" is wider than a
/// lane card, and two absolutely-positioned pills with no shared layout
/// don't notice until they're drawn on top of each other.
///
/// `ViewThatFits` tries the row first, which is pixel-for-pixel what this
/// used to look like whenever it fit. When the row would overrun the
/// photograph it falls back to a column instead of letting the two
/// collide — a long condition or a long signal wraps to its own line
/// rather than either one truncating.
private struct LaneCardBadges: View {
    let condition: String
    let signal: HomeFeedSignal

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.s) { pills }
            VStack(alignment: .leading, spacing: Space.s) { pills }
        }
    }

    @ViewBuilder private var pills: some View {
        ConditionPill(condition)
        FeedSignalChip(signal: signal)
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
                Eyebrow("Your next step", color: Color.rewound.primary)
                Spacer(minLength: 0)
                if let label = step.referenceLabel {
                    Text(label)
                        .font(RewoundType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
            }

            Text(module.title)
                .font(RewoundType.serif(.semiBold, 20, relativeTo: .title3))
                .foregroundStyle(Color.rewound.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = module.subtitle {
                Text(subtitle)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let due = step.dueAt {
                Text(Self.dueLine(due))
                    .font(RewoundType.label)
                    .foregroundStyle(due < .now ? Color.rewound.destructive : Color.rewound.mutedForeground)
            }

            if let action = module.action, let target = feedActionTarget(action.route) {
                Button(action.label) {
                    Haptics.shared.play(.press)
                    onAction(target)
                }
                .buttonStyle(.rewound(.primary, fullWidth: true))
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.borderBright, lineWidth: 1)
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
                        .font(RewoundType.bodyMedium)
                        .foregroundStyle(Color.rewound.foreground)
                        .multilineTextAlignment(.leading)
                    Text(card.cardModel.priceText)
                        .font(RewoundType.priceSmall)
                        .foregroundStyle(Color.rewound.foreground)
                    if let reason = card.reasonLine {
                        Text(reason)
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
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
            .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this watch")
    }

    private var accessibilityLabel: String {
        [card.cardModel.brand, card.cardModel.title, card.cardModel.priceText, card.reasonLine]
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
/// this replaced: it labeled itself personally while being filled from popular
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
///
/// Every card the server sent is drawn, fill-ins included. The site's grid
/// trims itself to complete rows because a grid can end on a ragged one; this
/// is a lane — one row that scrolls — so every card is in a complete row by
/// construction, and cutting it would only shorten the scroll. What separates
/// a fill-in from a ranked card is that it prints no reason (`reasonLine`),
/// and nothing else about it says which it is.
private struct FeedCardLane: View {
    @Environment(\.browsePush) private var push
    /// Read for one thing: whether each card's watch is already in the bag.
    @Environment(AppServices.self) private var services

    let cards: [HomeFeedCard]
    let laneKey: String
    let zoomNamespace: Namespace.ID

    @ScaledMetric(relativeTo: .body) private var scaledCardWidth: CGFloat = 168
    private var cardWidth: CGFloat { rewoundLaneCardWidth(scaledCardWidth) }

    /// Whether anything in this lane was justified. If one card carries a
    /// reason then every card in the lane holds the space for one, because the
    /// reason sits above the price and an unheld slot lifts that card's price
    /// clear of its neighbors'. A lane where the server justified nothing —
    /// recently viewed, say — spends no space at all.
    private var reservesReason: Bool {
        cards.contains { $0.reasonLine != nil }
    }

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
                        ListingCard(
                            model: card.laneCardModel(
                                reservesReason: reservesReason,
                                inCart: services.commerce.isInCart(listingID: card.listing.id)
                            )
                        ) { url in
                            ListingImageWell(url: url)
                        }
                        // The chip lands in the photograph's top-right corner,
                        // which is where the watcher count sits — so
                        // `laneCardModel` takes the count off any card that has
                        // one. Two badges stacked in one corner is not a
                        // composition, and a price cut is the sharper claim.
                        //
                        // When this card also has a condition, `laneCardModel`
                        // leaves ConditionPill undrawn too, and it comes back
                        // here paired with the chip in `LaneCardBadges`, which
                        // measures the two together instead of pinning each to
                        // its own corner and hoping they never meet.
                        .overlay(alignment: .topTrailing) {
                            if let signal = card.signal, card.cardModel.condition == nil {
                                FeedSignalChip(signal: signal)
                                    .padding(Space.s)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let signal = card.signal, let condition = card.cardModel.condition {
                                LaneCardBadges(condition: condition, signal: signal)
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
                            card.reasonLine,
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

/// The day's read, as a headline.
///
/// Only the title is on Home: the eyebrow that names the slot, the topic, an
/// archive chip when the pick came from the archive, and the title itself. The
/// paragraph, the author, the date, the correction and the sources all live on
/// the Bite's own page, and the whole block is one button to it — a headline
/// that opens a read, rather than the read printed between two shelves of
/// watches. The site draws the same module the same way.
///
/// The route is the server's when it sent one (`bites/<id>`) and the Bite's
/// own page otherwise: a Bite always has a page, so this module always has
/// somewhere to go, and a route this build cannot place falls back the same
/// way rather than leaving the headline dead.
///
/// Not a card. The poll below it is one, and two boxes in a row read as two
/// adverts; a rule above and a serif headline is what marks this as editorial.
struct FeedBiteModule: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let module: HomeFeedModule
    let slot: String
    let bite: Bite
    let onOpen: (FeedActionTarget) -> Void

    private var fromArchive: Bool { bite.isArchive || slot == "archive" }

    private var destination: FeedActionTarget {
        module.action.flatMap { feedActionTarget($0.route) } ?? .bite(bite.id)
    }

    /// The eyebrow row sits on one line while it fits. At an accessibility
    /// size three labels across one phone do not, so they stack — the same
    /// rule the brand rail and the poll's options follow.
    private var eyebrowRow: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
            : AnyLayout(HStackLayout(spacing: Space.s))
    }

    var body: some View {
        Button {
            Haptics.shared.play(.press)
            onOpen(destination)
        } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                Rectangle()
                    .fill(Color.rewound.border)
                    .frame(height: 1)

                HStack(spacing: Space.s) {
                    Eyebrow(module.title, color: Color.rewound.primary)
                    Spacer(minLength: Space.s)
                    if fromArchive {
                        FeedBiteArchiveChip()
                    }
                }
                .padding(.top, Space.s)

                if !bite.topic.isEmpty {
                    Eyebrow(bite.topic)
                }

                biteHeadline

                HStack(spacing: Space.xs) {
                    Text(module.action?.label ?? "Read it")
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.primary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.rewound.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the full Bite")
        .padding(.horizontal, Space.margin)
    }

    @ViewBuilder
    private var biteHeadline: some View {
        if let imageURL = bite.image?.url {
            LazyImage(url: imageURL) { state in
                if let image = state.image {
                    ZStack(alignment: .bottomLeading) {
                        image
                            .resizable()
                            .scaledToFill()
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        headline(color: Color(white: 1))
                            .padding(Space.l)
                    }
                } else {
                    ZStack(alignment: .bottomLeading) {
                        Color.rewound.accent
                        if state.error == nil {
                            Rectangle().fill(Color.rewound.secondary).shimmer()
                        }
                        headline(color: Color.rewound.foreground)
                            .padding(Space.l)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 176, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
        } else {
            headline(color: Color.rewound.foreground)
        }
    }

    private func headline(color: Color) -> some View {
        Text(bite.title)
            .font(RewoundType.sectionTitle)
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What is on screen and nothing more: the slot, the archive note when
    /// there is one, the topic, the headline. The paragraph is on the page
    /// this opens, for a VoiceOver reader as for anyone else.
    private var accessibilityLabel: String {
        [
            module.title,
            fromArchive ? "From the archive" : nil,
            bite.topic.isEmpty ? nil : bite.topic,
            bite.title,
            bite.imageAlt,
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}

/// "From the archive", without the date. The Bite's own page states the
/// original date beside this label; Home states only that the pick is an old
/// one, and never re-dates it.
private struct FeedBiteArchiveChip: View {
    var body: some View {
        Text("From the archive")
            .font(RewoundType.label)
            .foregroundStyle(Color.rewound.accentForeground)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 5)
            .background(Color.rewound.accent.opacity(0.7), in: Capsule())
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
                Eyebrow(module.title, color: Color.rewound.primary)
                Text(prompt.question)
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
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
        .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
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
                        .font(RewoundType.bodyMedium)
                        .foregroundStyle(Color.rewound.foreground)
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
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
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
                .font(mine ? RewoundType.bodyMedium : RewoundType.body)
                .foregroundStyle(Color.rewound.foreground)
                .multilineTextAlignment(.leading)
            HStack(spacing: Space.xs) {
                Text("\(option.percent)%")
                    .font(RewoundType.bodyMedium)
                    .monospacedDigit()
                    .foregroundStyle(Color.rewound.foreground)
                Text("\(option.votes)")
                    .font(RewoundType.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.rewound.mutedForeground)
                if mine {
                    Text("Your pick")
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.primary)
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
                    .fill(mine ? Color.rewound.primary.opacity(0.22) : Color.rewound.secondary)
                    .frame(width: proxy.size.width * CGFloat(option.percent) / 100)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(mine ? Color.rewound.primary : Color.rewound.border, lineWidth: 1)
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
                                    .foregroundStyle(Color.rewound.primary)
                                    .padding(5)
                            }
                        }
                        Text(watch.displayTitle)
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.secondaryForeground)
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
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.margin)
    }

    private var summary: String {
        CollectionSummaryCopy.sentence(
            watchCount: collection.watchCount,
            authenticatedCount: collection.authenticatedCount,
            estimatedTotal: collection.estimatedTotal,
            valuedCount: collection.valuedCount
        )
    }
}

/// The one sentence under the member's own collection, written in one place.
///
/// Three clients read one payload and said three different things about
/// somebody's own money: the website "estimated at $X across N of them", this
/// app "$X across N valued", and Android printed no figure at all. The wording
/// is being settled on the website, and this type exists so that settling it
/// here is a single edit rather than a hunt — nothing else in the app composes
/// this sentence.
///
/// What must survive any rewording: the valued count is said out loud beside
/// the total, so the figure can never be read as what the whole collection is
/// worth. With nothing valued there is no total to print, and the counts stand
/// alone.
enum CollectionSummaryCopy {
    static func sentence(
        watchCount: Int,
        authenticatedCount: Int,
        estimatedTotal: String?,
        valuedCount: Int
    ) -> String {
        let watches = "\(watchCount) watch\(watchCount == 1 ? "" : "es")"
        let authenticated = "\(authenticatedCount) authenticated"
        guard let total = estimatedTotal,
              let value = Decimal(string: total, locale: Locale(identifier: "en_US_POSIX")),
              valuedCount > 0 else {
            return "\(watches) · \(authenticated)"
        }
        let priced = PriceFormatter.format(value)
        return "\(watches) · \(authenticated) · \(priced) across \(valuedCount) valued"
    }
}

// MARK: - end_of_feed

/// The feed stops here: a rule, and the way onwards. Everything below it on
/// this screen is the app's furniture and is not part of the feed.
///
/// The server still sends "That's everything for you today." and no surface
/// renders it — Eytan had the farewell removed everywhere. What stays is the
/// button, which he asked for back after it briefly became Contact support;
/// the question that introduced it ("Need help buying, selling, or comparing
/// watches?") went with the support link it belonged to and is not a caption
/// for browsing.
///
/// A **degraded** feed keeps its title, because there it is not a farewell but
/// "we could not finish loading this", and it comes with the retry.
struct FeedEndModule: View {
    let module: HomeFeedModule
    let state: String
    let onBrowse: () -> Void
    let onRetry: () async -> Void

    private var degraded: Bool { state == "degraded" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Rectangle()
                .fill(Color.rewound.border)
                .frame(height: 1)

            if degraded {
                Text(module.title)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                // A degraded feed carries no CTA of its own — the retry is the
                // action, and it belongs to this side.
                RetryButton(variant: .secondary, fullWidth: true) {
                    await onRetry()
                }
            } else {
                Button("Browse all watches") {
                    Haptics.shared.play(.press)
                    onBrowse()
                }
                .buttonStyle(.rewound(.primary, fullWidth: true))
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
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = module.subtitle {
                    Text(subtitle)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s)
            if let action = module.action, let target = feedActionTarget(action.route) {
                Button(action.label) {
                    onAction(target)
                }
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.primary)
                .buttonStyle(PressableStyle())
                .frame(minHeight: Space.touchTarget)
                .accessibilityLabel(action.label)
            }
        }
    }
}
