import Foundation

/// An admin-authored daily question or poll. Results arrive only after the
/// member votes (or once the prompt closes).
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
    public let kind: String
    public let question: String
    public let options: [Option]
    public let startsOn: String
    public let endsOn: String
    public let closed: Bool
    public let myVote: String?
    public let results: Results?

    /// Leads with your own answer when you have one — that's the part worth
    /// passing on. Shared by every surface that offers this poll.
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

public struct CommunityToday: Decodable, Equatable, Sendable {
    public let daily: CommunityPrompt?
    public let polls: [CommunityPrompt]
    public let recent: [CommunityPrompt]
}
