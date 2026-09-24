import RewoundDesign
import RewoundKit
import SwiftUI

/// Every open buyer↔seller conversation this member is part of, either side.
/// Not support chat — that lives at `SupportChatScreen` and is a different
/// service entirely (`SupportStore`, not `MessagingStore`).
struct MessagesListScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var threads: [MessageThread] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var nextCursor: String?
    @State private var loadingMore = false

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "Your messages live here",
                    message: "Sign in to message a seller about a listing, or hear from a buyer about your own.",
                    actionTitle: "Sign in"
                ) {
                    session.require("Sign in to see your messages") {}
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .rewoundPageBackground()
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.isAuthenticated) {
            if session.isAuthenticated, loading { await load() }
        }
    }

    @ViewBuilder private var content: some View {
        if loading && threads.isEmpty {
            VStack(spacing: Space.m) {
                ForEach(0..<4, id: \.self) { _ in ThreadRowSkeleton() }
            }
            .padding(Space.margin)
        } else if let errorText, threads.isEmpty {
            EmptyState(
                icon: "wifi.exclamationmark",
                title: "Couldn't load your messages",
                message: errorText,
                actionTitle: "Try again"
            ) { await load() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if threads.isEmpty {
            EmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "No conversations yet",
                message: "Message a seller from any listing, or a buyer's question about yours shows up here."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Space.m) {
                    ForEach(threads) { thread in
                        NavigationLink {
                            MessageThreadScreen(threadID: thread.id, initialThread: thread)
                        } label: {
                            ThreadRow(thread: thread)
                        }
                        .buttonStyle(PressableStyle())
                        // Opening the thread is what marks it read, and the
                        // read POST answers with no body — so the row is
                        // zeroed here rather than waiting for a refetch that
                        // may not happen until the next visit.
                        .simultaneousGesture(TapGesture().onEnded {
                            markRead(thread)
                        })
                        .task {
                            if thread.id == threads.last?.id { await loadMore() }
                        }
                    }
                }
                .padding(Space.margin)
            }
            .refreshable { await load() }
        }
    }

    /// Zeroes one row's unread mark. The server call is the thread screen's
    /// own (`markRead` on appear); this is only the list catching up with it,
    /// so a failure there is not something to report twice.
    private func markRead(_ thread: MessageThread) {
        guard thread.unreadCount > 0 else { return }
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        threads[index] = thread.markedRead()
    }

    private func load() async {
        do {
            let page = try await services.messaging.listThreadsPage()
            // Most-recently-active conversation first; a thread with no
            // messages yet (just opened, nothing sent) sorts by when it was
            // opened instead.
            threads = page.items.sorted { ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt) }
            nextCursor = page.nextCursor
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
        }
        loading = false
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await services.messaging.listThreadsPage(cursor: cursor) else { return }
        var byID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
        for thread in page.items { byID[thread.id] = thread }
        threads = byID.values.sorted { ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt) }
        nextCursor = page.nextCursor
    }
}

private struct ThreadRow: View {
    let thread: MessageThread

    var body: some View {
        HStack(spacing: Space.m) {
            IconTile(systemName: "bubble.left.and.bubble.right")

            VStack(alignment: .leading, spacing: 3) {
                Text(thread.listingTitle ?? "A listing")
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                    .lineLimit(1)
                Text(subtitle)
                    .font(unread ? RewoundType.label : RewoundType.caption)
                    .foregroundStyle(unread ? Color.rewound.foreground : Color.rewound.mutedForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s)

            VStack(alignment: .trailing, spacing: 5) {
                Text(dateText)
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                if unread {
                    // The count, not a bare dot: how many are waiting is the
                    // thing the list can now say and could not before.
                    Text(String(thread.unreadCount))
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.primaryForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.rewound.primary, in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.rewound.mutedForeground)
                }
            }
        }
        .padding(Space.l)
        .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? "\(thread.unreadCount) unread" : "")
    }

    private var unread: Bool { thread.unreadCount > 0 }

    /// The last delivered line, which is what a person is actually looking for
    /// in a list of conversations. The generic "A buyer messaged you" it
    /// replaced was true of every row and told nobody anything.
    ///
    /// A thread with no delivered message yet is a real state — just opened,
    /// or everything in it still held by the guard — and says so rather than
    /// borrowing a sentence.
    private var subtitle: String {
        if thread.state == .blocked { return "This conversation is closed" }
        if let preview = thread.lastMessagePreview, !preview.isEmpty { return preview }
        return "No messages yet"
    }

    /// The preview's own stamp, which describes the same event as the words
    /// beside it. `lastMessageAt` is the fallback, and a thread with neither
    /// falls back to when it was opened.
    private var dateText: String {
        (thread.lastMessagePreviewAt ?? thread.lastMessageAt ?? thread.createdAt)
            .formatted(date: .abbreviated, time: .omitted)
    }
}

private struct ThreadRowSkeleton: View {
    var body: some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .frame(width: 40, height: 40)
                .shimmer()
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(width: 160, height: 14).shimmer()
                RoundedRectangle(cornerRadius: 4).frame(width: 110, height: 12).shimmer()
            }
            Spacer()
        }
        .padding(Space.l)
        .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
    }
}
