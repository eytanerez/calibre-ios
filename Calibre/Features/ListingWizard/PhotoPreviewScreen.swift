import CalibreDesign
import CalibreKit
import NukeUI
import PhotosUI
import SwiftUI

/// Which filled slot the seller tapped, for the preview-then-replace flow.
struct PhotoReplaceTarget: Identifiable {
    let category: ListingImageCategory
    var id: String { category.rawValue }
}

/// Tapping a slot that already holds a photo shows *that* photo first, with
/// the way to replace it underneath. Dropping straight into the camera meant a
/// seller checking their Clasp shot had no way to look without reshooting.
struct PhotoPreviewScreen: View {
    let target: PhotoReplaceTarget
    let slot: WizardPhotoSlot?
    /// The seller's own mark on this photo, when there is one. A mark is
    /// keyed on the photo's position, so replacing the picture drops it — the
    /// server discards it rather than re-pointing it at a different shot.
    var mark: ListingAnnotation?
    let onReplace: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var capturing = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingLibrary = false
    /// Set when a replacement is one confirmation away from losing a mark.
    @State private var pendingReplacement: Replacement?

    /// Which way the seller chose to replace the photo, held while they are
    /// asked about the mark it would take with it.
    private enum Replacement: Identifiable {
        case camera
        case library

        var id: Int {
            switch self {
            case .camera: 0
            case .library: 1
            }
        }
    }

    var body: some View {
        Group {
            if capturing {
                // Swapped inline rather than stacked as a second cover —
                // presenting one full-screen cover from another's dismissal
                // drops the presentation often enough to avoid entirely.
                CaptureScreen(target: CaptureTarget(category: target.category)) { image in
                    onReplace(image)
                    dismiss()
                }
            } else {
                preview
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onReplace(image)
                    dismiss()
                }
                pickerItem = nil
            }
        }
        // Losing a line is visible; a line drawn across the wrong part of the
        // watch is not. So the mark is cleared rather than moved, and the
        // seller is told before it happens rather than after.
        .alert(
            "Your mark comes off",
            isPresented: Binding(
                get: { pendingReplacement != nil },
                set: { if !$0 { pendingReplacement = nil } }
            ),
            presenting: pendingReplacement
        ) { replacement in
            Button("Replace the photo", role: .destructive) {
                pendingReplacement = nil
                proceed(with: replacement)
            }
            Button("Keep this one", role: .cancel) {
                pendingReplacement = nil
            }
        } message: { _ in
            Text(markWarning)
        }
    }

    private var markWarning: String {
        guard let note = mark?.note, !note.isEmpty else {
            return "You drew on this photo. A new one comes in without the mark, and you can draw it again."
        }
        return "You drew on this photo and wrote \u{201C}\(note)\u{201D}. A new one comes in without the mark, and you can draw it again."
    }

    /// Every route to a new photo goes through here, so the mark can only be
    /// lost on the far side of the question.
    private func replace(with replacement: Replacement) {
        guard mark != nil else {
            proceed(with: replacement)
            return
        }
        pendingReplacement = replacement
    }

    private func proceed(with replacement: Replacement) {
        switch replacement {
        case .camera:
            Haptics.shared.play(.press)
            capturing = true
        case .library:
            showingLibrary = true
        }
    }

    private var preview: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                photo
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: Space.m) {
                    Button("Take a new photo") {
                        replace(with: .camera)
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))

                    // A button rather than a `PhotosPicker` label: the picker
                    // opens the instant its label is tapped, and the question
                    // about the mark has to come first.
                    Button {
                        replace(with: .library)
                    } label: {
                        Text("Choose from library")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color(white: 1))
                            .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
                            .background(
                                Color(white: 1).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            )
                    }
                    .photosPicker(
                        isPresented: $showingLibrary,
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    )
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.l)
                .background(Color.black)
            }
            .ignoresSafeArea(edges: .top)

            VStack {
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
                    .accessibilityLabel("Close")

                    Spacer()

                    Text(target.category.label)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color(white: 1))
                        .padding(.horizontal, Space.l)
                        .padding(.vertical, Space.s)
                        .background(Color.black.opacity(0.45), in: Capsule())

                    Spacer()

                    Color.clear.frame(width: Space.touchTarget, height: Space.touchTarget)
                }
                .padding(.horizontal, Space.l)
                Spacer()
            }
        }
        .statusBarHidden()
    }

    @ViewBuilder
    private var photo: some View {
        if let localURL = slot?.localURL, let image = UIImage(contentsOfFile: localURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let remoteURL = slot?.remoteURL {
            LazyImage(url: remoteURL) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    ProgressView().tint(Color(white: 1))
                }
            }
        } else {
            Color.black
        }
    }
}
