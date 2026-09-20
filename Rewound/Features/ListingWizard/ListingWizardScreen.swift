import RewoundDesign
import RewoundKit
import SwiftUI

/// The camera-first listing wizard — Details → Photos → Price → Review, one
/// full-screen cover. Draft-first: the server listing exists from the moment
/// the wizard opens, and every edit lands on it debounced.
struct ListingWizardScreen: View {
    let context: WizardContext
    let onFinished: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: WizardModel?
    @State private var showSuccess = false
    @State private var creatingDraft = false
    /// Set when Continue is pressed on an incomplete step, to bring the first
    /// offending field into view.
    @State private var scrollTarget: WizardField?
    /// The last step the draft was kept on the way to — the crown's fact.
    /// Nil until the first forward step with a draft on the server.
    @State private var draftMarkKey: String?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.rewound.background
                        .onAppear { createModel() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rewoundPageBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeKeepingDraft()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.rewound.foreground)
                    }
                    // The promise is conditional, so the label has to be too.
                    // `persistSnapshot()` opens with `guard let listing`, and
                    // no server draft exists until `createDraftIfNeeded()`
                    // runs on step 0 → 1 — so on the Details step there is
                    // nothing to save and closing throws the form away. The
                    // toast beneath already knows this and stays silent;
                    // the label announced "your draft is saved" regardless,
                    // which is the one sentence a VoiceOver seller would act
                    // on before losing a brand, a reference, a year and five
                    // condition grades.
                    .accessibilityLabel(hasSavedDraft ? "Close — your draft is saved" : "Close")
                }
                ToolbarItem(placement: .principal) {
                    Eyebrow(headline)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        // The success cover is opaque pixels and nothing more: without this
        // the wizard underneath it stays fully readable, so a screen-reader
        // seller is still swiping through Continue and the price field while
        // the app says the listing is in review.
        .a11yCoveredBy(showSuccess)
        .overlay {
            if showSuccess {
                successMoment
            }
        }
    }

    private var headline: String {
        switch context.kind {
        case .new: "New listing"
        case .finishDraft: "Finish your draft"
        case .edit: "Edit listing"
        }
    }

    private func createModel() {
        // No commission rate is passed in — what the seller keeps, what the
        // buyer sees, and every figure between them come from the server's
        // publish preview.
        let created = WizardModel(
            kind: context.kind,
            seller: services.seller,
            sell: sell,
            config: services.config,
            vault: services.vault
        )
        model = created
        Task { await created.start() }
    }

    @ViewBuilder
    private func content(_ model: WizardModel) -> some View {
        switch model.bootstrap {
        case .working:
            wizardSkeleton
        case .failed(let message):
            EmptyState(
                icon: "square.and.pencil",
                title: "We couldn't open your draft",
                message: message,
                actionTitle: "Try again",
                action: { Task { await model.start() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: Space.m) {
                    ProgressCheckpoints(steps: WizardModel.stepTitles, currentIndex: model.step)
                    // The draft was kept on the way to this step: the crown
                    // winds beside the rail that shows which step. Keyed to
                    // the draft and the step it was kept at (`advance`), so
                    // a re-render leaves it caught on its detent and going
                    // back is not news; announced once per session per key.
                    // Nothing until the first advance has a draft to keep —
                    // no server draft exists before Details is completed.
                    // The rail's captions are the words; the mark has none.
                    if let draftMarkKey {
                        RewoundMark.crown(size: 36, trigger: draftMarkKey)
                            .markAnnounces(draftMarkKey)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)

                ScrollViewReader { proxy in
                    ScrollView {
                        stepBody(model)
                            .padding(.horizontal, Space.margin)
                            .padding(.top, Space.l)
                            .padding(.bottom, Space.xxl)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // A buyer who scrolled down reading step 1 used to land
                    // mid-page on step 2 — `advance(_:to:)` moved `model.step`
                    // but nothing ever moved the scroll offset back with it.
                    // `stepBody(model)` already carries `.id(model.step)`, so
                    // the step itself is the anchor: no separate marker to add
                    // or keep in sync with a fourth step down the line.
                    //
                    // This fires on every step change, forward (Continue) and
                    // back (Back) alike — `advance(_:to:)` is the only place
                    // `model.step` is ever written. It does not fire on a
                    // validation failure, because `continueTapped` returns
                    // before calling `advance` when the step is incomplete,
                    // so `model.step` never changes and the `scrollTarget`
                    // scroll-to-first-invalid-field below still wins.
                    .onChange(of: model.step) { _, step in
                        withAnimation(Motion.easeMedium) {
                            proxy.scrollTo(step, anchor: .top)
                        }
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(Motion.easeMedium) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        scrollTarget = nil
                    }
                }

                stepBar(model)
            }
        }
    }

    @ViewBuilder
    private func stepBody(_ model: WizardModel) -> some View {
        Group {
            switch model.step {
            case 0: DetailsStep(model: model)
            case 1: PhotosStep(model: model)
            case 2: PriceStep(model: model)
            default: ReviewStep(model: model, onSubmit: { submit(model) })
            }
        }
        .id(model.step)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
    }

    /// Back / Continue. The Review step owns its own submit button.
    @ViewBuilder
    private func stepBar(_ model: WizardModel) -> some View {
        if model.step < 3 {
            HStack(spacing: Space.m) {
                if model.step > 0 {
                    Button("Back") {
                        advance(model, to: model.step - 1)
                    }
                    .buttonStyle(.rewoundGhost)
                }
                // Always tappable: pressing it on an incomplete step is how a
                // seller asks what's missing, and the answer belongs beside
                // each field rather than in a list down here.
                Button {
                    continueTapped(model)
                } label: {
                    BusyLabel(title: "Continue", busy: creatingDraft)
                }
                .buttonStyle(.rewound(.primary, fullWidth: true))
                .disabled(creatingDraft)
                .accessibilityIdentifier("listing-wizard-continue")
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.m)
            .background(Color.rewound.background)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.rewound.border).frame(height: 1)
            }
        } else {
            HStack(spacing: Space.m) {
                Button("Back") {
                    advance(model, to: 2)
                }
                .buttonStyle(.rewoundGhost)
                Spacer()
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s)
        }
    }

    private func canContinue(_ model: WizardModel) -> Bool {
        switch model.step {
        case 0: model.detailsComplete
        case 2: model.priceDetailsComplete
        default: true
        }
    }

    private func continueTapped(_ model: WizardModel) {
        // Incomplete step: light up the offending fields, scroll to the first
        // one, and stay put.
        guard canContinue(model) else {
            withAnimation(Motion.easeFast) {
                model.markAttempted(model.step)
            }
            let firstInvalid = model.firstInvalidField(onStep: model.step)
            scrollTarget = firstInvalid
            announceFirstError(firstInvalid, on: model)
            Haptics.shared.play(.error)
            return
        }

        guard model.step == 0 else {
            advance(model, to: model.step + 1)
            return
        }
        // Step 0 → 1 is where the server draft is actually created — see
        // `createDraftIfNeeded()`.
        Task {
            creatingDraft = true
            defer { creatingDraft = false }
            guard await model.createDraftIfNeeded() else { return }
            advance(model, to: 1)
        }
    }

    /// The first thing Continue refused over, spoken.
    ///
    /// Every message lands beside its own field, which is exactly where a
    /// screen reader's cursor is not — scrolling moves the eye, not the
    /// focus. Without this, pressing Continue on an incomplete step is a
    /// button that does nothing at all. Silent when nothing is listening.
    private func announceFirstError(_ field: WizardField?, on model: WizardModel) {
        guard let field else { return }
        let message: String? = switch field {
        case .brand: model.brandError
        case .year: model.yearFieldError
        case .condition(let part): model.conditionError(part).map { "\(part.label). \($0)" }
        case .price: model.priceFieldError
        }
        if let message { A11y.announce(message, priority: .high) }
    }

    private func advance(_ model: WizardModel, to step: Int) {
        let from = model.step
        let to = min(max(step, 0), 3)
        withAnimation(Motion.easeMedium) {
            model.step = to
        }
        model.fieldChanged()
        // Forward, with a draft on the server to keep: the fact the crown
        // winds on. Back is not an advance and a draft that does not exist
        // yet cannot have been kept.
        if to > from, let listingID = model.listing?.id {
            draftMarkKey = "listing-draft:\(listingID):\(to)"
        }
    }

    private func submit(_ model: WizardModel) {
        Task {
            if await model.submit() {
                Haptics.shared.play(.success)
                // The form gathers up and the seal presses onto it. What
                // collapses is the seller's own filled-in wizard.
                RewoundMoments.play(.listingSubmitted)
                withAnimation(Motion.easeSlow) {
                    showSuccess = true
                }
                // The cover replaces the wizard outright, which is a screen
                // change nothing else announces.
                A11y.screenChanged("In review. We'll let you know the moment it's live.")
                // Two seconds is a glance to read and most of a sentence to
                // hear: on the timer a screen-reader seller loses the only
                // confirmation the submit ever gets. Nothing is waiting on
                // this — the listing is already in.
                try? await Task.sleep(
                    for: .seconds(
                        A11y.isNavigatingByFocus ? 8 : RewoundMoment.listingSubmitted.duration + 0.2
                    )
                )
                dismiss()
                onFinished()
            }
        }
    }

    /// Whether closing now would actually keep anything. False until the
    /// Details step is completed, because that is when the server draft
    /// `persistSnapshot()` requires is created.
    private var hasSavedDraft: Bool {
        model?.listing != nil
    }

    private func closeKeepingDraft() {
        model?.persistSnapshot()
        // Nothing to save yet if Details was never completed — no server
        // draft exists until `createDraftIfNeeded()` runs on step 0 → 1.
        let hasDraft = hasSavedDraft
        dismiss()
        if hasDraft, model?.submitted != true, model?.isEdit != true {
            toasts.show(
                title: "Draft saved",
                message: "Pick it back up any time from your storefront."
            )
        }
        onFinished()
    }

    // MARK: - Success moment

    private var successMoment: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.rewound.success)
            Text("In review.")
                .font(RewoundType.display)
                .foregroundStyle(Color.rewound.foreground)
            Text("We'll let you know the moment it's live.")
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.mutedForeground)
        }
        .multilineTextAlignment(.center)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rewoundPageBackground()
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    private var wizardSkeleton: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Rectangle().frame(maxWidth: .infinity).frame(height: 12).shimmer()
            ForEach(0..<4, id: \.self) { _ in
                Rectangle().frame(maxWidth: .infinity).frame(height: 48).shimmer()
            }
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.xl)
    }
}
