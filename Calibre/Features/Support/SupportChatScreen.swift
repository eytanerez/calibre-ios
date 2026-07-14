import CalibreDesign
import CalibreKit
import SwiftUI

/// Message Calibre — works for guests and signed-in users. Guests give an
/// email on their first message so support can reply; the thread survives
/// relaunch via a persisted token. Polls every 20 seconds while open.
struct SupportChatScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var draft = ""
    @State private var guestEmail = ""
    @State private var sending = false
    @State private var errorText: String?

    private var conversation: SupportConversation? { services.support.conversation }
    private var needsGuestEmail: Bool {
        !session.isAuthenticated && services.support.guestToken == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messages
            composer
        }
        .background(Color.calibre.background)
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAndPoll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Message Calibre").font(CalibreType.bodySemiBold).foregroundStyle(Color.calibre.foreground)
            Text("We typically reply within a day.")
                .font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.margin)
        .background(Color.calibre.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.calibre.border).frame(height: 1) }
    }

    @ViewBuilder private var messages: some View {
        if let conversation, !conversation.messages.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Space.m) {
                        ForEach(conversation.messages) { message in
                            SupportBubble(message: message).id(message.id)
                        }
                    }
                    .padding(Space.margin)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    withAnimation(Motion.easeMedium) {
                        proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                    }
                }
            }
        } else {
            EmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "How can we help?",
                message: "Ask us anything — about a watch, an order, selling, or your account. We read every message."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var composer: some View {
        VStack(spacing: Space.s) {
            if let errorText {
                Text(errorText).font(CalibreType.caption).foregroundStyle(Color.calibre.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if needsGuestEmail {
                CalibreTextField("Your email so we can reply", text: $guestEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }
            HStack(alignment: .bottom, spacing: Space.s) {
                CalibreTextField("Write a message", text: $draft)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.calibre.primaryForeground)
                        .frame(width: 40, height: 40)
                        .background(canSend ? Color.calibre.primary : Color.calibre.placeholder, in: Circle())
                }
                .disabled(!canSend || sending)
            }
        }
        .padding(Space.margin)
        .background(Color.calibre.card)
        .overlay(alignment: .top) { Rectangle().fill(Color.calibre.border).frame(height: 1) }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!needsGuestEmail || InputValidation.isValidEmail(guestEmail))
            && !sending
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              !sending,
              !needsGuestEmail || InputValidation.isValidEmail(guestEmail) else { return }
        sending = true
        errorText = nil
        defer { sending = false }
        do {
            _ = try await services.support.send(
                body,
                authenticated: session.isAuthenticated,
                guestEmail: needsGuestEmail ? InputValidation.trimmed(guestEmail).lowercased() : nil
            )
            draft = ""
            Haptics.shared.play(.selection)
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't send. Please try again."
            Haptics.shared.play(.error)
        }
    }

    private func loadAndPoll() async {
        _ = try? await services.support.loadThread(authenticated: session.isAuthenticated)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            _ = try? await services.support.loadThread(authenticated: session.isAuthenticated)
        }
    }
}

private struct SupportBubble: View {
    let message: SupportMessage

    private var isCustomer: Bool { message.sender == .customer }

    var body: some View {
        HStack {
            if isCustomer { Spacer(minLength: 40) }
            VStack(alignment: isCustomer ? .trailing : .leading, spacing: 3) {
                if !isCustomer {
                    Text("Calibre").font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
                }
                Text(message.body)
                    .font(CalibreType.body)
                    .foregroundStyle(isCustomer ? Color.calibre.primaryForeground : Color.calibre.foreground)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(
                        isCustomer ? Color.calibre.primary : Color.calibre.secondary,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    )
            }
            if !isCustomer { Spacer(minLength: 40) }
        }
    }
}
