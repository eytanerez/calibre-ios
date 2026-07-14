import CalibreDesign
import CalibreKit
import SwiftUI

/// Every negotiation in one place — Sent / Received segments, swipe actions
/// for the quick answers, tap through to the detail. Exported for the
/// Activity tab (route `.offers`).
struct OffersListScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    @State private var model: OffersListModel?
    @State private var segment: OffersSegment = .sent
    @State private var tutorial = TutorialController(
        id: "offers.list",
        steps: [
            TutorialStep(
                id: "swipe",
                anchor: "offers.list",
                title: "Swipe for the quick answer",
                message: "Swipe any offer row: Accept or Decline the ones waiting on you, or Cancel one you sent. Each offer expires 24 hours after the last move.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.card),
                cutoutPadding: Space.xs
            ),
            TutorialStep(
                id: "segments",
                anchor: "offers.segments",
                title: "Two sides to every deal",
                message: "Sent holds what you've offered; Received holds what buyers have offered you. Tap across to see the other side.",
                advance: .perform(event: "segment"),
                hint: .tap,
                cutout: .roundedRect(Radius.control),
                actionPrompt: "Tap a segment"
            ),
        ]
    )

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "arrow.left.arrow.right",
                    title: "Sign in to see your offers",
                    message: "Your negotiations — sent and received — live here once you're signed in.",
                    actionTitle: "Sign in",
                    action: { session.require("Sign in to see your offers") {} }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let model {
                content(model)
            } else {
                Color.calibre.background
            }
        }
        .background(Color.calibre.background.ignoresSafeArea())
        .tutorialOverlay(tutorial)
        .navigationTitle("Offers")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: segment) { _, _ in tutorial.fire("segment") }
        .task {
            guard session.isAuthenticated, model == nil else { return }
            let created = OffersListModel(
                catalog: services.catalog,
                commerce: services.commerce,
                userID: session.user?.id,
                toasts: toasts
            )
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func content(_ model: OffersListModel) -> some View {
        VStack(spacing: 0) {
            SegmentedTabs(
                selection: $segment,
                items: [(.sent, "Sent"), (.received, "Received")]
            )
            .padding(.horizontal, Space.margin)
            .tutorialAnchor("offers.segments")

            switch model.phase {
            case .loading:
                loadingRows
            case .failed(let message):
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: "We couldn't load your offers",
                    message: message,
                    actionTitle: "Try again",
                    action: { Task { await model.load() } }
                )
                Spacer()
            case .ready:
                let offers = model.offers(for: segment)
                if offers.isEmpty {
                    emptyState
                    Spacer()
                } else {
                    list(offers, model: model)
                }
            }
        }
    }

    private func list(_ offers: [Offer], model: OffersListModel) -> some View {
        List {
            ForEach(offers) { offer in
                OfferRow(
                    offer: offer,
                    viewerIsSeller: segment == .received,
                    thumbURL: model.thumbs.url(for: offer.listingId)
                )
                .onAppear { model.thumbs.warm(listingID: offer.listingId) }
                .listRowBackground(Color.calibre.background)
                .listRowSeparatorTint(Color.calibre.border)
                .listRowInsets(EdgeInsets(top: Space.m, leading: Space.margin, bottom: Space.m, trailing: Space.margin))
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if segment == .received, offer.status == .pendingSeller {
                        Button {
                            model.pendingAction = .accept(offer)
                        } label: {
                            Label("Accept", systemImage: "checkmark")
                        }
                        .tint(Color.calibre.success)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if segment == .received, offer.status == .pendingSeller {
                        Button {
                            model.pendingAction = .decline(offer)
                        } label: {
                            Label("Decline", systemImage: "xmark")
                        }
                        .tint(Color.calibre.destructive)
                    } else if segment == .sent, offerIsOpen(offer) {
                        Button {
                            model.pendingAction = .cancel(offer)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .tint(Color.calibre.destructive)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tutorialAnchor("offers.list")
        .onAppear { tutorial.startIfNeeded() }
        .refreshable { await model.load(quiet: true) }
        .confirmationDialog(
            model.pendingAction?.title ?? "",
            isPresented: Binding(
                get: { model.pendingAction != nil },
                set: { if !$0 { model.pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = model.pendingAction {
                Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                    Task { await model.perform(action) }
                }
            }
            Button("Not now", role: .cancel) { model.pendingAction = nil }
        } message: {
            if let action = model.pendingAction {
                Text(action.message)
            }
        }
    }

    private var loadingRows: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: Space.m) {
                        Rectangle().frame(width: 56, height: 56).shimmer()
                        VStack(alignment: .leading, spacing: Space.s) {
                            Rectangle().frame(width: 170, height: 13).shimmer()
                            Rectangle().frame(width: 80, height: 16).shimmer()
                            Rectangle().frame(width: 120, height: 11).shimmer()
                        }
                        Spacer()
                    }
                }
            }
            .padding(Space.margin)
        }
    }

    private var emptyState: some View {
        Group {
            switch segment {
            case .sent:
                EmptyState(
                    icon: "arrow.up.right",
                    title: "No offers yet",
                    message: "You haven't made any offers yet. Found a watch you love? Start the conversation."
                )
            case .received:
                EmptyState(
                    icon: "arrow.down.left",
                    title: "Nothing received yet",
                    message: "Offers on your listings land here, with 24 hours to respond to each one."
                )
            }
        }
    }
}

enum OffersSegment: Hashable {
    case sent, received
}

/// One offer row — thumb, serif amount, status, countdown, latest message.
private struct OfferRow: View {
    let offer: Offer
    let viewerIsSeller: Bool
    let thumbURL: URL?

    var body: some View {
        NavigationLink {
            OfferDetailScreen(offerID: offer.id)
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                SquareThumb(url: thumbURL, side: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.listing?.title ?? "Listing")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)

                    Text(PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency))
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)

                    HStack(spacing: Space.s) {
                        let presentation = offerStatusPresentation(for: offer, viewerIsSeller: viewerIsSeller)
                        StatusBadge(presentation.text, tone: presentation.tone)
                        if let deadline = offerLiveDeadline(for: offer) {
                            CountdownChip(until: deadline)
                        }
                    }
                    .padding(.top, 2)

                    if let preview = offerLatestMessage(offer) {
                        Text(preview)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// State + quick actions for the offers list.
@MainActor
@Observable
final class OffersListModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum QuickAction {
        case accept(Offer)
        case decline(Offer)
        case cancel(Offer)

        var title: String {
            switch self {
            case .accept: "Accept this offer?"
            case .decline: "Decline this offer?"
            case .cancel: "Cancel your offer?"
            }
        }

        var message: String {
            switch self {
            case .accept(let offer):
                "The listing is reserved and the buyer has 24 hours to pay \(PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency))."
            case .decline:
                "The buyer's hold is released and the negotiation ends."
            case .cancel:
                "Your $250 hold is released when the offer is withdrawn."
            }
        }

        var confirmLabel: String {
            switch self {
            case .accept: "Accept"
            case .decline: "Decline"
            case .cancel: "Cancel offer"
            }
        }

        var isDestructive: Bool {
            switch self {
            case .accept: false
            case .decline, .cancel: true
            }
        }
    }

    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let userID: String?
    @ObservationIgnored private let toasts: ToastCenter
    let thumbs: ListingThumbCache

    var phase: Phase = .loading
    private(set) var all: [Offer] = []
    var pendingAction: QuickAction?

    init(catalog: CatalogStore, commerce: CommerceStore, userID: String?, toasts: ToastCenter) {
        self.commerce = commerce
        self.userID = userID
        self.toasts = toasts
        self.thumbs = ListingThumbCache(catalog: catalog)
    }

    func load(quiet: Bool = false) async {
        if !quiet { phase = .loading }
        do {
            all = try await commerce.offers()
            phase = .ready
        } catch {
            if !quiet {
                phase = .failed((error as? APIError)?.errorDescription ?? "Something went wrong.")
            }
        }
    }

    func offers(for segment: OffersSegment) -> [Offer] {
        all.filter { offer in
            let isSeller = offerViewerIsSeller(offer, userID: userID)
            return segment == .received ? isSeller : !isSeller
        }
    }

    func perform(_ action: QuickAction) async {
        pendingAction = nil
        do {
            switch action {
            case .accept(let offer):
                _ = try await commerce.respond(toOffer: offer.id, .accept(message: nil))
                Haptics.shared.play(.success)
                toasts.show(title: "Offer accepted", message: "The buyer has 24 hours to pay.", tone: .success)
            case .decline(let offer):
                _ = try await commerce.respond(toOffer: offer.id, .decline(message: nil))
                toasts.show(title: "Offer declined")
            case .cancel(let offer):
                _ = try await commerce.cancelOffer(offerID: offer.id)
                toasts.show(title: "Offer withdrawn", message: "Your $250 hold has been released.")
            }
            await load(quiet: true)
        } catch {
            Haptics.shared.play(.error)
            toasts.show(
                title: "That didn't go through",
                message: (error as? APIError)?.errorDescription ?? "Please try again.",
                tone: .error
            )
        }
    }
}
