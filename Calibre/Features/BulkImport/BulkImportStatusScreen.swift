import CalibreDesign
import CalibreKit
import SwiftUI

/// Bulk-import jobs: status, live row progress while processing, results
/// summary, and the draft-finishing queue for imported listings that still
/// need photos or details. Owns its NavigationStack — present it modally.
///
/// Bulk import is one of the three things dealer status brings, so the
/// endpoints answer 403 `dealer_required` to everyone else. That refusal gets
/// the honest explanation and the way to apply rather than a generic error.
struct BulkImportStatusScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var jobs: [ListingImportJob]?
    @State private var loadError: String?
    @State private var dealerRequired = false
    @State private var dealerApplication: DealerApplication?
    @State private var showDealerApplication = false

    var body: some View {
        NavigationStack {
            Group {
                if dealerRequired {
                    dealerRequiredState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let jobs {
                    if jobs.isEmpty {
                        emptyState
                    } else {
                        jobList(jobs)
                    }
                } else if let loadError {
                    EmptyState(
                        icon: "tray.and.arrow.down",
                        title: "Imports didn't load",
                        message: loadError,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    skeleton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.calibre.background.ignoresSafeArea())
            .navigationTitle("Bulk imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: ImportJobRef.self) { ref in
                DraftFinishingQueueScreen(jobID: ref.id)
            }
        }
        // The application is one tap from the refusal rather than a trip back
        // to the dashboard to hunt for it.
        .sheet(isPresented: $showDealerApplication) {
            DealerApplicationScreen(application: dealerApplication) {
                Task { await load() }
            }
        }
        .task {
            await load()
            await pollWhileProcessing()
        }
    }

    private func load() async {
        loadError = nil
        do {
            jobs = try await services.seller.importJobs()
            dealerRequired = false
        } catch {
            if sellErrorCode(error, is: "dealer_required") {
                dealerRequired = true
                jobs = nil
                dealerApplication = try? await services.seller.dealerApplication()
            } else if jobs == nil {
                loadError = sellErrorMessage(error)
            }
        }
    }

    /// The honest explanation, and the way to become one.
    private var dealerRequiredState: some View {
        EmptyState(
            icon: "tray.and.arrow.down",
            title: "Bulk import is for verified dealers",
            message: "A dealer is a verified business. Completing the second verification step with your EIN and business details makes you one automatically — there is no approval queue and no waiting on a person. Dealer status also brings the lower seller rate and a badge buyers can see.",
            actionTitle: "Apply to become a dealer",
            action: { showDealerApplication = true }
        )
    }

    /// "Row X of Y" refresh loop — 1.5s while any job is still processing.
    private func pollWhileProcessing() async {
        while !Task.isCancelled {
            guard let jobs, jobs.contains(where: { $0.status == .processing }) else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    // MARK: - States

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                EmptyState(
                    icon: "tray.and.arrow.down",
                    title: "No imports yet",
                    message: "Bring your whole inventory over in one CSV — dealers list dozens of watches at a time this way."
                )
                CalloutBand(
                    icon: "desktopcomputer",
                    message: "Upload and column-map your CSV on the web — then finish drafts here."
                )
                .padding(.horizontal, Space.margin)
                approvalNote
                    .padding(.horizontal, Space.margin)
            }
        }
    }

    /// Said once, plainly, and left at that.
    private var approvalNote: some View {
        Text("Bulk-imported listings can take a little longer to approve.")
            .font(CalibreType.caption)
            .foregroundStyle(Color.calibre.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func jobList(_ jobs: [ListingImportJob]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                CalloutBand(
                    icon: "desktopcomputer",
                    message: "Upload and column-map your CSV on the web — then finish drafts here."
                )
                approvalNote
                ForEach(jobs) { job in
                    jobCard(job)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .refreshable {
            await load()
        }
    }

    private func jobCard(_ job: ListingImportJob) -> some View {
        NavigationLink(value: ImportJobRef(id: job.id)) {
            SellCard {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(job.originalFilename ?? "Inventory import")
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .lineLimit(1)
                        Spacer()
                        statusBadge(job)
                    }

                    if job.status == .processing {
                        processingProgress(job)
                    } else {
                        Text(resultSummary(job))
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    if let message = job.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.destructive)
                            .lineLimit(3)
                    }

                    if let created = job.createdAt {
                        Text(created.formatted(date: .abbreviated, time: .shortened))
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }

                    handoff(job)
                }
                .padding(Space.l)
            }
        }
        .buttonStyle(PressableStyle())
    }

    /// The way into the finishing queue. When the import left drafts without
    /// photos it says so and promises the shape of the work; otherwise it
    /// stays the quiet link it always was.
    @ViewBuilder
    private func handoff(_ job: ListingImportJob) -> some View {
        // Both figures are the server's, counted across the job's rows.
        // A payload that does not state them gets the plain link rather than
        // a ratio assembled here out of counts that mean something else.
        if let total = job.draftsTotal, let finished = job.draftsFinished, total > 0,
           let remaining = job.draftsRemaining, remaining > 0 {
            HStack(spacing: Space.m) {
                IconTile(systemName: "camera")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue bulk import \u{2014} \(finished) of \(total) finished")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A spreadsheet can't carry pictures. We'll take you through one watch at a time.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.calibre.primary)
            }
            .padding(Space.m)
            .background(
                Color.calibre.accent.opacity(0.6),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .accessibilityElement(children: .combine)
        } else if job.draftsRemaining == 0, (job.draftsTotal ?? 0) > 0 {
            Text("Every draft from this import has been finished.")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
        } else {
            handoffLink("Finish drafts")
        }
    }

    private func handoffLink(_ title: String) -> some View {
        HStack(spacing: Space.xs) {
            Spacer(minLength: 0)
            Text(title)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.primary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.calibre.primary)
        }
    }

    private func statusBadge(_ job: ListingImportJob) -> StatusBadge {
        switch job.status {
        case .mappingPending: StatusBadge("Waiting on mapping", tone: .info)
        case .processing: StatusBadge("Processing", tone: .info)
        case .completed: StatusBadge("Completed", tone: .success)
        case .completedWithErrors: StatusBadge("Needs attention", tone: .warning)
        case .failed: StatusBadge("Failed", tone: .danger)
        case .unknown: StatusBadge("Processing", tone: .neutral)
        }
    }

    private func processingProgress(_ job: ListingImportJob) -> some View {
        let processed = job.processedRows ?? 0
        let total = max(job.totalRows ?? 0, 1)
        return VStack(alignment: .leading, spacing: Space.s) {
            Text("Row \(processed) of \(total)")
                .font(CalibreType.label)
                .monospacedDigit()
                .foregroundStyle(Color.calibre.foreground)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.calibre.border)
                    Capsule()
                        .fill(Color.calibre.primary)
                        .frame(width: proxy.size.width * CGFloat(processed) / CGFloat(total))
                        .animation(Motion.easeMedium, value: processed)
                }
            }
            .frame(height: 4)
        }
    }

    private func resultSummary(_ job: ListingImportJob) -> String {
        var parts: [String] = []
        if let created = job.createdCount, created > 0 {
            parts.append("\(created) listing\(created == 1 ? "" : "s") created")
        }
        if let updated = job.updatedCount, updated > 0 {
            parts.append("\(updated) updated")
        }
        if let errors = job.errorCount, errors > 0 {
            parts.append("\(errors) need\(errors == 1 ? "s" : "") attention")
        }
        if parts.isEmpty {
            return job.status == .mappingPending
                ? "Map your columns on the web to start this import."
                : "Nothing to report yet."
        }
        // Skipped rows have no counter of their own and matched a listing that
        // was already live, so created + updated + errors never has to add up
        // to the row count — and this line never claims it does.
        return parts.joined(separator: ", ") + ". Every one is a draft until you finish it."
    }

    private var skeleton: some View {
        VStack(spacing: Space.l) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().frame(maxWidth: .infinity).frame(height: 110).shimmer()
            }
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.l)
    }
}

/// Push value for the draft-finishing queue — and the identity of the sheet
/// the Sell surface opens it in.
struct ImportJobRef: Hashable, Identifiable {
    let id: String
}

