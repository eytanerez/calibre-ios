import RewoundDesign
import RewoundKit
import ImageIO
import Nuke
import NukeUI
import SwiftUI

/// The PDP hero: a full-bleed square pager with counter dots and the
/// condition pill. Tap or pinch opens the full-screen lightbox.
///
/// The photograph tracks the finger and settles — it is a paging scroll view,
/// not a control that swaps one image for another when a swipe is recognized.
/// A page follows the drag one-to-one, comes to rest on the brand's own
/// deceleration, and stops dead at the first and last photograph rather than
/// rubber-banding past them (`.scrollBounceBehavior(.basedOnSize)`), because
/// §5's motion rules refuse bounce.
///
/// And the dots are honest while it moves: `page` is recomputed from the
/// scroll's own geometry as the finger travels, so the filled dot — and the
/// seller's caption under the photograph — change at the halfway point, with
/// the photograph they belong to. Read from `selection` they would lag until
/// the scroll had finished and the caption would belong to the previous
/// picture for the length of the swipe.
struct ListingGallery: View {
    let images: [URL?]
    let condition: String?
    let onOpenLightbox: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    var body: some View {
        VStack(spacing: Space.m) {
            pager

            if images.count > 1 {
                HStack(spacing: 6) {
                    ForEach(images.indices, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.rewound.primary : Color.rewound.borderBright)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        // The dot filling is the only motion here that is the interface's
        // rather than the reader's finger; under Reduce Motion it changes
        // without one.
        .animation(reduceMotion ? nil : Motion.easeFast, value: page)
    }

    /// The square the photographs travel across.
    ///
    /// `GeometryReader` under a 1:1 aspect ratio gives the square and, with it,
    /// the page width — every photograph is framed to exactly that, which is
    /// what makes each one a paging stop and what lets the scroll's offset be
    /// read back as a page number.
    private var pager: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                        photo(index: index, url: url)
                            .frame(width: side, height: proxy.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollDisabled(images.count < 2)
            .onScrollGeometryChange(for: Int.self) { geometry in
                guard side > 0 else { return 0 }
                // The midpoint of what is on screen, so the count turns over
                // as the next photograph takes the larger half of the frame.
                let crossed = Int(geometry.visibleRect.midX / side)
                return min(max(crossed, 0), max(images.count - 1, 0))
            } action: { _, reached in
                if page != reached { page = reached }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.rewound.secondary.opacity(0.5))
        .overlay(alignment: .topLeading) {
            if let condition {
                ConditionPill(condition)
                    .padding(Space.l)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if value.magnification > 1.15 {
                        onOpenLightbox(page)
                    }
                }
        )
    }

    private func photo(index: Int, url: URL?) -> some View {
        // A `Button`, not `.onTapGesture` — this tile sits inside a paging
        // `ScrollView` (`.scrollTargetBehavior(.paging)`), which wins gesture
        // arbitration over a bare discrete tap gesture and swallows it
        // entirely. Every other tappable image in the app is already a
        // `Button` for the same reason (`ListingGridCard` in
        // `BrowseSupport.swift`), and a real button's gesture machinery is
        // what coexists correctly with the enclosing scroll view.
        Button {
            onOpenLightbox(index)
        } label: {
            ListingImageWell(url: url, targetWidth: 900)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Photo \(index + 1) of \(images.count)")
    }
}

/// Which photo the lightbox opens on.
struct LightboxContext: Identifiable {
    let id = UUID()
    let page: Int
}

/// One picture the lightbox can show, and how its bytes may be fetched.
///
/// Two kinds, because they are two kinds of fetch (`VaultCoverSource` draws the
/// same line): a public photograph goes through Nuke like every other picture
/// in the app, and a member's own photograph is behind their session, so its
/// bytes come from `PrivateMediaLoader` and never touch Nuke's disk cache.
enum LightboxPicture: Equatable {
    case remote(URL?)
    case privateMedia(URL)

    /// What the page loads, so a page handed the same picture again does not
    /// start over.
    var address: URL? {
        switch self {
        case .remote(let url): url
        case .privateMedia(let url): url
        }
    }
}

/// Full-screen gallery: black stage, pinch-zoomable pages, drag-down to
/// dismiss (when not zoomed), photo counter and a close button.
struct GalleryLightbox: View {
    let pictures: [LightboxPicture]
    let startPage: Int
    /// Reads `.privateMedia` pictures. Nil where every picture is public,
    /// which is every listing.
    let privateMedia: (any PrivateMediaFetching)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false

    /// A listing's photographs: all public.
    init(images: [URL?], startPage: Int) {
        self.init(pictures: images.map(LightboxPicture.remote), startPage: startPage, privateMedia: nil)
    }

    init(pictures: [LightboxPicture], startPage: Int, privateMedia: (any PrivateMediaFetching)?) {
        self.pictures = pictures
        self.startPage = startPage
        self.privateMedia = privateMedia
        _page = State(initialValue: startPage)
    }

    private var count: Int { pictures.count }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(backdropOpacity)

            TabView(selection: $page) {
                ForEach(Array(pictures.enumerated()), id: \.offset) { index, picture in
                    ZoomableRemoteImage(picture: picture, privateMedia: privateMedia, isZoomed: $isZoomed)
                        .tag(index)
                        .accessibilityLabel("Photo \(index + 1) of \(count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: reduceMotion ? 0 : dragOffset)
        }
        .overlay(alignment: .top) {
            HStack {
                Text("\(page + 1) of \(count)")
                    .font(RewoundType.label)
                    .foregroundStyle(Color(white: 1).opacity(0.85))
                    .monospacedDigit()

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(white: 1).opacity(0.9))
                        .frame(width: Space.touchTarget, height: Space.touchTarget)
                        .contentShape(Circle())
                        // ONE layer, not two: this used to hand-roll its own
                        // translucent disc on top of the automatic chrome a
                        // plain circular icon button picks up on iOS 26 — two
                        // discs painted in the same place. There is no
                        // toolbar here to hand the chrome to (the admin
                        // app's `sharedBackgroundVisibility(.hidden)`
                        // precedent), so the app supplies the single layer
                        // itself with the design system's own glass instead
                        // of a bespoke background.
                        .rewoundGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close photos")
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s)
            .opacity(dragOffset == 0 ? 1 : 0.4)
        }
        .simultaneousGesture(dismissDrag)
        .statusBarHidden()
        .animation(Motion.easeFast, value: dragOffset == 0)
    }

    private var backdropOpacity: CGFloat {
        guard !reduceMotion else { return 1 }
        return max(0.4, 1 - dragOffset / 600)
    }

    /// Vertical pull dismisses; horizontal swipes stay with the pager, and a
    /// zoomed photo pans instead of dismissing.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !isZoomed,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !isZoomed else { return }
                if dragOffset > 110 || value.predictedEndTranslation.height > 320 {
                    dismiss()
                } else {
                    withAnimation(Motion.easeFast) { dragOffset = 0 }
                }
            }
    }
}

/// UIScrollView-backed pinch-zoom for one photo (1×–4×, double-tap
/// toggles). Reports zoom state so the container can arbitrate gestures.
private struct ZoomableRemoteImage: UIViewRepresentable {
    let picture: LightboxPicture
    let privateMedia: (any PrivateMediaFetching)?
    @Binding var isZoomed: Bool

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.delegate = context.coordinator
        context.coordinator.scrollView = view

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        context.coordinator.load(picture, privateMedia: privateMedia, into: view)
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        context.coordinator.onZoomChange = { zoomed in
            if isZoomed != zoomed {
                isZoomed = zoomed
            }
        }
        context.coordinator.load(picture, privateMedia: privateMedia, into: view)
    }

    static func dismantleUIView(_ uiView: ZoomScrollView, coordinator: Coordinator) {
        coordinator.cancelImageLoad()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: ZoomScrollView?
        var onZoomChange: ((Bool) -> Void)?
        private var imageTask: ImageTask?
        private var privateTask: Task<Void, Never>?
        private var loadedURL: URL?

        /// The long side a private photograph is decoded to. Enough to zoom
        /// into at 4× on a phone, and a fraction of a full-resolution decode of
        /// a picture the member took on the phone now drawing it.
        private static let privateDecodePixels = 2_400

        func load(_ picture: LightboxPicture, privateMedia: (any PrivateMediaFetching)?, into view: ZoomScrollView) {
            let url = picture.address
            guard loadedURL != url else { return }
            cancelImageLoad()
            loadedURL = url
            view.imageView.image = nil

            switch picture {
            case .remote(let url):
                guard let url else { return }
                imageTask = ImagePipeline.shared.loadImage(with: ImageRequest(url: url)) { [weak self, weak view] result in
                    guard let self, self.loadedURL == url else { return }
                    self.imageTask = nil
                    if case .success(let response) = result {
                        view?.imageView.image = response.image
                    }
                }
            case .privateMedia(let url):
                // No fetcher, no credential: a private picture is left blank
                // rather than handed to a loader that would send none.
                guard let privateMedia else { return }
                privateTask = Task { [weak self, weak view] in
                    guard let data = try? await privateMedia.data(for: url) else { return }
                    let image = await Self.decode(data, maxPixels: Self.privateDecodePixels)
                    guard !Task.isCancelled, let self, self.loadedURL == url else { return }
                    view?.imageView.image = image
                }
            }
        }

        func cancelImageLoad() {
            imageTask?.cancel()
            imageTask = nil
            privateTask?.cancel()
            privateTask = nil
            loadedURL = nil
        }

        private static func decode(_ data: Data, maxPixels: Int) async -> UIImage? {
            await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    return UIImage(data: data)
                }
                return UIImage(cgImage: cgImage)
            }.value
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
            onZoomChange?(scrollView.zoomScale > 1.02)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.02 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: scrollView.imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / 2.5,
                    height: scrollView.bounds.height / 2.5
                )
                scrollView.zoom(
                    to: CGRect(
                        x: point.x - size.width / 2,
                        y: point.y - size.height / 2,
                        width: size.width,
                        height: size.height
                    ),
                    animated: true
                )
            }
        }
    }
}

/// UIScrollView that keeps its aspect-fit image view sized to the viewport
/// and centered while zooming.
final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 {
            imageView.frame = bounds
            contentSize = bounds.size
        }
        centerContent()
    }

    func centerContent() {
        let dx = max(0, (bounds.width - contentSize.width) / 2)
        let dy = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }
}
