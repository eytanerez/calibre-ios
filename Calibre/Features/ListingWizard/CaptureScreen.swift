@preconcurrency import AVFoundation
import CalibreDesign
import CalibreKit
import PhotosUI
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
/// Falls back to PhotosPicker automatically when no camera exists
/// (simulator) or access is declined.
struct CaptureScreen: View {
    let target: CaptureTarget
    let onUse: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var captured: UIImage?
    @State private var flashOn = false
    @State private var gridOn = false
    @State private var pickerItem: PhotosPickerItem?

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
        .task {
            await camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    captured = image
                }
                pickerItem = nil
            }
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

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("Choose from library")
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .padding(.horizontal, Space.margin)

            Spacer()
        }
    }
}

// MARK: - Camera controller

/// Owns the AVCaptureSession off the main thread; publishes availability so
/// the view can fall back to PhotosPicker.
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

        device = camera
        let session = session
        let output = output
        queue.async {
            session.beginConfiguration()
            session.sessionPreset = .photo
            if let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()
            session.startRunning()
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
