import CalibreDesign
import CalibreKit
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
        .calibrePageBackground()
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
            ) { Task { await load() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if threads.isEmpty {
            EmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "No conversations yet",
                message: "Message a seller from any listing, or a buyer's question about yours shows up here.",
                aside: "Questions about condition, papers and timing get the fastest replies."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: Space.m) {
                    ForEach(threads) { thread in
                        NavigationLink {
                            MessageThreadScreen(threadID: thread.id)
                        } label: {
                            ThreadRow(thread: thread, isSeller: thread.sellerId == session.user?.id)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(Space.margin)
            }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            let fetched = try await services.messaging.listThreads()
            // Most-recently-active conversation first; a thread with no
            // messages yet (just opened, nothing sent) sorts by when it was
            // opened instead.
            threads = fetched.sorted { ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt) }
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
        }
        loading = false
    }
}

private struct ThreadRow: View {
    let thread: MessageThread
    let isSeller: Bool

    var body: some View {
        HStack(spacing: Space.m) {
            IconTile(systemName: "bubble.left.and.bubble.right")

            VStack(alignment: .leading, spacing: 3) {
                Text(thread.listingTitle ?? "A listing")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(1)
                Text(subtitle)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s)

            VStack(alignment: .trailing, spacing: 5) {
                Text(dateText)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if thread.state == .blocked { return "This conversation is closed" }
        return isSeller ? "A buyer messaged you" : "You messaged the seller"
    }

    private var dateText: String {
        (thread.lastMessageAt ?? thread.createdAt).formatted(date: .abbreviated, time: .omitted)
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
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}
