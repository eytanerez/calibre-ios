import CalibreDesign
import CalibreKit
import SwiftUI

/// The owner's own note about their own watch.
///
/// `vault_watches.notes` leaves the server on one payload and one only — the
/// owner's own view of their own collection. The sell handoff carries the
/// identity fields and nothing else, `/vault/matches` is deliberately narrower,
/// and the public Passport is built from passport events. So this is private,
/// and the panel says so where it is written rather than in a policy page
/// nobody opens.
///
/// Set in the interface's face, not the hand. The list of places the hand is
/// allowed is exhaustive (`CALIBRE_BY_HAND_CONTRACTS.md` §2.3) and an owner's
/// private note is not on it — the nickname is, and it is set in the hand
/// wherever it is drawn.
struct VaultOwnerNote: View {
    @Environment(AppServices.self) private var services

    let watch: VaultWatch
    let onSaved: (VaultWatch) -> Void

    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your note")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Spacer(minLength: Space.m)
                if !editing {
                    Button(watch.notes == nil ? "Add a note" : "Edit") {
                        draft = watch.notes ?? ""
                        errorMessage = nil
                        editing = true
                    }
                    .buttonStyle(.calibre(.secondary))
                }
            }

            HStack(spacing: Space.xs) {
                Image(systemName: "lock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
                Text("Only you can read this. It never goes on a listing or a Passport.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .accessibilityElement(children: .combine)

            if editing {
                CalibreTextEditor(
                    "Your note about this watch",
                    text: $draft,
                    placeholder: "Where it came from, who wore it before you, what you're waiting to do with it.",
                    minHeight: 120
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Space.m) {
                    Button(saveTitle) { save() }
                        .buttonStyle(.calibre(.primary))
                        .disabled(saving)
                    Button("Cancel") {
                        errorMessage = nil
                        editing = false
                    }
                    .buttonStyle(.calibre(.ghost))
                    .disabled(saving)
                }
            } else if let notes = watch.notes, !notes.isEmpty {
                Text(notes)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Nothing written down yet.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    private var saveTitle: String {
        if saving { return "Saving…" }
        return errorMessage == nil ? "Save note" : "Try again"
    }

    /// The editor stays open on a failure, holding exactly what was typed.
    private func save() {
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                let updated = try await services.vault.update(id: watch.id, notes: .text(draft))
                Haptics.shared.play(.save)
                onSaved(updated)
                editing = false
            } catch {
                errorMessage = (error as? APIError)?.errorDescription
                    ?? "We couldn't save that just now. Nothing you typed has been lost."
            }
        }
    }
}
