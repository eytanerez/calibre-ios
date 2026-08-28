import CalibreDesign
import CalibreKit
import Nuke
import NukeUI
import SwiftUI

/// Which photo the seller is marking, by the position the server indexes it
/// at. Not the wizard's category: a mark belongs to a photograph's place in
/// the listing, and the two are not the same key.
struct AnnotationTarget: Identifiable {
    let imageIndex: Int
    let url: URL?
    let existing: ListingAnnotation?

    var id: Int { imageIndex }
}

/// The seller draws a rough line on their own photograph and writes one line
/// about it.
///
/// Rough is the point. There is no shape picker, no colour, no undo stack —
/// one finger, one stroke, one caption. A tool that produced neat ellipses
/// would produce something that reads as the interface pointing at a defect;
/// a line somebody drew reads as the person who owns the watch showing you
/// the thing they would show you if you were holding it.
///
/// The stroke is simplified before it leaves the phone and its coordinates
/// are normalised against the photograph, never against this screen — see
/// `AnnotationPath`.
struct PhotoAnnotationScreen: View {
    let listingID: String
    let target: AnnotationTarget
    /// Called with what the server stored, or with nil when the mark was
    /// removed, so the wizard's copy matches what is on the listing.
    let onSaved: (ListingAnnotation?) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    /// Normalised against the photograph, appended as the finger moves.
    @State private var drawn: [CGPoint] = []
    @State private var note: String
    @State private var photoSize: CGSize?
    @State private var saving = false
    @State private var removing = false
    @State private var errorMessage: String?

    init(
        listingID: String,
        target: AnnotationTarget,
        onSaved: @escaping (ListingAnnotation?) -> Void
    ) {
        self.listingID = listingID
        self.target = target
        self.onSaved = onSaved
        _note = State(initialValue: target.existing?.note ?? "")
        _drawn = State(initialValue: target.existing?.path ?? [])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                controls
            }
            .calibrePageBackground()
            .navigationTitle("Mark a detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.calibre.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .tint(Color.calibre.primary)
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(saving || removing)
    }

    // MARK: - The photograph, and the ink on it

    /// The photo is laid out aspect-*fit* here, unlike the buyer's gallery,
    /// so the seller can draw on every part of the picture they published —
    /// including the part a square crop hides. The drawing surface is pinned
    /// to exactly the fitted rectangle, which is what makes a normalised
    /// coordinate mean the same place on every other screen.
    private var canvas: some View {
        GeometryReader { geometry in
            let box = fittedRect(in: geometry.size)
            ZStack {
                Color.black
                photo
                    .frame(width: box.width, height: box.height)
                    .overlay { AnnotationInk(points: drawn) }
                    .position(x: box.midX, y: box.midY)
                    .contentShape(Rectangle())
            }
            .contentShape(Rectangle())
            .gesture(drawing(in: box))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var photo: some View {
        LazyImage(request: target.url.map { ImageRequest(url: $0) }) { state in
            if let image = state.image {
                image.resizable().scaledToFit()
            } else if state.error != nil {
                Color.calibre.secondary
            } else {
                ProgressView().tint(Color(white: 1))
            }
        }
        .onAppear { measure() }
    }

    /// The rectangle the photograph actually occupies. Until its proportions
    /// are known there is nothing to draw on, so the surface stays empty
    /// rather than accepting a stroke that would be normalised against the
    /// wrong box.
    private func fittedRect(in size: CGSize) -> CGRect {
        guard let photoSize, photoSize.width > 0, photoSize.height > 0 else {
            return CGRect(origin: .zero, size: .zero)
        }
        let scale = min(size.width / photoSize.width, size.height / photoSize.height)
        let fitted = CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func measure() {
        guard photoSize == nil, let url = target.url else { return }
        Task {
            let request = ImageRequest(url: url)
            if let response = try? await ImagePipeline.shared.image(for: request) {
                photoSize = response.size
            }
        }
    }

    /// One continuous stroke. Starting a new one replaces the old: a photo
    /// carries a single mark, and letting a seller accumulate strokes would
    /// let them build the thing the drawn line exists instead of.
    private func drawing(in box: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard box.width > 0, box.height > 0 else { return }
                let point = CGPoint(
                    x: (value.location.x - box.minX) / box.width,
                    y: (value.location.y - box.minY) / box.height
                )
                // Outside the picture is not part of the mark. Clamping here
                // rather than dropping keeps the line continuous when a
                // finger strays over the edge and comes back.
                drawn.append(
                    CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
                )
                errorMessage = nil
            }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(drawn.isEmpty ? "Draw on the photo" : "Drawn")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                Spacer()
                if !drawn.isEmpty {
                    Button("Start again") { drawn = [] }
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                        .buttonStyle(PressableStyle())
                }
            }

            CalibreTextField(
                "What is it?",
                text: $note,
                placeholder: "Hairline on the bezel edge \u{2014} only catches the light at an angle",
                kind: .sentence
            )
            .onChange(of: note) { _, newValue in
                if newValue.count > ListingAnnotation.noteLimit {
                    note = String(newValue.prefix(ListingAnnotation.noteLimit))
                }
                errorMessage = nil
            }

            if let errorMessage {
                InlineErrorLine(message: errorMessage)
            }

            if target.existing != nil {
                Button {
                    remove()
                } label: {
                    BusyLabel(title: "Remove this mark", busy: removing)
                }
                .buttonStyle(.calibre(.ghost, fullWidth: true))
                .disabled(saving || removing)
            }
        }
        .padding(Space.margin)
        .calibrePageBackground()
        .overlay(alignment: .top) {
            Rectangle().fill(Color.calibre.border).frame(height: 1)
        }
    }

    private var canSave: Bool {
        !saving && !removing && drawn.count >= ListingAnnotation.minPoints
    }

    // MARK: - Flow

    private func save() {
        let simplified = AnnotationPath.simplify(drawn)
        guard !simplified.isEmpty else {
            errorMessage = "That mark is too short to draw \u{2014} keep the line going."
            Haptics.shared.play(.error)
            return
        }
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                let stored = try await services.seller.saveAnnotation(
                    listingID: listingID,
                    imageIndex: target.imageIndex,
                    path: simplified,
                    note: InputValidation.isNonBlank(note) ? InputValidation.trimmed(note) : nil
                )
                Haptics.shared.play(.success)
                onSaved(stored)
                dismiss()
            } catch {
                Haptics.shared.play(.error)
                errorMessage = sellErrorMessage(error)
            }
        }
    }

    private func remove() {
        removing = true
        errorMessage = nil
        Task {
            defer { removing = false }
            do {
                try await services.seller.deleteAnnotation(
                    listingID: listingID,
                    imageIndex: target.imageIndex
                )
                Haptics.shared.play(.save)
                onSaved(nil)
                dismiss()
            } catch {
                Haptics.shared.play(.error)
                errorMessage = sellErrorMessage(error)
            }
        }
    }
}
