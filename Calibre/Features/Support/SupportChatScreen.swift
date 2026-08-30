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
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: String

    /// `seed` is a first message written on the customer's behalf, for the
    /// screens that send someone here from a dead end rather than from a
    /// question of their own. It lands in the composer as a draft they can
    /// edit or delete — never as a message already sent, because the send is
    /// theirs to make.
    init(seed: String = "") {
        _draft = State(initialValue: seed)
    }

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
    /// Records the customer has named in the message they are writing.
    ///
    /// A text field holds characters, not objects, so the picker writes the
    /// record's label into the draft — the words the customer then reads and
    /// edits — and the reference is reattached at send by matching that label
    /// back up (`RecordRefs.compose`). Editing the words away drops the link
    /// and leaves the words, which is the degrade the format promises anyway.
    @State private var linkedRecords: [RecordRef] = []
    @State private var showingRecordPicker = false

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
        .calibrePageBackground()
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
                            SupportBubble(message: message) { url in
                                router.handle(url: url)
                            }
                            .id(message.id)
                        }
                    }
                    .padding(Space.margin)
                }
                .onChange(of: conversation.messages.count) { old, new in
                    // Reduce Motion asks for no sliding thread; it lands on the
                    // newest message either way.
                    if reduceMotion {
                        proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                    } else {
                        withAnimation(Motion.easeMedium) {
                            proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                        }
                    }
                    // The reply arrives while focus is still in the composer, so
                    // without this the answer lands in silence.
                    if new > old, let last = conversation.messages.last, last.sender != .customer {
                        A11y.announce("New reply: \(RecordRefs.flatten(last.body))")
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

            if !linkedRecords.isEmpty {
                linkedRecordStrip
            }

            HStack(alignment: .bottom, spacing: Space.s) {
                attachButton
                if canLinkRecords { linkRecordButton }
                CalibreTextField("Write a message", text: $draft, kind: .sentence)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.calibre.primaryForeground)
                        .frame(width: 40, height: 40)
                        .background(canSend ? Color.calibre.primary : Color.calibre.placeholder, in: Circle())
                        // The circle still draws at 40 and still takes 40 in the
                        // row; only the region that answers a finger grows.
                        .a11yExpandTarget(currentSize: 40)
                }
                .disabled(!canSend || sending)
                // An arrow glyph has no name of its own: this read as "button".
                .accessibilityLabel("Send message")
                .accessibilityHint(sendHint)
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
        .sheet(isPresented: $showingRecordPicker) {
            RecordPickerSheet { option in
                link(option.ref)
                showingRecordPicker = false
            }
        }
    }

    /// Only a signed-in member may name a record. The picker is scoped by the
    /// session — their orders, their listings — and a guest has neither, so the
    /// control is absent rather than present and empty.
    private var canLinkRecords: Bool {
        session.isAuthenticated
    }

    private var linkRecordButton: some View {
        Button {
            showingRecordPicker = true
        } label: {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.calibre.primary)
                .frame(width: 40, height: 40)
                .a11yExpandTarget(currentSize: 40)
        }
        .disabled(sending || uploading)
        .accessibilityLabel("Link an order or listing")
    }

    /// What this message will carry as chips, and the way to take one back off.
    /// Removing one leaves the words in the draft: the customer wrote them, and
    /// deleting somebody's sentence to undo a link is not what the ✕ means.
    private var linkedRecordStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(linkedRecords) { ref in
                    HStack(spacing: Space.xs) {
                        Image(systemName: ref.kind == .order ? "shippingbox" : "tag")
                            .font(.system(size: 12, weight: .medium))
                        Text(ref.label)
                            .font(CalibreType.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            linkedRecords.removeAll { $0.id == ref.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        .accessibilityLabel("Unlink \(ref.label)")
                        // A 13pt glyph was a 13pt target. The chip's own padding
                        // and the gap to the next chip absorb the growth, so the
                        // chip is drawn and measured exactly as before.
                        .a11yExpandTarget(currentSize: 13)
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(Color.calibre.secondary, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Writes the record's own name into the draft where the customer is
    /// writing, and remembers the reference behind it.
    private func link(_ ref: RecordRef) {
        let needsSpace = !draft.isEmpty && !draft.hasSuffix(" ") && !draft.hasSuffix("\n")
        draft += (needsSpace ? " " : "") + ref.label + " "
        linkedRecords.append(ref)
        Haptics.shared.play(.selection)
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
            .a11yExpandTarget(currentSize: 40)
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
                        // Same 13pt glyph, same absorbed growth as the record chips.
                        .a11yExpandTarget(currentSize: 13)
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

    /// Why the send is off. Otherwise the only account of it is a grey fill,
    /// and VoiceOver's flat "dimmed".
    private var sendHint: String {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Write a message first"
        }
        if needsGuestEmail && !InputValidation.isValidEmail(guestEmail) {
            return "Add the email we should reply to first"
        }
        return ""
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
                RecordRefs.compose(text: body, refs: linkedRecords),
                authenticated: session.isAuthenticated,
                guestEmail: needsGuestEmail ? InputValidation.trimmed(guestEmail).lowercased() : nil,
                attachmentIDs: attachments.map(\.id)
            )
            draft = ""
            attachments = []
            linkedRecords = []
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
    /// Where a chip goes. The reference serialises to `calibre://order/<id>`,
    /// which `AppRouter.handle(url:)` already understands, so a chip carries no
    /// route table of its own.
    let onOpen: (URL) -> Void

    private var isCustomer: Bool { message.sender == .customer }

    var body: some View {
        HStack {
            if isCustomer { Spacer(minLength: 40) }
            VStack(alignment: isCustomer ? .trailing : .leading, spacing: 3) {
                if !isCustomer {
                    Text("Calibre").font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
                }
                if !message.body.isEmpty {
                    Text(attributedBody)
                        .font(CalibreType.body)
                        .foregroundStyle(isCustomer ? Color.calibre.primaryForeground : Color.calibre.foreground)
                        .tint(isCustomer ? Color.calibre.primaryForeground : Color.calibre.foreground)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.s)
                        .background(
                            isCustomer ? Color.calibre.primary : Color.calibre.secondary,
                            in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        )
                        .environment(\.openURL, OpenURLAction { url in
                            onOpen(url)
                            return .handled
                        })
                        // The chips are decoration to a screen reader; what it
                        // should read is the sentence, which is exactly the
                        // body with every reference flattened to its label.
                        .accessibilityLabel(RecordRefs.flatten(message.body))
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

    /// The body with its record references drawn as chips.
    ///
    /// A run can carry a background and a link but not a corner radius, so the
    /// thin spaces stand in for the padding a drawn chip would have. Anything
    /// the format degrades — a kind this build has never heard of, a legacy
    /// console path — never reaches here as a reference at all: `RecordRefs`
    /// has already turned it into the words it says.
    private var attributedBody: AttributedString {
        var out = AttributedString("")
        for part in RecordRefs.parts(message.body) {
            switch part {
            case .text(let value):
                out.append(AttributedString(value))
            case .reference(let ref):
                var chip = AttributedString("\u{2009}\(ref.label)\u{2009}")
                chip.font = CalibreType.bodySemiBold
                chip.foregroundColor = isCustomer ? Color.calibre.primaryForeground : Color.calibre.foreground
                chip.backgroundColor = isCustomer
                    ? Color.calibre.primaryForeground.opacity(0.22)
                    : Color.calibre.primary.opacity(0.14)
                chip.link = ref.route
                out.append(chip)
            }
        }
        return out
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


/// The customer's own orders and live listings, to name one in a message.
///
/// Everything offered here is scoped to the signed-in customer by the server:
/// `/buyer/orders` filters on `buyer_id`, `/account/listings` on `seller_id`,
/// and the live filter is applied on top. There is no path from this screen to
/// anybody else's record, which is the point — this runs on a customer's phone.
private struct RecordPickerSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let onPick: (RecordRefOption) -> Void

    @State private var query = ""
    @State private var options: [RecordRefOption] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Text(errorText)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(options) { option in
                    Button {
                        onPick(option)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.ref.label)
                                .font(CalibreType.body)
                                .foregroundStyle(Color.calibre.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = option.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(CalibreType.caption)
                                    .foregroundStyle(Color.calibre.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if options.isEmpty && !loading && errorText == nil {
                    Text("Your own orders and live listings are what can be named here — nothing matches that yet.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search your orders and listings")
            .navigationTitle("Link a record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if loading && options.isEmpty {
                    ProgressView().tint(Color.calibre.primary)
                }
            }
        }
        .task(id: query) {
            // A keystroke is not a query. The pause is what keeps a search of
            // somebody's whole order history off every letter they type.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            options = try await services.support.linkableRecords(query: query)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn\u{2019}t load your records."
        }
    }
}
