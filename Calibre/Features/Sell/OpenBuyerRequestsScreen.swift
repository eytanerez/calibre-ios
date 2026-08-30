import CalibreDesign
import CalibreKit
import SwiftUI

/// The full list of open buyer sourcing requests — reached from the
/// dashboard's "Buyers are looking for" button rather than rendered inline,
/// so the shop's front page stays a summary, not a second inventory list.
///
/// `/dealer/watch-requests` is a verified-dealer endpoint (a request carries a
/// budget and a username), so a 403 `dealer_required` gets the honest
/// explanation and the way to apply rather than a generic error. The screen
/// re-fetches its own page so that refusal is observable here at all — the
/// dashboard swallows it to keep the shop opening.
struct OpenBuyerRequestsScreen: View {
    /// Rows the dashboard already had, shown while this screen's own fetch is
    /// in flight so the list doesn't flash a skeleton it doesn't need.
    let requests: [WatchRequest]
    let onListWatch: (WatchRequest) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [WatchRequest] = []
    @State private var total: Int?
    @State private var loaded = false
    @State private var loadError: String?
    @State private var dealerRequired = false
    @State private var dealerApplication: DealerApplication?
    @State private var showDealerApplication = false
    @State private var sort: DealerRequestSort = .latest

    var body: some View {
        NavigationStack {
            Group {
                if dealerRequired {
                    dealerRequiredState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty, let loadError, loaded == false {
                    EmptyState(
                        icon: "wifi.slash",
                        title: "Requests didn't load",
                        message: loadError,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    EmptyState(
                        icon: "sparkle.magnifyingglass",
                        title: "No open requests",
                        message: "When a buyer asks Calibre to source a watch, it shows up here for you to list against."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Space.m) {
                            ForEach(rows) { request in
                                requestRow(request)
                            }
                            if let total, total > rows.count {
                                Text("Showing \(rows.count) of \(total)")
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, Space.s)
                            }
                        }
                        .padding(Space.margin)
                    }
                    .refreshable { await load() }
                }
            }
            .calibrePageBackground()
            .navigationTitle("Buyers are looking for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Kept once a load has landed even when the page came back
                // empty, so a sort can never strand the control it needs.
                if !dealerRequired, loaded {
                    ToolbarItem(placement: .topBarLeading) {
                        sortMenu
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(CalibreType.bodyMedium)
                }
            }
        }
        .sheet(isPresented: $showDealerApplication) {
            DealerApplicationScreen(application: dealerApplication) {
                Task { await load() }
            }
        }
        .task {
            rows = requests
            await load()
        }
    }

    // MARK: - Loading

    private func load() async {
        loadError = nil
        do {
            let page = try await services.seller.openDealerRequests(sort: sort)
            rows = page.results
            total = page.total
            dealerRequired = false
            loaded = true
        } catch {
            if sellErrorCode(error, is: "dealer_required") {
                dealerRequired = true
                rows = []
                total = nil
                dealerApplication = try? await services.seller.dealerApplication()
            } else {
                loadError = sellErrorMessage(error)
            }
        }
    }

    /// Verified dealers only, said plainly, with the way in.
    private var dealerRequiredState: some View {
        EmptyState(
            icon: "sparkle.magnifyingglass",
            title: "Verified dealers can browse buyer requests",
            message: "A buyer request carries a budget and a name, so it stays with verified businesses. Completing dealer verification with your EIN and business details makes you one automatically — there is no approval queue.",
            actionTitle: "Apply to become a dealer",
            action: { showDealerApplication = true }
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                Text("Latest").tag(DealerRequestSort.latest)
                Text("Highest budget").tag(DealerRequestSort.budgetHigh)
                Text("Lowest budget").tag(DealerRequestSort.budgetLow)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.calibre.foreground)
        }
        .accessibilityLabel("Sort requests")
        .onChange(of: sort) {
            Task { await load() }
        }
    }

    // MARK: - Rows

    private func requestRow(_ request: WatchRequest) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Eyebrow(request.brand)
                Spacer(minLength: 0)
                // The buyer's text resolved to a catalog row, so brand/model/
                // reference here mean the same thing they mean on a listing.
                if request.isCatalogMatched {
                    StatusBadge("Catalog match", tone: .info)
                }
            }
            Text(request.model ?? "Any model")
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
            if let reference = request.reference, !reference.isEmpty {
                Text("Ref. \(reference)")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            HStack(spacing: Space.m) {
                if let budget = request.maxBudget {
                    Text("Up to \(PriceFormatter.format(budget.value))")
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)
                }
                if let year = request.productionYear {
                    Text(String(year))
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            if let notes = request.notes, !notes.isEmpty {
                Text(notes)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            // Counted server-side against the same catalog row: inventory the
            // dealer already has live, not something to go and list.
            if request.liveMatchCount > 0 {
                Label(
                    "You have \(request.liveMatchCount) live match\(request.liveMatchCount == 1 ? "" : "es")",
                    systemImage: "checkmark.seal"
                )
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.success)
            }
            Button("List this watch") {
                dismiss()
                onListWatch(request)
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
            .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}
