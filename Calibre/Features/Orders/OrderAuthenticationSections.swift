import CalibreDesign
import CalibreKit
import SwiftUI
import WebKit

// MARK: - Arrival

/// Where the watch physically is on its way to the bench.
///
/// `to_auth` is a single order status covering three genuinely different
/// situations, and until this build all three read as "on its way to our
/// authentication center" — including the days after it had already arrived.
/// Only the record can tell the last of them apart: the carrier's delivered
/// scan says a parcel reached a building, and `arrivedAt` says a watch reached
/// a person who opened the box and photographed it.
enum ArrivalPhase {
    case labelBought
    case inTransit
    case deliveredUnconfirmed
    case onTheBench
}

extension Order {
    var arrivalPhase: ArrivalPhase {
        if authentication?.arrivedAt != nil { return .onTheBench }
        if toAuthShipment?.deliveredAt != nil { return .deliveredUnconfirmed }
        if toAuthShipment?.shippedAt != nil { return .inTransit }
        return .labelBought
    }

    /// The buyer's sentence for `to_auth`, or nil for every other status —
    /// the caller keeps its own copy for those.
    var arrivalSummary: String? {
        guard status == .toAuth else { return nil }
        switch arrivalPhase {
        case .labelBought:
            return "The seller has their label. Your watch is with them until they hand it to the carrier."
        case .inTransit:
            return "With the carrier, on its way to our authentication centre."
        case .deliveredUnconfirmed:
            return "It has reached our authentication centre and is waiting to be checked in by hand."
        case .onTheBench:
            return "On the bench at our authentication centre."
        }
    }

    /// The same fact for the seller, whose question is "did it get there".
    var sellerArrivalSummary: String? {
        guard status == .toAuth else { return nil }
        switch arrivalPhase {
        case .labelBought:
            return "Your label is ready. Nothing has been scanned yet — the clock starts when the carrier takes it."
        case .inTransit:
            return "The carrier has your watch and it is on its way to authentication."
        case .deliveredUnconfirmed:
            return "Your watch has reached the authentication centre and is waiting to be checked in by hand."
        case .onTheBench:
            return "Your watch is on the bench at the authentication centre."
        }
    }
}

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

    private var body_: String {
        if record.holdReason == "service" || record.serviceRecommended == true {
            return "Our authentication centre found something worth a second opinion on how this watch is running. "
                + "Nothing is decided and nothing has changed about your order. A person at Calibre is reviewing it "
                + "and will write to you with what we found and what we suggest."
        }
        return "Your watch is with our authentication centre and a person at Calibre is reviewing it before it goes "
            + "any further. Nothing is decided yet. We will write to you with what we found, and you will be asked "
            + "before anything about your order changes."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("We are taking a closer look at your watch", systemImage: "hourglass")
                .font(CalibreType.bodySemiBold)
                .foregroundStyle(Color.calibre.foreground)
            Text(body_)
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
    }

    @Environment(AppServices.self) private var services
    let source: Source
    let reference: AuthenticationReportRef

    @State private var showing = false
    @State private var report: AuthenticationReport?
    @State private var failure: String?

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
                        ReportWebView(html: report.html)
                    } else if let failure {
                        EmptyState(
                            icon: "doc.text.magnifyingglass",
                            title: "We couldn't open the report",
                            message: failure,
                            actionTitle: "Try again"
                        ) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle("Report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { showing = false }
                    }
                    if let pdf = (report?.pdfUrl ?? reference.pdfUrl)?.url {
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
        if reference.version > 1 { parts.append("version \(reference.version)") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard report == nil else { return }
        failure = nil
        do {
            switch source {
            case .order(let id):
                report = try await services.client.authenticationReport(orderID: id)
            case .vault(let id):
                report = try await services.client.vaultAuthenticationReport(vaultID: id)
            }
        } catch {
            failure = (error as? APIError)?.errorDescription ?? "Try again in a moment."
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
            ProgressView()
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
