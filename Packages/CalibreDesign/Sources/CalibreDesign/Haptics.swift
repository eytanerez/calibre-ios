import CoreHaptics
import UIKit

/// One vocabulary of touch feedback for the whole app. Fire-and-forget;
/// generators are prepared and reused. One haptic per gesture — never stack.
@MainActor
public final class Haptics {
    public static let shared = Haptics()

    public enum Event {
        /// Primary CTA press.
        case press
        /// Deck drag crossed the commit threshold (armed).
        case armed
        /// Photo captured in the wizard.
        case capture
        /// Save/add-to-bag committed.
        case save
        /// Deck pass (soft).
        case pass
        /// Offer sent, listing submitted, order placed.
        case success
        /// Payment landed — the one bespoke CoreHaptics pattern.
        case paymentSuccess
        /// Decline, failure, hold error.
        case error
        /// Countdown expiring on-screen.
        case warning
        /// Segmented/filter selection.
        case selection
    }

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private var engine: CHHapticEngine?

    private init() {
        light.prepare()
        medium.prepare()
        soft.prepare()
        notification.prepare()
        selectionGenerator.prepare()
    }

    public func play(_ event: Event) {
        switch event {
        case .press, .armed: light.impactOccurred()
        case .capture, .save: medium.impactOccurred()
        case .pass: soft.impactOccurred()
        case .success: notification.notificationOccurred(.success)
        case .paymentSuccess: playPaymentPattern()
        case .error: notification.notificationOccurred(.error)
        case .warning: notification.notificationOccurred(.warning)
        case .selection: selectionGenerator.selectionChanged()
        }
    }

    /// Soft double-tap: 0.5 then 0.8 intensity, 120ms apart.
    private func playPaymentPattern() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            notification.notificationOccurred(.success)
            return
        }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.resetHandler = { [weak self] in self?.engine = nil }
            }
            try engine?.start()
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ], relativeTime: 0.12),
            ]
            let player = try engine?.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player?.start(atTime: 0)
        } catch {
            notification.notificationOccurred(.success)
        }
    }
}
