import CalibreDesign
import SwiftUI

/// Placeholder root for the Sell tab — replaced by the listing wizard (P6).
struct SellScreen: View {
    var body: some View {
        VStack {
            EmptyState(
                icon: "camera",
                title: "Selling starts here soon",
                message: "The guided listing wizard — six photos, one calm flow — arrives with the Sell build."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Sell")
        .navigationBarTitleDisplayMode(.inline)
    }
}
