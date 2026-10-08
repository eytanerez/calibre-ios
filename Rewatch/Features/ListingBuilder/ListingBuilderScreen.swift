import RewatchDesign
import RewatchKit
import SwiftUI

/// "List a watch" in the app: the site's listing builder at phone width, one
/// question per screen, with what an app adds: a haptic on each answer, the
/// keyboard's Next and Done walking the required fields, the native photo
/// picker and the camera, and photos that keep uploading in the background.
///
/// Presented full screen from the seller dashboard (behind the same seller
/// setup gate as before) for a new listing or a draft to finish. Editing a
/// listed watch stays on `ListingWizardScreen`.
struct ListingBuilderCover: View {
    let kind: BuilderKind
    let onFinished: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts
    @State private var model: ListingBuilderModel?

    var body: some View {
        Group {
            if let model {
                ListingBuilderScreen(model: model, onFinished: onFinished) { title, message in
                    toasts.show(title: title, message: message)
                }
            } else {
                Color.rewatch.background
                    .onAppear {
                        model = ListingBuilderModel(
                            kind: kind,
                            backend: LiveListingBuilderBackend(services: services, sell: sell)
                        )
                    }
            }
        }
        .rewatchPageBackground()
    }
}

struct ListingBuilderScreen: View {
    @Bindable var model: ListingBuilderModel
    let onFinished: () -> Void
    var toast: (String, String) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: BuilderField?
    @State private var showsCloseDialog = false
    @State private var showsSuccess = false
    @State private var closing = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressLine
            if model.step == .review {
                reviewBody
            } else {
                questionBody
            }
        }
        .background(Color.rewatch.background.ignoresSafeArea())
        .task { await model.start() }
        .interactiveDismissDisabled()
        .a11yCoveredBy(showsSuccess)
        .overlay {
            if showsSuccess { successMoment }
        }
        .confirmationDialog("Keep this listing as a draft?", isPresented: $showsCloseDialog, titleVisibility: .visible) {
            Button("Save draft") { Task { await saveAndClose() } }
            Button("Discard", role: .destructive) { finish(saved: false) }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("A draft waits on your storefront, photos and all, until you finish it.")
        }
        .onChange(of: model.step) { _, step in
            focus = nil
            if step == .watch, model.answers.brand.isEmpty {
                focus = .brand
            }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Space.m) {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.rewatch.foreground)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(closing || model.isSubmitting)
            .accessibilityLabel(model.listingID != nil ? "Close. Your draft is saved." : "Close")

            if model.step != .watch, !model.isSubmitting {
                Button {
                    Haptics.shared.play(.selection)
                    withAnimation(transition) { model.back() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text(model.step.previous.label)
                            .font(RewatchType.bodySemiBold)
                    }
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .frame(minHeight: Space.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to \(model.step.previous.label)")
                .transition(.opacity)
            }

            Spacer(minLength: Space.s)

            // The draft is kept: the crown winds, as it did on the old form.
            if let listingID = model.listingID, model.mode == .live {
                RewatchMark.crown(size: 28, trigger: "listing-draft:\(listingID)")
                    .markAnnounces("listing-draft:\(listingID)")
            }

            Text(model.step == .review ? "Review" : "\(model.step.index + 1) of \(BuilderStep.questionCount)")
                .font(RewatchType.label)
                .monospacedDigit()
                .foregroundStyle(Color.rewatch.mutedForeground)
                .contentTransition(.numericText(value: Double(model.step.index)))
                .animation(Motion.easeMedium, value: model.step)
        }
        .padding(.leading, Space.margin - 12)
        .padding(.trailing, Space.margin)
        .padding(.top, Space.xs)
        .animation(Motion.easeFast, value: model.step == .watch)
    }

    /// A copper hairline across the top, filling as the questions go.
    private var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.rewatch.border)
                Rectangle()
                    .fill(Color.rewatch.primary)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 1.5)
        .animation(reduceMotion ? nil : Motion.ease(0.7), value: progress)
        .accessibilityHidden(true)
    }

    private var progress: CGFloat {
        if showsSuccess || model.submitted { return 1 }
        return min(CGFloat(model.step.index) / CGFloat(BuilderStep.questionCount), 1)
    }

    private var transition: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .builderRise
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .offset(y: -8))
        )
    }

    // MARK: A question

    /// The first visit to the first question: it owns the screen, centred.
    private var alone: Bool { model.step == .watch && model.reached == 0 }

    private var context: BuilderStepContext {
        BuilderStepContext(
            model: model,
            focus: $focus,
            advance: { advance() },
            advanceLater: { step, milliseconds in
                Task {
                    try? await Task.sleep(for: .milliseconds(milliseconds))
                    guard model.step == step else { return }
                    advance()
                }
            },
            alone: alone
        )
    }

    private var questionBody: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        question
                            .id(model.step)
                            .transition(stepTransition)
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.top, alone ? 0 : Space.l)
                    .padding(.bottom, Space.xxl)
                    .frame(minHeight: alone ? proxy.size.height : nil, alignment: alone ? .center : .top)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.step) { _, _ in
                    scroller.scrollTo("top", anchor: .top)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { continueBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(keyboardActionTitle) { keyboardAction() }
                    .font(RewatchType.bodySemiBold)
                    .foregroundStyle(Color.rewatch.primaryDeep)
            }
        }
    }

    private var question: some View {
        let copy = model.step.question
        return VStack(alignment: .leading, spacing: 0) {
            // The encouraging line, or, when the server refused something on
            // this step, the refusal in its own words where the fix is.
            Group {
                if let error = model.sendError, error.step == model.step {
                    Text(error.message)
                        .foregroundStyle(Color.rewatch.destructive)
                } else {
                    Text(model.line)
                        .foregroundStyle(Color.rewatch.primaryDeep)
                }
            }
            .font(RewatchType.bodySemiBold)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(LineEntrance(key: model.line + (model.sendError?.message ?? "")))

            Text(copy.title)
                .font(alone ? RewatchType.serif(.semiBold, 34, relativeTo: .largeTitle) : RewatchType.serif(.semiBold, 27, relativeTo: .title))
                .foregroundStyle(Color.rewatch.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
                .accessibilityAddTraits(.isHeader)
            Text(copy.help)
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)

            stepView
                .padding(.top, Space.xl)

            if model.step == .price, let note = backgroundNote {
                Text(note)
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.m)
            }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .watch: BuilderWatchStep(context: context)
        case .year: BuilderYearStep(context: context)
        case .condition: BuilderConditionStep(context: context)
        case .box: BuilderBoxStep(context: context)
        case .history: BuilderHistoryStep(context: context)
        case .photos: BuilderPhotosStep(context: context)
        case .price: BuilderPriceStep(context: context)
        case .returns: BuilderReturnsStep(context: context)
        case .review: EmptyView()
        }
    }

    /// What the photos are doing while the seller prices the watch.
    private var backgroundNote: String? {
        if let error = model.photoSyncError {
            return "Your photos haven\u{2019}t gone up yet: \(error) They are tried again when you approve."
        }
        guard let progress = model.uploadProgress, progress.done < progress.total else { return nil }
        return "Uploading your photos in the background, \(progress.done) of \(progress.total) done."
    }

    private var continueBar: some View {
        let ready = model.canContinueHere
        return VStack(spacing: 0) {
            Rectangle().fill(Color.rewatch.border).frame(height: 1)
            Button {
                advance()
            } label: {
                Text(model.returnTo == .review ? "Back to review" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.rewatch(.primary, fullWidth: true))
            .disabled(!ready)
            .opacity(ready ? 1 : 0.55)
            .animation(Motion.easeFast, value: ready)
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.m)
            .accessibilityIdentifier("builder.continue")
        }
        .background(Color.rewatch.background)
    }

    private func advance() {
        let wasPhotos = model.step == .photos
        let moved = withAnimation(transition) { model.advance() }
        if moved {
            Haptics.shared.play(wasPhotos ? .save : .press)
            A11y.screenChanged(model.step.question.title)
        } else {
            Haptics.shared.play(.error)
        }
    }

    // MARK: The keyboard's own key

    private var keyboardActionTitle: String {
        switch focus {
        case .year: BuilderRules.yearIsValid(model.answers.year, currentYear: model.currentYear) ? "Next" : "Done"
        case .serviceYear: "Next"
        case .price: model.canContinue(.price) ? "Continue" : "Done"
        case .sellerNotes, .note: "Done"
        default: "Done"
        }
    }

    /// The number pads have no return key, so Next and Done live here: the
    /// year moves on to the stock number, the price to Continue.
    private func keyboardAction() {
        switch focus {
        case .year where BuilderRules.yearIsValid(model.answers.year, currentYear: model.currentYear):
            focus = .sku
        case .serviceYear:
            focus = nil
            if model.answers.serviceYear.isEmpty || BuilderRules.serviceYearProblem(model.answers.serviceYear, currentYear: model.currentYear) == nil {
                advance()
            }
        case .price where model.canContinue(.price):
            focus = nil
            advance()
        default:
            focus = nil
        }
    }

    // MARK: The review

    private var reviewBody: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(model.line)
                            .font(RewatchType.bodySemiBold)
                            .foregroundStyle(Color.rewatch.primaryDeep)
                            .modifier(LineEntrance(key: model.line))
                        Text(model.step.question.title)
                            .font(RewatchType.serif(.semiBold, 27, relativeTo: .title))
                            .foregroundStyle(Color.rewatch.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Text(model.step.question.help)
                            .font(RewatchType.body)
                            .foregroundStyle(Color.rewatch.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .id("top")
                    BuilderReviewStep(model: model, onApprove: approve)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxl)
                .transition(stepTransition)
            }
            .onAppear {
                scroller.scrollTo("top", anchor: .top)
                #if DEBUG
                // The preview harness's way to look at the bottom of the page
                // and at the approve itself without a finger on the glass.
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-listingBuilderReviewBottom") {
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        withAnimation { scroller.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                if arguments.contains("-listingBuilderAutoApprove") {
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        approve()
                    }
                }
                #endif
            }
        }
        .safeAreaInset(edge: .bottom) {
            BuilderApproveBar(model: model, onApprove: approve)
        }
    }

    private func approve() {
        Haptics.shared.play(.press)
        focus = nil
        Task {
            let done = await model.submit()
            if done {
                Haptics.shared.play(.success)
                RewatchMoments.play(.listingSubmitted)
                withAnimation(Motion.easeSlow) { showsSuccess = true }
                A11y.screenChanged("In review. We'll let you know the moment it's live.")
                try? await Task.sleep(for: .seconds(A11y.isNavigatingByFocus ? 8 : RewatchMoment.listingSubmitted.duration + 0.2))
                finish(saved: false)
            } else {
                Haptics.shared.play(.error)
                if let error = model.sendError { A11y.announce(error.message, priority: .high) }
            }
        }
    }

    // MARK: Closing

    private func close() {
        focus = nil
        if model.listingID != nil {
            Task { await saveAndClose() }
        } else if model.canSaveDraft, model.mode == .live {
            showsCloseDialog = true
        } else {
            finish(saved: false)
        }
    }

    private func saveAndClose() async {
        closing = true
        defer { closing = false }
        let saved = await model.saveDraft()
        if saved {
            toast("Draft saved", "Pick it back up any time from your storefront. Photos keep uploading.")
            finish(saved: true)
        } else {
            toast("Draft not saved", model.photoSyncError ?? "Check your connection and try again.")
        }
    }

    private func finish(saved: Bool) {
        dismiss()
        onFinished()
    }

    // MARK: The finish moment

    private var successMoment: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.rewatch.success)
            Text("In review.")
                .font(RewatchType.display)
                .foregroundStyle(Color.rewatch.foreground)
            Text("We'll let you know the moment it's live.")
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.mutedForeground)
        }
        .multilineTextAlignment(.center)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rewatchPageBackground()
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

/// The encouraging line arriving: a short rise out of a blur (the site's
/// `lb-line`). Plain under Reduce Motion.
private struct LineEntrance: ViewModifier {
    let key: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .blur(radius: shown || reduceMotion ? 0 : 3)
            .onChange(of: key, initial: true) { _, _ in
                guard !reduceMotion else {
                    shown = true
                    return
                }
                shown = false
                withAnimation(Motion.ease(0.52).delay(0.12)) { shown = true }
            }
    }
}
