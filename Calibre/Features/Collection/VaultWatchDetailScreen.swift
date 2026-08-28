import CalibreDesign
import CalibreKit
import SwiftUI

/// One watch in the member's vault: what Calibre knows about the reference,
/// what the reference is worth, and what the owner recorded themselves.
///
/// A pushed route rather than a sheet — it is a page about a thing, it can be
/// linked to, and it can push further (the Passport, the marketplace) without
/// stacking modals. It renders inside the Vault tab's gate; see `vaultGate`.
///
/// Three answers are possible, and the screen says which one it is rather
/// than smoothing them together:
///   • the reference is ours and priced — the sheet and the chart;
///   • the reference is ours and unpriced — the sheet and one honest line
///     where the chart would be. Never a substituted figure: the owner's
///     estimate is a differently-derived number, and two prices side by side
///     are worse than one absence;
///   • the reference isn't ours yet — the catalog-gap form.
struct VaultWatchDetailScreen: View {
    let vaultID: String

    @Environment(AppServices.self) private var services

    @State private var detail: VaultWatchDetail?
    @State private var price: MarketReferencePrice?
    @State private var series: MarketSeries?
    /// Set only when the price lookup itself failed — which is a different
    /// sentence from "this reference has no published price".
    @State private var priceUnreachable = false
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showGapSheet = false

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else if loadFailed {
                EmptyState(
                    icon: "wifi.slash",
                    title: "Couldn't load this watch",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    Task { await load() }
                }
            } else if isLoading {
                skeleton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calibrePageBackground()
        .navigationTitle(detail?.watch.displayTitle ?? "Watch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard detail == nil else { return }
            await load()
        }
        .refreshable { await load() }
        .sheet(isPresented: $showGapSheet) {
            if let detail {
                CatalogGapSheet(watch: detail.watch) {
                    Task { await load() }
                }
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        loadFailed = false
        do {
            let payload = try await services.vault.detail(id: vaultID)
            detail = payload
            await loadPrice(for: payload.referenceRow)
        } catch {
            if detail == nil { loadFailed = true }
        }
        isLoading = false
    }

    private func loadPrice(for row: VaultReferenceRow?) async {
        priceUnreachable = false
        guard let row else {
            price = nil
            series = nil
            return
        }
        do {
            let published = try await services.community.referencePrice(slug: row.slug)
            price = published
            series = published.map { MarketSeries(history: $0.history) }
        } catch {
            price = nil
            series = nil
            priceUnreachable = true
        }
    }

    private var skeleton: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color.calibre.card)
                        .frame(height: 140)
                        .shimmer()
                }
            }
            .padding(Space.l)
        }
    }

    // MARK: - Content

    private func content(_ detail: VaultWatchDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header(detail.watch)
                marketSection(detail)
                specSheet(detail)
                catalogGap(detail)
                ownerFacts(detail.watch)
                serviceHistory(detail.serviceRecords)
                sellButton(detail.watch)
            }
            .padding(Space.l)
        }
    }

    private func header(_ watch: VaultWatch) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let brand = watch.brand {
                Text(brand.uppercased())
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            // The owner's own name for it goes in their hand; the catalog's
            // name for it stays in the serif.
            Text(watch.displayTitle)
                .font(
                    watch.isNicknamed
                        ? CalibreType.hand
                        : CalibreType.serif(.semiBold, 26, relativeTo: .title)
                )
                .foregroundStyle(Color.calibre.foreground)
            Text(subtitle(watch))
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
            if watch.authenticated {
                AuthenticatedBadge()
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(_ watch: VaultWatch) -> String {
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
        return parts.isEmpty ? "No reference on file" : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - What the reference is worth

    @ViewBuilder
    private func marketSection(_ detail: VaultWatchDetail) -> some View {
        if let price, let series {
            VStack(alignment: .leading, spacing: Space.l) {
                priceHeader(price, series)
                if series.isDrawable {
                    MarketAreaChart(
                        series: series.values,
                        dates: series.dates,
                        color: MarketTrend.color(for: series.change),
                        formatValue: MarketFormat.usdCompact
                    )
                    performanceRow(series)
                }
                statGrid(price, series)
            }
        } else if detail.referenceRow != nil, priceUnreachable {
            note(
                icon: "wifi.slash",
                title: "Couldn't load the reference price",
                message: "Check your connection and try again."
            ) {
                Button("Try again") {
                    Task { await loadPrice(for: detail.referenceRow) }
                }
                .buttonStyle(.calibre(.secondary))
            }
        } else if detail.referenceRow != nil {
            note(
                icon: "chart.line.uptrend.xyaxis",
                title: "No published price yet",
                message: "Calibre publishes a reference price once there's enough of its own trade behind it. This reference isn't there yet."
            )
        }
    }

    private func priceHeader(_ price: MarketReferencePrice, _ series: MarketSeries) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("CALIBRE REFERENCE PRICE")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.primary)
            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                Text(MarketFormat.usdFull(price.currentValue))
                    .font(CalibreType.serif(.semiBold, 32, relativeTo: .largeTitle))
                    .foregroundStyle(Color.calibre.foreground)
                    .monospacedDigit()
                if series.isDrawable {
                    ChangePillView(change: series.change)
                }
            }
            if let set = MarketFormat.day(iso: price.setAt) {
                Text("Set \(set) \u{00B7} what the reference trades at, not what yours is worth")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func performanceRow(_ series: MarketSeries) -> some View {
        HStack(spacing: 0) {
            ForEach(windows(series), id: \.label) { window in
                VStack(spacing: Space.xs) {
                    Text(window.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.calibre.mutedForeground)
                    ChangePillView(change: window.value)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Space.m)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    /// Only the windows the published history reaches back over.
    private func windows(_ series: MarketSeries) -> [(label: String, value: Double)] {
        var out: [(label: String, value: Double)] = []
        if let month = series.change(overDays: 30) { out.append(("30-day", month)) }
        if let quarter = series.change(overDays: 90) { out.append(("90-day", quarter)) }
        if let year = series.change(overDays: 365) { out.append(("1-year", year)) }
        out.append(("All time", series.change))
        return out
    }

    private func statGrid(_ price: MarketReferencePrice, _ series: MarketSeries) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
            statCell(label: "Current price", value: MarketFormat.usdFull(price.currentValue))
            statCell(label: "Reference", value: price.reference)
            if series.isDrawable {
                statCell(label: "Published high", value: MarketFormat.usdFull(series.high))
                statCell(label: "Published low", value: MarketFormat.usdFull(series.low))
                statCell(
                    label: "Net change",
                    value: "\(series.changeAbs >= 0 ? "+" : "\u{2212}")\(MarketFormat.usdFull(abs(series.changeAbs)))",
                    tone: series.changeAbs >= 0 ? .up : .down
                )
                if let first = series.firstDate {
                    statCell(label: "First published", value: MarketFormat.day(first))
                }
            }
        }
    }

    // MARK: - The watch itself

    @ViewBuilder
    private func specSheet(_ detail: VaultWatchDetail) -> some View {
        let rows = detail.referenceRow?.specs.rows ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                sectionTitle("The watch")
                SpecList(rows)
            }
        }
    }

    @ViewBuilder
    private func catalogGap(_ detail: VaultWatchDetail) -> some View {
        // A row with no spec filled in is a name and nothing else, so it still
        // gets the form — `in_catalog` is the server's word for that, and the
        // client takes it rather than re-deciding.
        if detail.referenceRow?.inCatalog != true {
            if detail.pendingSuggestion {
                note(
                    icon: "clock",
                    title: "Thanks \u{2014} we're on it",
                    message: "You've told us about this watch. Someone on our team is reviewing it, and the spec sheet appears here once it's in the catalog."
                )
            } else {
                note(
                    icon: "questionmark.circle",
                    title: "We don't have this watch yet",
                    message: "Calibre has nothing on file for this reference. Tell us what it is and we'll add it to the catalog \u{2014} it's how the catalog grows."
                ) {
                    Button("Tell us about it") {
                        Haptics.shared.play(.press)
                        showGapSheet = true
                    }
                    .buttonStyle(.calibre(.primary))
                }
            }
        }
    }

    // MARK: - What the owner recorded

    @ViewBuilder
    private func ownerFacts(_ watch: VaultWatch) -> some View {
        let rows = ownerRows(watch)
        if !rows.isEmpty || watch.passportCode != nil || watch.notes != nil {
            VStack(alignment: .leading, spacing: Space.m) {
                sectionTitle("Your record")
                if !rows.isEmpty {
                    SpecList(rows)
                }
                if let notes = watch.notes, !notes.isEmpty {
                    Text(notes)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                if let code = watch.passportCode {
                    NavigationLink(value: Route.passport(code)) {
                        HStack(spacing: Space.s) {
                            Image(systemName: "doc.text")
                            Text("View Passport")
                        }
                    }
                    .buttonStyle(.calibre(.secondary))
                }
            }
        }
    }

    private func ownerRows(_ watch: VaultWatch) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let raw = watch.acquiredPrice, let value = Decimal(string: raw) {
            rows.append(("Acquired for", PriceFormatter.format(value)))
        }
        if let acquired = watch.acquiredDate, let day = MarketSeries.day(from: acquired) {
            rows.append(("Acquired", MarketFormat.day(day)))
        }
        if let added = watch.createdAt, let day = MarketSeries.day(from: added) {
            rows.append(("Added to vault", MarketFormat.day(day)))
        }
        return rows
    }

    @ViewBuilder
    private func serviceHistory(_ records: [VaultServiceRecord]) -> some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                sectionTitle("Service history")
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        if index > 0 {
                            Rectangle().fill(Color.calibre.border).frame(height: 1)
                        }
                        serviceRow(record)
                    }
                }
                .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
            }
        }
    }

    private func serviceRow(_ record: VaultServiceRecord) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.provider ?? "Service")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Spacer(minLength: Space.m)
                if let serviced = record.servicedAt, let day = MarketSeries.day(from: serviced) {
                    Text(MarketFormat.day(day))
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            if let details = record.details, !details.isEmpty {
                Text(details)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            if let raw = record.cost, let value = Decimal(string: raw) {
                Text(PriceFormatter.format(value))
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
    }

    private func sellButton(_ watch: VaultWatch) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button("Sell") {
                Haptics.shared.play(.press)
                services.router.startListing(prefill: ListingPrefill(vaultWatch: watch))
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            Text("Starts a listing with what we already know about this watch. You set the price.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    // MARK: - Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
            .foregroundStyle(Color.calibre.foreground)
    }

    private func note(icon: String, title: String, message: String) -> some View {
        note(icon: icon, title: title, message: message) { EmptyView() }
    }

    @ViewBuilder
    private func note<Action: View>(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.calibre.primary)
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
            }
            Text(message)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            action()
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    private enum Tone { case neutral, up, down }

    private func statCell(label: String, value: String, tone: Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(value)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(tone == .up ? Color.calibre.success : (tone == .down ? Color.calibre.destructive : Color.calibre.foreground))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }
}
