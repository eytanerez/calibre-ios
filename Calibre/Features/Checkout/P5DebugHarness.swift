#if DEBUG
import CalibreDesign
import CalibreKit
import SwiftUI

/// P5 verification harness — DEBUG only, reached via a temporary route wire.
/// Lets the money-track flows be driven end-to-end in the simulator before
/// the orchestrator wires the real entry points (PDP Buy Now / Make Offer).
struct P5DebugHarness: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    @State private var listings: [Listing] = []
    @State private var status = "Idle"
    @State private var checkoutTarget: CheckoutTarget?
    @State private var offerTarget: OfferTarget?
    @State private var offerID = ""

    struct CheckoutTarget: Identifiable {
        let listingID: String
        let offerID: String?
        var id: String { listingID + (offerID ?? "") }
    }

    struct OfferTarget: Identifiable {
        let listingID: String
        var id: String { listingID }
    }

    var body: some View {
        List {
            Section("Session") {
                Text(session.user.map { "\($0.username) <\($0.email)>" } ?? "guest")
                    .font(.footnote)
                if !session.isAuthenticated {
                    Button("Sign in as iosbuyer") {
                        Task {
                            do {
                                try await session.login(
                                    identifier: "iosbuyer.calibre@gmail.com",
                                    password: "CalibreiOS123!"
                                )
                                status = "signed in"
                            } catch {
                                status = "login failed: \(error.localizedDescription)"
                            }
                        }
                    }
                }
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }

            Section("Screens") {
                NavigationLink("Offers list") { OffersListScreen() }
                HStack {
                    TextField("offer id", text: $offerID)
                        .font(.caption.monospaced())
                    NavigationLink("Open") {
                        OfferDetailScreen(offerID: offerID.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(offerID.isEmpty)
                }
            }

            Section("Listings") {
                Button("Load listings") { Task { await load() } }
                ForEach(listings) { listing in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listing.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(PriceFormatter.format(listing.price.value)) · \(listing.id.prefix(8))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Buy") {
                                checkoutTarget = CheckoutTarget(listingID: listing.id, offerID: nil)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Offer") {
                                offerTarget = OfferTarget(listingID: listing.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("P5 Harness")
        .fullScreenCover(item: $checkoutTarget) { target in
            CheckoutFlow(listingID: target.listingID, offerID: target.offerID)
        }
        .sheet(item: $offerTarget) { target in
            MakeOfferSheet(listingID: target.listingID)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let page = try await services.catalog.browse(ListingQuery(page: 1, pageSize: 8))
            listings = page.results
            status = "loaded \(page.results.count) listings"
        } catch {
            status = "load failed: \(error.localizedDescription)"
        }
    }
}
#endif
