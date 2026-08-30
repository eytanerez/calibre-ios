import SwiftUI
import UIKit

/// Shared accessibility machinery. Everything here is invisible at the default
/// content size with no assistive technology running — these are semantics and
/// hit regions, not layout.
public enum A11y {
    /// How hard an announcement pushes. `.high` interrupts whatever VoiceOver is
    /// currently saying — right for an error the user must not miss; `.default`
    /// queues politely behind it.
    ///
    /// Spelled as our own type on purpose: the platform's equivalent is not
    /// exported into SwiftUI's scope, and naming it here keeps call sites
    /// writing `.high` / `.default` regardless of where Apple moves it.
    public enum Priority {
        case `default`, high
    }

    /// Speaks a sentence to VoiceOver without moving focus. Use for anything the
    /// app says in a banner a screen-reader user will never land on: a toast, an
    /// inline validation error, a load that finished.
    ///
    /// Silent when no screen reader is listening, so call sites need no guard.
    @MainActor
    public static func announce(_ message: String, priority: Priority = .default) {
        guard !message.isEmpty else { return }
        var announcement = AttributedString(message)
        switch priority {
        case .default: announcement.accessibilitySpeechAnnouncementPriority = .default
        case .high: announcement.accessibilitySpeechAnnouncementPriority = .high
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// Moves VoiceOver's cursor to whatever the system decides is first in the
    /// newly-presented content, and names the screen. Use when a cover or a
    /// success moment replaces what was on screen.
    @MainActor
    public static func screenChanged(_ message: String? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: message)
    }

    /// True when any assistive technology that navigates by focus is running.
    /// Timers that would race a screen-reader user should consult this rather
    /// than shortening for everybody.
    @MainActor
    public static var isNavigatingByFocus: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }
}

/// Grid columns for a card grid that collapses to a single column once the
/// reader has asked for accessibility text sizes.
///
/// Two cards side by side leave roughly 160pt of text width, which at AX5 is
/// about four characters — the brand, the watch's name and its reference all
/// truncate at once and the card stops identifying anything. One column gives
/// each card the full measure instead of a sliver of it.
///
/// Below the accessibility threshold this returns exactly the two flexible
/// columns the grids already use, so nothing moves for a default reader.
@MainActor
public func calibreGridColumns(
    _ typeSize: DynamicTypeSize,
    spacing: CGFloat = Space.m
) -> [GridItem] {
    typeSize.isAccessibilitySize
        ? [GridItem(.flexible(), spacing: spacing)]
        : [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)]
}

public extension View {
    /// Marks this view as the only thing assistive technology may reach, and
    /// removes whatever it is covering from the accessibility tree.
    ///
    /// A SwiftUI `.overlay` stacks pixels; it does not remove what is beneath it
    /// from the accessibility tree, so an opaque cover still leaves the content
    /// behind it fully readable by VoiceOver. Apply `a11yCoveredBy(_:)` to the
    /// content and `.accessibilityAddTraits(.isModal)` to the cover.
    func a11yCoveredBy(_ isCovered: Bool) -> some View {
        accessibilityHidden(isCovered)
    }

    /// Grows the tappable region to at least `Space.touchTarget` without
    /// changing the drawn pixels or the space the view takes in its parent.
    ///
    /// The padding grows the frame, `contentShape` claims the grown frame for
    /// hit testing, and the negative padding hands the layout back. Do not use
    /// this where two controls sit closer together than `2 * inset` — the later
    /// sibling is on top and silently wins the overlap.
    func a11yExpandTarget(to size: CGFloat = Space.touchTarget, currentSize: CGFloat) -> some View {
        let inset = max(0, (size - currentSize) / 2)
        return padding(inset)
            .contentShape(Rectangle())
            .padding(-inset)
    }

    /// Speaks `message` when `value` changes and the new value is non-nil.
    /// Used for inline validation errors, which appear beside a field VoiceOver
    /// focus is not on and are otherwise never spoken.
    func a11yAnnounce(_ message: String?) -> some View {
        onChange(of: message) { _, new in
            if let new, !new.isEmpty { A11y.announce(new, priority: .high) }
        }
    }
}
