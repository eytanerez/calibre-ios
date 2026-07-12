import CalibreDesign
import CalibreKit
import SwiftUI

/// The full-screen success moment — the watch breathes in over 420ms, a
/// serif "It's yours.", the order number, one strong action. No confetti;
/// restraint is the celebration.
struct CheckoutSuccessMoment: View {
    let order: Order
    let listing: Listing?
    let onViewOrder: () -> Void
    let onKeepBrowsing: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            SquareThumb(url: imageURL, side: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
                .calibreShadow(.lifted)
                .scaleEffect(arrived || reduceMotion ? 1 : 0.85)
                .opacity(arrived ? 1 : 0)

            Text("It's yours.")
                .font(CalibreType.display)
                .foregroundStyle(Color.calibre.foreground)
                .padding(.top, Space.xxl)
                .opacity(arrived ? 1 : 0)

            if let title = listing?.title ?? order.listing?.title {
                Text(title)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.s)
                    .padding(.horizontal, Space.xxl)
                    .opacity(arrived ? 1 : 0)
            }

            Eyebrow("Order \(shortOrderNumber)")
                .padding(.top, Space.m)
                .opacity(arrived ? 1 : 0)

            Spacer()

            VStack(spacing: Space.m) {
                Button {
                    Haptics.shared.play(.press)
                    onViewOrder()
                } label: {
                    Text("View your order")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))

                Button("Keep browsing") {
                    onKeepBrowsing()
                }
                .buttonStyle(.calibreGhost)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.l)
            .opacity(arrived ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background.ignoresSafeArea())
        .onAppear {
            Haptics.shared.play(.paymentSuccess)
            withAnimation(reduceMotion ? Motion.easeMedium : Motion.easeSlow) {
                arrived = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var imageURL: URL? {
        listing?.images.first?.url ?? order.listing?.image?.url
    }

    private var shortOrderNumber: String {
        String(order.id.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }
}
