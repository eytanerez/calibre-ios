import CalibreDesign
import CalibreKit
import SwiftUI

/// The full-screen success moment — the watch breathes in over 420ms, a
/// serif "It's yours.", the order number, one strong action. No confetti;
/// restraint is the celebration.
///
/// A purchase of several watches shows them all, fanned, and counts them —
/// "All three are yours." One payment, one moment, one order per watch.
struct CheckoutSuccessMoment: View {
    let orders: [Order]
    /// The full listings, in the same order as `orders`, for the images the
    /// order payload's summary may not carry. A missing one is simply nil.
    let listings: [Listing?]
    let onViewOrder: () -> Void
    let onKeepBrowsing: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    private var count: Int { orders.count }
    private var isMultiItem: Bool { count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            artwork
                .scaleEffect(arrived || reduceMotion ? 1 : 0.85)
                .opacity(arrived ? 1 : 0)

            Text(headline)
                .font(CalibreType.display)
                .foregroundStyle(Color.calibre.foreground)
                .multilineTextAlignment(.center)
                .padding(.top, Space.xxl)
                .padding(.horizontal, Space.xl)
                .opacity(arrived ? 1 : 0)

            if let subtitle {
                Text(subtitle)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.s)
                    .padding(.horizontal, Space.xxl)
                    .opacity(arrived ? 1 : 0)
            }

            Eyebrow(orderLine)
                .padding(.top, Space.m)
                .opacity(arrived ? 1 : 0)

            Spacer()

            VStack(spacing: Space.m) {
                Button {
                    Haptics.shared.play(.press)
                    onViewOrder()
                } label: {
                    Text(isMultiItem ? "View your orders" : "View your order")
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

    // MARK: - Pieces

    /// One watch fills the frame. Several are fanned behind it, at most three
    /// deep — past that the count carries the story better than the pile does.
    @ViewBuilder private var artwork: some View {
        if isMultiItem {
            ZStack {
                ForEach(Array(imageURLs.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                    SquareThumb(url: url, side: index == 0 ? 180 : 156)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
                        .calibreShadow(.lifted)
                        .rotationEffect(.degrees(fanAngle(index)))
                        .offset(x: fanOffset(index))
                        .zIndex(Double(3 - index))
                }
            }
            .frame(height: 200)
        } else {
            SquareThumb(url: imageURLs.first ?? nil, side: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
                .calibreShadow(.lifted)
        }
    }

    private func fanAngle(_ index: Int) -> Double {
        switch index {
        case 0: 0
        case 1: 7
        default: -7
        }
    }

    private func fanOffset(_ index: Int) -> CGFloat {
        switch index {
        case 0: 0
        case 1: 46
        default: -46
        }
    }

    private var headline: String {
        guard isMultiItem else { return "It's yours." }
        return count == 2 ? "Both are yours." : "All \(count) are yours."
    }

    /// The watch's name when there is one, the list when there are a few.
    private var subtitle: String? {
        let titles = zip(orders, paddedListings).compactMap { order, listing in
            listing?.title ?? order.listing?.title
        }
        guard !titles.isEmpty else { return nil }
        if titles.count == 1 { return titles[0] }
        if titles.count == 2 { return titles.joined(separator: " and ") }
        return titles.dropLast().joined(separator: ", ") + " and " + (titles.last ?? "")
    }

    private var orderLine: String {
        guard let first = orders.first else { return "Your order" }
        if isMultiItem {
            return "\(count) orders · one payment"
        }
        return "Order \(shortNumber(first.id))"
    }

    private var imageURLs: [URL?] {
        zip(orders, paddedListings).map { order, listing in
            listing?.images.first?.url ?? order.listing?.image?.url
        }
    }

    /// `listings` is expected to line up with `orders`, but a caller that
    /// hands over fewer must not crash the celebration.
    private var paddedListings: [Listing?] {
        guard listings.count < orders.count else { return listings }
        return listings + Array(repeating: nil, count: orders.count - listings.count)
    }

    private func shortNumber(_ id: String) -> String {
        String(id.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }
}
