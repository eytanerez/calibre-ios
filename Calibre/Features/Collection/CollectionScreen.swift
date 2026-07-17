import CalibreDesign
import CalibreKit
import SwiftUI

/// The Vault tab: every watch the member owns. Calibre purchases arrive
/// automatically on delivery — authenticated, with their Passport — and
/// manual adds cover the rest of the drawer.
struct CollectionScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(\.openURL) private var openURL

    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showAddSheet = false

    private var watches: [VaultWatch] { services.vault.watches }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "latch.2.case",
                    title: "Your vault lives here",
                    message: "Sign in and every watch you buy on Calibre arrives in your vault authenticated — plus anything else you own.",
                    actionTitle: "Sign in"
                ) {
                    services.auth.require("Sign in to see your vault") {}
                }
            } else if isLoading, watches.isEmpty {
                skeleton
            } else if watches.isEmpty, loadFailed {
                EmptyState(
                    icon: "wifi.slash",
                    title: "Couldn't load your vault",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    Task { await load() }
                }
            } else if watches.isEmpty {
                EmptyState(
                    icon: "latch.2.case",
                    title: "No watches yet",
                    message: "Buy on Calibre and your watch lands in your vault authenticated — or add what you already own to track its value.",
                    actionTitle: "Add a watch"
                ) {
                    showAddSheet = true
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Color.calibre.primary)
                    .accessibilityLabel("Add a watch")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCollectionWatchSheet()
        }
        .task {
            guard session.isAuthenticated else { return }
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        loadFailed = false
        do {
            _ = try await services.vault.load()
        } catch {
            if watches.isEmpty { loadFailed = true }
        }
        isLoading = false
    }

    private var skeleton: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.calibre.card)
                        .frame(height: 120)
                        .shimmer()
                }
            }
            .padding(Space.l)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header

                ForEach(watches) { watch in
                    CollectionWatchCard(watch: watch) {
                        Task {
                            do {
                                try await services.vault.remove(id: watch.id)
                                Haptics.shared.play(.save)
                            } catch {
                                services.toasts.show(title: "Couldn't remove that watch", message: "Please try again.")
                            }
                        }
                    } onPassport: { code in
                        if let url = URL(string: "https://buycalibre.com/passport/\(code)") {
                            openURL(url)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("ESTIMATED VALUE")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                Text(
                    services.vault.estimatedTotal > 0
                        ? PriceFormatter.format(Decimal(services.vault.estimatedTotal))
                        : "—"
                )
                .font(CalibreType.serif(.semiBold, 30, relativeTo: .largeTitle))
                .foregroundStyle(Color.calibre.foreground)
                .contentTransition(.numericText())
            }
            Spacer()
            Text("\(watches.count) watch\(watches.count == 1 ? "" : "es")")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }
}

private struct CollectionWatchCard: View {
    let watch: VaultWatch
    let onRemove: () -> Void
    let onPassport: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(watch.displayTitle)
                        .font(CalibreType.serif(.semiBold, 18, relativeTo: .headline))
                        .foregroundStyle(Color.calibre.foreground)
                    Text(subtitle)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                Spacer()
                if watch.isAuthenticated {
                    Text("AUTHENTICATED")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs)
                        .background(
                            Color.calibre.primary.opacity(0.1),
                            in: Capsule()
                        )
                }
            }

            HStack(spacing: Space.xl) {
                metric(label: "Est. value", value: money(watch.estimatedValue))
                metric(label: "Acquired for", value: money(watch.acquiredPrice))
            }

            HStack {
                if let code = watch.passportCode {
                    Button {
                        onPassport(code)
                    } label: {
                        Text("View Passport")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Text("Remove")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.calibre.card,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if watch.nickname != nil {
            let joined = [watch.brand, watch.model].compactMap { $0 }.joined(separator: " ")
            if !joined.isEmpty { parts.append(joined) }
        }
        if let reference = watch.reference, !reference.isEmpty {
            parts.append("Ref. \(reference)")
        }
        if let year = watch.productionYear {
            parts.append(String(year))
        }
        return parts.isEmpty ? "No reference on file" : parts.joined(separator: " · ")
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(value)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .monospacedDigit()
        }
    }

    private func money(_ raw: String?) -> String {
        guard let raw, let value = Decimal(string: raw) else { return "—" }
        return PriceFormatter.format(value)
    }
}

/// Manual add: brand is required, everything else optional.
private struct AddCollectionWatchSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var brand = ""
    @State private var model = ""
    @State private var reference = ""
    @State private var yearText = ""
    @State private var priceText = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    CalibreTextField("Brand", text: $brand, placeholder: "Rolex")
                    CalibreTextField("Model", text: $model, placeholder: "Submariner")
                    CalibreTextField("Reference", text: $reference, placeholder: "126610LN")
                    CalibreTextField("Year", text: $yearText, placeholder: "2022")
                        .keyboardType(.numberPad)
                    CalibreTextField("What you paid (USD)", text: $priceText, placeholder: "9,500")
                        .keyboardType(.decimalPad)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.destructive)
                    }

                    Button {
                        save()
                    } label: {
                        Text(saving ? "Adding…" : "Add to vault")
                            .font(CalibreType.bodyMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.m)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.calibre.primary)
                    .disabled(brand.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
                .padding(Space.l)
            }
            .background(Color.calibre.background)
            .navigationTitle("Add a watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.calibre.primary)
                }
            }
        }
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            defer { saving = false }
            do {
                _ = try await services.vault.add(
                    brand: brand.trimmingCharacters(in: .whitespaces),
                    model: model.trimmingCharacters(in: .whitespaces).isEmpty ? nil : model.trimmingCharacters(in: .whitespaces),
                    reference: reference.trimmingCharacters(in: .whitespaces).isEmpty ? nil : reference.trimmingCharacters(in: .whitespaces),
                    productionYear: Int(yearText.trimmingCharacters(in: .whitespaces)),
                    acquiredPrice: priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil
                        : priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                )
                Haptics.shared.play(.success)
                dismiss()
            } catch {
                errorMessage = "Couldn't add the watch. Check the details and try again."
            }
        }
    }
}
