import CalibreDesign
import Nuke
import NukeUI
import SwiftUI

/// The PDP hero: a full-bleed square pager with counter dots and the
/// condition pill. Tap or pinch opens the full-screen lightbox.
struct ListingGallery: View {
    let images: [URL?]
    let condition: String?
    let onOpenLightbox: (Int) -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: Space.m) {
            TabView(selection: $page) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                    ListingImageWell(url: url, targetWidth: 900)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onOpenLightbox(index)
                        }
                        .tag(index)
                        .accessibilityLabel("Photo \(index + 1) of \(images.count)")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(1, contentMode: .fit)
            .background(Color.calibre.secondary.opacity(0.5))
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

            if images.count > 1 {
                HStack(spacing: 6) {
                    ForEach(images.indices, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.calibre.primary : Color.calibre.borderBright)
                            .frame(width: 6, height: 6)
                    }
                }
                .animation(Motion.easeFast, value: page)
                .accessibilityHidden(true)
            }
        }
    }
}

/// Which photo the lightbox opens on.
struct LightboxContext: Identifiable {
    let id = UUID()
    let page: Int
}

/// Full-screen gallery: black stage, pinch-zoomable pages, drag-down to
/// dismiss (when not zoomed), photo counter and a close button.
struct GalleryLightbox: View {
    let images: [URL?]
    let startPage: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false

    init(images: [URL?], startPage: Int) {
        self.images = images
        self.startPage = startPage
        _page = State(initialValue: startPage)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(backdropOpacity)

            TabView(selection: $page) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                    ZoomableRemoteImage(url: url, isZoomed: $isZoomed)
                        .tag(index)
                        .accessibilityLabel("Photo \(index + 1) of \(images.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: reduceMotion ? 0 : dragOffset)
        }
        .overlay(alignment: .top) {
            HStack {
                Text("\(page + 1) of \(images.count)")
                    .font(CalibreType.label)
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
                        .background(Color(white: 1).opacity(0.12), in: Circle())
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

/// UIScrollView-backed pinch-zoom for one remote photo (1×–4×, double-tap
/// toggles). Reports zoom state so the container can arbitrate gestures.
private struct ZoomableRemoteImage: UIViewRepresentable {
    let url: URL?
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

        context.coordinator.load(url, into: view)
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        context.coordinator.onZoomChange = { zoomed in
            if isZoomed != zoomed {
                isZoomed = zoomed
            }
        }
        context.coordinator.load(url, into: view)
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
        private var loadedURL: URL?

        func load(_ url: URL?, into view: ZoomScrollView) {
            guard loadedURL != url else { return }
            imageTask?.cancel()
            imageTask = nil
            loadedURL = url
            view.imageView.image = nil

            guard let url else { return }
            imageTask = ImagePipeline.shared.loadImage(with: ImageRequest(url: url)) { [weak self, weak view] result in
                guard let self, self.loadedURL == url else { return }
                self.imageTask = nil
                if case .success(let response) = result {
                    view?.imageView.image = response.image
                }
            }
        }

        func cancelImageLoad() {
            imageTask?.cancel()
            imageTask = nil
            loadedURL = nil
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
