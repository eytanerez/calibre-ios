import Foundation

/// `GET /home/feed` — the whole Home feed, composed and **ordered by the
/// server**.
///
/// Ranking used to run twice: once on the server and once again in the web
/// browser, and the browser's answer won. That is exactly why this app could
/// never show the same Home as the site. It now runs once, on the server, and
/// this client's job is to draw `modules` in the order they arrive. There is
/// no scoring here, no re-ordering, no lane padding, and there must not be —
/// a second ranker is a second Home.
///
/// Named `Composed…` because `HomeFeed` is `/listings/home`'s payload — the
/// curated-lane read this one replaces on Home but does not remove.
public struct ComposedHomeFeed: Decodable, Sendable {
    /// Breaking-change counter for the ENVELOPE only. Adding a module type, a
    /// reason code or a card field does not move it (see `HomeFeedModule`).
    public let feedVersion: Int
    /// The UTC day the frozen ordering belongs to.
    public let feedDay: String
    public let generatedAt: Date
    /// After this the card *data* (price, availability) should not be trusted.
    /// The *order* is governed by `feedDay` — two different guarantees.
    public let validUntil: Date
    /// "member" or "guest", derived server-side from the session and never
    /// from a parameter.
    public let audience: String
    public let refreshed: Bool
    /// True when at least one module builder raised and was skipped. What did
    /// build is still worth drawing.
    public let degraded: Bool
    /// The module types a builder could not build. **Not** the modules that
    /// were legitimately empty — those are simply absent, and absence is the
    /// honest answer rather than a fault.
    public let omitted: [String]
    /// Ordered. Every entry is here because it has something true to say.
    public let modules: [HomeFeedModule]

    /// The modules this build can actually draw, in the server's order.
    ///
    /// A type this build has never heard of is skipped and the rest keep
    /// rendering — that is the additive contract, and it is what lets an
    /// installed app go on working after the server learns a new module.
    public var renderableModules: [HomeFeedModule] {
        modules.filter { !$0.isUnrecognized }
    }

    /// One module by its wire type, or nil when the server did not send it.
    ///
    /// Home places the feed's modules between shelves of its own rather than
    /// stacking them, so it asks for them by name. A module the server omitted
    /// is simply absent from the screen — there is nothing to pad it with — and
    /// a type this build has never heard of is not returned here either, which
    /// is what keeps an unknown module from being drawn as "another card".
    public func module(ofType type: String) -> HomeFeedModule? {
        renderableModules.first { $0.type == type }
    }

    /// The same feed with a freshly voted question in place of the one it was
    /// drawn with.
    ///
    /// Voting patches this one module and nothing else. Refetching the feed
    /// would recompute five other modules to redraw one bar chart, and would
    /// be entitled to drop a sold watch out from under the reader's thumb.
    public func replacingPoll(_ prompt: CommunityPrompt) -> ComposedHomeFeed {
        ComposedHomeFeed(
            feedVersion: feedVersion,
            feedDay: feedDay,
            generatedAt: generatedAt,
            validUntil: validUntil,
            audience: audience,
            refreshed: refreshed,
            degraded: degraded,
            omitted: omitted,
            modules: modules.map { $0.replacingPoll(prompt) }
        )
    }

    public init(
        feedVersion: Int,
        feedDay: String,
        generatedAt: Date,
        validUntil: Date,
        audience: String,
        refreshed: Bool,
        degraded: Bool,
        omitted: [String],
        modules: [HomeFeedModule]
    ) {
        self.feedVersion = feedVersion
        self.feedDay = feedDay
        self.generatedAt = generatedAt
        self.validUntil = validUntil
        self.audience = audience
        self.refreshed = refreshed
        self.degraded = degraded
        self.omitted = omitted
        self.modules = modules
    }
}

/// What justifies a module or a reason: the saved search, the prompt, the
/// Bite, the order. Empty when the module's provenance is its own card list.
public struct HomeFeedRecord: Decodable, Sendable, Hashable {
    public let type: String
    public let id: String
}

/// A module's call to action. `route` speaks the push/deep-link vocabulary the
/// notification routes already use; a route this build cannot place is dropped
/// rather than sent somewhere plausible.
public struct HomeFeedAction: Decodable, Sendable, Hashable {
    public let label: String
    public let route: String
}

/// That vocabulary, parsed into the destinations this build can actually open.
///
/// `init?` returning nil is the whole point: a route this build cannot place
/// makes its module render **without a CTA**. The shared notification
/// vocabulary falls back to the notification centre, which is right for a
/// notification and absurd for "Browse all inventory" — so an unrecognised
/// route gets no button rather than a button that goes somewhere else. A route
/// added on the server therefore costs an installed app one missing CTA, never
/// a wrong destination.
public enum HomeFeedRoute: Equatable, Sendable {
    case buy
    case buyNewest
    case alerts
    case support
    case community
    case vault
    case listing(String)
    case offer(String)
    /// Both `order/{id}` and `order/{id}/return`. Routing the second to the
    /// order is not a substitution: the return case is a card on the order's
    /// own screen, so that is where the route resolves.
    case order(String)
    case journalArticle(String)
    case bite(String)
    case seller(String)

    public init?(_ route: String) {
        switch route {
        case "buy": self = .buy; return
        case "buy?sort=newest": self = .buyNewest; return
        case "alerts": self = .alerts; return
        case "support": self = .support; return
        case "community": self = .community; return
        case "vault": self = .vault; return
        default: break
        }

        let parts = route.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[1].isEmpty else { return nil }
        switch parts[0] {
        case "listing": self = .listing(parts[1])
        case "offer": self = .offer(parts[1])
        case "order": self = .order(parts[1])
        case "journal": self = .journalArticle(parts[1])
        case "bites": self = .bite(parts[1])
        // `seller/{username}` is a storefront; `seller/listings/{id}` is the
        // seller's own listing editor, which this app does not have. The
        // second must not resolve to the first.
        case "seller" where parts.count == 2: self = .seller(parts[1])
        default: return nil
        }
    }
}

/// Why this watch was put in front of this reader.
///
/// `code` is machine-readable and `text` is the sentence — the client prints
/// `text` **verbatim** and never composes one from the code. That is what
/// makes a reason code added on the server safe on an installed build: the
/// code is unrecognised, the sentence is printed anyway.
public struct HomeFeedReason: Decodable, Sendable, Hashable {
    public let code: String
    public let text: String
    /// The record(s) that make the reason true. Empty for reasons whose
    /// evidence *is* the card.
    public let evidence: [HomeFeedRecord]
}

/// One high-signal chip on a card.
public struct HomeFeedSignal: Decodable, Sendable, Hashable {
    public let code: String
    public let label: String
    /// "drop" or "fresh". A tone this build has never heard of renders as the
    /// neutral chip rather than as an unpainted one.
    public let tone: String
}

/// One listing in a listing-bearing module.
///
/// `id` is the listing's id, duplicated deliberately so a card array can go
/// through the same identity-keyed reconciliation the lanes already use.
/// `reason` is null when the server could not justify one — there is no
/// filler, and the client must not write one.
public struct HomeFeedCard: Decodable, Sendable, Identifiable {
    public let id: String
    public let listing: Listing
    public let reason: HomeFeedReason?
    public let signal: HomeFeedSignal?
}

/// `your_next_step` — the one real action this member owes, if there is one.
public struct HomeFeedStep: Decodable, Sendable {
    public let code: String
    /// Null when the step has no deadline. A past deadline still goes out
    /// as-is: an overdue wire is more urgent, not less, and the client is the
    /// one that words the overdue state.
    public let dueAt: Date?
    public let referenceLabel: String?
}

/// `your_collection` — the member's own watches, and only the figures the
/// Vault itself would state for them.
public struct HomeFeedCollection: Decodable, Sendable {
    public struct Watch: Decodable, Sendable, Identifiable {
        public let id: String
        public let brand: String?
        public let model: String?
        public let reference: String?
        public let photoUrl: String?
        public let passportCode: String?
        public let authenticated: Bool
        public let estimatedValue: String?

        /// What to call it: the catalog's words, else the reference.
        public var displayTitle: String {
            let named = [brand, model]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !named.isEmpty { return named }
            return reference ?? "A watch in your Vault"
        }
    }

    public let watchCount: Int
    public let authenticatedCount: Int
    /// How many of the watches carry a figure the Vault would state. Said out
    /// loud beside the total so it can never be read as "the whole
    /// collection".
    public let valuedCount: Int
    /// Null when nothing in the collection has a stated value.
    public let estimatedTotal: String?
    public let watches: [Watch]
}

/// One module in the feed: the shared header, plus the body its type carries.
public struct HomeFeedModule: Decodable, Sendable, Identifiable {
    /// The typed part of a module.
    ///
    /// `unrecognized` is not an error state. `modules` is an ordered array of
    /// objects with a `type` string, a type is never removed from the
    /// vocabulary, and a client that meets one it has never heard of skips
    /// that entry and keeps rendering the rest.
    public enum Body: Sendable {
        case nextStep(HomeFeedStep)
        case listings([HomeFeedCard])
        case bite(slot: String, bite: Bite)
        case poll(CommunityPrompt)
        case collection(HomeFeedCollection)
        case endOfFeed(state: String)
        case unrecognized
    }

    public let type: String
    /// Server-composed and rendered verbatim.
    public let title: String
    /// Null unless it says something the title does not.
    public let subtitle: String?
    public let action: HomeFeedAction?
    public let sourceRecords: [HomeFeedRecord]
    public let body: Body

    /// A type appears at most once in a response, so the type *is* the id and
    /// there is no separate id field on the wire.
    public var id: String { type }

    public var isUnrecognized: Bool {
        if case .unrecognized = body { return true }
        return false
    }

    /// The cards this module carries, or none. Listing-bearing modules are the
    /// only ones with any.
    public var cards: [HomeFeedCard] {
        if case .listings(let cards) = body { return cards }
        return []
    }

    public init(
        type: String,
        title: String,
        subtitle: String?,
        action: HomeFeedAction?,
        sourceRecords: [HomeFeedRecord],
        body: Body
    ) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.sourceRecords = sourceRecords
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case type, title, subtitle, action, sourceRecords
        case step, cards, slot, bite, poll, collection, state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        action = try container.decodeIfPresent(HomeFeedAction.self, forKey: .action)
        sourceRecords = try container.decode([HomeFeedRecord].self, forKey: .sourceRecords)

        switch type {
        case "your_next_step":
            body = .nextStep(try container.decode(HomeFeedStep.self, forKey: .step))
        case "saved_search_matches", "worth_a_look":
            body = .listings(try container.decode([HomeFeedCard].self, forKey: .cards))
        case "todays_bite":
            body = .bite(
                slot: try container.decode(String.self, forKey: .slot),
                bite: try container.decode(Bite.self, forKey: .bite)
            )
        case "todays_poll":
            body = .poll(try container.decode(CommunityPrompt.self, forKey: .poll))
        case "your_collection":
            body = .collection(try container.decode(HomeFeedCollection.self, forKey: .collection))
        case "end_of_feed":
            body = .endOfFeed(state: try container.decode(String.self, forKey: .state))
        default:
            // A module type from a newer server. Skipped, not fatal, and not
            // guessed at — drawing it as "another card" would be inventing a
            // composition for something whose shape is unknown.
            body = .unrecognized
        }
    }

    /// The same module under a heading of the client's own.
    ///
    /// Used for exactly one module and stated here so it cannot spread: the
    /// ranked shelf is drawn under Home's greeting, so the greeting *is* its
    /// heading and a second one above it would say hello twice. Everything
    /// else — the cards, their order, their reasons, the action — is the
    /// server's and is untouched.
    public func retitled(_ title: String) -> HomeFeedModule {
        HomeFeedModule(
            type: type,
            title: title,
            subtitle: subtitle,
            action: action,
            sourceRecords: sourceRecords,
            body: body
        )
    }

    /// This module with a freshly voted question in it, when it is the poll.
    func replacingPoll(_ prompt: CommunityPrompt) -> HomeFeedModule {
        guard case .poll(let current) = body, current.id == prompt.id else { return self }
        return HomeFeedModule(
            type: type,
            title: title,
            subtitle: subtitle,
            action: action,
            sourceRecords: sourceRecords,
            body: .poll(prompt)
        )
    }
}

/// Home's greeting, and the heading it forms over the ranked shelf.
///
/// The name is resolved from the address book the way the address book itself
/// orders its entries: the default billing address, then the default shipping
/// one, then whichever is first on file. That is the same rule the server uses
/// to compose its own greeting, so the two never disagree about what to call
/// somebody.
///
/// A reader with no address on file — a guest, or a member who has not checked
/// out yet — is greeted by name-less English rather than by a blank or by a
/// username. There is no third state: the shelf always has a heading.
public enum HomeGreeting {
    /// What to call a reader the address book says nothing about.
    public static let fallbackName = "there"

    public static func firstName(from addresses: [Address]) -> String {
        let chosen = addresses.first { $0.isDefaultBilling }
            ?? addresses.first { $0.isDefaultShipping }
            ?? addresses.first
        guard let chosen else { return fallbackName }

        let given = (chosen.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given }

        // A single-field address book still knows the name; the first word of
        // it is the part somebody is called.
        let leading = (chosen.fullName ?? "").split(whereSeparator: \.isWhitespace).first
        guard let leading, !leading.isEmpty else { return fallbackName }
        return String(leading)
    }

    /// The heading the ranked shelf is drawn under.
    public static func watchesForYouTitle(addresses: [Address]) -> String {
        "Hi \(firstName(from: addresses)), here are some watches for you"
    }
}
