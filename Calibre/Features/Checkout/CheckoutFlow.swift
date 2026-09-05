import CalibreDesign
import CalibreKit
import SwiftUI

/// The checkout cover — three unhurried steps (Shipping → Payment → Review,
/// or wire instructions) in one NavigationStack, ending in the success
/// moment. Present as a fullScreenCover from the router's checkout request.
///
/// A checkout covers a set of watches: one payment, one order each. Buying a
/// single watch is a set of one, so nothing below has two shapes.
struct CheckoutFlow: View {
    let listingIDs: [String]
    let offerID: String?

    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model: CheckoutModel?

    init(listingIDs: [String], offerID: String? = nil) {
        self.listingIDs = listingIDs
        self.offerID = offerID
    }

    init(listingID: String, offerID: String? = nil) {
        self.init(listingIDs: [listingID], offerID: offerID)
    }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                guestGate
            } else if let model {
                CheckoutStack(model: model)
            } else {
                Color.calibre.background.ignoresSafeArea()
            }
        }
        .task {
            guard session.isAuthenticated, model == nil else { return }
            let created = CheckoutModel(
                listingIDs: listingIDs,
                offerID: offerID,
                catalog: services.catalog,
                commerce: services.commerce,
                client: services.client
            )
            model = created
            await created.load()
        }
    }

    /// Checkout is a signed-in place; a guest who lands here gets the warm
    /// gate, never a dead screen.
    private var guestGate: some View {
        VStack {
            EmptyState(
                icon: "creditcard",
                title: "Sign in to check out",
                message: listingIDs.count > 1
                    ? "Your watches are one sign-in away. We'll bring you right back here."
                    : "Your watch is one sign-in away. We'll bring you right back here.",
                actionTitle: "Sign in",
                action: {
                    dismiss()
                    session.require(
                        listingIDs.count > 1 ? "Sign in to buy these watches" : "Sign in to buy this watch"
                    ) {}
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calibrePageBackground()
    }
}

/// The internal stack + success overlay. Split from CheckoutFlow so the
/// model can be non-optional.
private struct CheckoutStack: View {
    @Bindable var model: CheckoutModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NavigationStack(path: $model.path) {
                CheckoutShippingStep(model: model)
                    .navigationDestination(for: CheckoutStep.self) { step in
                        switch step {
                        case .method:
                            CheckoutMethodStep(model: model)
                        case .review:
                            CheckoutReviewStep(model: model)
                        case .wire:
                            WireInstructionsScreen(model: model) { orders in
                                if let first = orders.first {
                                    router.open(.order(first.id))
                                }
                                dismiss()
                            }
                        }
                    }
            }
            .tint(Color.calibre.primary)
            // Inside pushed steps `\.dismiss` pops the stack; the cover's own
            // dismissal travels via this environment closure instead.
            .environment(\.checkoutClose, { dismiss() })
            .opacity(model.completedOrder == nil ? 1 : 0)
            // `.opacity(0)` hides pixels and nothing else — the whole checkout
            // form, card field included, stayed in the accessibility tree behind
            // the success screen, so a VoiceOver user could swipe back into a
            // payment they had already made.
            .a11yCoveredBy(model.completedOrder != nil)

            if let order = model.completedOrder {
                CheckoutSuccessMoment(
                    orders: model.completedOrders,
                    listings: model.completedOrders.map { model.listingsByID[$0.listingId] },
                    onViewOrder: {
                        router.open(.order(order.id))
                        dismiss()
                    },
                    onKeepBrowsing: { dismiss() }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02)))
                .accessibilityAddTraits(.isModal)
                // The single most important sentence the app ever says, and it
                // was said only in pixels. Focus does not follow an opacity
                // crossfade, so without this a blind buyer had no confirmation
                // that the payment they just authorised had gone through.
                .onAppear {
                    A11y.screenChanged(
                        model.completedOrders.count > 1
                            ? "Order confirmed. \(model.completedOrders.count) watches purchased."
                            : "Order confirmed."
                    )
                }
            }
        }
        .animation(Motion.easeSlow, value: model.completedOrder == nil)
    }
}

/// Dismisses the whole checkout cover (not just the current pushed step).
private struct CheckoutCloseKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var checkoutClose: @MainActor () -> Void {
        get { self[CheckoutCloseKey.self] }
        set { self[CheckoutCloseKey.self] = newValue }
    }
}

/// Shared close affordance for every checkout step.
struct CheckoutCloseButton: View {
    /// Set while money is moving.
    ///
    /// Closing the cover does not stop a payment — the confirm is already with
    /// Stripe, and the task that is waiting on it outlives the view. All
    /// dismissing does is take away the only screen that would have told the
    /// buyer their card went through, so the review step shuts this door for
    /// the seconds the payment is in flight. The back button is already
    /// hidden for exactly the same reason.
    var disabled: Bool = false

    @Environment(\.checkoutClose) private var close

    var body: some View {
        Button {
            close()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.calibre.secondaryForeground)
                .frame(width: 34, height: 34)
                .background(Color.calibre.secondary, in: Circle())
                // 34pt drawn, 44pt grabbable. The 5pt of growth spills into
                // the header's padding, which nothing else answers, so the
                // circle still draws and still measures 34.
                .a11yExpandTarget(currentSize: 34)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel("Close checkout")
        .accessibilityHint(disabled ? "Unavailable while your payment is going through" : "")
    }
}
