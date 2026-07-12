import CalibreDesign
import CalibreKit
import SwiftUI

/// The Activity tab — offers, orders, and the alerts inbox behind one
/// segmented control.
struct ActivityScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    enum Segment: Hashable {
        case offers, orders, alerts
    }

    @State private var segment: Segment = .offers

    var body: some View {
        VStack(spacing: 0) {
            SegmentedTabs(
                selection: $segment,
                items: [(.offers, "Offers"), (.orders, "Orders"), (.alerts, "Alerts")]
            )
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s)

            Group {
                switch segment {
                case .offers:
                    OffersListScreen()
                case .orders:
                    OrdersListScreen()
                case .alerts:
                    AlertsInboxScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.calibre.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}
