import RewoundDesign
import RewoundKit
import SwiftUI

/// Support opens here: the list of this customer's own conversations with
/// Rewound, newest activity first, with a New chat button.
///
/// It used to open straight onto a composer, because the backend could hold
/// exactly one conversation per customer and the New-chat control was wired to
/// a flag that was always false. There are real, separate conversations now,
/// and a person who wrote in about a return in March and an order today should
/// find two threads rather than one long one.
struct SupportThreadsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var threads: [SupportThreadSummary] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var openThread: SupportEntry?

    /// Who answers, named on the list as well as inside a conversation.
    ///
    /// This screen used to name nobody: the contact was read only off a loaded
    /// conversation, so Support opened on a list with no person on it although
    /// every account has one stamped. The member's account answers for them;
    /// a guest's newest thread answers for a guest. See `SupportContact.shown`.
    private var contact: SupportContact? {
        SupportContact.shown(
            onThread: nil,
            account: session.user?.assignedContact,
            isAuthenticated: session.isAuthenticated,
            newestThread: threads.first?.assignedContact
        )
    }

    private var contactFirstName: String? {
        contact?.name?.split(separator: " ").first.map(String.init)
    }

    var body: some View {
        Group {
            if loading && threads.isEmpty {
                RewoundLoadingView("Finding your conversations")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, threads.isEmpty {
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load your conversations",
                    message: errorText,
                    actionTitle: "Try again"
                ) { await load() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if threads.isEmpty {
                EmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: contactFirstName.map { "Write to \($0)" } ?? "How can we help?",
                    message: contactFirstName.map {
                        "Ask anything about a watch, an order, selling, or your account. \($0) answers personally."
                    } ?? "Ask us anything — about a watch, an order, selling, or your account. We read every message.",
                    actionTitle: contactFirstName.map { "Message \($0)" } ?? "New chat"
                ) { openThread = .newThread }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .rewoundPageBackground()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.shared.play(.press)
                    openThread = .newThread
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.primary)
                .accessibilityLabel("New chat")
            }
        }
        .navigationDestination(item: $openThread) { entry in
            SupportChatScreen(entry: entry)
                .routeStackNode()
        }
        .task { await load() }
        // The copy of the user read at launch can be days old; the name here
        // is the server's current one.
        .task { await session.refreshUser() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                if let contact, let name = contact.name {
                    SupportContactHeader(contact: contact, name: name)
                }

                Text("Write here or email support@shoprewound.com — it is the same conversation either way.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(threads) { thread in
                    Button {
                        openThread = .thread(thread.id)
                    } label: {
                        SupportThreadRow(thread: thread)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(Space.margin)
        }
        .refreshable { await load() }
    }

    private func load() async {
        defer { loading = false }
        do {
            threads = try await services.support.listThreads(authenticated: session.isAuthenticated)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
        }
    }
}

/// The person behind every conversation on the list, once, above it.
private struct SupportContactHeader: View {
    let contact: SupportContact
    let name: String

    var body: some View {
        HStack(spacing: Space.s) {
            AvatarInitial(initials: contact.initials, size: .s)
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Your contact at Rewound")
                Text(name)
                    .font(RewoundType.bodySemiBold)
                    .foregroundStyle(Color.rewound.foreground)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your contact at Rewound, \(name)")
    }
}

private struct SupportThreadRow: View {
    let thread: SupportThreadSummary

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(systemName: "bubble.left.and.bubble.right")

            VStack(alignment: .leading, spacing: 3) {
                // The date it was opened, in the server's words. Never the
                // first message — a thread named after its opening line
                // repeats a sentence that is already on screen inside it.
                Text(thread.title)
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                if !thread.snippet.isEmpty {
                    Text(thread.snippet)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: Space.s) {
                    if let statusText {
                        StatusBadge(statusText, tone: statusTone)
                    }
                    if !dateText.isEmpty {
                        Text(dateText)
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.placeholder)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.rewound.mutedForeground)
                .padding(.top, 3)
        }
        .padding(Space.l)
        .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Only the two states a customer can act on are named. "Open" says
    /// nothing they do not already know from the thread being in this list.
    private var statusText: String? {
        switch thread.status {
        case .waitingOnCustomer: "Waiting on you"
        case .closed: "Resolved"
        case .waitingOnRewound, .open, .unknown: nil
        }
    }

    private var statusTone: StatusBadge.Tone {
        thread.status == .waitingOnCustomer ? .warning : .neutral
    }

    private var dateText: String {
        guard let stamp = thread.lastMessageAt ?? thread.createdAt else { return "" }
        return stamp.formatted(.relative(presentation: .named))
    }

    private var accessibilityText: String {
        [thread.title, statusText, thread.snippet.isEmpty ? nil : thread.snippet, dateText.isEmpty ? nil : dateText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
