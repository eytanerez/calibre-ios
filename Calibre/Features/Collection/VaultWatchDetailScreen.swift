import CalibreDesign
import CalibreKit
import SwiftUI

/// One watch in the member's vault: their photograph of it, the records that
/// belong to it, what Calibre knows about the reference, and what the owner
/// recorded themselves.
///
/// A pushed route rather than a sheet — it is a page about a thing, it can be
/// linked to, and it can push further (the Passport, the marketplace) without
/// stacking modals. It renders inside the Vault tab's gate; see `vaultGate`.
///
/// Three answers are possible about the reference, and the screen says which
/// one it is rather than smoothing them together:
///   • the reference is ours and priced — the sheet and the chart;
///   • the reference is ours and unpriced — the sheet and one honest line
///     where the chart would be. Never a substituted figure: the owner's
///     estimate is a differently-derived number, and two prices side by side
///     are worse than one absence;
///   • the reference isn't ours yet — the catalog-gap form.
///
/// What Calibre thinks this particular watch is worth is not printed here in
/// any state. `VaultEstimate.note` explains the two absences that have an
/// explanation and stays quiet for the rest.
struct VaultWatchDetailScreen: View {
    let vaultID: String

    @Environment(AppServices.self) private var services

    @State private var detail: VaultWatchDetail?
    /// The owner's own row, which this screen can change — a photograph, a
    /// note. Held apart from `detail` so a save redraws the screen without a
    /// second round trip for the catalog half, which did not move.
    @State private var watch: VaultWatch?
    @State private var price: MarketReferencePrice?
    @State private var series: MarketSeries?
    /// Set only when the price lookup itself failed — which is a different
    /// sentence from "this reference has no published price".
    @State private var priceUnreachable = false
    /// The price lookup has finished, whatever it found. The screen draws as
    /// soon as the watch arrives and the price follows a moment later, so
    /// without this the estimate's sentence flashes up under every watch and
    /// then withdraws itself the instant a published price lands beside it.
    @State private var priceResolved = false
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showGapSheet = false
    @State private var showPhotoSheet = false

    /// The uppercase micro labels over the performance windows and the stat
    /// cells sit below caption2 on purpose, but the literal froze them at 10pt
    /// for everyone — they stayed 10pt at the largest setting in the OS.
    /// Identical at the default size, scaled above it.
    @ScaledMetric(relativeTo: .caption2) private var microSize: CGFloat = 10

    var body: some View {
        Group {
            if let detail, let watch {
                content(detail, watch)
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
        .navigationTitle(watch?.displayTitle ?? "Watch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard detail == nil else { return }
            await load()
        }
        .refreshable { await load() }
        .sheet(isPresented: $showGapSheet) {
            if let watch {
                CatalogGapSheet(watch: watch) {
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $showPhotoSheet) {
            if let watch {
                VaultPhotoLinkSheet(watch: watch) { saved in
                    self.watch = saved
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
            watch = payload.watch
            await loadPrice(for: payload.referenceRow)
        } catch {
            if detail == nil { loadFailed = true }
        }
        isLoading = false
    }

    private func loadPrice(for row: VaultReferenceRow?) async {
        priceUnreachable = false
        priceResolved = false
        defer { priceResolved = true }
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
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.calibre.card)
                    .aspectRatio(1, contentMode: .fit)
                    .shimmer()
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        .fill(Color.calibre.card)
                        .frame(height: 140)
                        .shimmer()
                }
            }
            .padding(Space.l)
        }
    }

    // MARK: - Content

    private func content(_ detail: VaultWatchDetail, _ watch: VaultWatch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                hero(watch)
                records(watch)
                VaultOwnerNote(watch: watch) { saved in self.watch = saved }
                marketSection(detail)
                specSheet(detail)
                catalogGap(detail, watch)
                ownerFacts(watch)
                serviceHistory(detail.serviceRecords)
                sellButton(watch)
            }
            .padding(Space.l)
        }
    }

    // MARK: - The photograph and what it is

    private func hero(_ watch: VaultWatch) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            GeometryReader { proxy in
                VaultPhotoFrame(watch: watch, variant: .hero, side: proxy.size.width)
            }
            .aspectRatio(1, contentMode: .fit)

            Button(watch.photoUrl == nil ? "Add a photo" : "Change the photo") {
                showPhotoSheet = true
            }
            .buttonStyle(.calibre(.ghost))

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
                HStack(spacing: Space.m) {
                    AuthenticatedBadge()
                    // Calibre's bench passed this watch. Said once, then simply
                    // standing — `markAnnounces` presses it the first time this
                    // session shows the fact and holds it stamped every time
                    // after, and holds it stamped from the first frame under
                    // Reduce Motion.
                    //
                    // No label: the badge beside it carries the words, and a
                    // mark that repeats them reads the fact out twice to a
                    // screen reader. `CalibreMark` hides every drawing.
                    //
                    // The one illustrated moment on this screen. The
                    // authentication report opens in a sheet, which is its own
                    // surface with this one behind it, so the loupe there can
                    // never be this screen's second mark — the same reason
                    // `OrderMarks` gives for leaving it out of the order
                    // screen's precedence.
                    //
                    // Off-square because it was pressed by hand. The angle is
                    // the Passport cover's.
                    if let key = watch.authenticationMarkKey {
                        CalibreMark.stamp(size: 44, trigger: key)
                            .rotationEffect(.degrees(-11))
                            .markAnnounces(key)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, Space.xs)
            } else {
                // A watch somebody typed in is a watch nobody at Calibre has
                // held, however handsome its card. The flag is the server's,
                // not this screen's reading of `source`.
                VStack(alignment: .leading, spacing: Space.xs) {
                    StatusBadge("Unverified", tone: .neutral)
                    Text("Calibre hasn't inspected this watch. It's here because you said you own it.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.xs)
            }

            // What the market lookup came back with, in words, for the two
            // states that explain an absence the owner can see. No figure in
            // any state.
            //
            // Withheld where the reference has a published price below, which
            // is the one case with no absence to explain: "we cannot put a
            // figure on it" above a chart of figures is a contradiction to
            // read, however carefully the two are distinguished further down.
            if priceResolved, price == nil, let note = watch.estimate?.note {
                Text(note)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - The records that belong to this watch

    /// Above the market and the specifications on purpose: the price is about
    /// the reference, and these are about THIS watch.
    @ViewBuilder
    private func records(_ watch: VaultWatch) -> some View {
        if watch.passportCode != nil || watch.authenticated {
            VStack(alignment: .leading, spacing: Space.m) {
                sectionTitle("Records")

                if let code = watch.passportCode {
                    NavigationLink(value: Route.passport(code)) {
                        HStack(spacing: Space.s) {
                            Image(systemName: "doc.text")
                            Text("View Passport")
                        }
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))
                }

                // Offered wherever Calibre stands behind the watch. The vault
                // payload carries nothing about the document, so nothing here
                // claims one exists — the route answers for itself, and its
                // not-found branch offers the way on rather than a dead end.
                if watch.authenticated {
                    AuthenticationReportRow(
                        source: .vault(watch.id),
                        passportCode: watch.passportCode
                    )
                }
            }
        }
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
                        .font(.system(size: microSize, weight: .semibold))
                        .foregroundStyle(Color.calibre.mutedForeground)
                    ChangePillView(change: window.value)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Space.m)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
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
    private func catalogGap(_ detail: VaultWatchDetail, _ watch: VaultWatch) -> some View {
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
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                sectionTitle("Your record")
                SpecList(rows)
                if watch.acquiredPrice != nil {
                    Text("Only you see what you paid.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
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
                .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
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

    /// Available, and quiet. A collection is not a shopfront, so this is the
    /// secondary button at the foot of the screen rather than the one strong
    /// action on a page about a watch somebody is keeping.
    private func sellButton(_ watch: VaultWatch) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button("Sell") {
                Haptics.shared.play(.press)
                services.router.startListing(prefill: ListingPrefill(vaultWatch: watch))
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
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
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    private enum Tone { case neutral, up, down }

    private func statCell(label: String, value: String, tone: Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: microSize, weight: .semibold))
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
