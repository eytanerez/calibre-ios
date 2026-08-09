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
    let onReplace: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var capturing = false
    @State private var pickerItem: PhotosPickerItem?

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
    }

    private var preview: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                photo
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: Space.m) {
                    Button("Take a new photo") {
                        Haptics.shared.play(.press)
                        capturing = true
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))

                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Text("Choose from library")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color(white: 1))
                            .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
                            .background(
                                Color(white: 1).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            )
                    }
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
