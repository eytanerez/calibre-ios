import CalibreDesign
import CalibreKit
import SwiftUI

/// One buyer↔seller conversation, anchored to a listing. Not support chat —
/// see `MessagesListScreen`.
///
/// Messages arrive two ways, exactly like the web client: fetched on load,
/// and pushed live over SSE while the thread is open (`messageStream`). A
/// coarse poll runs alongside the stream as a safety net — if the live
/// connection is ever quietly failing, the thread still catches up within a
/// few seconds instead of going stale for the rest of the visit.
///
/// A guard inspects every outgoing message for attempts to move the
/// conversation off-platform. Nothing is ever edited or silently dropped:
/// the composer clears optimistically, but every bubble is rendered from
/// what the *server* says happened to that message — delivered, or held and
/// visible only to the person who sent it. See `MessageBubbleRow` and
/// `MessageDeliveryState`.
struct MessageThreadScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let threadID: String

    @State private var messages: [ThreadMessage] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var loading = true
    @State private var loadErrorText: String?
    @State private var sendErrorText: String?

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            composer
        }
        .calibrePageBackground()
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: threadID) { await run() }
    }

    // MARK: - Messages

    @ViewBuilder private var messagesList: some View {
        if loading && messages.isEmpty {
            ProgressView()
                .tint(Color.calibre.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadErrorText, messages.isEmpty {
            EmptyState(
                icon: "wifi.exclamationmark",
                title: "Couldn't load this conversation",
                message: loadErrorText,
                actionTitle: "Try again"
            ) { Task { await loadMessages() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty {
            EmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "Say hello",
                message: "Ask about condition, papers or timing — it goes straight to them."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Space.m) {
                        ForEach(messages) { message in
                            MessageBubbleRow(message: message, isMine: message.senderId == session.user?.id)
                                .id(message.id)
                        }
                    }
                    .padding(Space.margin)
                }
                .onChange(of: messages.count) { old, new in
                    if reduceMotion {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    } else {
                        withAnimation(Motion.easeMedium) {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    if new > old, let last = messages.last, last.senderId != session.user?.id {
                        A11y.announce("New message")
                    }
                }
            }
        }
    }

    // MARK: - Composer
    //
    // Text only, deliberately. The whole point of this surface is a guard
    // that stops contact details leaving the platform in *text*; a photo or
    // a file is a channel that guard cannot see into at all — a screenshot
    // of a phone number walks straight past it. So there is no attach
    // control here, unlike the support-chat composer this screen otherwise
    // resembles.

    private var composer: some View {
        VStack(spacing: Space.s) {
            if let sendErrorText {
                Text(sendErrorText)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: Space.s) {
                CalibreTextField("Write a message", text: $draft, kind: .sentence)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.calibre.primaryForeground)
                        .frame(width: 40, height: 40)
                        .background(canSend ? Color.calibre.primary : Color.calibre.placeholder, in: Circle())
                        .a11yExpandTarget(currentSize: 40)
                }
                .disabled(!canSend || sending)
                .accessibilityLabel("Send message")
                .accessibilityHint(canSend ? "" : "Write a message first")
            }
        }
        .padding(Space.margin)
        .background(Color.calibre.card)
        .overlay(alignment: .top) { Rectangle().fill(Color.calibre.border).frame(height: 1) }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        sendErrorText = nil
        defer { sending = false }
        do {
            let result = try await services.messaging.send(threadID: threadID, body: body)
            draft = ""
            // Always the server's own message, never the local draft — the
            // server decided delivered vs held, and this is that decision.
            append(result.message)
            Haptics.shared.play(result.action == .hold ? .selection : .save)
        } catch {
            sendErrorText = (error as? APIError)?.errorDescription ?? "Couldn't send. Please try again."
            Haptics.shared.play(.error)
        }
    }

    // MARK: - Load / live delivery

    private func run() async {
        await loadMessages()
        async let stream: Void = listen()
        async let poll: Void = pollLoop()
        _ = await (stream, poll)
    }

    private func loadMessages(silent: Bool = false) async {
        if !silent { loading = messages.isEmpty }
        do {
            let fetched = try await services.messaging.listMessages(threadID: threadID)
            merge(fetched)
            loadErrorText = nil
            try? await services.messaging.markRead(threadID: threadID)
        } catch {
            if !silent {
                loadErrorText = (error as? APIError)?.errorDescription ?? "Couldn't load this conversation."
            }
        }
        loading = false
    }

    /// A live-streamed message and a polled refresh can each learn about the
    /// same message first; merging by id (rather than replacing the array)
    /// means whichever arrives first wins and neither one can make an
    /// already-visible message disappear.
    private func merge(_ fetched: [ThreadMessage]) {
        var byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in fetched { byID[message.id] = message }
        messages = byID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func append(_ incoming: ThreadMessage) {
        guard !messages.contains(where: { $0.id == incoming.id }) else { return }
        messages.append(incoming)
    }

    private func listen() async {
        for await incoming in services.messaging.messageStream(threadID: threadID) {
            append(incoming)
            if incoming.senderId != session.user?.id {
                try? await services.messaging.markRead(threadID: threadID)
            }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            await loadMessages(silent: true)
        }
    }
}

// MARK: - Bubble

/// One message, in one of three states — see `MessageDeliveryState`.
///
///   delivered  normal bubble, no annotation
///   held       amber ring + notice, sender-only
///   denied     red ring + notice, sender-only
///
/// The bubble keeps its ordinary shape in every state; only a thin ring and
/// a small notice line beneath it change. Restyling the bubble itself as an
/// error block would read as "the app broke" rather than "this message is
/// being checked" — the difference matters, because one makes a person
/// retry harder and the other makes them read. The recipient never sees any
/// of this: `stopped` is gated on `isMine`, so a message the guard held or an
/// admin denied renders as an ordinary bubble — nothing at all — to whoever
/// did not send it.
private struct MessageBubbleRow: View {
    let message: ThreadMessage
    let isMine: Bool

    private var state: MessageDeliveryState { message.deliveryState }
    private var stopped: Bool { isMine && state != .delivered }

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                Text(message.body)
                    .font(CalibreType.body)
                    .foregroundStyle(isMine ? Color.calibre.primaryForeground : Color.calibre.foreground)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(
                        isMine ? Color.calibre.primary : Color.calibre.secondary,
                        in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    )
                    .overlay {
                        if stopped {
                            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                                .strokeBorder(tone, lineWidth: 2)
                        }
                    }

                if stopped, let notice = MessagingCopy.notice(for: state) {
                    HStack(alignment: .top, spacing: Space.xs) {
                        Image(systemName: state == .held ? "clock" : "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                        Text(notice)
                            .font(CalibreType.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(tone)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .frame(maxWidth: 280, alignment: .leading)
                    .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }

            if !isMine { Spacer(minLength: 40) }
        }
    }

    private var tone: Color {
        state == .held ? Color.calibre.warning : Color.calibre.destructive
    }
}
