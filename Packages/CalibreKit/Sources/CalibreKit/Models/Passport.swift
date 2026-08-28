import Foundation

/// `GET /passports/{public_code}` — the permanent, public record of one
/// specific watch: every authentication, sale and owner-added service entry,
/// carried with the watch for life.
///
/// Anonymized on the server. Ownership and sale prices never reach this
/// payload, so nothing here needs a session to read — it is the page an owner
/// sends to a buyer.
public struct WatchPassport: Decodable, Sendable {
    public let publicCode: String
    public let brand: String?
    public let model: String?
    public let reference: String?
    public let productionYear: Int?
    public let createdAt: Date?
    /// Oldest first, the order a booklet is filled in.
    public let events: [PassportEvent]
    /// Present only when this watch resolves to a listing; `status` says
    /// whether that listing is one a reader can still buy.
    public let listing: PassportListingState?

    public var title: String {
        let joined = [brand, model].compactMap { $0 }.joined(separator: " ")
        return joined.isEmpty ? "Watch" : joined
    }

    /// The line under the title: reference and year, whichever the record has.
    public var subtitle: String? {
        var parts: [String] = []
        if let reference, !reference.isEmpty { parts.append("Ref. \(reference)") }
        if let productionYear { parts.append(String(productionYear)) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}

public struct PassportListingState: Decodable, Sendable {
    public let listingId: String
    public let status: ListingStatus
}

/// One line in the booklet.
public struct PassportEvent: Decodable, Sendable {
    /// authenticated | transferred | sold | listed | service_added, and the
    /// server may add more — an unrecognised kind still renders its summary
    /// rather than disappearing from a record that claims to be complete.
    public let kind: String
    public let summary: String
    public let occurredAt: Date?
    public let details: PassportEventDetails?

    /// The one kind a person wrote themselves. Everything else on the
    /// timeline is Calibre stating a fact about the watch, and only this
    /// takes the hand.
    public var isOwnerWritten: Bool { kind == "service_added" }

    /// What the owner actually typed, with the server's own lead-in removed.
    ///
    /// The server stores the entry as one sentence — its label, then the
    /// provider and details the owner gave it — because the timeline is read
    /// as prose on the web. A booklet renders the label as a heading, so
    /// repeating it inside the entry would print it twice. An entry that
    /// carries no lead-in is used whole.
    public var ownerEntry: String {
        let lead = "Service record added: "
        guard summary.hasPrefix(lead) else { return summary }
        return String(summary.dropFirst(lead.count))
    }

    /// The date this line is stamped with. A service entry records when the
    /// watch was serviced, which is not when the owner got round to writing
    /// it down; every other kind happened when it was recorded.
    public var marginDate: Date? {
        details?.servicedDay ?? occurredAt
    }
}

/// The typed half of an event's `details`. The bag is open-ended on the
/// server, so this reads the keys the booklet renders and ignores the rest.
public struct PassportEventDetails: Decodable, Sendable {
    /// Per-part condition, on an `authenticated` event.
    public let grades: PassportConditionGrades?
    /// The authenticator confirmed box and papers alongside the watch.
    public let boxPapers: Bool?
    /// The full authentication report, when one was published.
    public let reportPdfUrl: MediaURL?
    /// On a `service_added` event: when the watch was serviced.
    ///
    /// Kept as the server sent it, the way `VaultServiceRecord` keeps the
    /// same field. It is a calendar day rather than an instant — a service
    /// happened on a date, not at a time — so it arrives as `2026-03-04` and
    /// the client's ISO-8601 date strategy would throw on it and take the
    /// whole passport down with it. Read `servicedDay` for the parsed value.
    public let servicedAt: String?
    /// On a `service_added` event: who did the work.
    public let provider: String?

    /// `servicedAt` as a date. Nil when the field is absent or is not a form
    /// this app reads — the entry still prints, stamped with the day it was
    /// recorded, rather than the record refusing to open.
    public var servicedDay: Date? {
        guard let servicedAt else { return nil }
        return Self.day.date(from: servicedAt) ?? Self.instant.date(from: servicedAt)
    }

    /// A calendar day is not local to the reader — it is the day printed on
    /// the invoice — so it is read in a fixed zone rather than drifting a
    /// service into the previous evening for anyone west of the workshop.
    // Both formatters are immutable once built and the underlying types are
    // documented thread-safe; the annotation only tells Swift 6 that sharing
    // them is intentional. Same reading as `APIClient`'s own pair.
    nonisolated(unsafe) private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// The same field arrives as a full timestamp on records written before
    /// the column was a date, so both forms are read rather than one of them
    /// silently losing its entry's date.
    nonisolated(unsafe) private static let instant: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// The authenticator's per-part grades, in the order a watch is inspected.
/// Every field is optional because a report fills in what it examined — an
/// unfilled part is not a grade, so it is left out rather than shown empty.
public struct PassportConditionGrades: Decodable, Sendable {
    public let crystal: String?
    public let bezel: String?
    public let bracelet: String?
    public let clasp: String?
    public let caseback: String?
    public let overall: String?

    /// Label/value pairs in inspection order, with the ungraded parts
    /// dropped.
    public var rows: [(label: String, value: String)] {
        var out: [(label: String, value: String)] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            out.append((label, value))
        }
        add("Crystal", crystal)
        add("Bezel", bezel)
        add("Bracelet", bracelet)
        add("Clasp", clasp)
        add("Caseback", caseback)
        add("Overall", overall)
        return out
    }

    public var isEmpty: Bool { rows.isEmpty }
}
