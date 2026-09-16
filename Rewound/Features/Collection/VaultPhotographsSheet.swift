import RewoundDesign
import RewoundKit
import PhotosUI
import SwiftUI

/// The owner's own photographs of one watch: adding them, arranging them, and
/// taking one off for good.
///
/// This replaced a form that asked for an `https://` address and said, in the
/// form, that Rewound did not store pictures for watches in a vault. It does
/// now, so the link form is gone rather than kept beside the picker — two ways
/// to set one photograph is how a surface ends up with copy explaining which
/// one is real.
///
/// Three rulings shape it (contracts §9d):
///
/// - **A gallery, not one slot.** A watch gets photographed from several
///   angles. The first is the cover and the rest sit behind it.
/// - **There is no "make this the cover" verb.** The cover is position zero,
///   so making one the cover is dragging it to the front — one gesture that
///   already exists rather than a second control that would have to agree with
///   it.
/// - **Deleting is permanent.** No tombstone, no undo, so it is asked about
///   first.
///
/// The order is the server's, not the screen's. Every verb answers with the
/// whole gallery and the cover as it now stands, so a write is followed by
/// redrawing on the answer rather than on what was hoped for — and the watch
/// behind the sheet is handed the same answer, so its card is right without a
/// second round trip.
struct VaultPhotographsSheet: View {
    let watch: VaultWatch
    /// Handed every gallery the server answers with, so the screen behind
    /// redraws its hero and its card on the cover this sheet just settled.
    let onChanged: (VaultGallery) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [VaultPhoto] = []
    /// Set once the gallery has been read from the server, so an empty gallery
    /// and a gallery not yet loaded are two different screens rather than the
    /// same blank one.
    @State private var loaded = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var picked: [PhotosPickerItem] = []
    @State private var showingPicker = false
    @State private var pendingDeletion: VaultPhoto?

    /// The photograph under the finger, and where it started. `origin` is what
    /// decides whether the drag actually moved anything: a lift that lands
    /// back where it began is not a write.
    @State private var dragging: (id: String, origin: Int)?
    @State private var dragPoint: CGPoint = .zero
    /// The order as it stood before the lift, restored if the move is refused.
    @State private var orderBeforeDrag: [VaultPhoto] = []

    private static let columns = 3
    private static let gridSpace = "vault-gallery-grid"

    private var remaining: Int { max(0, VaultGallery.maximum - photos.count) }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cell = cellSide(in: proxy.size.width)
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        Text(explanation)
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)

                        if loaded {
                            grid(cell: cell)
                        } else {
                            skeleton(cell: cell)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(RewoundType.caption)
                                .foregroundStyle(Color.rewound.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button(addTitle) {
                            errorMessage = nil
                            showingPicker = true
                        }
                        .buttonStyle(.rewound(.primary, fullWidth: true))
                        .disabled(busy || !loaded || remaining == 0)

                        if loaded, remaining == 0 {
                            Text("You can keep up to eight photographs of a watch. Delete one to add another.")
                                .font(RewoundType.caption)
                                .foregroundStyle(Color.rewound.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Space.l)
                }
            }
            .rewoundPageBackground()
            .navigationTitle("Photographs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(Color.rewound.primary)
                }
            }
        }
        .photosPicker(
            isPresented: $showingPicker,
            selection: $picked,
            // Never offer a slot the server would only refuse.
            maxSelectionCount: remaining,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await add(items) }
        }
        // An alert rather than a confirmation dialog, and the difference is
        // not cosmetic: the dialog rendered this question with neither its
        // title nor its cancel button, so the only thing the owner could see
        // to press was Delete. A destructive question has to show the way out
        // as plainly as the way through.
        .alert(
            "Delete this photograph?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { photo in
            Button("Delete", role: .destructive) {
                pendingDeletion = nil
                Task { await delete(photo) }
            }
            Button("Keep it", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("It is removed from Rewound for good. There is no undo.")
        }
        .task { await load() }
    }

    private var explanation: String {
        if photos.isEmpty {
            return "Your own photographs of this watch. The first one you add becomes the cover."
        }
        return "The first is the cover. Press and hold a photograph to move it."
    }

    private var addTitle: String {
        if busy { return "Working\u{2026}" }
        return photos.isEmpty ? "Add photographs" : "Add more"
    }

    // MARK: - The grid

    private func cellSide(in width: CGFloat) -> CGFloat {
        let inner = width - Space.l * 2 - Space.m * CGFloat(Self.columns - 1)
        return max(44, (inner / CGFloat(Self.columns)).rounded(.down))
    }

    private func grid(cell: CGFloat) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(cell), spacing: Space.m, alignment: .topLeading),
                count: Self.columns
            ),
            alignment: .leading,
            spacing: Space.m
        ) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                tile(photo, index: index, cell: cell)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The drag reports against the grid's own top-left, which is the same
        // corner `center(of:)` measures from. Naming the space here rather
        // than on the scroll view is what makes the two comparable without
        // anything having to know how tall the sentence above the grid is.
        .coordinateSpace(name: Self.gridSpace)
    }

    private func skeleton(cell: CGFloat) -> some View {
        HStack(spacing: Space.m) {
            ForEach(0..<Self.columns, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .fill(Color.rewound.secondary)
                    .frame(width: cell, height: cell)
                    .shimmer()
            }
        }
        .accessibilityLabel("Loading your photographs")
    }

    private func tile(_ photo: VaultPhoto, index: Int, cell: CGFloat) -> some View {
        let lifted = dragging?.id == photo.id
        return ZStack(alignment: .topTrailing) {
            ZStack {
                Color.rewound.secondary
                if let url = photo.url?.url {
                    PrivateImage(url: url, side: cell) { phase in
                        switch phase {
                        case .loaded(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failed:
                            unreadable
                        case .loading:
                            Rectangle().shimmer()
                        }
                    }
                } else {
                    // `url` is nil only when the stored object cannot be
                    // addressed at all. Saying so is better than an empty
                    // square the owner would read as a photograph that failed
                    // to arrive over the network.
                    unreadable
                }
            }
            .frame(width: cell, height: cell)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if index == 0 {
                    Text("Cover")
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.primaryForeground)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs)
                        .background(
                            Capsule().fill(Color.rewound.primaryDeep.opacity(0.92))
                        )
                        .padding(Space.s)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )

            Button {
                Haptics.shared.play(.warning)
                pendingDeletion = photo
            } label: {
                // This sits on a photograph, not on the theme's ground, so it
                // does not flip with the theme: keyed to the foreground token
                // it became a cream disc on a cream watch under dark, and the
                // way to remove a photograph all but disappeared. Dark ink
                // under a white glyph is what every other control this app
                // draws over photography uses.
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(white: 1))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.rewound.shadowTint.opacity(0.62)))
                    // The dot is small because it sits on somebody's
                    // photograph; the target around it is not.
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Inside the tile's own corner rather than straddling it: the
            // rightmost column sits against the page margin, and a badge hung
            // off that corner is the one that gets clipped.
            .disabled(busy || dragging != nil)
            .accessibilityLabel("Remove this photograph")
        }
        .frame(width: cell, height: cell)
        .scaleEffect(lifted ? 1.06 : 1)
        .shadow(
            color: Color.rewound.shadowTint.opacity(lifted ? 0.28 : 0),
            radius: lifted ? 14 : 0,
            y: lifted ? 8 : 0
        )
        .offset(liftedOffset(index: index, cell: cell, lifted: lifted))
        .zIndex(lifted ? 1 : 0)
        .gesture(dragGesture(photo, cell: cell))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(index == 0 ? "Cover photograph" : "Photograph")
        // A drag is not reachable with a screen reader, so the one thing the
        // drag is for is offered as an action instead. It is worded as what it
        // does — the cover is position zero — rather than as a second verb the
        // server does not have.
        .accessibilityAction(named: Text("Move to the front")) {
            guard index != 0 else { return }
            Task { await move(photo, to: 0) }
        }
    }

    private var unreadable: some View {
        Text("Unreadable")
            .font(RewoundType.caption)
            .foregroundStyle(Color.rewound.mutedForeground)
            .multilineTextAlignment(.center)
            .padding(Space.s)
    }

    // MARK: - Long press, then drag

    private func liftedOffset(index: Int, cell: CGFloat, lifted: Bool) -> CGSize {
        guard lifted else { return .zero }
        let home = center(of: index, cell: cell)
        return CGSize(width: dragPoint.x - home.x, height: dragPoint.y - home.y)
    }

    /// Where a cell's middle sits in the grid's own coordinate space — the
    /// same space the drag reports in.
    private func center(of index: Int, cell: CGFloat) -> CGPoint {
        let column = index % Self.columns
        let row = index / Self.columns
        return CGPoint(
            x: CGFloat(column) * (cell + Space.m) + cell / 2,
            y: CGFloat(row) * (cell + Space.m) + cell / 2
        )
    }

    private func index(at point: CGPoint, cell: CGFloat) -> Int {
        let column = min(Self.columns - 1, max(0, Int(point.x / (cell + Space.m))))
        let row = max(0, Int(point.y / (cell + Space.m)))
        return min(photos.count - 1, max(0, row * Self.columns + column))
    }

    private func dragGesture(_ photo: VaultPhoto, cell: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(coordinateSpace: .named(Self.gridSpace)))
            .onChanged { value in
                switch value {
                case .first(true):
                    lift(photo, cell: cell)
                case .second(true, let drag):
                    guard let drag, dragging?.id == photo.id else { return }
                    dragPoint = drag.location
                    reorderUnderFinger(cell: cell)
                default:
                    break
                }
            }
            .onEnded { _ in
                Task { await commitDrag() }
            }
    }

    private func lift(_ photo: VaultPhoto, cell: CGFloat) {
        guard dragging == nil, !busy, let index = photos.firstIndex(where: { $0.id == photo.id })
        else { return }
        orderBeforeDrag = photos
        dragging = (id: photo.id, origin: index)
        dragPoint = center(of: index, cell: cell)
        Haptics.shared.play(.armed)
    }

    private func reorderUnderFinger(cell: CGFloat) {
        guard let dragging,
              let from = photos.firstIndex(where: { $0.id == dragging.id }) else { return }
        let to = index(at: dragPoint, cell: cell)
        guard to != from else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            let moved = photos.remove(at: from)
            photos.insert(moved, at: to)
        }
        Haptics.shared.play(.selection)
    }

    private func commitDrag() async {
        guard let lift = dragging else { return }
        let landing = photos.firstIndex(where: { $0.id == lift.id })
        dragging = nil
        dragPoint = .zero
        guard let landing, landing != lift.origin,
              let photo = photos.first(where: { $0.id == lift.id }) else {
            orderBeforeDrag = []
            return
        }
        await move(photo, to: landing)
    }

    // MARK: - The four verbs

    private func load() async {
        do {
            let gallery = try await services.vault.photos(id: watch.id)
            apply(gallery)
        } catch {
            errorMessage = message(from: error)
        }
        loaded = true
    }

    private func add(_ items: [PhotosPickerItem]) async {
        guard !busy else { return }
        picked = []
        busy = true
        errorMessage = nil
        defer { busy = false }
        var addedCount = 0
        var failures: [String] = []
        for item in items {
            do {
                guard let original = try await item.loadTransferable(type: Data.self) else {
                    throw PhotoImport.Failure.unreadable
                }
                // Photos can return a representation different from the
                // first advertised type. Decode the actual bytes, and shrink
                // large originals before the server's 25MB request limit.
                let data = try await Task.detached(priority: .userInitiated) {
                    try PhotoImport.jpegData(original)
                }.value
                let added = try await services.vault.addPhoto(
                    id: watch.id,
                    data: data,
                    filename: "photo.jpg",
                    contentType: "image/jpeg"
                )
                apply(added.gallery)
                addedCount += 1
            } catch {
                failures.append((error as? APIError)?.errorDescription
                    ?? (error as? PhotoImport.Failure)?.errorDescription
                    ?? "A photo couldn’t be loaded or uploaded. Check your connection and try again.")
            }
        }
        if let failure = failures.first {
            let progress = addedCount > 0 ? "Added \(addedCount) of \(items.count) photographs. " : ""
            let remaining = failures.count == 1
                ? "One photo wasn’t added. "
                : "\(failures.count) photos weren’t added. "
            errorMessage = progress + remaining + failure
            Haptics.shared.play(.error)
        } else {
            Haptics.shared.play(.save)
        }
    }

    private func delete(_ photo: VaultPhoto) async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            apply(try await services.vault.deletePhoto(id: watch.id, photoID: photo.id))
            Haptics.shared.play(.save)
        } catch {
            errorMessage = message(from: error)
            Haptics.shared.play(.error)
        }
    }

    private func move(_ photo: VaultPhoto, to position: Int) async {
        let restore = orderBeforeDrag.isEmpty ? photos : orderBeforeDrag
        orderBeforeDrag = []
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            apply(try await services.vault.movePhoto(id: watch.id, photoID: photo.id, to: position))
            Haptics.shared.play(.save)
        } catch {
            // The tiles are already sitting where the finger left them, and
            // leaving them there would tell the owner an arrangement was saved
            // that was not. So the order goes back to what the server still
            // holds, and the refusal says why.
            withAnimation { photos = restore }
            errorMessage = message(from: error)
            Haptics.shared.play(.error)
        }
    }

    private func apply(_ gallery: VaultGallery) {
        photos = gallery.results
        onChanged(gallery)
    }

    private func message(from error: Error) -> String {
        (error as? APIError)?.errorDescription
            ?? "We couldn\u{2019}t do that just now. Nothing has been lost."
    }
}
