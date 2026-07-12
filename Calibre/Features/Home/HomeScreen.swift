import CalibreDesign
import SwiftUI

/// Placeholder root for the Home tab — replaced by the Browse build (P3).
struct HomeScreen: View {
    var body: some View {
        VStack {
            EmptyState(
                icon: "house",
                title: "The home feed is on its way",
                message: "Curated listings and the market at a glance arrive with the Browse build."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Calibre")
        .navigationBarTitleDisplayMode(.inline)
    }
}
