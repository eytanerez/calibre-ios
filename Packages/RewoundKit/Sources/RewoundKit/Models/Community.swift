import Foundation

/// The lanes a question is asked in. They differ in what they are *for*,
/// not in how they work: a watch question exists to be worth answering, and a
/// site-feedback one exists to be worth reading.
///
/// Declaration order is asking order. The watch question leads because it is
/// the one a collector came for, which leaves the question about Calibre
/// reading as a follow-up rather than as the toll for being here.
public enum CommunityPromptKind: String, CaseIterable, Sendable, Hashable {
    case watch
    case siteFeedback = "site_feedback"

    public var voice: CommunityPromptVoice { CommunityPromptVoice.forKind(rawValue) }
}

/// How a lane introduces itself.
///
/// Each lane is a different invitation — the watch one is for fun, the
/// Calibre one is product input — and a reader who cannot tell which they are
/// answering will answer them all in the same voice. Kept beside the model
/// rather than in a screen because every consumer surface asks the same
/// questions and the words have to match across them.
public struct CommunityPromptVoice: Equatable, Sendable {
    /// Above a live question.
    public let eyebrow: String
    /// The one line that says what answering is for. Live questions only.
    public let invitation: String
    /// Above one that has already run, where the invitation is over.
    public let closedEyebrow: String
    /// What this lane says when its bank has run dry.
    public let emptyLane: String

    /// The words for a lane this client has never heard of.
    ///
    /// Reachable through `recent`, which carries whatever kind each past
    /// question was asked in: a lane added on the server starts closing
    /// questions into that list before this build knows its name, and an
    /// unnamed lane is still a question somebody answered.
    static let unknown = CommunityPromptVoice(
        eyebrow: "Question of the day",
        invitation: "",
        closedEyebrow: "Asked earlier",
        emptyLane: "Today's question is being wound. Check back soon."
    )

    public static func forKind(_ kind: String) -> CommunityPromptVoice {
        switch CommunityPromptKind(rawValue: kind) {
        case .watch:
            return CommunityPromptVoice(
                eyebrow: "Today's watch question",
                invitation: "A collectors' question — answer it for the fun of it.",
                closedEyebrow: "Asked earlier · Watches",
                emptyLane: "Today's watch question is being wound. Check back soon."
            )
        case .siteFeedback:
            return CommunityPromptVoice(
                eyebrow: "Today's Calibre question",
                invitation: "About Calibre itself — what you say here shapes what we build.",
                closedEyebrow: "Asked earlier · Calibre",
                emptyLane: "Today's Calibre question is being wound. Check back soon."
            )
        case nil:
            return unknown
        }
    }
}

/// One admin-authored question and its answers. Results arrive only after the
/// member votes (or once the question closes).
public struct CommunityPrompt: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public struct Option: Decodable, Equatable, Hashable, Sendable, Identifiable {
        public let key: String
        public let label: String
        public var id: String { key }
    }

    public struct ResultOption: Decodable, Equatable, Hashable, Sendable, Identifiable {
        public let key: String
        public let label: String
        public let votes: Int
        public let percent: Int
        public var id: String { key }
    }

    public struct Results: Decodable, Equatable, Hashable, Sendable {
        public let totalVotes: Int
        public let options: [ResultOption]
    }

    public let id: String
    /// Which lane it was asked in, as the server words it. Kept a string
    /// rather than the enum because it is a wire value: a lane added on the
    /// server reaches this build as a word it has never heard, and the screen
    /// has to render that question rather than fail to decode the whole feed.
    public let kind: String
    public let question: String
    public let options: [Option]
    /// The day it was asked. Null only for one that has not been asked yet.
    public let askedOn: String?
    public let closed: Bool
    public let myVote: String?
    public let results: Results?

    public var voice: CommunityPromptVoice { CommunityPromptVoice.forKind(kind) }

    /// Leads with your own answer when you have one — that's the part worth
    /// passing on. Shared by every surface that offers this question.
    public var shareText: String {
        let mine = options.first { $0.key == myVote }?.label
            ?? results?.options.first { $0.key == myVote }?.label
        if let mine {
            return "I said \"\(mine)\" to this on Calibre: \(question) — what are your thoughts?"
        }
        return "\(question) — what do you think? Answered on Calibre."
    }

    public var shareURL: URL {
        URL(string: "https://buycalibre.com/community?poll=\(id)")
            ?? URL(string: "https://buycalibre.com/community")!
    }
}

/// One lane on the Today screen: which kind, and what it is asking — or
/// nothing, when that bank has run dry.
public struct CommunityLane: Identifiable, Equatable, Sendable {
    public let kind: CommunityPromptKind
    public let prompt: CommunityPrompt?

    public var id: String { kind.rawValue }
    public var voice: CommunityPromptVoice { kind.voice }
}

/// Today's questions — one per kind — and the ones before them.
///
/// The payload also carries a single `today`, which repeats one of these for a
/// client written before the second lane existed. This one does not decode it:
/// reading it would show a single lane's question and silently drop the rest.
public struct CommunityToday: Decodable, Equatable, Sendable {
    /// The live question in each lane, or nil where that bank has run dry —
    /// a real state the screen has words for rather than a reason to re-ask
    /// something or to borrow from the other lane.
    public struct LiveByKind: Decodable, Equatable, Sendable {
        public let watch: CommunityPrompt?
        public let siteFeedback: CommunityPrompt?

        public init(watch: CommunityPrompt?, siteFeedback: CommunityPrompt?) {
            self.watch = watch
            self.siteFeedback = siteFeedback
        }

        public func prompt(for kind: CommunityPromptKind) -> CommunityPrompt? {
            switch kind {
            case .watch: return watch
            case .siteFeedback: return siteFeedback
            }
        }
    }

    public let todayByKind: LiveByKind
    public let recent: [CommunityPrompt]

    public init(todayByKind: LiveByKind, recent: [CommunityPrompt]) {
        self.todayByKind = todayByKind
        self.recent = recent
    }

    /// Every lane, in asking order, live or dry.
    public var lanes: [CommunityLane] {
        CommunityPromptKind.allCases.map {
            CommunityLane(kind: $0, prompt: todayByKind.prompt(for: $0))
        }
    }

    /// The lanes asking something right now.
    public var liveLanes: [CommunityLane] { lanes.filter { $0.prompt != nil } }

    /// The lanes with nothing to ask.
    public var dryLanes: [CommunityLane] { lanes.filter { $0.prompt == nil } }

    /// Folds a freshly voted question back into whichever lane (or the
    /// history) it came from.
    public func replacing(_ updated: CommunityPrompt) -> CommunityToday {
        CommunityToday(
            todayByKind: LiveByKind(
                watch: todayByKind.watch?.id == updated.id ? updated : todayByKind.watch,
                siteFeedback: todayByKind.siteFeedback?.id == updated.id
                    ? updated
                    : todayByKind.siteFeedback
            ),
            recent: recent.map { $0.id == updated.id ? updated : $0 }
        )
    }
}
