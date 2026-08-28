import SwiftUI

/// The illustration vocabulary. A mark is a drawing that reacts to something
/// that happened — never a control, never a decoration, and never a second one
/// on the same screen. One illustrated moment per step of a journey.
///
/// Adding another one is a product decision rather than an implementation one,
/// and the same names exist on web and Android: a mark that only exists here
/// is a mark the other two surfaces will quietly invent a different name for.
///
/// **Where they do not go:** on a price, on an error, or anywhere after the pay
/// button. And no admin surface takes one at all.
///
/// Everything except `balanceWheel` fires once, when it appears and again
/// whenever `trigger` changes. `balanceWheel` is the one that loops, because
/// looping is the thing it is saying.
@MainActor
public enum CalibreMark {
    /// The square a mark renders on when the caller does not say. The geometry
    /// is authored on the same square, so this is also the size at which the
    /// stroke is exactly the logo's.
    public static let defaultSize: CGFloat = MarkGrid.side

    /// Work in progress — any loading state.
    public static func balanceWheel(size: CGFloat = defaultSize) -> some View {
        BalanceWheelMark(size: size)
    }

    /// Authentication passed.
    public static func stamp(
        size: CGFloat = defaultSize,
        trigger: AnyHashable = 0
    ) -> some View {
        StampMark(size: size, trigger: trigger)
    }

    /// Agreed and binding — an offer agreed, a deal closed.
    public static func waxSeal(
        size: CGFloat = defaultSize,
        trigger: AnyHashable = 0
    ) -> some View {
        WaxSealMark(size: size, trigger: trigger)
    }

    /// Inspection — a condition report opened.
    public static func loupe(
        size: CGFloat = defaultSize,
        trigger: AnyHashable = 0
    ) -> some View {
        LoupeMark(size: size, trigger: trigger)
    }

    /// Time remaining — offer expiry, hold and return windows. `value` runs
    /// 0 (spent) to 1 (the whole window still ahead).
    public static func dialArc(
        _ value: Double,
        size: CGFloat = defaultSize,
        trigger: AnyHashable = 0
    ) -> some View {
        DialArcMark(value: value, size: size, trigger: trigger)
    }

    /// Stored value — seller balance, payout released. `value` runs 0 to 1.
    public static func powerReserve(
        _ value: Double,
        size: CGFloat = defaultSize,
        trigger: AnyHashable = 0
    ) -> some View {
        PowerReserveMark(value: value, size: size, trigger: trigger)
    }

    /// Discrete progress — seller setup, a listing draft saving.
    public static func crown(
        size: CGFloat = defaultSize,
        trigger: AnyHashable = 0
    ) -> some View {
        CrownMark(size: size, trigger: trigger)
    }

    /// In transit — shipping milestones.
    public static func box(
        size: CGFloat = defaultSize,
        trigger: AnyHashable = 0
    ) -> some View {
        BoxMark(size: size, trigger: trigger)
    }
}
