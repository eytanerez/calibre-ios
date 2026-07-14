import CalibreDesign
import CalibreKit
import SwiftUI

/// The full list of open buyer sourcing requests — reached from the
/// dashboard's "Buyers are looking for" button rather than rendered inline,
/// so the shop's front page stays a summary, not a second inventory list.
struct OpenBuyerRequestsScreen: View {
    let requests: [WatchRequest]
    let onListWatch: (WatchRequest) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if requests.isEmpty {
                    EmptyState(
                        icon: "sparkle.magnifyingglass",
                        title: "No open requests",
                        message: "When a buyer asks Calibre to source a watch, it shows up here for you to list against."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Space.m) {
                            ForEach(requests) { request in
                                requestRow(request)
                            }
                        }
                        .padding(Space.margin)
                    }
                }
            }
            .background(Color.calibre.background)
            .navigationTitle("Buyers are looking for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(CalibreType.bodyMedium)
                }
            }
        }
    }

    private func requestRow(_ request: WatchRequest) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(request.brand)
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
            Button("List this watch") {
                dismiss()
                onListWatch(request)
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
            .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}
