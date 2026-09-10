import CalibreDesign
import CalibreKit
import SwiftUI

/// "This one sold." — the notice a member gets when a watch they had saved or
/// in their cart is bought by somebody else.
///
/// Three rules from the contract are load-bearing here and none of them is
/// cosmetic:
///
/// 1. It is said **once**, per person, per listing. The server holds a row per
///    pair to make that provable; this view's job is to not spend it wrongly.
/// 2. So the acknowledgement goes out **after the banner has rendered**, from
///    `onAppear`, and never from the fetch that served it. Saved and Cart both
///    refetch when their tab appears, so acknowledging on load would burn the
///    notice while the phone was face-down in a pocket.
/// 3. One watch names itself; three or more roll up into a single line that
///    expands to name them. Two still name themselves — a two-line list is
///    shorter than the sentence that would summarise it, and the roll-up
///    exists to stop a long list, not to hide a short one.
struct ListingGoneNoticeBanner: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    /// Where this banner is drawn, which is all that changes in the wording.
    let surface: Surface

    /// Whether the card supplies its own page margins. The bag sheet already
    /// insets everything it holds, and a second margin there would step this
    /// card in from every other row on the screen.
    var insetsFromPage = true

    enum Surface {
        case saved
        case cart
    }

    /// The notices this banner has taken responsibility for showing. Held here
    /// rather than read live off the store, because acknowledging empties the
    /// store's list and the person is still reading.
    @State private var showing: [ListingGoneNotice] = []
    @State private var expanded = false

    /// Three or more roll up. Below that they name themselves.
    private static let rollUpFrom = 3

    private var rollsUp: Bool { showing.count >= Self.rollUpFrom }

    var body: some View {
        Group {
            if !showing.isEmpty {
                card
            }
        }
        .onAppear { adopt() }
        .onChange(of: services.commerce.listingNotices) { _, _ in adopt() }
        // `adopt()` refuses to spend a notice while the scene is not active,
        // and the two triggers above will not come round again on their own:
        // `onAppear` fires once per view identity, and a refetch that returns
        // the same pending rows is `Equatable`-equal, so it publishes no
        // change. Without this, notices that land while the app is backgrounded
        // — the ordinary case, the Saved/Cart fetch still in flight when the
        // phone goes in a pocket — are never shown at all.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { adopt() }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subline)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    Haptics.shared.play(.press)
                    // Closing answers the notices on screen and only those.
                    // Recorded on the store so it outlives this view, which a
                    // tab switch destroys.
                    services.commerce.dismissListingNotices(ids: showing.map(\.id))
                    withAnimation(Motion.easeFast) { showing = [] }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .frame(width: Space.touchTarget, height: Space.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Dismiss")
            }

            if rollsUp {
                Button {
                    withAnimation(Motion.easeFast) { expanded.toggle() }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(expanded ? "Hide them" : "Show them")
                            .font(CalibreType.label)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.calibre.primary)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(expanded ? "Hide the watches that sold" : "Show the watches that sold")
            }

            if !rollsUp || expanded {
                VStack(spacing: Space.s) {
                    ForEach(showing) { notice in
                        row(notice)
                    }
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        // The margin belongs to the card and not to the caller: this view
        // draws nothing at all when there is nothing pending, and padding
        // applied outside it would leave a band of empty page behind on every
        // ordinary visit.
        .padding(.horizontal, insetsFromPage ? Space.margin : 0)
        .padding(.vertical, Space.m)
    }

    /// The watch itself, still openable: a sold listing is readable by nobody
    /// but its seller, so this is a name and a price rather than a link.
    private func row(_ notice: ListingGoneNotice) -> some View {
        HStack(spacing: Space.m) {
            ListingImageWell(url: notice.image?.url, targetWidth: 120)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title ?? "A watch you were following")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let value = notice.priceValue {
                    Text(PriceFormatter.format(value, currency: notice.currency))
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if let only = showing.first, showing.count == 1 {
            return "\(only.title ?? "A watch you were following") sold"
        }
        return "\(showing.count) watches you were following sold"
    }

    private var subline: String {
        let place: String
        switch surface {
        case .saved: place = "your saved list"
        case .cart: place = "your cart"
        }
        return showing.count == 1
            ? "It has been taken out of \(place)."
            : "They have been taken out of \(place)."
    }

    /// Takes the pending notices on, then tells the server they were shown.
    ///
    /// The acknowledgement is deliberately the *second* thing that happens
    /// here and not part of the read that produced these rows. `onAppear` is
    /// the first moment this view is genuinely on screen, and the scene phase
    /// check keeps a background refresh from counting as having been read.
    ///
    /// Refusing on an inactive scene defers the adoption rather than
    /// cancelling it, which is why the scene becoming active is a trigger of
    /// its own above.
    private func adopt() {
        guard scenePhase == .active else { return }
        let pending = services.commerce.showableListingNotices
        guard !pending.isEmpty else { return }
        let known = Set(showing.map(\.id))
        let fresh = pending.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        showing.append(contentsOf: fresh)
        let ids = fresh.map(\.id)
        Task { try? await services.commerce.acknowledgeListingNotices(ids: ids) }
    }
}
