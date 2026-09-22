@preconcurrency import AVFoundation
import RewoundDesign
import RewoundKit
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
    /// Set when the screen underneath will open the photo library itself.
    ///
    /// The library button then stops the camera and hands over rather than
    /// presenting Photos on top of a live capture session. That is the one
    /// thing Vault's picker, which has never failed, does not have to survive:
    /// it opens from a plain sheet. Opening Photos from here meant a picker
    /// three modal levels deep over a running `AVCaptureSession`, and the
    /// listing library went on failing through two fixes aimed at the session
    /// alone. The presenter is expected to remove this screen when called;
    /// `ListingPhotoCapture` is the one that does. Left nil — returns still
    /// leave it nil — the library opens here, as it always has.
    var onChooseLibrary: (() -> Void)? = nil
    let onUse: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var captured: UIImage?
    @State private var flashOn = false
    @State private var gridOn = false
    @State private var libraryFailed = false
    @State private var showingLibrary = false
    @State private var librarySelectionPending = false
    @State private var handingOff = false

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
            // PhotosUI dismisses before its asynchronous import finishes. Keep
            // the preview mounted until AVFoundation has stopped before
            // replacing it (REWOUND-IOS-3).
            librarySelectionPending = true
            Task { @MainActor in
                await camera.stopAndWait()
                // The screen can go while the import is still in flight — the
                // seller taps the X, or the wizard moves on. `abandonImport()`
                // is what clears this, and without something clearing it the
                // guard was decoration: nothing but the success path below
                // ever wrote to it, so it could not be false when read.
                guard librarySelectionPending else { return }
                captured = image
                librarySelectionPending = false
            }
        } onFailure: {
            librarySelectionPending = false
            libraryFailed = true
        })
        .alert("Couldn't open this photo", isPresented: $libraryFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try another photo, or download it from iCloud in Photos and try again.")
        }
        .task(id: showingLibrary || captured != nil || librarySelectionPending) {
            if showingLibrary || captured != nil || librarySelectionPending {
                await camera.stopAndWait()
            } else {
                await camera.start()
            }
        }
        .onDisappear {
            abandonImport()
            camera.stop()
        }
    }

    /// Open the photo library: from the screen underneath when it offered
    /// to (`onChooseLibrary`), otherwise here over the camera as before.
    ///
    /// The camera is stopped before the handoff, not by the presenter tearing
    /// this screen down, so the session is never running while its preview
    /// leaves the hierarchy. `handingOff` stops a second tap during that await
    /// from handing over twice.
    private func chooseFromLibrary() {
        guard let onChooseLibrary else {
            showingLibrary = true
            return
        }
        guard !handingOff else { return }
        handingOff = true
        abandonImport()
        Task { @MainActor in
            await camera.stopAndWait()
            onChooseLibrary()
        }
    }

    private func closeCapture() {
        abandonImport()
        Task { @MainActor in
            await camera.stopAndWait()
            dismiss()
        }
    }

    /// Drop a library import whose screen is already going.
    ///
    /// The import outlives the tap that started it: PhotosUI hands the bytes
    /// back on its own schedule, and the decode runs off the main thread after
    /// that. A seller who selects a photo and immediately closes the camera
    /// would otherwise have it arrive into a screen they left, restart the
    /// camera behind them through `.task(id:)`, and land a photo in the slot
    /// they had just decided against.
    private func abandonImport() {
        librarySelectionPending = false
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
                            .font(RewoundType.bodyMedium)
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
                closeCapture()
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
                .font(RewoundType.bodyMedium)
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
                .foregroundStyle(active ? Color.rewound.primary : Color(white: 1))
                .frame(width: Space.touchTarget, height: Space.touchTarget)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var shutterRow: some View {
        ZStack {
            // Shutter stays dead-center; the library sits out to its right.
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
            chooseFromLibrary()
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
                .buttonStyle(.rewound(.secondary, fullWidth: true))

                Button("Use photo") {
                    Task { @MainActor in
                        await camera.stopAndWait()
                        onUse(image)
                        dismiss()
                    }
                }
                .buttonStyle(.rewound(.primary, fullWidth: true))
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
                    closeCapture()
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
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color(white: 1))
                Text(camera.deniedAccess
                    ? "Camera access is off for Rewound. You can allow it in Settings, or pick a photo from your library."
                    : "No camera here — pick a photo from your library instead.")
                    .font(RewoundType.body)
                    .foregroundStyle(Color(white: 0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xxl)
                Text(target.instruction)
                    .font(RewoundType.label)
                    .foregroundStyle(Color(white: 0.72))
            }

            Button("Choose from library") {
                chooseFromLibrary()
            }
            .buttonStyle(.rewound(.primary, fullWidth: true))
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
    @ObservationIgnored private let queue = DispatchQueue(label: "com.shoprewound.capture")
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
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
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
                continuation.resume()
            }
        }
        #endif
    }

    func stop() {
        Task { @MainActor in
            await stopAndWait()
        }
    }

    /// Stop after queued configuration work and resume once the preview can
    /// safely be removed from the view hierarchy.
    func stopAndWait() async {
        let session = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
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
        .modifier(ListingPhotoCapture(target: $target) { image, _ in photo = image })
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
            .onChange(of: selection) { _, items in
                guard let item = items.first else { return }
                Task { await importSelection(item) }
            }
    }

    /// Keep the picker lifecycle separate from the async import. Clearing the
    /// binding from a `.task(id:)` cancels that task on some iOS releases,
    /// which made the listing picker dismiss before the image reached the
    /// wizard. Vault uses this on-change pattern successfully as well.
    @MainActor
    private func importSelection(_ item: PhotosPickerItem) async {
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
            guard let image else { throw PhotoImport.Failure.unreadable }
            Observability.log(.info, "listing_photo_library_ready")
            onPick(image)
        } catch {
            Observability.log(.warning, "listing_photo_library_decode_failed")
            onFailure()
        }
    }
}

/// The camera for a listing photo, with the library opened the way Vault
/// opens it: from this screen, which is a plain one, and never over the live
/// camera.
///
/// The camera's library button hands over (`CaptureScreen.onChooseLibrary`).
/// This closes the camera, waits for the dismissal to finish, and only then
/// shows Photos. Presenting in the same update as the dismissal is the other
/// way a SwiftUI picker silently fails to appear, so the order is the cover's
/// own `onDismiss`, not a guess at an animation length.
///
/// A photo from the library goes straight into the slot, as it does in Vault.
/// The camera's review step exists to allow a retake, and a photo picked from
/// the library has already been chosen.
struct ListingPhotoCapture: ViewModifier {
    @Binding var target: CaptureTarget?
    let onPhoto: (UIImage, CaptureTarget) -> Void

    /// The slot the camera asked the library to fill, held across the
    /// dismissal that has to finish before Photos can open.
    @State private var pendingLibrary: CaptureTarget?
    /// The slot the open picker is filling. Read when the photo arrives, which
    /// is after the picker has closed.
    @State private var libraryTarget: CaptureTarget?
    @State private var showingLibrary = false
    @State private var libraryFailed = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $target, onDismiss: openPendingLibrary) { current in
                CaptureScreen(target: current, onChooseLibrary: {
                    pendingLibrary = current
                    target = nil
                }) { image in
                    onPhoto(image, current)
                }
            }
            .modifier(ListingPhotoLibrary(isPresented: $showingLibrary) { image in
                guard let filling = libraryTarget else { return }
                libraryTarget = nil
                onPhoto(image, filling)
            } onFailure: {
                libraryTarget = nil
                libraryFailed = true
            })
            .alert("Couldn't open this photo", isPresented: $libraryFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try another photo, or download it from iCloud in Photos and try again.")
            }
    }

    private func openPendingLibrary() {
        guard let pending = pendingLibrary else { return }
        pendingLibrary = nil
        libraryTarget = pending
        showingLibrary = true
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
        .rewoundPageSwipe(selection: $page, values: [0, 1, 2])
    }
}
#endif
