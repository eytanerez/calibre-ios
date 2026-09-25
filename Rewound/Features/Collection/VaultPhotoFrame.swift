import RewoundDesign
import RewoundKit
import Nuke
import NukeUI
import SwiftUI

/// One watch's cover photograph, or the space it will occupy.
///
/// Square in both places on purpose. The card's frame and the detail's hero
/// hand the picture to each other on a push, and a uniform scale between two
/// squares is a movement where a change of aspect would be a distortion.
///
/// **It draws `cover_url` and never `photo_url`.** The server settles which
/// picture leads (`_cover_url`): the owner's own first photograph the moment
/// they have one, and the link the watch arrived with until then. A frame that
/// kept reaching for the link would show the seller's picture of a watch its
/// owner has since photographed themselves.
///
/// The two kinds of address behind that one field are not fetched the same
/// way, which is what `VaultCoverSource` is for — Rewound's own objects need
/// the member's credential and somebody else's host must never be sent it.
///
/// **The placeholder is never a picture of a watch.** Not a stock image, not
/// the catalog's photograph of the reference, not another example of it — an
/// owner looking at their own collection has to be able to trust that what is
/// on the card is the thing in their drawer. What stands in is a letter on a
/// ground: plainly not a photograph, and it says whose watch is missing from
/// it.
///
/// A cover a device cannot load falls back to the same ground rather than to a
/// broken glyph. A link points somewhere else, so it can stop resolving
/// without anybody at Rewound or at the keyboard doing anything.
struct VaultPhotoFrame: View {
    enum Variant {
        /// In the collection.
        case card
        /// The first thing on the watch's own screen, when there is nothing to
        /// page through: the monogram and the words that ask for a photograph.
        case hero
        /// One page of the watch's gallery on its own screen. A page that
        /// cannot load keeps quiet: it stands for a picture that exists, so
        /// "Add your photographs" over it would be the wrong sentence.
        case page
    }

    let watch: VaultWatch
    let variant: Variant
    /// The frame's drawn side, in points. The caller measures it, because only
    /// the caller knows how wide its column is.
    let side: CGFloat
    /// The picture to draw in place of the cover: a page of the gallery. Nil
    /// draws `cover_url`, which is every card and the empty hero.
    var picture: URL? = nil

    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack {
            Color.rewound.secondary
            if let source {
                switch source {
                case .privateMedia(let url):
                    PrivateImage(url: url, side: side) { phase in
                        switch phase {
                        case .loaded(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failed:
                            placeholder
                        case .loading:
                            Rectangle().shimmer()
                        }
                    }
                case .link(let url):
                    LazyImage(request: linkRequest(url)) { state in
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

    private var source: VaultCoverSource? {
        if let picture {
            return VaultCoverSource.resolve(picture, apiOrigin: services.client.baseURL)
        }
        return VaultCoverSource.cover(watch, apiOrigin: services.client.baseURL)
    }

    /// Everything anyone may fetch goes through Nuke — a seller's link, and
    /// Rewound's own public `/media/` files alike. What does not is the
    /// owner's own photograph: the proxy answers `Cache-Control: private,
    /// no-store` and Nuke's pipeline here is backed by an app-owned disk
    /// cache, so those are fetched and held by `PrivateMediaLoader` instead —
    /// in memory, for this session only.
    private func linkRequest(_ url: URL) -> ImageRequest {
        let pixels = side * UIScreen.main.scale
        return ImageRequest(
            url: url,
            processors: [.resize(size: CGSize(width: pixels, height: pixels), unit: .pixels, crop: true)],
            // The hero is the first thing on its screen and the collection's
            // frames are a column being scrolled past.
            priority: variant == .card ? .normal : .high
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.rewound.secondary
            Text(initial)
                .font(RewoundType.serif(.semiBold, side * 0.42, relativeTo: .largeTitle))
                .foregroundStyle(Color.rewound.placeholder.opacity(0.35))
                .accessibilityHidden(true)
            // Only the hero speaks. The screen it sits on carries the button
            // that adds one, so the words are next to the thing that does it;
            // a card in the collection grid would be inviting a tap that
            // pushes a screen rather than opening a picker.
            if variant == .hero {
                VStack {
                    Spacer()
                    HStack {
                        Text("Add your photographs")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                        Spacer()
                    }
                }
                .padding(Space.m)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
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
    /// A Rewound purchase arrives carrying the seller's photographs of that
    /// exact watch: taken by them, checked against the watch on the bench, and
    /// shipped with it. So the picture is of the owner's watch without being
    /// the owner's picture. Calling it theirs would be a small lie told only to
    /// the people reading with a screen reader, which is the worst audience to
    /// tell it to.
    ///
    /// Which of the two it is, is now a fact rather than a guess from
    /// `source`: an owner's uploaded photograph is served from Rewound's own
    /// origin and a seller's is not, and that is exactly the distinction
    /// `VaultCoverSource` draws.
    private var accessibilityLabel: String {
        guard let source else { return "No photograph of your \(catalogTitle) yet" }
        let whose = switch source {
        case .privateMedia: "Your photograph"
        case .link: "The seller's photograph"
        }
        if let nickname = watch.nickname {
            return "\(nickname) \u{2014} \(whose.lowercased()) of your \(catalogTitle)"
        }
        return "\(whose) of your \(catalogTitle)"
    }

    private var catalogTitle: String {
        let joined = [watch.brand, watch.model].compactMap { $0 }.joined(separator: " ")
        return joined.isEmpty ? "watch" : joined
    }
}
