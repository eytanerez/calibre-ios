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
            }
        }
    }

    private func jobList(_ jobs: [ListingImportJob]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                CalloutBand(
                    icon: "desktopcomputer",
                    message: "Upload and column-map your CSV on the web — then finish drafts here."
                )
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

                    HStack {
                        if let created = job.createdAt {
                            Text(created.formatted(date: .abbreviated, time: .shortened))
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        Spacer()
                        HStack(spacing: Space.xs) {
                            Text("Finish drafts")
                                .font(CalibreType.label)
                                .foregroundStyle(Color.calibre.primary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.calibre.primary)
                        }
                    }
                }
                .padding(Space.l)
            }
        }
        .buttonStyle(PressableStyle())
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
        return parts.joined(separator: ", ")
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

/// Push value for the draft-finishing queue.
struct ImportJobRef: Hashable {
    let id: String
}
