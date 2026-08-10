import SwiftUI

/// One thing a row can do. Rows declare their actions once and every
/// affordance — the ⋯ menu, the swipe, the long press — is built from the same
/// list, so they can never drift apart.
public struct RowAction: Identifiable {
    public let id = UUID()
    public let title: String
    public let systemImage: String
    public let isDestructive: Bool
    public let tint: Color?
    public let action: () -> Void

    public init(
        _ title: String,
        systemImage: String,
        isDestructive: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.tint = tint
        self.action = action
    }
}

/// The ⋯ button. Present on every row that has actions, alongside swipe and
/// long-press, because people reach for different ones and shouldn't have to
/// learn which a given list supports.
public struct RowActionsMenu: View {
    let actions: [RowAction]
    let label: String

    public init(actions: [RowAction], label: String) {
        self.actions = actions
        self.label = label
    }

    public var body: some View {
        if !actions.isEmpty {
            Menu {
                RowActionButtons(actions: actions)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(label)
        }
    }
}

/// The buttons themselves, shared by the ⋯ menu and `.contextMenu`.
public struct RowActionButtons: View {
    let actions: [RowAction]

    public init(actions: [RowAction]) {
        self.actions = actions
    }

    public var body: some View {
        ForEach(actions) { action in
            Button(role: action.isDestructive ? .destructive : nil) {
                action.action()
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        }
    }
}

/// The swipe rail, built from the same list.
public struct RowActionSwipeButtons: View {
    let actions: [RowAction]

    public init(actions: [RowAction]) {
        self.actions = actions
    }

    public var body: some View {
        ForEach(actions) { action in
            Button(role: action.isDestructive ? .destructive : nil) {
                action.action()
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .tint(action.tint ?? (action.isDestructive ? Color.calibre.destructive : Color.calibre.primary))
        }
    }
}

public extension View {
    /// Gives a row all three affordances from one list: swipe, long-press, and
    /// (via `RowActionsMenu` in the row's own layout) the ⋯ button.
    func rowActions(_ actions: [RowAction]) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            RowActionSwipeButtons(actions: actions)
        }
        .contextMenu {
            RowActionButtons(actions: actions)
        }
    }
}
