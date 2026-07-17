import Foundation

/// An admin-authored daily question or poll. Results arrive only after the
/// member votes (or once the prompt closes).
public struct CommunityPrompt: Decodable, Equatable, Sendable, Identifiable {
    public struct Option: Decodable, Equatable, Sendable, Identifiable {
        public let key: String
        public let label: String
        public var id: String { key }
    }

    public struct ResultOption: Decodable, Equatable, Sendable, Identifiable {
        public let key: String
        public let label: String
        public let votes: Int
        public let percent: Int
        public var id: String { key }
    }

    public struct Results: Decodable, Equatable, Sendable {
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
}

public struct CommunityToday: Decodable, Equatable, Sendable {
    public let daily: CommunityPrompt?
    public let polls: [CommunityPrompt]
    public let recent: [CommunityPrompt]
}
