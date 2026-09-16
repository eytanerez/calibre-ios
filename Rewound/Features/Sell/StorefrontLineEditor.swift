import CalibreDesign
import CalibreKit
import SwiftUI

/// Where a verified dealer writes the one line that sits on their storefront.
///
/// The whole of the feature is: write, wait, appear. Somebody reads it before
/// a buyer does, because it is published beside a verified-business badge on
/// a page buyers arrive at from search — so this editor's job is to be honest
/// about which of those three the dealer is currently in, and to never imply
/// the line is live when it is not.
///
/// Two texts are in play and they are deliberately not the same one. `bio` is
/// what the dealer last submitted; `live` is what a buyer is reading right
/// now. Editing an approved line returns it to review and leaves the approved
/// words on the storefront meanwhile, which is the difference between
/// moderation and a penalty for editing your own copy.
///
/// Approval happens in the admin app. Nothing here can grant it.
///
/// This used to be a sheet that fetched its own state (`StorefrontLineScreen`).
/// It is now the Storefront tab's content, and the tab owns the fetch, because
/// the preview above it — the one showing what a buyer is reading right now —
/// reads the same object. The seeing-what-is-live half of the old screen lives
/// there: it is the same promise, kept somewhere a dealer will actually look.
struct StorefrontLineEditor: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts

    /// The line as the server last stated it.
    let state: DealerBio
    /// The server's answer after a successful submit, handed back so the
    /// preview and the review state above update with it.
    let onSubmitted: (DealerBio) -> Void

    @State private var draft = ""
    @State private var seeded = false
    @State private var saving = false
    @State private var submitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            reviewState

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
                BusyLabel(title: submitTitle, busy: saving)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(!canSubmit)
        }
        // An inline error appears beside a field VoiceOver focus is not on,
        // and is otherwise never spoken.
        .a11yAnnounce(submitError)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            draft = state.bio ?? ""
        }
    }

    private var submitTitle: String {
        state.status == nil ? "Send it for review" : "Send the change for review"
    }

    private var canSubmit: Bool {
        guard !saving, InputValidation.isNonBlank(draft) else { return false }
        // Resubmitting the identical sentence would restart review on words
        // that are already in it, for nothing.
        return InputValidation.trimmed(draft) != state.bio
    }

    // MARK: - Where review got to

    /// `status` is nil — not a word — for a dealer who has never submitted
    /// one, which is almost all of them. That state gets no badge at all
    /// rather than a "pending" the server never said.
    @ViewBuilder
    private var reviewState: some View {
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
                lines: rejectionLines
            )
        case .unknown:
            EmptyView()
        }
    }

    /// The reviewer's own sentence, when they left one. Never a substitute
    /// written here: a dealer told "it didn't pass" and nothing else has no
    /// way to fix it.
    private var rejectionLines: [String] {
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - Flow

    private func submit() {
        guard canSubmit else { return }
        saving = true
        submitError = nil
        Haptics.shared.play(.press)
        Task {
            defer { saving = false }
            do {
                let saved = try await services.seller.updateDealerBio(InputValidation.trimmed(draft))
                Haptics.shared.play(.success)
                toasts.show(
                    title: "Sent for review",
                    message: "We'll let you know once it's up.",
                    tone: .success
                )
                onSubmitted(saved)
            } catch {
                Haptics.shared.play(.error)
                submitError = sellErrorMessage(error)
            }
        }
    }
}
