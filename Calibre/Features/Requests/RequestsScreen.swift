import CalibreDesign
import CalibreKit
import SwiftUI

/// Watch sourcing requests — "tell us what you're hunting." Buyers post wanted
/// watches; sellers see open requests and list against them.
struct RequestsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    @State private var requests: [WatchRequest] = []
    @State private var loaded = false
    @State private var showNew = false

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
                            RequestRow(request: request) {
                                if let listingID = request.fulfilledListingId {
                                    services.router.open(.listing(listingID))
                                }
                            } onDelete: {
                                Task { await delete(request) }
                            }
                        }
                    }
                    .padding(Space.margin)
                }
            }
        }
        .background(Color.calibre.background)
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
            NewRequestSheet { created in
                requests.insert(created, at: 0)
            }
        }
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated else { return }
            await load()
        }
    }

    private func load() async {
        requests = (try? await services.seller.myWatchRequests()) ?? []
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
    let onViewMatch: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text([request.brand, request.model].compactMap { $0 }.joined(separator: " "))
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
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
                Text(notes).font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground).lineLimit(2)
            }
            HStack(spacing: Space.m) {
                if request.status == .fulfilled, request.fulfilledListingId != nil {
                    Button("View match", action: onViewMatch).buttonStyle(.calibre(.secondary))
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(Color.calibre.destructive)
                }
                .accessibilityLabel("Remove request")
            }
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(CalibreType.caption).foregroundStyle(Color.calibre.placeholder)
            Text(value).font(CalibreType.label).foregroundStyle(Color.calibre.foreground)
        }
    }
}

private struct NewRequestSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    let onCreate: (WatchRequest) -> Void

    @State private var brand = ""
    @State private var model = ""
    @State private var reference = ""
    @State private var year = ""
    @State private var budget = ""
    @State private var notes = ""
    @State private var saving = false

    var body: some View {
        SheetScaffold(title: "Request a watch", detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Tell us what you're hunting. Sellers see open requests and list against them.")
                        .font(CalibreType.body).foregroundStyle(Color.calibre.mutedForeground)
                    CalibreTextField("Brand (required)", text: $brand)
                    CalibreTextField("Model", text: $model)
                    CalibreTextField("Reference", text: $reference)
                    CalibreTextField(
                        "Year",
                        text: $year,
                        error: yearError
                    )
                    .keyboardType(.numberPad)
                    CalibreTextField(
                        "Max budget (USD)",
                        text: $budget,
                        error: budgetError
                    )
                    .keyboardType(.decimalPad)
                    CalibreTextField("Notes", text: $notes)
                        .onChange(of: notes) { _, value in
                            if value.count > 2_000 { notes = String(value.prefix(2_000)) }
                        }
                    Button(saving ? "Posting…" : "Post request") {
                        Task { await submit() }
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(!canSubmit)
                }
                .padding(Space.margin)
            }
        }
    }

    private var yearError: String? {
        InputValidation.isNonBlank(year) && InputValidation.productionYear(year) == nil
            ? "Enter a 4-digit year, or leave it blank."
            : nil
    }

    private var budgetError: String? {
        InputValidation.isNonBlank(budget) && InputValidation.positiveMoney(budget) == nil
            ? "Enter an amount greater than zero, or leave it blank."
            : nil
    }

    private var canSubmit: Bool {
        InputValidation.isNonBlank(brand)
            && yearError == nil
            && budgetError == nil
            && !saving
    }

    private func submit() async {
        guard canSubmit else { return }
        saving = true
        defer { saving = false }
        do {
            let created = try await services.seller.createWatchRequest(
                brand: InputValidation.trimmed(brand),
                model: InputValidation.isNonBlank(model) ? InputValidation.trimmed(model) : nil,
                reference: InputValidation.isNonBlank(reference) ? InputValidation.trimmed(reference) : nil,
                productionYear: InputValidation.productionYear(year),
                maxBudget: InputValidation.positiveMoney(budget),
                notes: InputValidation.isNonBlank(notes) ? InputValidation.trimmed(notes) : nil
            )
            onCreate(created)
            Haptics.shared.play(.success)
            toasts.show(title: "Request posted", message: "We'll let you know when a match goes live.", tone: .success)
            dismiss()
        } catch {
            toasts.show(title: "Couldn't post request", message: error.orderMessage, tone: .error)
        }
    }
}
