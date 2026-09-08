import CalibreDesign
import CalibreKit
import Nuke
import NukeUI
import SwiftUI

/// One watch's photograph, or the space it will occupy.
///
/// Square in both places on purpose. The card's frame and the detail's hero
/// hand the picture to each other on a push, and a uniform scale between two
/// squares is a movement where a change of aspect would be a distortion.
///
/// **The placeholder is never a picture of a watch.** Not a stock image, not
/// the catalog's photograph of the reference, not another example of it — an
/// owner looking at their own collection has to be able to trust that what is
/// on the card is the thing in their drawer. What stands in is a letter on a
/// ground: plainly not a photograph, and it says whose watch is missing from
/// it.
///
/// A link a device cannot load falls back to the same ground rather than to a
/// broken glyph. `photo_url` points somewhere else, so it can stop resolving
/// without anybody at Calibre or at the keyboard doing anything.
struct VaultPhotoFrame: View {
    enum Variant {
        /// In the collection.
        case card
        /// The first thing on the watch's own screen.
        case hero
    }

    let watch: VaultWatch
    let variant: Variant
    /// The frame's drawn side, in points. The caller measures it, because only
    /// the caller knows how wide its column is.
    let side: CGFloat

    var body: some View {
        ZStack {
            Color.calibre.secondary
            if let request {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if state.error != nil {
                        placeholder
                    } else {
                        Rectangle().shimmer()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var request: ImageRequest? {
        guard let url = watch.photoUrl.flatMap(VaultPhotoLink.usable) else { return nil }
        let pixels = side * UIScreen.main.scale
        return ImageRequest(
            url: url,
            processors: [.resize(size: CGSize(width: pixels, height: pixels), unit: .pixels, crop: true)],
            // The hero is the first thing on its screen and the collection's
            // frames are a column being scrolled past.
            priority: variant == .hero ? .high : .normal
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.calibre.secondary
            Text(initial)
                .font(CalibreType.serif(.semiBold, side * 0.42, relativeTo: .largeTitle))
                .foregroundStyle(Color.calibre.placeholder.opacity(0.35))
                .accessibilityHidden(true)
            VStack {
                Spacer()
                HStack {
                    Text("No photo yet")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                    Spacer()
                }
            }
            .padding(Space.m)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    /// The first letter of the brand, where there is one. A watch entered with
    /// nothing but a nickname gets an empty ground rather than the first letter
    /// of the nickname, which would read as a monogram.
    private var initial: String {
        String(watch.brand?.trimmingCharacters(in: .whitespaces).prefix(1) ?? "").uppercased()
    }

    /// Whose picture it is, then whose watch — the watch is theirs either way,
    /// and their name for it is theirs and leads the description.
    ///
    /// A Calibre purchase arrives carrying the seller's photographs of that
    /// exact watch: taken by them, checked against the watch on the bench, and
    /// shipped with it. So the picture is of the owner's watch without being
    /// the owner's picture. Calling it theirs would be a small lie told only to
    /// the people reading with a screen reader, which is the worst audience to
    /// tell it to. Worded identically on web (`VaultPhoto.tsx`).
    private var accessibilityLabel: String {
        guard request != nil else { return "No photo of your \(catalogTitle) yet" }
        let whose = watch.source == "calibre_order" ? "The seller's photograph" : "Your photograph"
        if let nickname = watch.nickname {
            return "\(nickname) — \(whose.lowercased()) of your \(catalogTitle)"
        }
        return "\(whose) of your \(catalogTitle)"
    }

    private var catalogTitle: String {
        let joined = [watch.brand, watch.model].compactMap { $0 }.joined(separator: " ")
        return joined.isEmpty ? "watch" : joined
    }
}

/// Adding the photograph.
///
/// Calibre has no endpoint that stores a picture for a watch in somebody's
/// vault, so this asks for a link and says that is what it is asking for. It
/// does not offer a photo picker it could not honour and it does not describe
/// itself as an upload — `VaultPhotoLink.usable` is the same https-only rule
/// the web applies to the same column.
struct VaultPhotoLinkSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let watch: VaultWatch
    /// Handed the saved watch so the screen behind can redraw without a refetch.
    let onSaved: (VaultWatch) -> Void

    @State private var draft = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var preview: URL? { VaultPhotoLink.usable(draft) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    CalibreTextField(
                        "Link to your photo",
                        text: $draft,
                        placeholder: "https://…",
                        kind: .url
                    )

                    Text("Calibre doesn't store pictures for watches in your vault yet, so this keeps the link and shows what is at the end of it. Use your own photograph of your own watch — a stock picture of the reference is a picture of somebody else's.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    if let preview {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Eyebrow("Preview")
                            LazyImage(url: preview) { state in
                                if let image = state.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else if state.error != nil {
                                    Text("Nothing loaded from that link.")
                                        .font(CalibreType.caption)
                                        .foregroundStyle(Color.calibre.mutedForeground)
                                        .padding(Space.m)
                                } else {
                                    Rectangle().shimmer()
                                }
                            }
                            .frame(width: 132, height: 132)
                            .background(Color.calibre.secondary)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(saveTitle) { save(.text(draft)) }
                        .buttonStyle(.calibre(.primary, fullWidth: true))
                        .disabled(preview == nil || saving)

                    if watch.photoUrl != nil {
                        Button("Remove the photo") { save(.clear) }
                            .buttonStyle(.calibre(.secondary, fullWidth: true))
                            .disabled(saving)
                    }
                }
                .padding(Space.l)
            }
            .calibrePageBackground()
            .navigationTitle(watch.photoUrl == nil ? "Add a photo" : "Change the photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.calibre.primary)
                }
            }
        }
        .onAppear { draft = watch.photoUrl ?? "" }
    }

    private var saveTitle: String {
        if saving { return "Saving…" }
        return errorMessage == nil ? "Save the photo" : "Try again"
    }

    /// The draft survives a failure: the sheet stays open on exactly what was
    /// typed, so a link that took a minute to find is not lost to a dropped
    /// connection.
    private func save(_ edit: VaultFieldEdit) {
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                let updated = try await services.vault.update(id: watch.id, photoUrl: edit)
                Haptics.shared.play(.save)
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription
                    ?? "We couldn't save that just now. Nothing you typed has been lost."
            }
        }
    }
}
