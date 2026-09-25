import RewoundDesign
import RewoundKit
import SwiftUI

/// Watch sourcing requests — "tell us what you're hunting." Buyers post wanted
/// watches; sellers see open requests and list against them.
struct RequestsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.routePush) private var routePush

    @State private var requests: [WatchRequest] = []
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var showNew = false
    @State private var confirmDelete: WatchRequest?

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "sparkle.magnifyingglass",
                    title: "Can't find it? Request it",
                    message: "Sign in to tell us what you're hunting. Sellers see open requests and list against them.",
                    actionTitle: "Sign in"
                ) { session.require("Sign in to request a watch") {} }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requests.isEmpty && loadFailed {
                EmptyState(
                    icon: "wifi.slash",
                    title: "Requests are out of reach",
                    message: "We couldn't load your requests. Check your connection and try again.",
                    actionTitle: "Try again"
                ) { await load() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requests.isEmpty && loaded {
                EmptyState(
                    icon: "sparkle.magnifyingglass",
                    title: "No requests yet",
                    message: "Tell us the watch you're after. We'll notify you the moment a match goes live.",
                    actionTitle: "Request a watch"
                ) { showNew = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.m) {
                        ForEach(requests) { request in
                            RequestRow(request: request, actions: rowActions(for: request))
                                .rowActions(rowActions(for: request))
                        }
                    }
                    .padding(Space.margin)
                }
            }
        }
        .rewoundPageBackground()
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Request a watch")
                }
            }
        }
        .sheet(isPresented: $showNew) {
            NewRequestSheet(entryPoint: .requests) { created in
                requests.insert(created, at: 0)
            }
        }
        .alert(
            "Remove this request?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            presenting: confirmDelete
        ) { request in
            Button("Remove", role: .destructive) {
                Task { await delete(request) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("We'll stop looking for \([request.brand, request.model].compactMap { $0 }.joined(separator: " ")).")
        }
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated else { return }
            await load()
        }
    }

    /// One definition, shared by the ⋯ menu, the swipe and long-press.
    private func rowActions(for request: WatchRequest) -> [RowAction] {
        var actions: [RowAction] = []
        if request.status == .fulfilled, let listingID = request.fulfilledListingId {
            actions.append(
                RowAction("View match", systemImage: "arrow.up.right") {
                    routePush(.listing(listingID))
                }
            )
        }
        actions.append(
            RowAction("Remove request", systemImage: "trash", isDestructive: true) {
                confirmDelete = request
            }
        )
        return actions
    }

    private func load() async {
        do {
            requests = try await services.seller.myWatchRequests()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        loaded = true
    }

    private func delete(_ request: WatchRequest) async {
        do {
            try await services.seller.deleteWatchRequest(id: request.id)
            requests.removeAll { $0.id == request.id }
            Haptics.shared.play(.selection)
        } catch {
            toasts.show(title: "Couldn't remove request", message: error.orderMessage, tone: .error)
        }
    }
}

private struct RequestRow: View {
    let request: WatchRequest
    let actions: [RowAction]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text([request.brand, request.model].compactMap { $0 }.joined(separator: " "))
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Spacer()
                StatusBadge(
                    request.status == .fulfilled ? "Sourced" : "Active",
                    tone: request.status == .fulfilled ? .success : .info
                )
            }
            HStack(spacing: Space.m) {
                if let year = request.productionYear {
                    detail("Year", String(year))
                }
                if let budget = request.maxBudget {
                    detail("Budget", PriceFormatter.format(budget.value, currency: request.currency ?? "USD"))
                }
                if let reference = request.reference {
                    detail("Ref.", reference)
                }
            }
            if let notes = request.notes, !notes.isEmpty {
                Text(notes).font(RewoundType.caption).foregroundStyle(Color.rewound.mutedForeground).lineLimit(2)
            }
            HStack(spacing: Space.m) {
                if let match = actions.first, request.status == .fulfilled {
                    Button(match.title) { match.action() }
                        .buttonStyle(.rewound(.secondary))
                }
                Spacer()
                RowActionsMenu(
                    actions: actions,
                    label: "Options for this request"
                )
            }
        }
        .padding(Space.l)
        .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.rewound.border, lineWidth: 1))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(RewoundType.caption).foregroundStyle(Color.rewound.placeholder)
            Text(value).font(RewoundType.label).foregroundStyle(Color.rewound.foreground)
        }
    }
}
