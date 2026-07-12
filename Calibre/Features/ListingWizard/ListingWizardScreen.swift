import CalibreDesign
import CalibreKit
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

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.calibre.background
                        .onAppear { createModel() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.calibre.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeKeepingDraft()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .accessibilityLabel("Close — your draft is saved")
                }
                ToolbarItem(placement: .principal) {
                    Eyebrow(headline)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
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
        let feePercent = services.seller.dashboard?.dealer?.currentFeePercent.value ?? Decimal(8)
        let created = WizardModel(
            kind: context.kind,
            seller: services.seller,
            sell: sell,
            feePercent: feePercent
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
                ProgressCheckpoints(steps: WizardModel.stepTitles, currentIndex: model.step)
                    .padding(.horizontal, Space.margin)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.s)

                ScrollView {
                    stepBody(model)
                        .padding(.horizontal, Space.margin)
                        .padding(.top, Space.l)
                        .padding(.bottom, Space.xxl)
                }
                .scrollDismissesKeyboard(.interactively)

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
                    .buttonStyle(.calibreGhost)
                }
                Button("Continue") {
                    advance(model, to: model.step + 1)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.step == 0 && model.brand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.m)
            .background(Color.calibre.background)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.calibre.border).frame(height: 1)
            }
        } else {
            HStack(spacing: Space.m) {
                Button("Back") {
                    advance(model, to: 2)
                }
                .buttonStyle(.calibreGhost)
                Spacer()
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s)
        }
    }

    private func advance(_ model: WizardModel, to step: Int) {
        withAnimation(Motion.easeMedium) {
            model.step = min(max(step, 0), 3)
        }
        model.fieldChanged()
    }

    private func submit(_ model: WizardModel) {
        Task {
            if await model.submit() {
                Haptics.shared.play(.success)
                withAnimation(Motion.easeSlow) {
                    showSuccess = true
                }
                try? await Task.sleep(for: .seconds(2))
                dismiss()
                onFinished()
            }
        }
    }

    private func closeKeepingDraft() {
        model?.persistSnapshot()
        dismiss()
        if model?.submitted != true, model?.isEdit != true {
            toasts.show(
                title: "Draft saved",
                message: "Pick it back up any time from your shop."
            )
        }
        onFinished()
    }

    // MARK: - Success moment

    private var successMoment: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.calibre.success)
            Text("In review.")
                .font(CalibreType.display)
                .foregroundStyle(Color.calibre.foreground)
            Text("We'll let you know the moment it's live.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .multilineTextAlignment(.center)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .transition(.opacity)
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
