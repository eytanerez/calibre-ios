import CalibreDesign
import CalibreKit
import SwiftUI

/// A single poll on its own page: the question, what everyone answered, what
/// *you* answered, and a way to pass it on. Reached by tapping any past poll
/// in "How the community answered".
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
                    Eyebrow(prompt.kind == "daily" ? "Question of the day" : "Poll")
                    Text(prompt.question)
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(voteSummary)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                if let results = prompt.results, !results.options.isEmpty {
                    VStack(spacing: Space.m) {
                        ForEach(results.options) { option in
                            resultBar(option)
                        }
                    }
                } else {
                    Text("No votes were cast on this one.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                ShareLink(item: prompt.shareURL, message: Text(prompt.shareText)) {
                    Label("Share this poll", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .navigationTitle("Poll")
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
                    .font(isMine ? CalibreType.bodySemiBold : CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                if isMine {
                    Text("YOUR ANSWER")
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
                    Capsule()
                        .fill(Color.calibre.secondary)
                    Capsule()
                        .fill(isMine ? Color.calibre.primary : Color.calibre.primary.opacity(0.35))
                        .frame(width: max(proxy.size.width * CGFloat(option.percent) / 100, 2))
                }
            }
            .frame(height: 8)

            Text(option.votes == 1 ? "1 vote" : "\(option.votes) votes")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }
}
