import CalibreDesign
import CalibreKit
import SwiftUI

/// A watch's Passport, as the booklet it is.
///
/// The record itself is not new — it has always been at
/// `buycalibre.com/passport/<code>`, and until now the app's only answer was
/// to hand the reader to Safari. What is new is that it reads like the thing
/// it describes: kraft stock, a stamp pressed into the front, and service
/// entries filled in by hand with the date out in the margin, the way a real
/// service booklet is kept.
///
/// And it is paged, not scrolled. The passport exists to be handed to a
/// stranger deciding whether to trust a watch, and a booklet is the form that
/// object takes in the real world — a cover you open and leaves you move
/// through one at a time. `CALIBRE_PASSPORT_BOOKLET.md` is the contract the
/// three platforms share: the page order, the stamp rule, the fixed-zone
/// dates and the turn. Only the gesture is ours.
///
/// The split is the whole design. Everything Calibre states about the watch —
/// what it is, that it was authenticated, that it sold — is set in the sans,
/// because it is a fact on a record. Only the entry a person wrote themselves
/// is in the hand. A booklet where the printing and the handwriting look the
/// same is a booklet nobody can tell has been filled in.
///
/// Public and anonymized: no session, no owner, no prices. It is the page
/// people send to a buyer, so it keeps a share affordance.
struct PassportScreen: View {
    let publicCode: String

    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var passport: WatchPassport?
    @State private var loadFailed = false
    /// Fires the stamp once, when the record arrives — never on a redraw, and
    /// never on a passport whose authentication has not happened.
    @State private var stampTrigger = 0
    /// Which leaf is face up. The cover is one of them: opening the booklet
    /// is the turn off it.
    @State private var leafIndex = 0
    @State private var readingWhole = false
    /// The date column, scaled with the type it holds. Fixed rather than
    /// sized to content so the entries line up down the page.
    @ScaledMetric(relativeTo: .caption) private var marginWidth: CGFloat = 74

    var body: some View {
        Group {
            if let passport {
                booklet(passport)
            } else if loadFailed {
                EmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "Passport not found",
                    message: "This link may be incomplete, or the passport may not exist."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                skeleton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Kraft.desk.ignoresSafeArea())
        .navigationTitle("Passport")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only once the record is on screen — sharing a link to a
            // passport that turned out not to exist sends the reader to the
            // same dead end.
            if passport != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Kraft.ink)
                    .accessibilityLabel("Share this Passport")
                }
            }
        }
        .sheet(isPresented: $readingWhole) {
            if let passport {
                wholePassport(passport)
            }
        }
        .task {
            guard passport == nil else { return }
            await load()
        }
    }

    /// The web address, not a deep link: the person receiving it may not have
    /// the app, and a passport that only opens for people who do is not the
    /// document being described.
    private var shareURL: URL {
        URL(string: "https://buycalibre.com/passport/\(publicCode)")
            ?? URL(string: "https://buycalibre.com")!
    }

    // MARK: - The booklet

    private func booklet(_ passport: WatchPassport) -> some View {
        let leaves = self.leaves(passport)

        return VStack(spacing: Space.xl) {
            Spacer(minLength: 0)

            // Held, not filled: a passport is a small object, and a leaf
            // stretched to the height of a phone stops being one.
            BookletDeck(count: leaves.count, index: $leafIndex) { index in
                leafView(leaves[index], passport)
            }
            .aspectRatio(Booklet.proportion, contentMode: .fit)

            indicator(count: leaves.count)

            Button {
                readingWhole = true
            } label: {
                Text("Read the whole passport")
                    .font(CalibreType.label)
                    .foregroundStyle(Kraft.primary)
                    .padding(.vertical, Space.s)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Shows every page of the booklet in one list")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.l)
    }

    /// Dots under the booklet, current leaf filled. A status readout and not a
    /// control: on a phone the way through the booklet is the gesture, and
    /// six-point targets are not a way through anything.
    private func indicator(count: Int) -> some View {
        HStack(spacing: Space.s) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Kraft.ink.opacity(index == leafIndex ? 1 : 0.22))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(leafIndex + 1) of \(count)")
    }

    // MARK: - The pages

    /// The booklet's fixed order.
    ///
    /// A leaf with nothing on it is not in the booklet at all — a blank page
    /// in a record reads as evidence that went missing, which is the opposite
    /// of what this document is for.
    private enum Leaf: Hashable {
        case cover
        case watch
        case authentication
        case service
        case ownership
    }

    private func leaves(_ passport: WatchPassport) -> [Leaf] {
        var leaves: [Leaf] = [.cover]
        if !watchSpecs(passport).isEmpty { leaves.append(.watch) }
        if !authentications(passport).isEmpty { leaves.append(.authentication) }
        if !serviceEntries(passport).isEmpty { leaves.append(.service) }
        if !provenanceEntries(passport).isEmpty || activeListing(passport) != nil {
            leaves.append(.ownership)
        }
        return leaves
    }

    @ViewBuilder
    private func leafView(_ leaf: Leaf, _ passport: WatchPassport, scrolls: Bool = true) -> some View {
        let surface = LeafSurface(isCover: leaf == .cover, scrolls: scrolls) {
            leafContent(leaf, passport)
        }
        if leaf == .cover {
            // The surface takes the hit, not the stamp — see `markImpact`.
            surface.markImpact(trigger: stampTrigger)
        } else {
            surface
        }
    }

    @ViewBuilder
    private func leafContent(_ leaf: Leaf, _ passport: WatchPassport) -> some View {
        switch leaf {
        case .cover: coverLeaf(passport)
        case .watch: watchLeaf(passport)
        case .authentication: authenticationLeaf(passport)
        case .service: serviceLeaf(passport)
        case .ownership: ownershipLeaf(passport)
        }
    }

    // MARK: Cover

    /// The front of the booklet: the house mark, what the watch is, its
    /// number, and the stamp.
    ///
    /// The stamp is the one illustrated moment on this screen — a passport
    /// exists because an authentication happened, so it is the thing the
    /// booklet is about. It sits rotated off square because a stamp pressed
    /// by hand never lands square, and the jolt of it landing goes on the
    /// leaf underneath rather than on the stamp itself.
    private func coverLeaf(_ passport: WatchPassport) -> some View {
        VStack(spacing: Space.m) {
            CalibreLogoMark(size: 34)

            Eyebrow("Calibre Passport", color: Kraft.coverInkMuted)

            Text(passport.title)
                .font(CalibreType.serif(.semiBold, 26, relativeTo: .title))
                .foregroundStyle(Kraft.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.m)

            if let subtitle = passport.subtitle {
                Text(subtitle)
                    .font(CalibreType.body)
                    .foregroundStyle(Kraft.coverInkMuted)
            }

            Rule()
                .frame(width: 44)
                .padding(.vertical, Space.m)

            Eyebrow("Passport number", color: Kraft.coverInkMuted)

            Text(passport.publicCode.uppercased())
                .font(CalibreType.label)
                .tracking(2)
                .monospaced()
                .foregroundStyle(Kraft.ink)

            if isAuthenticated(passport) {
                CalibreMark.stamp(size: 72, trigger: stampTrigger)
                    .rotationEffect(.degrees(-11))
                    .padding(.top, Space.l)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// A passport that has been through authentication has an event saying
    /// so. The stamp says "authentication passed", so it is fired by that
    /// fact rather than by the page appearing.
    private func isAuthenticated(_ passport: WatchPassport) -> Bool {
        passport.events.contains { $0.kind == "authenticated" }
    }

    // MARK: The watch

    private func watchLeaf(_ passport: WatchPassport) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            runningHead("The watch")
            specTable(watchSpecs(passport))
            Text("The permanent record of this specific watch on Calibre — every authentication, sale, and owner-added service entry, carried with the watch for life.")
                .font(CalibreType.body)
                .foregroundStyle(Kraft.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the record knows the watch to be. Each line is only printed when
    /// the record actually carries it — a spec page with "Unknown" down it
    /// says less than one that stops.
    private func watchSpecs(_ passport: WatchPassport) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let brand = passport.brand, !brand.isEmpty { rows.append(("Brand", brand)) }
        if let model = passport.model, !model.isEmpty { rows.append(("Model", model)) }
        if let reference = passport.reference, !reference.isEmpty {
            rows.append(("Reference", reference))
        }
        if let year = passport.productionYear { rows.append(("Production year", String(year))) }
        if let opened = passport.createdAt {
            rows.append(("Passport opened", opened.formatted(Self.margin)))
        }
        return rows
    }

    // MARK: Authentication

    private func authenticationLeaf(_ passport: WatchPassport) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            runningHead("Authentication")

            ForEach(Array(authentications(passport).enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(marginDate(event))
                        .font(CalibreType.caption)
                        .foregroundStyle(Kraft.inkMuted)
                        .monospacedDigit()

                    // The outcome and the desk that signed it, in the
                    // server's own words. Set in the sans like every other
                    // fact on the record.
                    Text(event.summary)
                        .font(CalibreType.sans(.medium, 17, relativeTo: .body))
                        .foregroundStyle(Kraft.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if event.details?.boxPapers == true {
                        Text("Verified with box & papers.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Kraft.inkMuted)
                    }

                    if let grades = event.details?.grades, !grades.isEmpty {
                        gradeTable(grades)
                    }

                    if let report = event.details?.reportPdfUrl?.url {
                        Link(destination: report) {
                            Text("View authentication report")
                                .font(CalibreType.label)
                                .foregroundStyle(Kraft.primary)
                        }
                    }
                }
            }
        }
    }

    /// Usually one. A watch that came back through the desk has more, and a
    /// record that claims to be complete prints all of them.
    private func authentications(_ passport: WatchPassport) -> [PassportEvent] {
        Array(passport.events.filter { $0.kind == "authenticated" }.reversed())
    }

    // MARK: Service history

    private func serviceLeaf(_ passport: WatchPassport) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            runningHead("Service history")

            VStack(spacing: 0) {
                ForEach(Array(serviceEntries(passport).enumerated()), id: \.offset) { index, event in
                    if index > 0 { Rule() }
                    marginRow(event) {
                        // The only lines in the booklet a person wrote, and
                        // the only ones in the hand. There is no label above
                        // them: the page is titled, and every entry on it is
                        // the same kind of thing.
                        Text(event.ownerEntry)
                            .font(CalibreType.hand)
                            .foregroundStyle(Kraft.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Newest first — a service booklet is read from the last time the watch
    /// was opened backwards.
    private func serviceEntries(_ passport: WatchPassport) -> [PassportEvent] {
        Array(passport.events.filter(\.isOwnerWritten).reversed())
    }

    // MARK: Ownership

    private func ownershipLeaf(_ passport: WatchPassport) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            runningHead("Ownership")

            VStack(spacing: 0) {
                ForEach(Array(provenanceEntries(passport).enumerated()), id: \.offset) { index, event in
                    if index > 0 { Rule() }
                    marginRow(event) {
                        Text(label(for: event.kind))
                            .font(CalibreType.eyebrow)
                            .tracking(CalibreType.eyebrowTracking)
                            .foregroundStyle(Kraft.primary)

                        Text(event.summary)
                            .font(CalibreType.body)
                            .foregroundStyle(Kraft.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // The reader's next question, answered before they ask it: the
            // names are not withheld from them specifically, they are not on
            // the document at all.
            Text("A public passport records the transfers, never the owners.")
                .font(CalibreType.caption)
                .foregroundStyle(Kraft.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let listing = activeListing(passport) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Rule()
                    Text("This watch is on Calibre right now.")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Kraft.ink)
                    NavigationLink(value: Route.listing(listing.listingId)) {
                        Text("View the listing")
                    }
                    .buttonStyle(.calibre(.primary))
                }
                .padding(.top, Space.s)
            }
        }
    }

    /// Everything that happened to the watch that is neither the desk's
    /// verdict nor the owner's own hand: sales, transfers, listings — and any
    /// kind the server has grown since, which lands here rather than nowhere.
    private func provenanceEntries(_ passport: WatchPassport) -> [PassportEvent] {
        Array(
            passport.events
                .filter { $0.kind != "authenticated" && !$0.isOwnerWritten }
                .reversed()
        )
    }

    private func activeListing(_ passport: WatchPassport) -> PassportListingState? {
        guard let listing = passport.listing, listing.status == .active else { return nil }
        return listing
    }

    // MARK: Shared page furniture

    /// The head at the top of every leaf but the cover. A reader who lands
    /// mid-booklet needs to know which part of the record they are in, and it
    /// is the first thing VoiceOver reads on entering the leaf.
    private func runningHead(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(title, color: Kraft.primary)
            Rule()
        }
    }

    /// One filled-in line: the date out in the margin, the entry beside it.
    ///
    /// A booklet is read down the dates, so they hold their own column and
    /// stay in the sans and monospaced — a handwritten date in a margin is a
    /// date you have to decipher. The margin is fixed rather than sized to
    /// content so the entries stay aligned down the page.
    private func marginRow<Content: View>(
        _ event: PassportEvent,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let date = Text(marginDate(event))
            .font(CalibreType.caption)
            .foregroundStyle(Kraft.inkMuted)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
        let entry = VStack(alignment: .leading, spacing: Space.s, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)

        return Group {
            if sideBySide {
                HStack(alignment: .top, spacing: Space.l) {
                    date.frame(width: marginWidth, alignment: .leading)
                    entry
                }
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    date
                    entry
                }
            }
        }
        .padding(.vertical, Space.l)
    }

    /// Whether two things still fit across a leaf.
    ///
    /// A leaf is the width of a passport, not of a phone. At an accessibility
    /// size a date margin takes half of it and breaks the entry beside it
    /// mid-word, and a grade gets about a word to itself. Past that point
    /// everything paired goes one above the other — the date still read
    /// first, just no longer in the margin.
    private var sideBySide: Bool { !typeSize.isAccessibilitySize }

    private func specTable(_ rows: [(label: String, value: String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                if index > 0 { Rule() }
                specRow(rows[index])
                    .padding(.vertical, Space.m)
            }
        }
    }

    @ViewBuilder
    private func specRow(_ row: (label: String, value: String)) -> some View {
        let label = Text(row.label)
            .font(CalibreType.body)
            .foregroundStyle(Kraft.inkMuted)
        let value = Text(row.value)
            .font(CalibreType.bodyMedium)
            .foregroundStyle(Kraft.ink)

        if sideBySide {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                label
                Spacer(minLength: Space.l)
                value.multilineTextAlignment(.trailing)
            }
        } else {
            VStack(alignment: .leading, spacing: Space.xs) {
                label
                value
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The authenticator's findings, part by part. Two to a row on a leaf
    /// this wide, and one at an accessibility size, where two would leave
    /// each grade about a word across.
    private func gradeTable(_ grades: PassportConditionGrades) -> some View {
        let column = GridItem(.flexible(), alignment: .topLeading)
        return LazyVGrid(
            columns: sideBySide ? [column, column] : [column],
            alignment: .leading,
            spacing: Space.s
        ) {
            ForEach(grades.rows, id: \.label) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Kraft.inkMuted)
                    Text(row.value)
                        .font(CalibreType.label)
                        .foregroundStyle(Kraft.ink)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kraft.inset, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func marginDate(_ event: PassportEvent) -> String {
        guard let date = event.marginDate else { return "—" }
        return date.formatted(Self.margin)
    }

    /// The booklet's dates are read in a fixed zone rather than the reader's.
    ///
    /// A passport is a document about a watch, not a feed: the date beside an
    /// entry is the date on the record, and it must not change depending on
    /// who is holding it. Rendered locally, a service dated the 4th prints as
    /// the 3rd for everyone west of the workshop, and the owner and the buyer
    /// they sent it to end up reading two different booklets.
    private static let margin = Date.FormatStyle(
        date: .abbreviated,
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
    )

    /// The server's own vocabulary for what happened. An unrecognised kind
    /// keeps its raw word rather than vanishing: this is a record that claims
    /// to be complete, so a line it cannot label still gets printed.
    private func label(for kind: String) -> String {
        switch kind {
        case "authenticated": "AUTHENTICATED"
        case "transferred": "OWNERSHIP TRANSFERRED"
        case "sold": "SOLD ON CALIBRE"
        case "listed": "LISTED ON CALIBRE"
        case "service_added": "SERVICE RECORDED"
        default: kind.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    // MARK: - The whole record, unpaged

    /// Every leaf stacked in order. The turn is a way of reading the booklet,
    /// not the only one: this is the path for a reader who would rather
    /// scroll, and the one that still shows the whole record if the paging
    /// ever fails them.
    private func wholePassport(_ passport: WatchPassport) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(leaves(passport), id: \.self) { leaf in
                        leafView(leaf, passport, scrolls: false)
                    }

                    Text("Every watch sold on Calibre passes physical authentication before delivery.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Kraft.inkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.l)
                }
                .padding(Space.margin)
            }
            .background(Kraft.desk.ignoresSafeArea())
            .navigationTitle("The whole passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { readingWhole = false }
                        .tint(Kraft.primary)
                }
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Kraft.page)
                .shimmer()
            Spacer(minLength: 0)
        }
        .padding(Space.margin)
        .padding(.bottom, Space.xxl)
    }

    // MARK: - Loading

    private func load() async {
        loadFailed = false
        do {
            let record = try await services.vault.passport(code: publicCode)
            passport = record
            // One press, on arrival. Re-firing it on every reload would make
            // the stamp a decoration rather than a confirmation.
            if stampTrigger == 0, record.events.contains(where: { $0.kind == "authenticated" }) {
                stampTrigger = 1
            }
        } catch {
            if passport == nil { loadFailed = true }
        }
    }
}

// MARK: - The deck

/// The leaves, bound at a spine that does not move.
///
/// Only the leaf being read and the one it is turning onto are ever built. A
/// booklet is a stack rather than a strip: the page underneath is already
/// lying flat, so there is nothing for the rest of them to do, and holding
/// them all live would keep the whole record rendered behind one page of it.
private struct BookletDeck<Leaf: View>: View {
    let count: Int
    @Binding var index: Int
    @ViewBuilder let leaf: (Int) -> Leaf

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which way a leaf is being turned, or nil when the booklet is at rest.
    ///
    /// Deliberately its own state rather than the sign of `turn`: which leaf
    /// is lying flat has to be settled before the animation starts and stay
    /// settled until after it finishes. Derive it from `turn` and the leaf
    /// underneath changes identity inside the animation, which SwiftUI reads
    /// as a transition and cross-fades — two pages of the record printed over
    /// each other.
    @State private var turning: Int?
    /// 0…1 through that turn.
    @State private var turn: Double = 0
    /// How far a pull at the front or the back cover has moved the whole
    /// booklet, since there is no leaf there to turn.
    @State private var strain: CGFloat = 0
    /// Held while a committed turn plays out, so a second swipe cannot start
    /// one on top of it and land the reader two leaves away.
    @State private var settling = false
    /// A drag decides on its first movement whether it is turning a leaf or
    /// reading down one, and does not change its mind.
    @State private var pulling: Bool?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - Booklet.spineReveal - Booklet.foreEdge
            let height = proxy.size.height - Booklet.foreEdge * 2

            ZStack(alignment: .leading) {
                board

                ZStack(alignment: .leading) {
                    if let base = baseLeaf {
                        leaf(base)
                            .frame(width: width, height: height)
                            .overlay { castShadow }
                            .clipShape(Booklet.leafShape)
                    }

                    if let moving = movingLeaf {
                        leaf(moving)
                            .frame(width: width, height: height)
                            .overlay { Color.black.opacity(turn * 0.14) }
                            .clipShape(Booklet.leafShape)
                            .shadow(color: .black.opacity(0.3 * turn), radius: 16, x: -8, y: 0)
                            .rotation3DEffect(
                                .degrees(leafAngle),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .leading,
                                perspective: 0.55
                            )
                    }
                }
                .padding(.leading, Booklet.spineReveal)
                .padding(.trailing, Booklet.foreEdge)
                .padding(.vertical, Booklet.foreEdge)
            }
            .offset(x: reduceMotion ? 0 : strain)
            .contentShape(Rectangle())
            .simultaneousGesture(pageTurn(width: width))
            // The tap zones sit on the container rather than over the leaf, so
            // a tap that lands on the one link a page carries still goes to
            // the link.
            .onTapGesture(coordinateSpace: .local) { point in
                if point.x < Booklet.edgeZone {
                    advance(by: -1)
                } else if point.x > proxy.size.width - Booklet.edgeZone {
                    advance(by: 1)
                }
            }
        }
        // VoiceOver never gets the gesture, so it gets the same two moves by
        // name and by its own paging swipe. Every leaf stays reachable.
        .accessibilityElement(children: .contain)
        .accessibilityScrollAction { edge in
            advance(by: edge == .trailing || edge == .bottom ? 1 : -1)
        }
        .accessibilityAction(named: "Next page") { advance(by: 1) }
        .accessibilityAction(named: "Previous page") { advance(by: -1) }
    }

    // MARK: Which leaf is where

    /// The leaf lying flat: the one being turned onto going forward, and the
    /// one being covered coming back.
    ///
    /// Under Reduce Motion the drag is still measured — it is how the booklet
    /// knows the reader wants the next leaf — but nothing renders it. The leaf
    /// on show is the one they are on until the turn commits, and then it is
    /// the next one. That is the cut.
    private var baseLeaf: Int? {
        let base = turning == 1 && !reduceMotion ? index + 1 : index
        return base >= 0 && base < count ? base : nil
    }

    /// The leaf in the air, if one is.
    private var movingLeaf: Int? {
        guard !reduceMotion, let turning else { return nil }
        let moving = turning == 1 ? index : index - 1
        return moving >= 0 && moving < count ? moving : nil
    }

    /// The leaf travels the full half-circle over its own bound edge, so the
    /// reader watches it lift and fall rather than slide. Halfway through it
    /// is edge-on and the leaf beneath is completely uncovered; the rest is
    /// the follow-through, out past the spine. Coming back, it runs the same
    /// arc the other way.
    private var leafAngle: Double {
        -180 * (turning == 1 ? turn : 1 - turn)
    }

    /// The turning leaf's shadow on the page beneath it — deepest at the
    /// spine, and strongest at mid-turn when the leaf is standing over it.
    private var castShadow: some View {
        let depth = movingLeaf == nil ? 0 : sin(turn * .pi) * 0.34
        return LinearGradient(
            stops: [
                .init(color: .black.opacity(depth), location: 0),
                .init(color: .black.opacity(depth * 0.3), location: 0.4),
                .init(color: .clear, location: 0.9),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .allowsHitTesting(false)
    }

    // MARK: The board

    /// The boards the leaves are bound into, sewn at the spine. It is what
    /// the reader is holding, so it is the thing that casts a shadow and the
    /// thing that stays put — only the leaf moves.
    private var board: some View {
        Booklet.boardShape
            .fill(Kraft.cover)
            .calibreShadow(.modal)
            .overlay(alignment: .leading) {
                Stitching()
                    .stroke(Kraft.rule, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [9, 13]))
                    .frame(width: Booklet.spineReveal)
            }
            .accessibilityHidden(true)
    }

    // MARK: Turning

    private func pageTurn(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !settling, width > 0 else { return }
                if pulling == nil {
                    pulling = abs(value.translation.width) > abs(value.translation.height)
                }
                guard pulling == true else { return }

                let pulled = -value.translation.width / width
                let step = pulled > 0 ? 1 : -1
                if canTurn(by: step) {
                    turning = step
                    turn = min(abs(pulled), 1)
                    strain = 0
                } else {
                    // Nothing left to turn. The booklet gives a little and
                    // comes back, the way the end of anything paged does.
                    turning = nil
                    turn = 0
                    strain = value.translation.width * 0.2
                }
            }
            .onEnded { value in
                defer { pulling = nil }
                guard pulling == true else { return }
                guard let step = turning else {
                    release()
                    return
                }

                let flung = -value.predictedEndTranslation.width / width * Double(step) > 0.5
                if turn > Booklet.commit || (turn > 0.06 && flung) {
                    settle(step)
                } else {
                    release()
                }
            }
    }

    /// Turn one leaf from rest — the edge zones and VoiceOver's own moves.
    private func advance(by step: Int) {
        guard !settling, canTurn(by: step) else { return }
        turning = step
        turn = 0
        settle(step)
    }

    private func canTurn(by step: Int) -> Bool {
        let next = index + step
        return next >= 0 && next < count
    }

    /// Commit: the leaf finishes its arc, and only then does the reader's
    /// place change. Under Reduce Motion it is a cut — the booklet still
    /// pages, it just does not perform the turn.
    private func settle(_ step: Int) {
        Haptics.shared.play(.selection)

        guard !reduceMotion else {
            index += step
            turn = 0
            turning = nil
            return
        }

        settling = true
        withAnimation(Booklet.turn) {
            turn = 1
            strain = 0
        } completion: {
            // The leaf ends the arc showing exactly what a rested booklet
            // one page along shows, so the swap is invisible.
            index += step
            turn = 0
            turning = nil
            settling = false
        }
    }

    /// Not far enough. The leaf falls back where it was.
    private func release() {
        guard !reduceMotion else {
            turn = 0
            turning = nil
            strain = 0
            return
        }
        withAnimation(Booklet.turn) {
            turn = 0
            strain = 0
        } completion: {
            // Unless the reader has already started pulling it again, in
            // which case the leaf they are holding is the one that decides.
            if turn == 0 { turning = nil }
        }
    }
}

/// Shared booklet geometry and the one animation in it.
private enum Booklet {
    /// Width over height. A passport is a little taller than it is wide, and
    /// holding that proportion is most of what makes it read as one object
    /// rather than as a screen with a border.
    static let proportion: CGFloat = 88.0 / 125.0
    /// How much board shows past the bound edge of a leaf, and how much shows
    /// past the other three — the cover of a booklet always stands slightly
    /// proud of the pages it protects.
    static let spineReveal: CGFloat = 9
    static let foreEdge: CGFloat = 4
    /// The strip at either edge of the booklet that turns a leaf when tapped.
    static let edgeZone: CGFloat = 56
    /// How far a leaf has to be pulled before letting go turns it.
    static let commit: Double = 0.3

    /// The turn, from `CALIBRE_PASSPORT_BOOKLET.md` §4: 420ms, accelerating
    /// into contact and settling without overshoot.
    ///
    /// `Motion`'s ease-out is the interface's curve and stays exactly that —
    /// this is a leaf with weight rather than a control confirming a state
    /// change, which is the same carve-out the marks get. The duration is the
    /// interface's own slow beat; only the shape of it differs.
    static let turn = Animation.timingCurve(0.4, 0, 0.2, 1, duration: Motion.slow)

    /// Square where it is bound, cut round on the fore edge — the profile of
    /// a leaf in a stitched booklet.
    static let leafShape = UnevenRoundedRectangle(
        topLeadingRadius: 3,
        bottomLeadingRadius: 3,
        bottomTrailingRadius: Radius.box,
        topTrailingRadius: Radius.box,
        style: .continuous
    )

    /// The same profile, one board wider.
    static let boardShape = UnevenRoundedRectangle(
        topLeadingRadius: Radius.control,
        bottomLeadingRadius: Radius.control,
        bottomTrailingRadius: Radius.panel,
        topTrailingRadius: Radius.panel,
        style: .continuous
    )
}

/// One leaf's stock and its margins.
private struct LeafSurface<Content: View>: View {
    var isCover = false
    /// Off when the leaf is being stacked with the others rather than read on
    /// its own, where the page around it is doing the scrolling.
    var scrolls = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if scrolls {
                // The leaf holds its shape whatever is printed on it: a page
                // shorter than the leaf still occupies the whole leaf, and one
                // longer than it scrolls rather than being cut off.
                GeometryReader { proxy in
                    ScrollView {
                        page.frame(minHeight: proxy.size.height, alignment: alignment)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                page
            }
        }
        .background(isCover ? Kraft.cover : Kraft.page)
        .clipShape(Booklet.leafShape)
        .overlay { Booklet.leafShape.strokeBorder(Kraft.rule, lineWidth: 1) }
    }

    /// The cover is a title page and sits in the middle of the board; every
    /// other leaf is a page of a record and starts at the top of it.
    private var alignment: Alignment { isCover ? .center : .top }

    private var page: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.xl)
    }
}

/// The thread down the spine.
private struct Stitching: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + Space.l))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - Space.l))
        return path
    }
}

/// The booklet's own stock.
///
/// Deliberately local and deliberately not in the palette: this is one
/// document that looks like a physical object, not a new theme. Kraft board
/// under a lighter leaf, warm ink on both, and it holds in dark mode by going
/// darker rather than by turning into a normal screen — a passport that
/// stops being paper at night stops being a passport.
private enum Kraft {
    /// The surface the booklet is lying on. It has to clear the board it is
    /// holding — or the booklet stops reading as an object resting on
    /// something — while still taking the navigation bar's own type and the
    /// two controls under the booklet at full contrast.
    static let desk = dynamic(light: 0xE8DCC6, dark: 0x17120E)
    /// The board it is bound in — the cover, and the spine.
    static let cover = dynamic(light: 0xC9AF8C, dark: 0x2A211A)
    /// A leaf.
    static let page = dynamic(light: 0xEFE2CC, dark: 0x392E25)
    /// An inset panel on a leaf — the grade table.
    static let inset = dynamic(light: 0xE4D4B9, dark: 0x453930)
    /// Ruled lines and edges.
    static let rule = dynamic(light: 0xBFA987, dark: 0x50412F)
    static let ink = dynamic(light: 0x342A20, dark: 0xF0E5D5)
    static let inkMuted = dynamic(light: 0x6E5C46, dark: 0xB6A48C)
    /// Secondary type on the cover board. `inkMuted` is mixed for a leaf and
    /// falls under three to one on the darker stock of the cover, so it drops
    /// the ink's own weight instead of changing colour.
    static let coverInkMuted = ink.opacity(0.72)
    /// The stamp, the heads down the leaves, and the links.
    static let primary = dynamic(light: 0x7D5440, dark: 0xC79274)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// A ruled line across a leaf.
private struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(Kraft.rule)
            .frame(height: 1)
    }
}
