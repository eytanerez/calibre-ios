import CalibreDesign
import CalibreKit
import Foundation
import Nuke
import NukeUI
import SwiftUI

// MARK: - Sell session (per-tab services)

/// Everything the Sell suite shares beneath `SellScreen`: the photo upload
/// pipeline, the seller-ops store and the cached Stripe publishable key.
/// Created once when the Sell tab first renders, injected via environment.
@MainActor
@Observable
final class SellSession {
    let ops: SellerOpsStore
    let board: UploadProgressBoard
    @ObservationIgnored let uploads: UploadQueue

    /// Cached after the first fetch — the key is static per environment.
    private var publishableKey: String?

    init(services: AppServices) {
        let board = UploadProgressBoard()
        self.board = board
        self.ops = SellerOpsStore(client: services.client)
        self.uploads = UploadQueue(client: services.client, auth: services.auth, board: board)
        Task { [uploads] in
            await uploads.resumePersisted()
        }
    }

    func stripeKey() async throws -> String {
        if let publishableKey {
            return publishableKey
        }
        let key = try await ops.stripePublishableKey()
        publishableKey = key
        return key
    }
}

// MARK: - Seller status display

/// Human words + tone for the backend's derived `seller_status`.
enum SellerStatusDisplay {
    static func badge(for listing: Listing) -> (text: String, tone: StatusBadge.Tone) {
        switch listing.sellerStatus ?? listing.status.rawValue {
        case "draft": ("Draft", .neutral)
        case "awaiting_approval", "pending_review": ("In review", .info)
        case "live", "active": ("Live", .success)
        case "reserved": ("Reserved", .info)
        case "awaiting_wire_transfer": ("Awaiting wire", .warning)
        case "sold_awaiting_label_creation": ("Sold \u{2014} shipping details needed", .warning)
        case "in_transit": ("In transit", .info)
        case "delivered": ("Delivered", .success)
        case "refunded": ("Refunded", .danger)
        case "cancelled": ("Cancelled", .neutral)
        case "disputed": ("Disputed", .danger)
        case "rejected": ("Needs changes", .danger)
        // Calibre took this one down, not the seller. Never folded into
        // "archived": archiving is a deliberate seller action, and this one
        // returns to the market by itself once a valid credit card is on file.
        case "paused_card": ("Paused \u{2014} card lapsed", .warning)
        case "archived": ("Archived", .neutral)
        case "sold": ("Sold", .success)
        default: (listing.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, .neutral)
        }
    }

    /// Rows the "Needs action" inventory filter keeps.
    static func needsAction(_ listing: Listing) -> Bool {
        switch listing.sellerStatus ?? listing.status.rawValue {
        case "draft", "rejected", "paused_card", "sold_awaiting_label_creation", "awaiting_wire_transfer": true
        default: false
        }
    }

    static func badge(forOrder status: OrderStatus) -> (text: String, tone: StatusBadge.Tone) {
        switch status {
        case .awaitingWire: ("Awaiting wire", .warning)
        case .purchased: ("Awaiting shipment", .warning)
        case .toAuth: ("At authentication", .info)
        case .authPass: ("Authenticated", .success)
        case .authFail: ("Authentication issue", .danger)
        case .toBuyer: ("On its way to the buyer", .info)
        case .delivered: ("Delivered", .success)
        case .cancelled: ("Cancelled", .neutral)
        case .refunded: ("Refunded", .danger)
        case .unknown: ("Processing", .neutral)
        }
    }
}

// MARK: - Small shared views

/// Square image well used across dashboard rows — LazyImage on the quiet
/// secondary fill, downsampled to the container.
struct SellThumb: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Color.calibre.secondary.opacity(0.5)
            if let request {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else if state.error != nil {
                        fallbackGlyph
                    } else {
                        Rectangle().shimmer()
                    }
                }
            } else {
                fallbackGlyph
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var request: ImageRequest? {
        guard let url else { return nil }
        return ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: CGSize(width: size, height: size), crop: true)]
        )
    }

    private var fallbackGlyph: some View {
        Image(systemName: "clock")
            .font(.system(size: size * 0.32, weight: .light))
            .foregroundStyle(Color.calibre.placeholder)
            .accessibilityHidden(true)
    }
}

/// Section header used by every dashboard section — serif title, optional
/// trailing action.
struct SellSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            Spacer()
            trailing
        }
    }
}

/// Bordered card container matching the SpecList chrome.
struct SellCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
    }
}

/// A shimmering placeholder row while a section loads.
struct SellRowSkeleton: View {
    var body: some View {
        HStack(spacing: Space.m) {
            Rectangle().frame(width: 56, height: 56).shimmer()
            VStack(alignment: .leading, spacing: Space.s) {
                Rectangle().frame(width: 150, height: 13).shimmer()
                Rectangle().frame(width: 90, height: 11).shimmer()
            }
            Spacer()
        }
        .padding(Space.l)
    }
}

// MARK: - The payout ledger

/// The four lines a payout is made of, exactly as the server states them:
/// sale price, commission (with its rate, and a plain note when the
/// marketplace minimum applied instead), the label Calibre bought, and what
/// is left. Nothing here is arithmetic — a figure the payload omits is simply
/// not a row, because a payout figure we can't stand behind is worse than
/// none at all.
///
/// Money is never truncated or abbreviated: every figure is written out in
/// full and wraps rather than shrinking.
struct PayoutLedger: View {
    let breakdown: PayoutBreakdown
    var currency: String = "USD"
    /// The heading, when the caller wants one.
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let title {
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    ledgerRow(row.label, row.value, emphasized: row.emphasized)
                    if index < rows.count - 1 {
                        Rectangle().fill(Color.calibre.border).frame(height: 1)
                    }
                }
            }
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )

            if breakdown.commission?.minimumApplied == true {
                Text("Minimum applied \u{2014} the marketplace minimum commission was charged on this sale rather than the percentage.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct Row {
        let label: String
        let value: String
        let emphasized: Bool
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let sale = breakdown.salePrice?.value {
            rows.append(Row(label: "Sale price", value: money(sale), emphasized: false))
        }
        if let commission = breakdown.commission, let amount = commission.amount?.value {
            let label = commission.percent.map { "Calibre\u{2019}s commission (\(feePercentText($0.value))%)" }
                ?? "Calibre\u{2019}s commission"
            rows.append(Row(label: label, value: "\u{2212} " + money(amount), emphasized: false))
        }
        if let label = breakdown.shippingLabel?.value {
            rows.append(
                Row(
                    label: "Shipping label to authentication",
                    value: "\u{2212} " + money(label),
                    emphasized: false
                )
            )
        }
        if let payout = breakdown.amount?.value {
            rows.append(Row(label: "Your payout", value: money(payout), emphasized: true))
        }
        return rows
    }

    private func money(_ value: Decimal) -> String {
        PriceFormatter.format(value, currency: currency)
    }

    /// A money figure is never shortened to fit. When the two halves cannot
    /// share a line they stack, and the number stays whole.
    private func ledgerRow(_ label: String, _ value: String, emphasized: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Text(label)
                    .font(emphasized ? CalibreType.bodyMedium : CalibreType.body)
                    .foregroundStyle(emphasized ? Color.calibre.foreground : Color.calibre.mutedForeground)
                Spacer(minLength: Space.m)
                Text(value)
                    .font(emphasized ? CalibreType.price : CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(1)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(label)
                    .font(emphasized ? CalibreType.bodyMedium : CalibreType.body)
                    .foregroundStyle(emphasized ? Color.calibre.foreground : Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(emphasized ? CalibreType.price : CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Money helpers

extension Decimal {
    /// Parses user-typed money text ("12,400" / "12400.50"). Nil when empty
    /// or unparseable.
    static func fromMoneyText(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension APIError {
    /// The message to surface for a Sell-suite failure — the backend's words
    /// when it spoke, gentle fallbacks otherwise.
    var sellMessage: String {
        errorDescription ?? "Something went wrong. Please try again."
    }
}

func sellErrorMessage(_ error: Error) -> String {
    (error as? APIError)?.sellMessage ?? error.localizedDescription
}

/// True when the backend refused with this exact machine-readable code.
func sellErrorCode(_ error: Error, is code: String) -> Bool {
    (error as? APIError)?.serverCode == code
}

// MARK: - Percentages

/// Renders a rate the server sent. "6.00" reads as "6"; a genuinely
/// fractional rate keeps its digits. Never rounds to a different number, and
/// never invents one — the caller passes a payload figure or nothing at all.
func feePercentText(_ value: Decimal) -> String {
    var raw = value
    var whole = Decimal()
    NSDecimalRound(&whole, &raw, 0, .plain)
    if whole == value {
        return "\(whole)"
    }
    var text = "\(value)"
    guard text.contains(".") else { return text }
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
}

/// The share of the sale a seller keeps at a server-stated rate. Returns nil
/// when the rate hasn't arrived, so the sentence can be written without a
/// number rather than with a guessed one.
func sellerKeepPercentText(feePercent: Decimal?) -> String? {
    guard let feePercent else { return nil }
    return feePercentText(100 - feePercent)
}
