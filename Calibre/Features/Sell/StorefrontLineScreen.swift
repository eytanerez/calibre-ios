import CalibreDesign
import CalibreKit
import SwiftUI

/// Where a verified dealer writes the one line that sits on their storefront.
///
/// The whole of the feature is: write, wait, appear. Somebody reads it before
/// a buyer does, because it is published beside a verified-business badge on
/// a page buyers arrive at from search — so this screen's job is to be honest
/// about which of those three the dealer is currently in, and to never imply
/// the line is live when it is not.
///
/// Two texts are in play and they are deliberately not the same one. `bio` is
/// what the dealer last submitted; `live` is what a buyer is reading right
/// now. Editing an approved line returns it to review and leaves the approved
/// words on the storefront meanwhile, which is the difference between
/// moderation and a penalty for editing your own copy. Both are shown when
/// they differ, because a dealer who cannot see that is left guessing whether
/// their edit went anywhere.
///
/// Approval happens in the admin app. Nothing here can grant it.
struct StorefrontLineScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var state: DealerBio?
    @State private var draft = ""
    @State private var loadFailed = false
    @State private var saving = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let state {
                    form(state)
                } else if loadFailed {
                    EmptyState(
                        icon: "wifi.slash",
                        title: "Couldn't load your storefront line",
                        message: "Check your connection and try again.",
                        actionTitle: "Try again"
                    ) {
                        Task { await load() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    skeleton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .calibrePageBackground()
            .navigationTitle("Your storefront line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .tint(Color.calibre.primary)
                }
            }
        }
        .task {
            guard state == nil else { return }
            await load()
        }
    }

    // MARK: - Form

    private func form(_ state: DealerBio) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Say who you are, in one line")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("It sits under your name on your storefront, beside your dealer badge. One line, no line breaks. Someone reads it before it goes up.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                reviewState(state)

                CalibreTextEditor(
                    "Your line",
                    text: $draft,
                    placeholder: "Vintage Seiko out of a workshop in Osaka, since 1998.",
                    minHeight: 92,
                    characterLimit: DealerBio.characterLimit
                )
                .onChange(of: draft) { _, newValue in
                    // A line break would be silently dropped by the server;
                    // folding it into a space keeps what was typed and keeps
                    // the field honest about what will be stored.
                    let flattened = newValue
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\r", with: " ")
                    let capped = String(flattened.prefix(DealerBio.characterLimit))
                    if capped != newValue { draft = capped }
                    submitError = nil
                }

                if let submitError {
                    InlineErrorLine(message: submitError)
                }

                Button {
                    submit()
                } label: {
                    BusyLabel(title: submitTitle(state), busy: saving)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(!canSubmit)

                livePreview(state)
            }
            .padding(Space.margin)
            .padding(.bottom, Space.xxl)
        }
    }

    private func submitTitle(_ state: DealerBio) -> String {
        state.status == nil ? "Send it for review" : "Send the change for review"
    }

    private var canSubmit: Bool {
        guard !saving, InputValidation.isNonBlank(draft) else { return false }
        // Resubmitting the identical sentence would restart review on words
        // that are already in it, for nothing.
        return InputValidation.trimmed(draft) != state?.bio
    }

    // MARK: - Where review got to

    /// `status` is nil — not a word — for a dealer who has never submitted
    /// one, which is almost all of them. That state gets no badge at all
    /// rather than a "pending" the server never said.
    @ViewBuilder
    private func reviewState(_ state: DealerBio) -> some View {
        switch state.status {
        case .none:
            EmptyView()
        case .pending:
            statusCard(
                badge: "With a reviewer",
                tone: .info,
                lines: [
                    state.live == nil
                        ? "Nothing is on your storefront yet. It goes up as soon as this clears."
                        : "Your storefront keeps the line it already had until this one clears."
                ]
            )
        case .approved:
            statusCard(
                badge: "Live",
                tone: .success,
                lines: ["This is what buyers are reading on your storefront."]
            )
        case .rejected:
            statusCard(
                badge: "Not approved",
                tone: .warning,
                lines: rejectionLines(state)
            )
        case .unknown:
            EmptyView()
        }
    }

    /// The reviewer's own sentence, when they left one. Never a substitute
    /// written here: a dealer told "it didn't pass" and nothing else has no
    /// way to fix it.
    private func rejectionLines(_ state: DealerBio) -> [String] {
        guard let reason = state.rejectedReason, InputValidation.isNonBlank(reason) else {
            return ["This line wasn't approved. Rewrite it and send it again."]
        }
        return [reason, "Rewrite it and send it again."]
    }

    private func statusCard(badge: String, tone: StatusBadge.Tone, lines: [String]) -> some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.s) {
                StatusBadge(badge, tone: tone)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
        }
    }

    // MARK: - What a buyer sees

    /// Only worth showing while it differs from the draft — otherwise it is
    /// the same sentence printed twice.
    @ViewBuilder
    private func livePreview(_ state: DealerBio) -> some View {
        if let live = state.live, InputValidation.trimmed(draft) != live {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow("On your storefront now")
                Text(live)
                    .font(CalibreType.hand)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.l)
                    .background(
                        Color.calibre.card,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Color.calibre.border, lineWidth: 1)
                    )
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Rectangle().frame(maxWidth: .infinity).frame(height: 18).shimmer()
            Rectangle().frame(maxWidth: .infinity).frame(height: 92).shimmer()
            Spacer()
        }
        .padding(Space.margin)
        .padding(.top, Space.xl)
    }

    // MARK: - Flow

    private func load() async {
        loadFailed = false
        do {
            let bio = try await services.seller.dealerBio()
            state = bio
            draft = bio.bio ?? ""
        } catch {
            if state == nil { loadFailed = true }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        saving = true
        submitError = nil
        Haptics.shared.play(.press)
        Task {
            defer { saving = false }
            do {
                state = try await services.seller.updateDealerBio(InputValidation.trimmed(draft))
                Haptics.shared.play(.success)
                toasts.show(
                    title: "Sent for review",
                    message: "We'll let you know once it's up.",
                    tone: .success
                )
            } catch {
                Haptics.shared.play(.error)
                submitError = sellErrorMessage(error)
            }
        }
    }
}
