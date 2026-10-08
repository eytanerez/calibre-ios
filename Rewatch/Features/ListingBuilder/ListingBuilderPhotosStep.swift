import NukeUI
@preconcurrency import PhotosUI
import RewatchDesign
import RewatchKit
import SwiftUI
import UIKit

// MARK: - 6 · Photos

/// The six angles and any extras, from the photo library (several at once)
/// or the camera. Photos are prepared on the phone as they are picked and go
/// up only when the seller leaves this step.
struct BuilderPhotosStep: View {
    let context: BuilderStepContext
    private var model: ListingBuilderModel { context.model }

    /// Where a library pick goes.
    private enum LibraryTarget: Equatable {
        case slot(ListingImageCategory)
        case fill
        case extras
    }

    @State private var libraryTarget: LibraryTarget?
    @State private var showsLibrary = false
    @State private var librarySelection: [PhotosPickerItem] = []
    @State private var cameraTarget: CaptureTarget?
    /// The camera handed over to the library for this target.
    @State private var pendingLibrary: CaptureTarget?
    /// "Take photos": after each shot, the next empty angle opens.
    @State private var takingAll = false
    @State private var menuFor: ListingImageCategory?
    @State private var extrasMenu = false
    @State private var preparing = 0
    /// The same lesson id the old photo step used, so a seller who has seen
    /// it is not shown it again.
    @State private var tutorial = TutorialController(
        id: "sell.wizard.photos",
        steps: [
            TutorialStep(
                id: "angles",
                anchor: "builder.photos.grid",
                title: "Six angles, one story",
                message: "All six are required. Choose them from your library, several at once, or take them with the camera. They upload when you continue, and your Front photo becomes the listing's hero.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.box)
            ),
        ]
    )
    @State private var gridWidth: CGFloat = 350

    private var side: CGFloat { max(40, (gridWidth - Space.s * 3) / 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // Two rows of four squares, sized from the width the step has:
            // the six angles, then "More photos" across the last two.
            VStack(spacing: Space.s) {
                HStack(spacing: Space.s) {
                    tile(.front, index: 0)
                    tile(.leftProfile, index: 1)
                    tile(.rightProfile, index: 2)
                    tile(.caseback, index: 3)
                }
                HStack(spacing: Space.s) {
                    tile(.clasp, index: 4)
                    tile(.fullSet, index: 5)
                    moreTile
                        .frame(width: side * 2 + Space.s, height: side)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .tutorialAnchor("builder.photos.grid")

            if !model.extras.isEmpty {
                extrasStrip
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }

            Text(hint ?? " ")
                .font(RewatchType.caption)
                .foregroundStyle(model.photoError != nil ? Color.rewatch.destructive : Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(hint == nil)

            // Side by side when both labels fit on one line, stacked when not.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.m) { pickButtons(oneLine: true) }
                VStack(spacing: Space.s) { pickButtons(oneLine: false) }
            }

            Text("Each photo is made smaller on your phone, and its location is removed, before it goes up. They upload when you continue, while you set the price.")
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            #if DEBUG
            Button("Use sample photos") { useSamples() }
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.primaryDeep)
                .frame(minHeight: Space.touchTarget)
                .accessibilityIdentifier("builder.photos.samples")
            #endif
        }
        .animation(Motion.easeMedium, value: model.extras.map(\.id))
        .tutorialOverlay(tutorial)
        .onAppear {
            if model.mode == .live { tutorial.startIfNeeded() }
        }
        .overlay {
            if preparing > 0 {
                ProgressView("Preparing photos")
                    .padding(Space.l)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.box))
            }
        }
        .photosPicker(
            isPresented: $showsLibrary,
            selection: $librarySelection,
            maxSelectionCount: libraryTarget.map { if case .slot = $0 { 1 } else { 20 } } ?? 1,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: librarySelection) { _, items in
            guard !items.isEmpty, let target = libraryTarget else { return }
            librarySelection = []
            Task { await importLibrary(items, into: target) }
        }
        .fullScreenCover(item: $cameraTarget, onDismiss: afterCamera) { target in
            CaptureScreen(target: target, onChooseLibrary: {
                pendingLibrary = target
                takingAll = false
                cameraTarget = nil
            }) { image in
                Task { await importCapture(image, for: target) }
            }
        }
        .confirmationDialog(
            menuFor.map { "\($0.label) photo" } ?? "",
            isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }),
            titleVisibility: .visible,
            presenting: menuFor
        ) { category in
            Button(model.slot(category)?.hasImage == true ? "Retake with the camera" : "Take with the camera") {
                takingAll = false
                cameraTarget = CaptureTarget(category: category)
            }
            Button("Choose from your library") { open(.slot(category)) }
            if model.slot(category)?.hasImage == true {
                Button("Remove photo", role: .destructive) {
                    Haptics.shared.play(.selection)
                    model.removePhoto(category)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { category in
            if let help = SellFieldHelp.photoAngle(category) { Text(help) }
        }
        .confirmationDialog("More photos", isPresented: $extrasMenu, titleVisibility: .visible) {
            Button("Take with the camera") {
                takingAll = false
                cameraTarget = CaptureTarget(category: nil)
            }
            Button("Choose from your library") { open(.extras) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Optional. Anything else a buyer should see: a mark, the movement, the bracelet's last link.")
        }
    }

    @ViewBuilder
    private func pickButtons(oneLine: Bool) -> some View {
        Button {
            open(.fill)
        } label: {
            Label("Choose photos", systemImage: "photo.on.rectangle")
                .fixedSize(horizontal: oneLine, vertical: false)
        }
        .buttonStyle(.rewatch(.secondary, fullWidth: true))
        .accessibilityIdentifier("builder.photos.choose")

        Button {
            takeAll()
        } label: {
            Label("Take photos", systemImage: "camera")
                .fixedSize(horizontal: oneLine, vertical: false)
        }
        .buttonStyle(.rewatch(.secondary, fullWidth: true))
    }

    private var hint: String? {
        if let error = model.photoError { return error }
        let missing = BuilderRules.missingPhotos(filled: model.photosFilled, mode: model.mode)
        guard !model.photosFilled.isEmpty, !missing.isEmpty else { return nil }
        return "Still needed: " + missing.map(\.shortLabel).joined(separator: ", ") + "."
    }

    // MARK: Tiles

    private func tile(_ category: ListingImageCategory, index: Int) -> some View {
        let slot = model.slot(category)
        let status = model.uploadStatus(category)
        return Button {
            Haptics.shared.play(.selection)
            menuFor = category
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .fill(Color.rewatch.card)
                if let slot, slot.hasImage {
                    BuilderPhotoThumb(localURL: slot.fileName.map(model.photoURL), remoteURL: slot.remoteURL)
                        .id(slot.fileName ?? slot.remoteURL?.absoluteString ?? "")
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.rewatch.mutedForeground)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewatch.border, lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                Text(category.shortLabel)
                    .font(RewatchType.sans(.semiBold, 11, relativeTo: .caption2))
                    .foregroundStyle(Color.rewatch.foreground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(slot?.hasImage == true ? Color.rewatch.background.opacity(0.9) : Color.clear, in: Capsule())
                    .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                if let status { UploadBadge(status: status).padding(5) }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(slot?.hasImage == true ? "\(category.label) photo. Change or remove it." : "Add the \(category.label) photo")
        .accessibilityIdentifier("builder.photo.\(category.rawValue)")
        .builderRise(index)
    }

    private var moreTile: some View {
        Button {
            Haptics.shared.play(.selection)
            extrasMenu = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text("More photos")
                    .font(RewatchType.sans(.semiBold, 12, relativeTo: .caption))
                Text(model.extras.isEmpty ? "Optional" : "\(model.extras.count) added")
                    .font(RewatchType.caption)
            }
            .foregroundStyle(Color.rewatch.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewatch.borderBright, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .builderRise(6)
    }

    private var extrasStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(model.extras) { extra in
                    ZStack(alignment: .topTrailing) {
                        BuilderPhotoThumb(localURL: extra.fileName.map(model.photoURL), remoteURL: extra.remoteURL)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                if let status = model.uploadStatus(extra: extra) { UploadBadge(status: status).padding(3) }
                            }
                        Button {
                            Haptics.shared.play(.selection)
                            model.removeExtra(extra.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.rewatch.foreground)
                                .frame(width: 20, height: 20)
                                .background(Color.rewatch.background.opacity(0.92), in: Circle())
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove this extra photo")
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, 6)
        }
    }

    // MARK: Picking

    private func open(_ target: LibraryTarget) {
        libraryTarget = target
        showsLibrary = true
    }

    private func takeAll() {
        guard let first = BuilderRules.photoLayout.first(where: { model.slot($0)?.hasImage != true }) else {
            cameraTarget = CaptureTarget(category: nil)
            return
        }
        takingAll = true
        cameraTarget = CaptureTarget(category: first)
    }

    private func afterCamera() {
        if let pending = pendingLibrary {
            pendingLibrary = nil
            open(pending.category.map { .slot($0) } ?? .extras)
            return
        }
        guard takingAll else { return }
        guard let next = BuilderRules.photoLayout.first(where: { model.slot($0)?.hasImage != true }) else {
            takingAll = false
            return
        }
        Task {
            // The cover has to finish leaving before the next one can open.
            try? await Task.sleep(for: .milliseconds(450))
            if takingAll { cameraTarget = CaptureTarget(category: next) }
        }
    }

    private func importCapture(_ image: UIImage, for target: CaptureTarget) async {
        preparing += 1
        defer { preparing -= 1 }
        let shot = UncheckedImage(image)
        let result = await Task.detached(priority: .userInitiated) {
            Result { try ListingPhotoPrep.jpeg(from: shot.image) }
        }.value
        switch result {
        case .success(let jpeg):
            Haptics.shared.play(.capture)
            if let category = target.category {
                model.setPhoto(jpeg, for: category)
            } else {
                model.addExtra(jpeg)
            }
        case .failure(let error):
            takingAll = false
            model.reportPhotoProblem(error.localizedDescription)
        }
    }

    private func importLibrary(_ items: [PhotosPickerItem], into target: LibraryTarget) async {
        preparing += 1
        defer { preparing -= 1 }
        var prepared: [Data] = []
        var failed = 0
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                failed += 1
                continue
            }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ListingPhotoPrep.jpeg(from: data) }
            }.value
            switch result {
            case .success(let jpeg): prepared.append(jpeg)
            case .failure: failed += 1
            }
        }
        if !prepared.isEmpty { Haptics.shared.play(.capture) }
        switch target {
        case .slot(let category):
            if let jpeg = prepared.first { model.setPhoto(jpeg, for: category) }
        case .fill:
            model.fill(with: prepared)
        case .extras:
            for jpeg in prepared { model.addExtra(jpeg) }
        }
        if failed > 0 {
            model.reportPhotoProblem(failed == 1
                ? "One photo couldn\u{2019}t be read. Try it again, or download it from iCloud in Photos first."
                : "\(failed) photos couldn\u{2019}t be read. Try them again, or download them from iCloud in Photos first.")
        }
    }

    #if DEBUG
    private func useSamples() {
        for (category, image) in PhotoPipeline.sampleImages() where model.slot(category)?.hasImage != true {
            if let jpeg = try? ListingPhotoPrep.jpeg(from: image) {
                model.setPhoto(jpeg, for: category)
            }
        }
    }
    #endif
}

/// A captured photo carried to the preparing task. Read once, there.
private struct UncheckedImage: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

extension ListingImageCategory {
    /// The tile's word (the site's: Front, Left, Right, Caseback, Clasp, Full set).
    var shortLabel: String {
        switch self {
        case .front: "Front"
        case .leftProfile: "Left"
        case .rightProfile: "Right"
        case .caseback: "Caseback"
        case .clasp: "Clasp"
        case .fullSet: "Full set"
        }
    }
}

/// An upload's state on its photo: a ring filling, a check, or a retry mark.
struct UploadBadge: View {
    let status: BuilderUploadStatus

    var body: some View {
        ZStack {
            Circle().fill(Color.rewatch.background.opacity(0.92))
            switch status.phase {
            case .queued:
                Circle().strokeBorder(Color.rewatch.borderBright, lineWidth: 2).padding(3)
            case .uploading(let fraction):
                Circle().strokeBorder(Color.rewatch.borderBright, lineWidth: 2).padding(3)
                Circle()
                    .trim(from: 0, to: max(0.04, fraction))
                    .stroke(Color.rewatch.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.rewatch.success)
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.rewatch.destructive)
            }
        }
        .frame(width: 22, height: 22)
        .animation(Motion.easeFast, value: status.phase)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch status.phase {
        case .queued: "Waiting to upload"
        case .uploading(let fraction): "Uploading, \(Int(fraction * 100)) percent"
        case .done: "Uploaded"
        case .failed: "Upload failed"
        }
    }
}

/// A photo the builder holds: the local file, drawn small and off the main
/// thread, or the server's copy. It develops into place (the site's
/// `lb-develop`).
struct BuilderPhotoThumb: View {
    let localURL: URL?
    let remoteURL: URL?
    var maxPixel: CGFloat = 480
    @State private var image: UIImage?
    @State private var developed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cache = NSCache<NSURL, UIImage>()

    var body: some View {
        Group {
            if let localURL {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .saturation(developed ? 1 : 0.2)
                        .scaleEffect(developed || reduceMotion ? 1 : 1.04)
                        .opacity(developed ? 1 : 0)
                        .onAppear {
                            withAnimation(reduceMotion ? nil : Motion.ease(0.7)) { developed = true }
                        }
                } else {
                    Color.rewatch.secondary
                }
                Color.clear
                    .task(id: localURL) { image = await Self.load(localURL, maxPixel: maxPixel) }
            } else if let remoteURL {
                LazyImage(url: remoteURL) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.rewatch.secondary
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    static func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = url as NSURL
        if let hit = cache.object(forKey: key) { return hit }
        let made = await Task.detached(priority: .userInitiated) { () -> UncheckedImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  ] as CFDictionary) else { return nil }
            return UncheckedImage(UIImage(cgImage: cg))
        }.value
        if let made { cache.setObject(made.image, forKey: key) }
        return made?.image
    }
}
