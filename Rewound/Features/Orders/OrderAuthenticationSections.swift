import RewoundDesign
import RewoundKit
import SwiftUI

// MARK: - The hold

/// A watch a person at Rewound is looking at more closely.
///
/// What this replaces printed the bench's own notes under "Authentication
/// issue", and only ever appeared on `auth_pass` or `auth_fail` — so on the one
/// state it exists for, a misrepresentation, it never appeared at all, because
/// a misrepresentation never reaches `auth_fail`.
///
/// The reason for the hold is not named. It is private to the two parties while
/// it is open, and naming it would be Rewound's finding announced before
/// Rewound has finished making it.
struct AuthenticationHoldCard: View {
    let record: OrderAuthentication
    /// The seller is told their payout is paused; the buyer is not told that.
    let audience: Audience

    enum Audience { case buyer, seller }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(record.holdTitle, systemImage: "hourglass")
                .font(RewoundType.bodySemiBold)
                .foregroundStyle(Color.rewound.foreground)
            Text(record.holdBody)
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.mutedForeground)
            Text(
                audience == .seller
                    ? "Your payout is paused while we look. Nothing is expected of you right now."
                    : "Nothing is expected of you right now."
            )
            .font(RewoundType.caption)
            .foregroundStyle(Color.rewound.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .authCardSurface()
    }
}

// MARK: - The report

/// Which document to open, and what to offer if there is not one.
///
/// Carried by value on the navigation path, which is what lets the report be a
/// page rather than a sheet.
struct AuthenticationReportTarget: Hashable {
    enum Subject: Hashable {
        case order(String)
        case vaultWatch(String)
    }

    let subject: Subject
    /// Offered when the document turns out not to be on file. The Passport is
    /// the record of what has happened to the watch, and it is a better answer
    /// than a dead end.
    var passportCode: String?
    /// The PDF the order payload advertised, carried so the share control
    /// survives the two cases where the fetched report cannot supply one: a
    /// fetch that fails, and a filed document whose own row has no PDF while
    /// the order's reference does. As a sheet this screen read both; as a page
    /// it can only read what the target hands it.
    var pdfUrl: MediaURL?

    /// Stable enough to key a mark on: the document belongs to this order or
    /// this watch, and opening the same one twice is the same document.
    var key: String {
        switch subject {
        case .order(let id): "order:\(id)"
        case .vaultWatch(let id): "vault:\(id)"
        }
    }
}

/// The row on an order or a vault watch, and the page it opens.
struct AuthenticationReportRow: View {
    @Environment(\.routePush) private var routePush
    let source: AuthenticationReportTarget.Subject
    /// What the order payload advertises about the document. Nil where the
    /// caller has no advertisement to go on — `GET /vault/{id}` carries no
    /// report key at all, and the route answers for itself.
    var reference: AuthenticationReportRef?
    var passportCode: String?

    var body: some View {
        Button {
            routePush(.authenticationReport(
                AuthenticationReportTarget(
                    subject: source,
                    passportCode: passportCode,
                    pdfUrl: reference?.pdfUrl
                )
            ))
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.rewound.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Authentication report")
                        .font(RewoundType.bodyMedium)
                        .foregroundStyle(Color.rewound.foreground)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.rewound.placeholder)
            }
            .padding(Space.l)
            .authCardSurface()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens the authentication report for this watch")
    }

    private var subtitle: String {
        var parts: [String] = ["What our authentication center found"]
        if let version = reference?.version, version > 1 { parts.append("version \(version)") }
        return parts.joined(separator: " · ")
    }
}

/// The authentication report, as a page.
///
/// **A page and not a sheet, which is a change of kind.** The envelope
/// sequence opens onto the document itself — the report grows out of the
/// envelope and the verification stamp presses onto it as it settles — and a
/// sheet is its own presentation above the root, so the film had to be hosted
/// a second time inside it or it would have played behind the thing it was
/// opening. Two hosts, two grounds, and a document that was a card on top of
/// the order rather than the place the reader had arrived at. It is pushed on
/// the stack now, the root's own host plays the film over it, and Back is the
/// ordinary Back.
///
/// **The PDF stays**, as the share control in the toolbar: a buyer who wants a
/// file to keep or forward gets exactly the document they got before. The PDF
/// is for printing; this is for reading.
struct AuthenticationReportScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.routePush) private var routePush

    let target: AuthenticationReportTarget

    @State private var report: AuthenticationReport?
    @State private var failure: String?
    /// The server has told us there is no document, which is a different
    /// sentence from a request that did not get through.
    @State private var notOnFile = false

    var body: some View {
        Group {
            if let report {
                reportPage(report)
            } else if notOnFile {
                noFiledReport
            } else if let failure {
                EmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "We couldn't open the report",
                    message: failure,
                    actionTitle: "Try again"
                ) { Task { await load() } }
            } else {
                RewoundLoadingView("Opening the report")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Both sources, the way the sheet read them: the fetched document
            // first, then what the order advertised. Either alone loses the
            // control on a case where it used to be there.
            if let pdf = (report?.pdfUrl ?? target.pdfUrl)?.url {
                ToolbarItem(placement: .topBarTrailing) {
                    // A custom label replaces ShareLink's own, and a bare
                    // glyph carries none — VoiceOver reached this button with
                    // nothing to announce.
                    ShareLink(item: pdf) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share the authentication report")
                }
            }
        }
        // Fetched here rather than on the order screen: the stored document is
        // a few megabytes, and nobody should pay for it by opening an order
        // page.
        .task { await load() }
    }

    @ViewBuilder
    private func reportPage(_ report: AuthenticationReport) -> some View {
        if let content = report.content {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    reportHeader(report)
                    NativeAuthenticationReport(content: content)
                }
                .padding(Space.l)
            }
            .rewoundPageBackground()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    reportHeader(report)
                    EmptyState(
                        icon: "doc.text",
                        title: "This earlier report is archived as a PDF",
                        message: "The native findings are not available for this version. You can refresh in case the archive has been updated, or open the filed PDF."
                    )
                    if let pdf = (report.pdfUrl ?? target.pdfUrl)?.url {
                        Link("Open the filed PDF", destination: pdf)
                            .buttonStyle(.rewound(.secondary, fullWidth: true))
                    }
                    Button("Refresh report") { Task { await reload() } }
                        .buttonStyle(.rewound(.ghost, fullWidth: true))
                }
                .padding(Space.l)
            }
            .rewoundPageBackground()
        }
    }

    /// The lens comes to rest over the document that arrived — not over the
    /// button that was pressed. This page has a real not-found branch, and a
    /// magnifier that swooped in and found something in front of it would be
    /// inventing an inspection that never happened.
    ///
    /// The report is its own screen, with the order behind it in the stack, so
    /// the loupe here can never be an order screen's second mark
    /// (REWOUND_BY_HAND_CONTRACTS.md §4 — one illustrated moment per step).
    private func reportHeader(_ report: AuthenticationReport) -> some View {
        HStack(spacing: Space.m) {
            RewoundMark.loupe(size: 40, trigger: markKey(report))
                .markAnnounces(markKey(report))
            VStack(alignment: .leading, spacing: 2) {
                Text("Authentication report")
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Text(issuedLine(report))
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rewound.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
    }

    /// A re-issued report is a new document and deserves a new look; the same
    /// one opened twice in a session does not.
    private func markKey(_ report: AuthenticationReport) -> String {
        "report:\(target.key):\(report.version)"
    }

    private func issuedLine(_ report: AuthenticationReport) -> String {
        var parts: [String] = []
        if let issued = report.issuedAt {
            parts.append("Issued \(issued.formatted(date: .abbreviated, time: .omitted))")
        }
        if report.version > 1 { parts.append("version \(report.version)") }
        return parts.isEmpty ? "Filed by our authentication center" : parts.joined(separator: " · ")
    }

    /// Rewound stands behind the watch and has no filed document to open for
    /// it. What goes here is the route the owner actually has, rather than a
    /// "Try again" that can never work.
    private var noFiledReport: some View {
        VStack(spacing: Space.l) {
            EmptyState(
                icon: "doc.text.magnifyingglass",
                title: "No filed report for this one",
                message: "Rewound inspected this watch before it shipped, and there's no report document on file to open. Its Passport is the record of what has happened to it, and our team can tell you what the bench found."
            )
            VStack(spacing: Space.m) {
                // Ordinary pushes now. This is a page on the reader's own
                // stack, so what it offers goes above it and Back still walks
                // the way they came — the sheet had to dismiss itself first,
                // because a link inside it looked like a way out without being
                // one.
                if let code = target.passportCode {
                    Button("Open its Passport") { routePush(.passport(code)) }
                        .buttonStyle(.rewound(.secondary, fullWidth: true))
                }
                Button("Ask us about this watch") { routePush(.supportChat) }
                    .buttonStyle(.rewound(.ghost, fullWidth: true))
            }
            .padding(.horizontal, Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard report == nil else { return }
        failure = nil
        notOnFile = false
        do {
            switch target.subject {
            case .order(let id):
                report = try await services.client.authenticationReport(orderID: id)
            case .vaultWatch(let id):
                report = try await services.client.vaultAuthenticationReport(vaultID: id)
            }
        } catch {
            // 404 is the route saying there is no such document, which is not a
            // fault and has a better answer than a retry.
            if (error as? APIError)?.httpStatus == 404 {
                notOnFile = true
            } else {
                failure = (error as? APIError)?.errorDescription ?? "Try again in a moment."
            }
        }
    }

    private func reload() async {
        report = nil
        await load()
    }
}

// MARK: - Native report content

/// The immutable bench findings, rendered with native text, rows and images.
/// The PDF remains a shareable archive; it is not the reading surface.
private struct NativeAuthenticationReport: View {
    let content: AuthenticationReportContent

    private var photographs: [AuthenticationReportPhotograph] {
        content.gallery.isEmpty ? content.photographs : content.gallery
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Space.xl) {
            result
            serviceRecommendation
            timepiece
            condition
            inclusions
            performance
            visualFindings
            technicalFindings
            notes
            photographGallery

            if let footer = content.findingsFooter, !footer.isEmpty {
                Text(footer)
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(content.headLabel, color: Color.rewound.primary)
            Text(content.title)
                .font(RewoundType.title)
                .foregroundStyle(Color.rewound.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if let lede = content.lede, !lede.isEmpty {
                Text(lede)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                StatusBadge(content.result.label, tone: resultTone)
                if let qualifier = content.result.qualifier, !qualifier.isEmpty {
                    Text(qualifier)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
                Spacer(minLength: 0)
                if let date = content.result.date, !date.isEmpty {
                    Text(date)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
            }
        }
        .padding(Space.l)
        .authReportSurface()
    }

    private var resultTone: StatusBadge.Tone {
        switch content.result.verdict?.lowercased() {
        case "authenticated": .success
        case "misrepresented", "counterfeit", "failed": .danger
        default: .neutral
        }
    }

    @ViewBuilder
    private var serviceRecommendation: some View {
        if content.record.serviceRecommended == true {
            CalloutBand(
                icon: "wrench.and.screwdriver",
                title: "Service recommended",
                message: "The authentication record recommends mechanical service. See the findings below for the recorded measurements and notes."
            )
        }
    }

    @ViewBuilder
    private var timepiece: some View {
        if !content.timepiece.isEmpty {
            reportSection("Timepiece") {
                VStack(spacing: 0) {
                    ForEach(Array(content.timepiece.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                            Text(row.label)
                                .font(RewoundType.caption)
                                .foregroundStyle(Color.rewound.mutedForeground)
                            Spacer(minLength: Space.m)
                            let valueFont = row.strong == true ? RewoundType.bodySemiBold : RewoundType.body
                            Text(row.value)
                                .font(row.tabular == true ? valueFont.monospacedDigit() : valueFont)
                                .foregroundStyle(Color.rewound.foreground)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, Space.m)
                        if index < content.timepiece.count - 1 { reportDivider }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var condition: some View {
        if !content.condition.rows.isEmpty || !(content.condition.overall ?? "").isEmpty {
            reportSection("Condition") {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let overall = content.condition.overall, !overall.isEmpty {
                        LabeledContent("Overall") {
                            Text(overall)
                                .font(RewoundType.bodySemiBold)
                                .foregroundStyle(Color.rewound.foreground)
                        }
                    }
                    if let lede = content.condition.lede, !lede.isEmpty {
                        Text(lede)
                            .font(RewoundType.body)
                            .foregroundStyle(Color.rewound.secondaryForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !content.condition.scale.isEmpty {
                        Text("Scale: \(content.condition.scale.joined(separator: " · "))")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(content.condition.rows.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: Space.s) {
                                HStack {
                                    Text(row.label).font(RewoundType.bodyMedium)
                                    Spacer()
                                    Label(
                                        row.agrees ? "Matches" : "Different",
                                        systemImage: row.agrees ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                                    )
                                    .font(RewoundType.caption)
                                    .foregroundStyle(row.agrees ? Color.rewound.success : Color.rewound.warning)
                                }
                                comparisonLine("Seller", row.seller)
                                comparisonLine("Calibre", row.calibre)
                            }
                            .padding(.vertical, Space.m)
                            if index < content.condition.rows.count - 1 { reportDivider }
                        }
                    }
                    if let footnote = content.condition.footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func comparisonLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(label)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var inclusions: some View {
        if !content.inclusions.isEmpty {
            reportSection("Included") {
                VStack(spacing: 0) {
                    ForEach(Array(content.inclusions.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: Space.m) {
                            Image(systemName: item.present ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(item.present ? Color.rewound.success : Color.rewound.mutedForeground)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label).font(RewoundType.bodyMedium)
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(RewoundType.caption)
                                        .foregroundStyle(Color.rewound.mutedForeground)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Space.m)
                        .accessibilityElement(children: .combine)
                        if index < content.inclusions.count - 1 { reportDivider }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var performance: some View {
        if !content.performance.isEmpty {
            reportSection("Performance") {
                VStack(spacing: 0) {
                    ForEach(Array(content.performance.enumerated()), id: \.element.id) { index, item in
                        findingRow(title: item.label, value: item.verdict, detail: item.detail)
                            .padding(.vertical, Space.m)
                        if index < content.performance.count - 1 { reportDivider }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var visualFindings: some View {
        if !content.visual.isEmpty {
            reportSection("Visual findings") {
                VStack(spacing: 0) {
                    ForEach(Array(content.visual.enumerated()), id: \.element.id) { index, item in
                        findingRow(title: item.label, value: nil, detail: item.note)
                            .padding(.vertical, Space.m)
                        if index < content.visual.count - 1 { reportDivider }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var technicalFindings: some View {
        if !content.technical.isEmpty {
            reportSection("Technical findings") {
                VStack(spacing: 0) {
                    ForEach(Array(content.technical.enumerated()), id: \.element.id) { index, item in
                        findingRow(title: item.label, value: item.value, detail: item.explanation)
                            .padding(.vertical, Space.m)
                        if index < content.technical.count - 1 { reportDivider }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if !content.notes.isEmpty {
            reportSection("Notes") {
                VStack(spacing: 0) {
                    ForEach(Array(content.notes.enumerated()), id: \.element.id) { index, note in
                        findingRow(title: note.title, value: nil, detail: note.body)
                            .padding(.vertical, Space.m)
                        if index < content.notes.count - 1 { reportDivider }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var photographGallery: some View {
        if !photographs.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Photographs")
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
                ForEach(photographs) { photograph in
                    AuthenticationReportPhoto(photograph: photograph)
                }
            }
        }
    }

    private func findingRow(title: String, value: String?, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Spacer(minLength: Space.m)
                if let value, !value.isEmpty {
                    Text(value)
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reportSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(RewoundType.sectionTitle)
                .foregroundStyle(Color.rewound.foreground)
            content()
                .padding(.horizontal, Space.l)
                .authReportSurface()
        }
    }

    private var reportDivider: some View {
        Rectangle().fill(Color.rewound.border).frame(height: 1)
    }
}

private struct AuthenticationReportPhoto: View {
    let photograph: AuthenticationReportPhotograph

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            GeometryReader { proxy in
                if let url = photograph.url.url {
                    PrivateImage(url: url, side: proxy.size.width) { phase in
                        switch phase {
                        case .loaded(let image):
                            image.resizable().scaledToFit()
                        case .failed:
                            ContentUnavailableView("Photograph unavailable", systemImage: "photo")
                        case .loading:
                            Rectangle().fill(Color.rewound.secondary).shimmer()
                        }
                    }
                } else {
                    ContentUnavailableView("Photograph unavailable", systemImage: "photo")
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .background(Color.rewound.secondary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))

            if let title = photograph.title, !title.isEmpty {
                Text(title)
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
            }
            if let caption = photograph.caption, !caption.isEmpty {
                Text(caption)
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func authReportSurface() -> some View {
        background(Color.rewound.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
    }
}

// MARK: - The case

/// The proposal, and the two buttons.
///
/// Both figures go to both parties. That is deliberate and it is the opposite
/// of the obvious choice: an asymmetric offer collapses the moment either side
/// screenshots it. Rewound's own remainder is in neither payload.
///
/// There is no countdown here and no default. Silence decides nothing.
struct AuthCaseCard: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    let caseID: String
    /// Called after an answer lands so the order can be re-read.
    var onAnswered: () -> Void = {}

    @State private var payload: AuthCaseProposalPayload?
    @State private var discrepancy: AuthCaseDiscrepancy?
    @State private var showingDocument = false
    @State private var answering = false

    var body: some View {
        Group {
            if let payload {
                card(payload)
            } else {
                EmptyView()
            }
        }
        .task(id: caseID) { await load() }
    }

    @ViewBuilder private func card(_ payload: AuthCaseProposalPayload) -> some View {
        let proposal = payload.proposal
        VStack(alignment: .leading, spacing: Space.m) {
            Text(headline(payload))
                .font(RewoundType.bodySemiBold)
                .foregroundStyle(Color.rewound.foreground)

            Text(
                payload.summary
                    ?? "Our authentication center found something that does not match how this watch was described. "
                    + "A person at Rewound is working out what should happen."
            )
            .font(RewoundType.body)
            .foregroundStyle(Color.rewound.mutedForeground)

            Button(showingDocument ? "Hide what we found" : "See what we found") {
                showingDocument.toggle()
                if showingDocument, discrepancy == nil { Task { await loadDocument() } }
            }
            .font(RewoundType.label)
            .foregroundStyle(Color.rewound.primary)

            if showingDocument { documentBody() }

            if let proposal {
                figures(payload, proposal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .authCardSurface()
    }

    @ViewBuilder private func documentBody() -> some View {
        if let discrepancy {
            VStack(alignment: .leading, spacing: Space.s) {
                if let faults = discrepancy.faultTypes, !faults.isEmpty {
                    Text(faults.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " · "))
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
                if let notes = discrepancy.notes, !notes.isEmpty {
                    Text(notes).font(RewoundType.body).foregroundStyle(Color.rewound.foreground)
                }
                let photos = (discrepancy.photos ?? []).filter { $0.url?.url != nil }
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(photos) { photo in
                                if let url = photo.url?.url {
                                    PrivateImage(url: url, side: 140) { phase in
                                        switch phase {
                                        case .loaded(let image):
                                            image.resizable().scaledToFill()
                                        case .loading:
                                            Color.rewound.border.shimmer()
                                        case .failed:
                                            Image(systemName: "photo")
                                                .foregroundStyle(Color.rewound.mutedForeground)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(Color.rewound.secondary)
                                        }
                                    }
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                                }
                            }
                        }
                    }
                }
                if (discrepancy.notes ?? "").isEmpty, photos.isEmpty, (discrepancy.faultTypes ?? []).isEmpty {
                    Text("The written findings are still being put together. Your Rewound contact will send them through.")
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
            }
        } else {
            RewoundLoadingView()
        }
    }

    @ViewBuilder private func figures(_ payload: AuthCaseProposalPayload, _ proposal: AuthCaseProposal) -> some View {
        let youAreBuyer = payload.youAre == "buyer"
        let yours = youAreBuyer ? proposal.buyerReceives : proposal.sellerReceives
        let theirs = youAreBuyer ? proposal.sellerReceives : proposal.buyerReceives
        VStack(alignment: .leading, spacing: Space.s) {
            SpecList([
                (youAreBuyer ? "Refunded to you" : "Paid out to you", money(yours, proposal.currency)),
                (youAreBuyer ? "Paid out to the seller" : "Refunded to the buyer", money(theirs, proposal.currency)),
            ])
            Text("Both of you are shown both figures.")
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)

            if proposal.youAcceptedAt != nil {
                Text(
                    proposal.otherPartyAccepted == true
                        ? "You accepted this. Both sides have agreed."
                        : "You accepted this. We are waiting on the other side — nothing happens until they answer."
                )
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
            } else if proposal.declinedBy != nil {
                Text("This proposal was declined. Your Rewound contact will come back with another way forward.")
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
            } else if proposal.canRespond == true {
                HStack(spacing: Space.s) {
                    Button("Accept this") { Task { await answer(true) } }
                        .buttonStyle(.rewound(.primary))
                        .disabled(answering)
                    Button("Decline") { Task { await answer(false) } }
                        .buttonStyle(.rewound(.secondary))
                        .disabled(answering)
                }
                Text("There is no deadline on this. Nothing happens until both of you have agreed.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
        }
    }

    private func headline(_ payload: AuthCaseProposalPayload) -> String {
        if payload.status != "open" { return "This was settled" }
        return payload.proposal == nil ? "We are looking at this watch" : "A proposal from Rewound"
    }

    private func money(_ amount: String?, _ currency: String?) -> String {
        guard let amount, let value = Decimal(string: amount) else { return "—" }
        return value.formatted(.currency(code: currency ?? "USD"))
    }

    private func load() async {
        // A case the caller is not party to answers 404 with the same sentence
        // as a case that does not exist, so there is nothing to draw and no
        // failure worth reporting.
        payload = try? await services.client.authCaseProposal(caseID: caseID)
    }

    private func loadDocument() async {
        discrepancy = try? await services.client.authCaseDiscrepancy(caseID: caseID)
    }

    private func answer(_ accept: Bool) async {
        answering = true
        defer { answering = false }
        do {
            let response = try await services.client.respondToAuthCase(caseID: caseID, accept: accept)
            payload = try? await services.client.authCaseProposal(caseID: caseID)
            onAnswered()
            if !accept {
                toasts.show(title: "We have recorded that", message: "Your Rewound contact will come back to you with another way forward.")
            } else if response.settlement?.status == "settled" {
                toasts.show(title: "Agreed", message: "Both sides have accepted and this is settled.")
            } else {
                // A settlement that failed is still their answer recorded.
                // Telling them otherwise would ask them to agree twice.
                toasts.show(title: "Your answer is recorded")
            }
        } catch {
            toasts.show(
                title: "We could not record that",
                message: (error as? APIError)?.errorDescription ?? "Try again in a moment.",
                tone: .error
            )
        }
    }
}

// MARK: - Shared surface

extension View {
    /// The order detail's card surface, reachable from these sections too.
    func authCardSurface() -> some View {
        background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
    }
}
