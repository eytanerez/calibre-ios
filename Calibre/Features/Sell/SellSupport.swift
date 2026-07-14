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
        case "sold_awaiting_label_creation": ("Sold — label needed", .warning)
        case "in_transit": ("In transit", .info)
        case "delivered": ("Delivered", .success)
        case "refunded": ("Refunded", .danger)
        case "cancelled": ("Cancelled", .neutral)
        case "disputed": ("Disputed", .danger)
        case "rejected": ("Needs changes", .danger)
        case "archived": ("Archived", .neutral)
        case "sold": ("Sold", .success)
        default: (listing.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, .neutral)
        }
    }

    /// Rows the "Needs action" inventory filter keeps.
    static func needsAction(_ listing: Listing) -> Bool {
        switch listing.sellerStatus ?? listing.status.rawValue {
        case "draft", "rejected", "sold_awaiting_label_creation", "awaiting_wire_transfer": true
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
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
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
