@preconcurrency import AVFoundation
import CalibreDesign
import CalibreKit
@preconcurrency import PhotosUI
import SwiftUI
import UIKit

/// What the camera opens onto: a required category slot or a free extra shot.
struct CaptureTarget: Identifiable {
    let category: ListingImageCategory?
    var id: String { category?.rawValue ?? "extra" }

    var title: String { category?.label ?? "More photos" }
    var instruction: String { category?.instruction ?? "Anything else a buyer should see" }
}

/// The camera moment: AVCapture preview with a per-category framing overlay,
/// tap-to-focus, flash and grid toggles, shutter → review → use/retake.
/// Falls back to the system photo library when no camera exists
/// (simulator) or access is declined.
struct CaptureScreen: View {
    let target: CaptureTarget
    let onUse: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var captured: UIImage?
    @State private var flashOn = false
    @State private var gridOn = false
    @State private var libraryFailed = false
    @State private var showingLibrary = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let captured {
                reviewLayer(captured)
            } else if camera.unavailable {
                pickerFallback
            } else {
                cameraLayer
            }
        }
        .statusBarHidden()
        // Keep the native popup attached to this stable screen root, like
        // Vault's picker, rather than a camera subview that can be replaced.
        .modifier(ListingPhotoLibrary(isPresented: $showingLibrary) { image in
            captured = image
        } onFailure: {
            libraryFailed = true
        })
        .alert("Couldn't open this photo", isPresented: $libraryFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try another photo, or download it from iCloud in Photos and try again.")
        }
        .task(id: showingLibrary || captured != nil) {
            if showingLibrary || captured != nil {
                camera.stop()
            } else {
                await camera.start()
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    // MARK: - Live camera

    private var cameraLayer: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreview(controller: camera)
                    .ignoresSafeArea()
                    .onTapGesture { location in
                        camera.focus(at: location, in: proxy.size)
                    }

                if gridOn {
                    gridOverlay
                }

                overlayShape
                    .stroke(Color(white: 1).opacity(0.35), lineWidth: 2)
                    .padding(overlayPadding)
                    .allowsHitTesting(false)

                VStack {
                    topBar
                    Spacer()
                    VStack(spacing: Space.l) {
                        Text(target.instruction)
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color(white: 1))
                            .padding(.horizontal, Space.l)
                            .padding(.vertical, Space.s)
                            .background(Color.black.opacity(0.45), in: Capsule())
                        shutterRow
                    }
                    .padding(.bottom, Space.xxl)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(white: 1))
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .background(Color.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Close camera")

            Spacer()

            Text(target.title)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color(white: 1))

            Spacer()

            HStack(spacing: Space.s) {
                cameraToggle(
                    icon: gridOn ? "grid.circle.fill" : "grid.circle",
                    label: "Grid",
                    active: gridOn
                ) {
                    gridOn.toggle()
                }
                cameraToggle(
                    icon: flashOn ? "bolt.fill" : "bolt.slash",
                    label: "Flash",
                    active: flashOn
                ) {
                    flashOn.toggle()
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private func cameraToggle(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Color.calibre.primary : Color(white: 1))
                .frame(width: Space.touchTarget, height: Space.touchTarget)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var shutterRow: some View {
        ZStack {
            // Shutter stays dead-centre; the library sits out to its right.
            Button {
                Haptics.shared.play(.capture)
                camera.capture(flash: flashOn) { image in
                    captured = image
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color(white: 1), lineWidth: 4)
                        .frame(width: 74, height: 74)
                    Circle()
                        .fill(Color(white: 1))
                        .frame(width: 60, height: 60)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Take photo")

            HStack {
                Spacer()
                libraryButton
            }
            .padding(.horizontal, Space.xl)
        }
    }

    /// Not every good shot happens live — let sellers reach their camera roll
    /// without backing out of the wizard.
    private var libraryButton: some View {
        Button {
            showingLibrary = true
        } label: {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(white: 1))
                .frame(width: 52, height: 52)
                .background(Color.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(Color(white: 1).opacity(0.35), lineWidth: 1))
        }
        .accessibilityLabel("Choose from library")
    }

    private var gridOverlay: some View {
        GeometryReader { proxy in
            Path { path in
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    path.move(to: CGPoint(x: proxy.size.width * fraction, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width * fraction, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: proxy.size.height * fraction))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * fraction))
                }
            }
            .stroke(Color(white: 1).opacity(0.25), lineWidth: 0.5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Framing overlays

    /// Per-category guide at 35% opacity.
    private var overlayShape: AnyShape {
        switch target.category {
        case .front, .caseback:
            AnyShape(Circle())
        case .leftProfile, .rightProfile:
            AnyShape(RoundedRectangle(cornerRadius: 60, style: .continuous))
        case .clasp:
            AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .fullSet, .none:
            AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var overlayPadding: EdgeInsets {
        switch target.category {
        case .front, .caseback:
            EdgeInsets(top: 140, leading: 36, bottom: 220, trailing: 36)
        case .leftProfile, .rightProfile:
            EdgeInsets(top: 130, leading: 90, bottom: 210, trailing: 90)
        case .clasp:
            EdgeInsets(top: 200, leading: 60, bottom: 280, trailing: 60)
        case .fullSet, .none:
            EdgeInsets(top: 170, leading: 30, bottom: 250, trailing: 30)
        }
    }

    // MARK: - Review

    private func reviewLayer(_ image: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: Space.m) {
                Button("Retake") {
                    captured = nil
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))

                Button("Use photo") {
                    onUse(image)
                    dismiss()
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.l)
            .background(Color.black)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Picker fallback (simulator / no camera access)

    private var pickerFallback: some View {
        VStack(spacing: Space.xl) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(white: 1))
                        .frame(width: Space.touchTarget, height: Space.touchTarget)
                        .background(Color(white: 1).opacity(0.14), in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)

            Spacer()

            VStack(spacing: Space.m) {
                IconTile(systemName: "camera")
                Text(target.title)
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color(white: 1))
                Text(camera.deniedAccess
                    ? "Camera access is off for Calibre. You can allow it in Settings, or pick a photo from your library."
                    : "No camera here — pick a photo from your library instead.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color(white: 0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xxl)
                Text(target.instruction)
                    .font(CalibreType.label)
                    .foregroundStyle(Color(white: 0.72))
            }

            Button("Choose from library") {
                showingLibrary = true
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .padding(.horizontal, Space.margin)

            Spacer()
        }
    }
}

// MARK: - Camera controller

/// Owns the AVCaptureSession off the main thread; publishes availability so
/// the view can fall back to the system photo library.
@MainActor
@Observable
final class CameraController {
    private(set) var unavailable = false
    private(set) var deniedAccess = false

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.buycalibre.capture")
    @ObservationIgnored private var delegateBox: PhotoDelegate?
    @ObservationIgnored weak var previewLayer: AVCaptureVideoPreviewLayer?

    func start() async {
        #if targetEnvironment(simulator)
        unavailable = true
        return
        #else
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            unavailable = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                deniedAccess = true
                unavailable = true
                return
            }
        case .denied, .restricted:
            deniedAccess = true
            unavailable = true
            return
        case .authorized:
            break
        @unknown default:
            break
        }

        guard !Task.isCancelled else { return }
        device = camera
        let session = session
        let output = output
        queue.async {
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.inputs.isEmpty,
               let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
        #endif
    }

    func stop() {
        let session = session
        queue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// Tap-to-focus at a point in view coordinates.
    func focus(at point: CGPoint, in size: CGSize) {
        guard let device else { return }
        let devicePoint: CGPoint
        if let previewLayer {
            devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        } else {
            devicePoint = CGPoint(x: point.y / size.height, y: 1 - point.x / size.width)
        }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    func capture(flash: Bool, completion: @escaping @MainActor (UIImage) -> Void) {
        let settings = AVCapturePhotoSettings()
        if output.supportedFlashModes.contains(.on) {
            settings.flashMode = flash ? .on : .off
        }
        let delegate = PhotoDelegate { image in
            Task { @MainActor in
                completion(image)
            }
        }
        delegateBox = delegate
        output.capturePhoto(with: settings, delegate: delegate)
    }

    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        private let onImage: @Sendable (UIImage) -> Void

        init(onImage: @escaping @Sendable (UIImage) -> Void) {
            self.onImage = onImage
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                return
            }
            onImage(image)
        }
    }
}

/// The AVCaptureVideoPreviewLayer host.
private struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = controller.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        controller.previewLayer = view.videoPreviewLayer
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

#if DEBUG
/// Offline regression fixture retaining the wizard → capture modal stack.
struct ListingPhotoPickerSmokeScreen: View {
    @State private var wizard = false
    var body: some View {
        Button("Open listing wizard") { wizard = true }
            .fullScreenCover(isPresented: $wizard) { ListingPhotoPickerSmokeWizard() }
    }
}
private struct ListingPhotoPickerSmokeWizard: View {
    @State private var target: CaptureTarget?
    @State private var photo: UIImage?
    @State private var replacement: PhotoReplaceTarget?
    var body: some View {
        VStack {
            Button("Add front photo") { target = CaptureTarget(category: .front) }
            if let photo {
                Image(uiImage: photo).resizable().scaledToFit()
                Text("Photo received")
                Button("Replace front photo") { replacement = PhotoReplaceTarget(category: .front) }
            }
        }
        .fullScreenCover(item: $target) { target in
            CaptureScreen(target: target) { photo = $0 }
        }
        .fullScreenCover(item: $replacement) { target in
            PhotoPreviewScreen(target: target, slot: nil) { photo = $0 }
        }
    }
}
#endif

/// The same native Photos popup used by Vault. The modifier stays attached
/// to the capture/preview root while the camera and selected image change.
struct ListingPhotoLibrary: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (UIImage) -> Void
    let onFailure: () -> Void

    @State private var selection: [PhotosPickerItem] = []
    @State private var loading = false

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $selection,
                maxSelectionCount: 1,
                matching: .images,
                preferredItemEncoding: .current
            )
            .overlay {
                if loading && !isPresented {
                    ProgressView("Loading photo")
                        .padding(Space.l)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.box))
                }
            }
            .onChange(of: isPresented) { _, opened in
                if opened { Observability.log(.info, "listing_photo_library_open") }
            }
            .task(id: selection) {
                guard let item = selection.first else { return }
                loading = true
                defer {
                    loading = false
                    selection = []
                }
                Observability.log(.info, "listing_photo_library_selected")
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw PhotoImport.Failure.unreadable
                    }
                    let image = await Task.detached(priority: .userInitiated) {
                        PhotoImport.decode(data)
                    }.value
                    guard !Task.isCancelled else { return }
                    guard let image else { throw PhotoImport.Failure.unreadable }
                    Observability.log(.info, "listing_photo_library_ready")
                    onPick(image)
                } catch {
                    guard !Task.isCancelled else { return }
                    Observability.log(.warning, "listing_photo_library_decode_failed")
                    onFailure()
                }
            }
    }
}

#if DEBUG
struct ConsumerPageSwipeSmokeScreen: View {
    @State private var page = 0
    @State private var scrollY: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabs(selection: $page, items: [(0, "Listings"), (1, "Market"), (2, "Offers")])
            Text("Page \(page), offset \(Int(scrollY))").accessibilityIdentifier("swipe-status")
            ScrollView {
                VStack(spacing: 20) {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(0..<12) { index in Text("Filter \(index)").frame(width: 100, height: 48) }
                        }
                    }
                    .accessibilityIdentifier("swipe-rail")
                    ForEach(0..<30) { index in
                        Text("Page \(page) row \(index)")
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in scrollY = value }
        }
        .calibrePageSwipe(selection: $page, values: [0, 1, 2])
    }
}
#endif
