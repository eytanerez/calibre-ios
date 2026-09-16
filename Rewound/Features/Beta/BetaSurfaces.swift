import RewoundDesign
import RewoundKit
import SwiftUI

/// The three things a beta tester sees in the app: the welcome, the bar, and
/// the demo card wherever a card is asked for.
///
/// All three render nothing at all when the program is off, so a build
/// shipped after the beta closes is identical to one built before it opened.
///
/// **What TestFlight already does, and what it does not.** A tester on a
/// TestFlight build can screenshot any screen, tap the thumbnail, press the
/// checkmark and choose "Share Beta Feedback" — that is Apple's, it needs no
/// code, and it is the right way to report "this screen looks wrong". What it
/// cannot do is ask the forty questions in the survey, or reach anybody who
/// installed from the App Store later. That is what these are for.

// MARK: - The card

/// The demo card as three copyable fields.
///
/// It cannot fill the payment sheet: Stripe's card entry is Stripe's, and
/// nothing of ours can write a character into it. So the number sits directly
/// above the field, one tap from the clipboard.
struct BetaTestCardPanel: View {
    let card: BetaTestCard

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Image(systemName: "creditcard")
                    .foregroundStyle(Color.rewound.primary)
                Text(card.caption)
                    .font(RewoundType.bodySemiBold)
                    .foregroundStyle(Color.rewound.foreground)
            }

            HStack(spacing: Space.s) {
                CopyableValue(label: "Card number", value: card.number)
                CopyableValue(label: "Exp", value: card.expiry)
                CopyableValue(label: "CVC", value: card.cvc)
            }

            Text(card.note)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rewound.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.box))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box)
                .stroke(Color.rewound.primary.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct CopyableValue: View {
    let label: String
    let value: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(RewoundType.eyebrow)
                .tracking(RewoundType.eyebrowTracking)
                .foregroundStyle(Color.rewound.mutedForeground)

            Button {
                UIPasteboard.general.string = value.replacingOccurrences(of: " ", with: "")
                // A copy is a selection, not a completed piece of work — the
                // success notification is reserved for an order or a submission.
                Haptics.shared.play(.selection)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                HStack(spacing: Space.xs) {
                    Text(value)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.rewound.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(copied ? Color.rewound.success : Color.rewound.mutedForeground)
                }
                .padding(.horizontal, Space.s)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.rewound.background, in: RoundedRectangle(cornerRadius: Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .stroke(Color.rewound.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "\(label) copied" : "Copy \(label)")
        }
    }
}

/// The callout that goes above a payment field. Absent when there is no beta,
/// so the one line each payment screen adds costs a shipped build nothing.
struct BetaCardCallout: View {
    @Environment(BetaStore.self) private var beta

    var body: some View {
        if beta.isEnabled, let card = beta.config.testCard {
            BetaTestCardPanel(card: card)
        }
    }
}

// MARK: - The bar

/// A slim strip under the navigation bar, on every tab, for the beta's length.
///
/// Not dismissible, and that is the point: a tester notices a problem three
/// screens into a session, not on the one where they read the welcome, so the
/// way to report it has to be wherever they are when it happens.
struct BetaBar: View {
    @Environment(BetaStore.self) private var beta
    let onTapFeedback: () -> Void
    let onTapWelcome: () -> Void

    var body: some View {
        if beta.isEnabled, let bar = beta.config.bar {
            HStack(spacing: Space.s) {
                Button(action: onTapWelcome) {
                    HStack(spacing: Space.xs) {
                        Text(bar.text)
                            .font(RewoundType.caption)
                            .lineLimit(2)
                        Image(systemName: "info.circle")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.rewound.background)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Beta: demo card and instructions")

                Spacer(minLength: Space.s)

                Button(action: onTapFeedback) {
                    Text(bar.action)
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.foreground)
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.rewound.background)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity)
            .background(Color.rewound.foreground)
        }
    }
}

// MARK: - The welcome

struct BetaWelcomeSheet: View {
    @Environment(BetaStore.self) private var beta
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let welcome = beta.config.welcome {
                        Text(welcome.title)
                            .font(RewoundType.title)
                            .foregroundStyle(Color.rewound.foreground)
                            .accessibilityAddTraits(.isHeader)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: Space.m) {
                            // Indexed rather than keyed by content: the copy is
                            // a fixed list of sentences from the server with no
                            // id of its own, and two identical paragraphs would
                            // collapse into one under a content-keyed ForEach.
                            ForEach(Array(welcome.body.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(RewoundType.body)
                                    .foregroundStyle(Color.rewound.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let card = beta.config.testCard {
                            BetaTestCardPanel(card: card)
                        }

                        Text(welcome.signoff)
                            .font(RewoundType.hand)
                            .foregroundStyle(Color.rewound.foreground)
                    }

                    Button("Start exploring") { dismiss() }
                        .buttonStyle(.rewoundPrimary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.xxl)
            }
        }
    }
}

// MARK: - Fill this in for me

/// The button on every form the beta asks a tester to complete.
///
/// A tester who has to invent a phone number and a street address before they
/// can reach checkout will either invent a bad one, hit a validator, and report
/// *that* as a bug, or stop before seeing the part we wanted them to look at.
/// Neither is the feedback the beta exists to collect.
///
/// The values come from the server, fresh on every press, so two testers in the
/// same minute never collide on a username — the unique-constraint error the
/// second one would get being exactly the dead end this removes.
struct BetaFillButton: View {
    @Environment(BetaStore.self) private var beta
    var label: String = "Fill this in for me"
    let onFill: (BetaDemoFill) -> Void

    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        if beta.isEnabled {
            VStack(alignment: .leading, spacing: Space.xs) {
                Button {
                    guard !isLoading else { return }
                    isLoading = true
                    failed = false
                    Task {
                        do {
                            onFill(try await beta.demoFill())
                            Haptics.shared.play(.success)
                        } catch {
                            // The tester can still type. Saying so beats a
                            // button that looks like it worked and left the
                            // form empty.
                            failed = true
                        }
                        isLoading = false
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                        Text(isLoading ? "Filling…" : label)
                            .font(RewoundType.label)
                    }
                    .foregroundStyle(Color.rewound.primary)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(
                        Capsule().fill(Color.rewound.primary.opacity(0.08))
                    )
                    .overlay(
                        Capsule().stroke(Color.rewound.primary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                if failed {
                    Text("That did not work — please type whatever you like instead.")
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
