import RewatchDesign
import RewatchKit
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
                        .font(RewatchType.title)
                        .foregroundStyle(Color.rewatch.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(voteSummary)
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                }

                if let results = prompt.results, !results.options.isEmpty {
                    VStack(spacing: Space.m) {
                        ForEach(results.options) { option in
                            resultBar(option)
                        }
                    }
                } else {
                    Text("No votes were cast on this one.")
                        .font(RewatchType.body)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                }

                ShareLink(item: prompt.shareURL, message: Text(prompt.shareText)) {
                    Label("Share this question", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.rewatch(.secondary, fullWidth: true))
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .rewatchPageBackground()
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
                    .font(isMine ? RewatchType.bodySemiBold : RewatchType.body)
                    .foregroundStyle(Color.rewatch.foreground)
                if isMine {
                    Text("YOUR ANSWER")
                        .font(RewatchType.label)
                        .foregroundStyle(Color.rewatch.primary)
                }
                Spacer()
                Text("\(option.percent)%")
                    .font(RewatchType.bodyMedium)
                    .foregroundStyle(Color.rewatch.foreground)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.rewatch.secondary)
                    Capsule()
                        .fill(isMine ? Color.rewatch.primary : Color.rewatch.primary.opacity(0.35))
                        .frame(width: max(proxy.size.width * CGFloat(option.percent) / 100, 2))
                }
            }
            .frame(height: 8)

            Text(option.votes == 1 ? "1 vote" : "\(option.votes) votes")
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
        }
    }
}
