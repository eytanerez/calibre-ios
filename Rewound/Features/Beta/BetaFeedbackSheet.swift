import CalibreDesign
import CalibreKit
import PhotosUI
import SwiftUI

/// The survey, in the app.
///
/// Every question it draws comes from the server. There is no list of questions
/// in this file and there must never be one — the website, this app and the
/// server's own validator all read one catalogue
/// (`Backend/app/services/beta_program.py`), which is what stops an option
/// reworded on the site and still shipping in a TestFlight build from producing
/// two answers to one question that can never be counted together.
struct BetaFeedbackSheet: View {
    @Environment(BetaStore.self) private var beta
    @Environment(\.dismiss) private var dismiss

    @State private var kind: String?
    @State private var answers: [String: BetaAnswer] = [:]
    @State private var attachments: [BetaAttachment] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    private var sections: [BetaSection] {
        guard let kind, let form = beta.config.form else { return [] }
        return form.sections[kind] ?? []
    }

    private var canSend: Bool {
        kind != nil && BetaStore.hasAnyAnswer(answers) && !isSending
    }

    var body: some View {
        NavigationStack {
            Group {
                if sent {
                    sentView
                } else if kind == nil {
                    doorPicker
                } else {
                    questionsView
                }
            }
            .background(Color.calibre.background)
            .navigationTitle("Beta feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if kind != nil && !sent {
                        Button("Back") { kind = nil }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - The first question

    private var doorPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                if let form = beta.config.form {
                    Text(form.kindQuestion)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)

                    ForEach(form.kinds) { choice in
                        Button {
                            kind = choice.value
                            prefillDeviceAndBrowser()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.label)
                                    .font(CalibreType.bodySemiBold)
                                    .foregroundStyle(Color.calibre.foreground)
                                if let description = choice.description {
                                    Text(description)
                                        .font(CalibreType.caption)
                                        .foregroundStyle(Color.calibre.mutedForeground)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.m)
                            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.box)
                                    .stroke(Color.calibre.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.margin)
        }
    }

    // MARK: - The questions

    private var questionsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    ForEach(sections) { section in
                        let visible = BetaStore.visibleQuestions(in: section, answers: answers)
                        // A section whose every question is conditional and
                        // currently hidden must not leave a heading over
                        // nothing.
                        if !visible.isEmpty {
                            VStack(alignment: .leading, spacing: Space.l) {
                                Text(section.title.uppercased())
                                    .font(CalibreType.eyebrow)
                                    .tracking(CalibreType.eyebrowTracking)
                                    .foregroundStyle(Color.calibre.mutedForeground)

                                ForEach(visible) { question in
                                    BetaQuestionRow(
                                        question: question,
                                        answer: binding(for: question.id),
                                        attachments: $attachments
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(Space.margin)
                .padding(.bottom, Space.xxl)
            }

            VStack(spacing: Space.s) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(isSending ? "Sending…" : "Send feedback") { send() }
                    .buttonStyle(.calibrePrimary)
                    .frame(maxWidth: .infinity)
                    .disabled(!canSend)
                if !BetaStore.hasAnyAnswer(answers) {
                    Text("Answer at least one question to send.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            .padding(Space.margin)
            .background(Color.calibre.card)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.calibre.border).frame(height: 1)
            }
        }
    }

    private var sentView: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.calibre.success)
            Text("That is with us")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            Text("We read every one of these. Thank you for taking the time.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Send something else") {
                sent = false
                kind = nil
            }
            .buttonStyle(.calibreGhost)
        }
        .padding(Space.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Plumbing

    private func binding(for id: String) -> Binding<BetaAnswer?> {
        Binding(
            get: { answers[id] },
            set: { newValue in
                if let newValue, !newValue.isEmpty {
                    answers[id] = newValue
                } else {
                    answers.removeValue(forKey: id)
                }
            }
        )
    }

    /// The two questions the device already knows the answer to.
    ///
    /// Only where they are still unanswered: a tester who corrected one and
    /// then went back to change the door must not have their correction
    /// overwritten.
    private func prefillDeviceAndBrowser() {
        let idiom = UIDevice.current.userInterfaceIdiom
        if answers["bug_device"] == nil {
            answers["bug_device"] = .text(idiom == .pad ? "ipad_tablet" : "iphone")
        }
        if answers["bug_browser"] == nil {
            // Not a browser at all. The catalogue offers "Calibre iOS app" for
            // exactly this, and it is the true answer.
            answers["bug_browser"] = .text("calibre_ios_app")
        }
    }

    private func send() {
        guard let kind else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                _ = try await beta.submit(
                    kind: kind,
                    answers: answers,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                )
                Haptics.shared.play(.success)
                sent = true
                answers = [:]
                attachments = []
                self.kind = nil
            } catch {
                errorMessage = "That could not be sent. Please try again."
            }
            isSending = false
        }
    }
}

// MARK: - One question, of whatever shape

private struct BetaQuestionRow: View {
    let question: BetaQuestion
    @Binding var answer: BetaAnswer?
    @Binding var attachments: [BetaAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(question.prompt)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if let help = question.help {
                Text(help)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }

            switch BetaAnswerKind(question.type) {
            case .single:
                SingleChoice(question: question, answer: $answer)
            case .multi:
                MultiChoice(question: question, answer: $answer)
            case .scale:
                ScaleChoice(question: question, answer: $answer)
            case .matrix:
                MatrixChoice(question: question, answer: $answer)
            case .files:
                FilePicker(answer: $answer, attachments: $attachments)
            case .longtext:
                // The label is empty because the prompt above already IS the
                // label; passing the question again would print it twice.
                CalibreTextEditor("", text: textBinding)
            case .text, .email:
                CalibreTextField("", text: textBinding)
                    .keyboardType(BetaAnswerKind(question.type) == .email ? .emailAddress : .default)
                    .textInputAutocapitalization(
                        BetaAnswerKind(question.type) == .email ? .never : .sentences
                    )
            case .unsupported:
                // A question type added to the catalogue after this build
                // shipped. Named rather than silently skipped, so a tester who
                // sees a gap knows it is not their app failing to draw
                // something — and so nobody reads its absence as an answer.
                Text("This question needs a newer version of the app.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: {
                if case .text(let value) = answer { return value }
                return ""
            },
            set: { answer = $0.isEmpty ? nil : .text($0) }
        )
    }
}

private struct ChoiceChip: View {
    let label: String
    let isOn: Bool
    let isBlocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(CalibreType.label)
                .foregroundStyle(isOn ? Color.calibre.primaryForeground : Color.calibre.foreground)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(
                    Capsule().fill(isOn ? Color.calibre.primary : Color.calibre.card)
                )
                .overlay(
                    Capsule().stroke(
                        isOn ? Color.calibre.primary : Color.calibre.border,
                        lineWidth: 1
                    )
                )
                .opacity(isBlocked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

private struct SingleChoice: View {
    let question: BetaQuestion
    @Binding var answer: BetaAnswer?

    var body: some View {
        FlowRow(spacing: Space.s) {
            ForEach(question.options ?? []) { option in
                let isOn = answer == .text(option.value)
                ChoiceChip(label: option.label, isOn: isOn, isBlocked: false) {
                    // Tapping the chosen one again clears it. Every question is
                    // optional, so a stray tap needs a way back to having said
                    // nothing — otherwise the only way out is a different wrong
                    // answer.
                    answer = isOn ? nil : .text(option.value)
                }
            }
        }
    }
}

private struct MultiChoice: View {
    let question: BetaQuestion
    @Binding var answer: BetaAnswer?

    private var selected: [String] {
        if case .choices(let values) = answer { return values }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            FlowRow(spacing: Space.s) {
                ForEach(question.options ?? []) { option in
                    let isOn = selected.contains(option.value)
                    let atCeiling = question.maxSelect.map { selected.count >= $0 } ?? false
                    ChoiceChip(label: option.label, isOn: isOn, isBlocked: atCeiling && !isOn) {
                        var next = selected
                        if isOn {
                            next.removeAll { $0 == option.value }
                        } else {
                            next.append(option.value)
                        }
                        answer = next.isEmpty ? nil : .choices(next)
                    }
                }
            }
            if let ceiling = question.maxSelect {
                Text("\(selected.count) of \(ceiling) chosen")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
    }
}

private struct ScaleChoice: View {
    let question: BetaQuestion
    @Binding var answer: BetaAnswer?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            FlowRow(spacing: Space.xs) {
                ForEach(Array(stride(from: question.min ?? 1, through: question.max ?? 10, by: 1)), id: \.self) { step in
                    let isOn = answer == .number(step)
                    Button {
                        answer = isOn ? nil : .number(step)
                    } label: {
                        Text("\(step)")
                            .font(CalibreType.label)
                            .monospacedDigit()
                            .foregroundStyle(isOn ? Color.calibre.primaryForeground : Color.calibre.foreground)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.control)
                                    .fill(isOn ? Color.calibre.primary : Color.calibre.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.control)
                                    .stroke(isOn ? Color.calibre.primary : Color.calibre.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            if question.minLabel != nil || question.maxLabel != nil {
                HStack {
                    Text(question.minLabel ?? "")
                    Spacer()
                    Text(question.maxLabel ?? "")
                }
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
    }
}

private struct MatrixChoice: View {
    let question: BetaQuestion
    @Binding var answer: BetaAnswer?

    private var values: [String: String] {
        if case .matrix(let map) = answer { return map }
        return [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(question.rows ?? []) { row in
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(row.label)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.foreground)
                    FlowRow(spacing: Space.xs) {
                        ForEach(question.options ?? []) { option in
                            let isOn = values[row.value] == option.value
                            ChoiceChip(label: option.label, isOn: isOn, isBlocked: false) {
                                var next = values
                                if isOn {
                                    next.removeValue(forKey: row.value)
                                } else {
                                    next[row.value] = option.value
                                }
                                answer = next.isEmpty ? nil : .matrix(next)
                            }
                        }
                    }
                }
                .padding(Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box))
            }
        }
    }
}

private struct FilePicker: View {
    @Environment(BetaStore.self) private var beta
    @Binding var answer: BetaAnswer?
    @Binding var attachments: [BetaAttachment]

    @State private var picked: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PhotosPicker(
                selection: $picked,
                maxSelectionCount: 5,
                matching: .any(of: [.images, .videos])
            ) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "paperclip").font(.caption)
                    Text(isUploading ? "Uploading…" : "Choose from your photos")
                        .font(CalibreType.label)
                }
                .foregroundStyle(Color.calibre.foreground)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(Capsule().fill(Color.calibre.card))
                .overlay(Capsule().stroke(Color.calibre.border, lineWidth: 1))
            }
            .disabled(isUploading)

            ForEach(attachments) { attachment in
                HStack {
                    Text(attachment.filename)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                        answer = attachments.isEmpty ? nil : .choices(attachments.map(\.id))
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(attachment.filename)")
                }
                .padding(.horizontal, Space.s)
                .padding(.vertical, 6)
                .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.control))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.destructive)
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            upload(items)
        }
    }

    private func upload(_ items: [PhotosPickerItem]) {
        isUploading = true
        errorMessage = nil
        Task {
            // One at a time rather than in parallel: refusals are per file, so
            // a tester who picked one screenshot and one very long recording
            // keeps the screenshot and is told about the recording.
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let type = item.supportedContentTypes.first
                    let mime = type?.preferredMIMEType ?? "image/jpeg"
                    let ext = type?.preferredFilenameExtension ?? "jpg"
                    let uploaded = try await beta.upload(
                        filename: "beta-\(UUID().uuidString.prefix(8)).\(ext)",
                        contentType: mime,
                        data: data
                    )
                    attachments.append(uploaded)
                } catch {
                    errorMessage = "One of those could not be attached."
                }
            }
            answer = attachments.isEmpty ? nil : .choices(attachments.map(\.id))
            picked = []
            isUploading = false
        }
    }
}

/// Chips that wrap, which `HStack` does not do.
///
/// A survey of forty questions has option sets of fifteen words; laid out in an
/// HStack they compress to illegibility, and in a horizontal ScrollView the ones
/// past the edge are never seen — which silently biases every answer toward the
/// first four options.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
