import RewoundDesign
import RewoundKit
import SwiftUI

/// Every picture of one watch in the member's vault, one square page at a
/// time, with the dots under it. Any page opens full screen.
///
/// The pictures are `VaultWatch.viewingGallery(listingPhotos:)`: the cover,
/// the owner's own photographs, then the seller's from the listing it was
/// bought from. Before this the screen drew the cover alone, so a watch bought
/// here with eight listing photographs showed one of them.
///
/// Built like the listing page's pager (`ListingGallery`) on purpose: a
/// paging scroll view the photograph follows one-to-one, no rubber band past
/// the ends, and dots worked out from the scroll's own geometry so they turn
/// over at the halfway point with the picture. Each page is a `Button`, not a
/// bare tap gesture: a paging `ScrollView` wins arbitration over a discrete
/// tap and swallows it, which is exactly how the listing gallery's lightbox
/// once stopped opening.
struct VaultGalleryPager: View {
    let watch: VaultWatch
    /// Absolute addresses, each already known to resolve to a fetchable
    /// source; the screen filters before it builds this.
    let pictures: [URL]
    let onOpen: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    var body: some View {
        VStack(spacing: Space.m) {
            GeometryReader { proxy in
                let side = proxy.size.width
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(pictures.enumerated()), id: \.element) { index, url in
                            Button {
                                onOpen(index)
                            } label: {
                                VaultPhotoFrame(watch: watch, variant: .page, side: side, picture: url)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                            .frame(width: side, height: side)
                            .accessibilityValue(pictures.count > 1 ? "\(index + 1) of \(pictures.count)" : "")
                            .accessibilityHint("Opens the photograph full screen")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollDisabled(pictures.count < 2)
                .onScrollGeometryChange(for: Int.self) { geometry in
                    guard side > 0 else { return 0 }
                    let crossed = Int(geometry.visibleRect.midX / side)
                    return min(max(crossed, 0), max(pictures.count - 1, 0))
                } action: { _, reached in
                    if page != reached { page = reached }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            // Each page is rounded by its own frame, but a page mid-swipe is
            // cut by the edge of the square rather than showing its corners
            // sliding past its neighbour's.
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            if pictures.count > 1 {
                HStack(spacing: 6) {
                    ForEach(pictures.indices, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.rewound.primary : Color.rewound.borderBright)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : Motion.easeFast, value: page)
    }
}
