import CalibreDesign
import CalibreKit
import SwiftUI
import WebKit

// MARK: - The hold

/// A watch a person at Calibre is looking at more closely.
///
/// What this replaces printed the bench's own notes under "Authentication
/// issue", and only ever appeared on `auth_pass` or `auth_fail` — so on the one
/// state it exists for, a misrepresentation, it never appeared at all, because
/// a misrepresentation never reaches `auth_fail`.
///
/// The reason for the hold is not named. It is private to the two parties while
/// it is open, and naming it would be Calibre's finding announced before
/// Calibre has finished making it.
struct AuthenticationHoldCard: View {
    let record: OrderAuthentication
    /// The seller is told their payout is paused; the buyer is not told that.
    let audience: Audience

    enum Audience { case buyer, seller }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(record.holdTitle, systemImage: "hourglass")
                .font(CalibreType.bodySemiBold)
                .foregroundStyle(Color.calibre.foreground)
            Text(record.holdBody)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(
                audience == .seller
                    ? "Your payout is paused while we look. Nothing is expected of you right now."
                    : "Nothing is expected of you right now."
            )
            .font(CalibreType.caption)
            .foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .authCardSurface()
    }
}

// MARK: - The report

/// The stored document, displayed exactly as it was filed.
///
/// `loadHTMLString` with a nil base URL: the report is self-contained — fonts,
/// photographs and both QR codes travel inside it — so it has nothing to fetch,
/// and giving it no origin means it could not fetch anything if it tried.
private struct ReportWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .white
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // The initial load only. A document nobody can navigate out of is
            // the whole point of an archive.
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}

/// The row on an order or a vault watch, and the sheet it opens.
struct AuthenticationReportRow: View {
    enum Source {
        case order(String)
        case vault(String)

        /// Stable enough to key a mark on: the document belongs to this order
        /// or this watch, and opening the same one twice is the same document.
        var key: String {
            switch self {
            case .order(let id): "order:\(id)"
            case .vault(let id): "vault:\(id)"
            }
        }
    }

    @Environment(AppServices.self) private var services
    let source: Source
    /// What the order payload advertises about the document. Nil where the
    /// caller has no advertisement to go on — `GET /vault/{id}` carries no
    /// report key at all, and the route answers for itself.
    var reference: AuthenticationReportRef?
    /// Offered when the document turns out not to be on file. The Passport is
    /// the record of what has happened to the watch, and it is a better answer
    /// than a dead end.
    var passportCode: String?

    @State private var showing = false
    @State private var report: AuthenticationReport?
    @State private var failure: String?
    /// The server has told us there is no document, which is a different
    /// sentence from a request that did not get through.
    @State private var notOnFile = false

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.calibre.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Authentication report")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.calibre.placeholder)
            }
            .padding(Space.l)
            .authCardSurface()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens the authentication report for this watch")
        .sheet(isPresented: $showing) {
            NavigationStack {
                Group {
                    if let report {
                        VStack(spacing: 0) {
                            reportHeader(report)
                            ReportWebView(html: report.html)
                        }
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
                        CalibreLoadingView("Opening the report")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle("Report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { showing = false }
                    }
                    if let pdf = (report?.pdfUrl ?? reference?.pdfUrl)?.url {
                        ToolbarItem(placement: .topBarTrailing) {
                            // A custom label replaces ShareLink's own, and a
                            // bare glyph carries none — VoiceOver reached this
                            // button with nothing to announce.
                            ShareLink(item: pdf) { Image(systemName: "square.and.arrow.up") }
                                .accessibilityLabel("Share the authentication report")
                        }
                    }
                }
            }
            // Fetched here rather than on the order screen: the stored document
            // is a few megabytes, and nobody should pay for it by opening an
            // order page.
            .task { await load() }
        }
    }

    private var subtitle: String {
        var parts: [String] = ["What our authentication centre found"]
        if let version = reference?.version, version > 1 { parts.append("version \(version)") }
        return parts.joined(separator: " · ")
    }

    /// The lens comes to rest over the document that arrived — not over the
    /// button that was pressed. This sheet has a real not-found branch, and a
    /// magnifier that swooped in and found something in front of it would be
    /// inventing an inspection that never happened.
    ///
    /// The sheet is its own surface, with the screen that opened it behind, so
    /// the loupe here can never be an order screen's second mark
    /// (CALIBRE_BY_HAND_CONTRACTS.md §4 — one illustrated moment per step).
    private func reportHeader(_ report: AuthenticationReport) -> some View {
        HStack(spacing: Space.m) {
            CalibreMark.loupe(size: 40, trigger: markKey(report))
                .markAnnounces(markKey(report))
            VStack(alignment: .leading, spacing: 2) {
                Text("Authentication report")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Text(issuedLine(report))
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.calibre.border).frame(height: 1)
        }
    }

    /// A re-issued report is a new document and deserves a new look; the same
    /// one opened twice in a session does not.
    private func markKey(_ report: AuthenticationReport) -> String {
        "report:\(source.key):\(report.version)"
    }

    private func issuedLine(_ report: AuthenticationReport) -> String {
        var parts: [String] = []
        if let issued = report.issuedAt {
            parts.append("Issued \(issued.formatted(date: .abbreviated, time: .omitted))")
        }
        if report.version > 1 { parts.append("version \(report.version)") }
        return parts.isEmpty ? "Filed by our authentication centre" : parts.joined(separator: " · ")
    }

    /// Calibre stands behind the watch and has no filed document to open for
    /// it. What goes here is the route the owner actually has, rather than a
    /// "Try again" that can never work.
    private var noFiledReport: some View {
        VStack(spacing: Space.l) {
            EmptyState(
                icon: "doc.text.magnifyingglass",
                title: "No filed report for this one",
                message: "Calibre inspected this watch before it shipped, and there's no report document on file to open. Its Passport is the record of what has happened to it, and our team can tell you what the bench found."
            )
            VStack(spacing: Space.m) {
                // Dismiss first, then push: this sheet carries its own
                // NavigationStack and it has no route table, so a link inside
                // it would look like a way out and be one.
                if let passportCode {
                    Button("Open its Passport") {
                        showing = false
                        services.router.push(.passport(passportCode))
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))
                }
                Button("Ask us about this watch") {
                    showing = false
                    services.router.push(.supportChat)
                }
                .buttonStyle(.calibre(.ghost, fullWidth: true))
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
            switch source {
            case .order(let id):
                report = try await services.client.authenticationReport(orderID: id)
            case .vault(let id):
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
}

// MARK: - The case

/// The proposal, and the two buttons.
///
/// Both figures go to both parties. That is deliberate and it is the opposite
/// of the obvious choice: an asymmetric offer collapses the moment either side
/// screenshots it. Calibre's own remainder is in neither payload.
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
                .font(CalibreType.bodySemiBold)
                .foregroundStyle(Color.calibre.foreground)

            Text(
                payload.summary
                    ?? "Our authentication centre found something that does not match how this watch was described. "
                    + "A person at Calibre is working out what should happen."
            )
            .font(CalibreType.body)
            .foregroundStyle(Color.calibre.mutedForeground)

            Button(showingDocument ? "Hide what we found" : "See what we found") {
                showingDocument.toggle()
                if showingDocument, discrepancy == nil { Task { await loadDocument() } }
            }
            .font(CalibreType.label)
            .foregroundStyle(Color.calibre.primary)

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
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                if let notes = discrepancy.notes, !notes.isEmpty {
                    Text(notes).font(CalibreType.body).foregroundStyle(Color.calibre.foreground)
                }
                let photos = (discrepancy.photos ?? []).filter { $0.url?.url != nil }
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(photos) { photo in
                                AsyncImage(url: photo.url?.url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.calibre.border
                                }
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                            }
                        }
                    }
                }
                if (discrepancy.notes ?? "").isEmpty, photos.isEmpty, (discrepancy.faultTypes ?? []).isEmpty {
                    Text("The written findings are still being put together. Your Calibre contact will send them through.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
        } else {
            CalibreLoadingView()
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
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)

            if proposal.youAcceptedAt != nil {
                Text(
                    proposal.otherPartyAccepted == true
                        ? "You accepted this. Both sides have agreed."
                        : "You accepted this. We are waiting on the other side — nothing happens until they answer."
                )
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
            } else if proposal.declinedBy != nil {
                Text("This proposal was declined. Your Calibre contact will come back with another way forward.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
            } else if proposal.canRespond == true {
                HStack(spacing: Space.s) {
                    Button("Accept this") { Task { await answer(true) } }
                        .buttonStyle(.calibre(.primary))
                        .disabled(answering)
                    Button("Decline") { Task { await answer(false) } }
                        .buttonStyle(.calibre(.secondary))
                        .disabled(answering)
                }
                Text("There is no deadline on this. Nothing happens until both of you have agreed.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
    }

    private func headline(_ payload: AuthCaseProposalPayload) -> String {
        if payload.status != "open" { return "This was settled" }
        return payload.proposal == nil ? "We are looking at this watch" : "A proposal from Calibre"
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
                toasts.show(title: "We have recorded that", message: "Your Calibre contact will come back to you with another way forward.")
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
        background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
}
