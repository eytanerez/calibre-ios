import SwiftUI

/// Waiting, in the app's own hand.
///
/// The balance wheel is the marks vocabulary's loading mark — the regulator
/// that oscillates while a movement runs, and the only mark allowed to loop,
/// because looping is the thing it is saying. Everywhere this app used to
/// raise a system `ProgressView` it was borrowing Apple's vocabulary for a
/// sentence Calibre already had a word for.
///
/// Three shapes, and no fourth:
///
/// - `CalibreLoadingView` — a screen or a section with nothing in it yet.
/// - `CalibreInlineLoading` — a small wheel where a control's own content will
///   go, on a surface the app paints.
/// - `CalibreBusyLabel` — a pending button. The label keeps its words; the
///   wheel joins them.
///
/// A content-shaped skeleton still beats all three where the shape of what is
/// coming is known — see `Shimmer`. These are for the waits where it is not.
///
/// Reduced motion is handled inside the mark: it renders its end state, the
/// wheel at rest, rather than a blank frame or a stopped mid-swing.

/// A whole screen, or a whole section, still loading. One mark and one line
/// about what is being waited on — a mark with no words is a spinner with
/// extra steps.
public struct CalibreLoadingView: View {
    private let label: String?
    private let size: CGFloat

    /// `label` is what the person is waiting on, in their words, not the
    /// app's ("Working out your exact refund." beats "Loading…"). Nil where
    /// the surrounding screen has already said it.
    public init(_ label: String? = nil, size: CGFloat = 44) {
        self.label = label
        self.size = size
    }

    public var body: some View {
        VStack(spacing: Space.m) {
            CalibreMark.balanceWheel(size: size)
            if let label {
                Text(label)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
        // The wheel itself is hidden from VoiceOver — it is a drawing. The
        // waiting is the fact, so the container carries it, and it carries it
        // even where there is no visible label to read.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Loading")
    }
}

/// A small wheel standing in for a control's content while the control works,
/// on a surface the app paints itself.
public struct CalibreInlineLoading: View {
    private let size: CGFloat
    private let tint: Color?

    public init(size: CGFloat = 22, tint: Color? = nil) {
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        CalibreMark.balanceWheel(size: size, tint: tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Working")
    }
}

/// A button that has been pressed and is working.
///
/// The words stay. A button whose label is replaced by a spinner has taken
/// away the one thing that said what is happening, and "Place order" going
/// blank at the moment money moves is the worst possible place to do it. The
/// mark joins the label; it does not replace it.
///
/// `tint` defaults to the primary foreground because the pending button this
/// was built for is the filled one, where the mark's own copper would be
/// copper on copper. A ghost or secondary button passes its own foreground.
public struct CalibreBusyLabel: View {
    private let title: String
    private let busy: Bool
    private let tint: Color
    private let fullWidth: Bool

    public init(
        _ title: String,
        busy: Bool,
        tint: Color = Color.calibre.primaryForeground,
        fullWidth: Bool = true
    ) {
        self.title = title
        self.busy = busy
        self.tint = tint
        self.fullWidth = fullWidth
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            if busy {
                CalibreMark.balanceWheel(size: 20, tint: tint)
            }
            Text(title)
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        // Read as one thing. Without this the mark's own hidden-ness leaves
        // the title alone, and VoiceOver says "Place order" for a button that
        // is already placing it.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(busy ? "\(title), working" : title)
    }
}

#Preview("Loading", traits: .sizeThatFitsLayout) {
    VStack(spacing: Space.xl) {
        CalibreLoadingView("Working out your exact refund.")
        CalibreInlineLoading()
        CalibreBusyLabel("Place order", busy: true)
            .padding(.vertical, Space.m)
            .background(Color.calibre.primary, in: RoundedRectangle(cornerRadius: Radius.control))
            .foregroundStyle(Color.calibre.primaryForeground)
    }
    .padding(Space.xl)
    .calibrePageBackground()
}
