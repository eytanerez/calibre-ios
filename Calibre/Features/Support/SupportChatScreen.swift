import CalibreDesign
import CalibreKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

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
    /// Files staged against the thread, waiting for the message that carries
    /// them. Cleared when that message sends.
    @State private var attachments: [SupportAttachment] = []
    @State private var uploading = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false

    private var conversation: SupportConversation? { services.support.conversation }
    private var needsGuestEmail: Bool {
        !session.isAuthenticated && services.support.guestToken == nil
    }

    /// The named person on the Calibre side, once one is assigned. Everything
    /// below falls back to the generic wording while this is nil.
    private var contactName: String? {
        guard let name = conversation?.assignedContact?.displayName else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        VStack(alignment: .leading, spacing: 3) {
            Text(contactName.map { "You're talking with \($0)" } ?? "Message Calibre")
                .font(CalibreType.bodySemiBold)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(statusLine)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text("Write here or email support@buycalibre.com — it is the same conversation either way.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.margin)
        .background(Color.calibre.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.calibre.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// Where the thread stands right now. Every conversation state is named
    /// explicitly so the two waiting states never fall through to a blank
    /// or generic line.
    private var statusLine: String {
        guard let conversation else {
            return "We typically reply within a day."
        }
        switch conversation.status {
        case .waitingOnCalibre:
            if let contactName {
                return "\(contactName) has your message and will reply, usually within a day."
            }
            return "We have your message and will reply, usually within a day."
        case .waitingOnCustomer:
            if let contactName {
                return "\(contactName) has replied and is waiting to hear back from you."
            }
            return "We have replied and are waiting to hear back from you."
        case .closed:
            return "This conversation is closed. Write again any time and it reopens."
        case .open, .unknown:
            if contactName != nil {
                return "Messages come personally from them. We typically reply within a day."
            }
            return "We typically reply within a day."
        }
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
                CalibreTextField("Your email so we can reply", text: $guestEmail, kind: .email)
            }

            if !attachments.isEmpty {
                stagedAttachments
            }

            HStack(alignment: .bottom, spacing: Space.s) {
                attachButton
                CalibreTextField("Write a message", text: $draft, kind: .sentence)
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

            if !canAttach {
                Text("Send your first message and you can attach photos or a PDF to the thread after that.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.margin)
        .background(Color.calibre.card)
        .overlay(alignment: .top) { Rectangle().fill(Color.calibre.border).frame(height: 1) }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                await stagePickedPhoto(item)
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                Task { await stagePickedPDF(url) }
            }
        }
    }

    /// An upload cannot start a conversation — the server refuses one until a
    /// thread exists — so the control only turns on once there is a thread to
    /// hang the file on.
    private var canAttach: Bool {
        conversation != nil
    }

    private var attachButton: some View {
        Menu {
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Photo", systemImage: "photo")
            }
            Button {
                showingFileImporter = true
            } label: {
                Label("PDF", systemImage: "doc")
            }
        } label: {
            Group {
                if uploading {
                    ProgressView().controlSize(.small).tint(Color.calibre.primary)
                } else {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(canAttach ? Color.calibre.primary : Color.calibre.placeholder)
                }
            }
            .frame(width: 40, height: 40)
        }
        .disabled(!canAttach || uploading || sending)
        .accessibilityLabel("Attach a file")
    }

    private var stagedAttachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(attachments) { attachment in
                    HStack(spacing: Space.xs) {
                        Image(systemName: attachment.isPDF ? "doc" : "photo")
                            .font(.system(size: 12, weight: .medium))
                        Text(attachment.filename ?? "Attachment")
                            .font(CalibreType.caption)
                            .lineLimit(1)
                        if let size = attachment.sizeText {
                            Text(size)
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        .accessibilityLabel("Remove \(attachment.filename ?? "attachment")")
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(Color.calibre.secondary, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!needsGuestEmail || InputValidation.isValidEmail(guestEmail))
            && !sending
            && !uploading
    }

    // MARK: - Attachments

    /// Images and PDFs only, at most 10MB each and 20MB across a message —
    /// the server enforces all three; these checks only save the buyer a
    /// pointless upload.
    private func stage(_ data: Data, filename: String, contentType: String) async {
        guard !uploading else { return }
        errorText = nil
        guard data.count <= SupportAttachment.maxBytesPerFile else {
            errorText = "An attached file can be at most 10MB."
            return
        }
        let staged = attachments.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        guard staged + data.count <= SupportAttachment.maxBytesPerMessage else {
            errorText = "One message can carry at most 20MB of files."
            return
        }
        uploading = true
        defer { uploading = false }
        do {
            let attachment = try await services.support.uploadAttachment(
                filename: filename,
                contentType: contentType,
                data: data,
                authenticated: session.isAuthenticated
            )
            attachments.append(attachment)
            Haptics.shared.play(.selection)
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn\u{2019}t attach that file."
            Haptics.shared.play(.error)
        }
    }

    private func stagePickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorText = "Couldn\u{2019}t read that photo."
            return
        }
        let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
        await stage(
            data,
            filename: "photo." + (type?.preferredFilenameExtension ?? "jpg"),
            contentType: type?.preferredMIMEType ?? "image/jpeg"
        )
    }

    private func stagePickedPDF(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorText = "Couldn\u{2019}t read that file."
            return
        }
        await stage(data, filename: url.lastPathComponent, contentType: "application/pdf")
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
                guestEmail: needsGuestEmail ? InputValidation.trimmed(guestEmail).lowercased() : nil,
                attachmentIDs: attachments.map(\.id)
            )
            draft = ""
            attachments = []
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
                if !message.body.isEmpty {
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

                // Signed, time-limited links, so they open in the browser
                // rather than being cached anywhere they would outlive.
                ForEach(message.attachments) { attachment in
                    attachmentRow(attachment)
                }
            }
            if !isCustomer { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: SupportAttachment) -> some View {
        let label = HStack(spacing: Space.xs) {
            Image(systemName: attachment.isPDF ? "doc" : "photo")
                .font(.system(size: 12, weight: .medium))
            Text(attachment.filename ?? "Attachment")
                .font(CalibreType.caption)
                .lineLimit(1)
            if let size = attachment.sizeText {
                Text(size)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .foregroundStyle(Color.calibre.foreground)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .background(Color.calibre.secondary, in: Capsule())

        if let url = attachment.url?.url {
            Link(destination: url) { label }
        } else {
            label
        }
    }
}
