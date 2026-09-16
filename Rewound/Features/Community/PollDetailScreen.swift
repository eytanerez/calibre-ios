import RewoundDesign
import RewoundKit
import SwiftUI

/// A single question on its own page: what everyone answered, what *you*
/// answered, and a way to pass it on. Reached by tapping any past question in
/// "How the community answered", where both lanes' history is interleaved —
/// hence the eyebrow naming which lane this one was asked in.
struct PollDetailScreen: View {
    let prompt: CommunityPrompt

    private var totalVotes: Int { prompt.results?.totalVotes ?? 0 }

    private var myAnswerLabel: String? {
        guard let vote = prompt.myVote else { return nil }
        return prompt.options.first { $0.key == vote }?.label
            ?? prompt.results?.options.first { $0.key == vote }?.label
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow(prompt.closed ? prompt.voice.closedEyebrow : prompt.voice.eyebrow)
                    Text(prompt.question)
                        .font(RewoundType.title)
                        .foregroundStyle(Color.rewound.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(voteSummary)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }

                if let results = prompt.results, !results.options.isEmpty {
                    VStack(spacing: Space.m) {
                        ForEach(results.options) { option in
                            resultBar(option)
                        }
                    }
                } else {
                    Text("No votes were cast on this one.")
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }

                ShareLink(item: prompt.shareURL, message: Text(prompt.shareText)) {
                    Label("Share this question", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.rewound(.secondary, fullWidth: true))
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .rewoundPageBackground()
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var voteSummary: String {
        let votes = totalVotes == 1 ? "1 answer" : "\(totalVotes) answers"
        guard let myAnswerLabel else { return votes }
        return "\(votes) · you said \(myAnswerLabel)"
    }

    private func resultBar(_ option: CommunityPrompt.ResultOption) -> some View {
        let isMine = option.key == prompt.myVote
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(option.label)
                    .font(isMine ? RewoundType.bodySemiBold : RewoundType.body)
                    .foregroundStyle(Color.rewound.foreground)
                if isMine {
                    Text("YOUR ANSWER")
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
                    Capsule()
                        .fill(Color.rewound.secondary)
                    Capsule()
                        .fill(isMine ? Color.rewound.primary : Color.rewound.primary.opacity(0.35))
                        .frame(width: max(proxy.size.width * CGFloat(option.percent) / 100, 2))
                }
            }
            .frame(height: 8)

            Text(option.votes == 1 ? "1 vote" : "\(option.votes) votes")
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
        }
    }
}
