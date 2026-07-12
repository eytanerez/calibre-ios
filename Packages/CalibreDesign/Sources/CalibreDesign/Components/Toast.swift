import Observation
import SwiftUI

/// App-wide toast presenter. Own one `ToastCenter` near the root, attach
/// `.toastHost(center)` to the root view, and call
/// `show(title:message:tone:action:)` from anywhere on the main actor.
/// One toast at a time; a new toast replaces the current one.
@MainActor @Observable
public final class ToastCenter {
    /// Semantic voice of a toast. Tones tint a thin left bar — never the
    /// whole card.
    public enum Tone: Sendable {
        case neutral, success, error

        var tint: Color {
            switch self {
            case .neutral: Color.calibre.borderBright
            case .success: Color.calibre.success
            case .error: Color.calibre.destructive
            }
        }
    }

    /// Optional trailing action ("Undo", "View") shown inside the toast.
    public struct Action {
        public let label: String
        public let handler: () -> Void

        public init(label: String, handler: @escaping () -> Void) {
            self.label = label
            self.handler = handler
        }
    }

    public struct Toast: Identifiable {
        public let id: UUID
        public let title: String
        public let message: String?
        public let tone: Tone
        public let action: Action?
    }

    public private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    public init() {}

    /// Presents a toast, replacing any visible one. Auto-dismisses after 4s;
    /// the user can also swipe it down.
    public func show(
        title: String,
        message: String? = nil,
        tone: Tone = .neutral,
        action: Action? = nil
    ) {
        dismissTask?.cancel()
        current = Toast(id: UUID(), title: title, message: message, tone: tone, action: action)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

/// Overlays the current toast above the bottom safe area. Attach once, at
/// the root of the screen (or app) that owns the `ToastCenter`.
public struct ToastHost: ViewModifier {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = center.current {
                    ToastCard(toast: toast, center: center)
                        .offset(y: dragOffset)
                        .gesture(dismissDrag)
                        .padding(.horizontal, Space.margin)
                        .padding(.bottom, Space.s)
                        .transition(entrance)
                        .id(toast.id)
                }
            }
            .animation(Motion.easeMedium, value: center.current?.id)
            .onChange(of: center.current?.id) { _, _ in dragOffset = 0 }
    }

    /// Toast entrance: translateY(14) + scale(0.97) fade — a plain crossfade
    /// under Reduce Motion.
    private var entrance: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity
                .combined(with: .offset(y: 14))
                .combined(with: .scale(scale: 0.97, anchor: .bottom))
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 24 {
                    center.dismiss()
                } else {
                    withAnimation(Motion.easeFast) { dragOffset = 0 }
                }
            }
    }
}

public extension View {
    /// Hosts toasts from `center` above this view's bottom safe area.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHost(center: center))
    }
}

private struct ToastCard: View {
    let toast: ToastCenter.Toast
    let center: ToastCenter

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Capsule()
                .fill(toast.tone.tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                if let message = toast.message {
                    Text(message)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action = toast.action {
                Button {
                    action.handler()
                    center.dismiss()
                } label: {
                    Text(action.label)
                        .font(CalibreType.bodySemiBold)
                        .foregroundStyle(Color.calibre.primary)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.l)
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .calibreShadow(.menu)
        .accessibilityElement(children: .combine)
    }
}

private struct ToastPreviewHost: View {
    @State private var center = ToastCenter()

    var body: some View {
        VStack(spacing: Space.m) {
            Button("Neutral") { center.show(title: "Link copied") }
                .buttonStyle(.calibreSecondary)
            Button("Success") {
                center.show(
                    title: "Offer sent",
                    message: "The seller has 48 hours to respond.",
                    tone: .success
                )
            }
            .buttonStyle(.calibreSecondary)
            Button("Error") {
                center.show(
                    title: "Payment failed",
                    message: "Your card was declined.",
                    tone: .error,
                    action: .init(label: "Retry") {}
                )
            }
            .buttonStyle(.calibreSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .toastHost(center)
    }
}

#Preview("Toast — light") {
    ToastPreviewHost()
}

#Preview("Toast — dark") {
    ToastPreviewHost()
        .preferredColorScheme(.dark)
}
