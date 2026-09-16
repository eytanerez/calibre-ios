import Foundation

/// A record named inside a support message body — the format four clients agree on.
///
/// Source of truth: `Backend/docs/admin-contracts.md` §12.9b and
/// `Backend/app/services/record_refs.py`. The admin console and the storefront
/// hold the same rule; this is the iOS copy, and all of them must serialise
/// identically or a chip written on one client stops being a chip on the next.
///
/// A support message is plain text. An order or a listing inside one is a
/// markdown link whose target is a `calibre:` reference URI:
///
///     Any update on [Order #13](calibre:order/9f3c…)?
///
/// **The label is authoritative.** It is the record's human name, and it is
/// what a reader sees whatever their client does with the target. A client that
/// does not know the scheme, or the kind, or cannot resolve the id, renders the
/// label as plain text and nothing else — never the brackets, never the URI,
/// never a route it guessed. The worst thing anybody can see is the words
/// `Order #13`.
///
/// **The target is not a path.** `/orders/<uuid>` reads as a route on whichever
/// app happens to be rendering it, and the console's chip editor used to
/// serialise exactly that. Legacy bodies still contain that shape, so it is
/// read here — and flattened to its label, because a console path is not
/// somewhere this app may send anybody.
public enum RecordRefKind: String, Sendable, Hashable, CaseIterable {
    case order
    case listing
}

/// One reference as it was written: what it says, and what it points at.
public struct RecordRef: Sendable, Hashable, Identifiable {
    public let kind: RecordRefKind
    public let recordID: String
    /// The record's human name. This is what the message reads as.
    public let label: String

    public init(kind: RecordRefKind, recordID: String, label: String) {
        self.kind = kind
        self.recordID = recordID
        self.label = label
    }

    public var id: String { "\(kind.rawValue)/\(recordID)" }

    /// The target this reference serialises to.
    public var target: String { RecordRefs.target(kind: kind.rawValue, recordID: recordID) }

    /// Where this app opens it — the deep link `AppRouter.handle(url:)` already
    /// understands, so a chip needs no route table of its own.
    public var route: URL? { URL(string: "calibre://\(kind.rawValue)/\(recordID)") }
}

/// One piece of a body as a renderer draws it.
public enum RecordRefPart: Sendable, Hashable {
    /// Prose. Also everything that degraded: an unknown kind, a legacy console
    /// path, a URL somebody pasted — all of them arrive here as their words.
    case text(String)
    case reference(RecordRef)
}

/// One record a composer may offer. `detail` is for the picker only and never
/// goes on the wire.
public struct RecordRefOption: Sendable, Hashable, Identifiable {
    public let ref: RecordRef
    public let detail: String?

    public init(ref: RecordRef, detail: String? = nil) {
        self.ref = ref
        self.detail = detail
    }

    public var id: String { ref.id }
}

public enum RecordRefs {
    /// The scheme. A marker, not a URL scheme anybody registers.
    public static let scheme = "calibre"

    /// The target a composer writes for one record.
    public static func target(kind: String, recordID: String) -> String {
        "\(scheme):\(kind.lowercased())/\(recordID)"
    }

    /// `(kind, id)` for a `calibre:` target, or nil for anything else.
    public static func parseTarget(_ target: String) -> (kind: String, recordID: String)? {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        let prefix = "\(scheme):"
        guard trimmed.hasPrefix(prefix) else { return nil }
        let rest = trimmed.dropFirst(prefix.count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let kind = String(rest[rest.startIndex..<slash])
        let recordID = String(rest[rest.index(after: slash)...])
        guard !kind.isEmpty, !recordID.isEmpty else { return nil }
        return (kind, recordID)
    }

    /// `[label](target)` — every shape a body may carry.
    ///
    /// The paths and URLs match so their brackets can be stripped: printing
    /// `[Order 13](/orders/…)` at a customer is the bug this format closes, and
    /// a body written before the format exists still contains one.
    private static let linkPattern = try? NSRegularExpression(
        pattern: #"\[([^\]\n]+)\]\((calibre:[^)\s]+|/[^)\s]*|https?://[^)\s]+)\)"#
    )

    /// A body split into the pieces a renderer draws: prose, and references.
    ///
    /// Every read surface goes through this, so "renders the label as plain
    /// text" is one function rather than a promise each screen keeps on its own.
    public static func parts(_ body: String) -> [RecordRefPart] {
        guard let linkPattern, !body.isEmpty else {
            return body.isEmpty ? [] : [.text(body)]
        }
        let ns = body as NSString
        var result: [RecordRefPart] = []
        var cursor = 0

        for match in linkPattern.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result.append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let label = ns.substring(with: match.range(at: 1))
            let target = ns.substring(with: match.range(at: 2))
            if let parsed = parseTarget(target), let kind = RecordRefKind(rawValue: parsed.kind) {
                result.append(.reference(RecordRef(kind: kind, recordID: parsed.recordID, label: label)))
            } else {
                // The degrade the format promises, in the one place it is owed:
                // a kind this build has never heard of, or a console path, is
                // the words it says and nothing more.
                result.append(.text(label))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            result.append(.text(ns.substring(from: cursor)))
        }
        return result
    }

    /// The body as words alone — what a surface with nowhere to send anybody
    /// shows. A notification, a list snippet, an accessibility label.
    public static func flatten(_ body: String) -> String {
        parts(body).map { part in
            switch part {
            case .text(let value): return value
            case .reference(let ref): return ref.label
            }
        }.joined()
    }

    /// Every record named in a body, in the order they appear.
    public static func references(in body: String) -> [RecordRef] {
        parts(body).compactMap { part in
            if case .reference(let ref) = part { return ref }
            return nil
        }
    }

    /// The wire body for a message the customer typed, with the records they
    /// picked turned back into references.
    ///
    /// A phone's text field holds characters, not objects: the picker writes
    /// the record's *label* into the draft, which is the thing the customer
    /// then reads and edits, and the reference is reattached here at send.
    /// Each ref claims the earliest occurrence of its own label that is still
    /// unclaimed, so two picks of the same record become two chips in the order
    /// they were made.
    ///
    /// A ref whose label the customer has since edited away is dropped, and
    /// dropping it is correct rather than lossy: what they are left with is the
    /// words they wrote, which is exactly what the format degrades to anyway.
    public static func compose(text: String, refs: [RecordRef]) -> String {
        var remaining = refs.filter { !$0.label.isEmpty }
        guard !remaining.isEmpty else { return text }

        var out = ""
        var rest = Substring(text)

        while !remaining.isEmpty {
            var best: (range: Range<Substring.Index>, index: Int)?
            for (index, ref) in remaining.enumerated() {
                guard let found = rest.range(of: ref.label) else { continue }
                if best == nil || found.lowerBound < best!.range.lowerBound {
                    best = (found, index)
                }
            }
            guard let found = best else { break }
            let ref = remaining.remove(at: found.index)
            out += rest[rest.startIndex..<found.range.lowerBound]
            out += "[\(ref.label)](\(ref.target))"
            rest = rest[found.range.upperBound...]
        }

        out += rest
        return out
    }
}
