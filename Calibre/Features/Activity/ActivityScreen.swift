import CalibreDesign
import SwiftUI

/// Placeholder root for the Activity tab — replaced by offers, orders, and
/// alerts in the Activity build (P7).
struct ActivityScreen: View {
    var body: some View {
        VStack {
            EmptyState(
                icon: "bell",
                title: "Nothing to report yet",
                message: "Offers, orders, and alerts gather here once the Activity build lands."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}
