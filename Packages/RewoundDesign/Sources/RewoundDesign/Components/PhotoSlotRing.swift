import SwiftUI

/// Upload phase of a photo slot in the listing wizard's 6-shot rail.
public enum PhotoSlotPhase: Equatable, Sendable {
    /// No photo yet — dashed border and a plus.
    case empty
    /// Upload in flight; progress is 0...1, shown as a ring and percent.
    case uploading(Double)
    /// Uploaded — check badge.
    case done
    /// Upload failed — destructive retry badge.
    case failed
}

/// Circular photo slot with a determinate chocolate progress ring on a
/// hairline track. Wrap in a `Button` for tap-to-capture / tap-to-retry;
/// the ring itself is display-only.
public struct PhotoSlotRing<Thumbnail: View>: View {
    let phase: PhotoSlotPhase
    let size: CGFloat
    let thumbnail: Thumbnail

    private let ringWidth: CGFloat = 3

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        phase: PhotoSlotPhase,
        size: CGFloat = 64,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) {
        self.phase = phase
        self.size = size
        self.thumbnail = thumbnail()
    }

    public var body: some View {
        slot
            .animation(Motion.easeMedium, value: phase)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    /// The ring is a fixed circle the caller sizes — 76 in the wizard's grid,
    /// 64 in the return flow, 56 on the extras rail — so it cannot grow with
    /// the type. At accessibility sizes the percent chip grows anyway, spills
    /// past the circle and covers the very progress it is reporting, so above
    /// the threshold it steps out from under the ring and sits below it.
    /// Below the threshold the chip is inside the circle, unchanged.
    @ViewBuilder
    private var slot: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: Space.xs) {
                ringStack(showsPercent: false)
                if case .uploading(let progress) = phase {
                    percentLabel(progress)
                }
            }
        } else {
            ringStack(showsPercent: true)
        }
    }

    private func ringStack(showsPercent: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.calibre.secondary.opacity(0.5))

            thumbnail
                .frame(width: size - 10, height: size - 10)
                .clipShape(Circle())
                .opacity(isUploading ? 0.6 : 1)

            ring

            if case .empty = phase {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.28, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }

            if showsPercent, case .uploading(let progress) = phase {
                percentLabel(progress)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) { badge }
    }

    private func percentLabel(_ progress: Double) -> some View {
        Text("\(Int((progress * 100).rounded()))%")
            .font(CalibreType.caption)
            .monospacedDigit()
            .foregroundStyle(Color.calibre.foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.calibre.background.opacity(0.8), in: Capsule())
    }

    @ViewBuilder
    private var ring: some View {
        switch phase {
        case .empty:
            Circle()
                .strokeBorder(
                    Color.calibre.borderBright,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        case .uploading(let progress):
            Circle()
                .strokeBorder(Color.calibre.border, lineWidth: ringWidth)
            Circle()
                .inset(by: ringWidth / 2)
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    Color.calibre.primary,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        case .done, .failed:
            Circle()
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch phase {
        case .done:
            badgeCircle(icon: "checkmark", tint: Color.calibre.success)
        case .failed:
            badgeCircle(icon: "arrow.clockwise", tint: Color.calibre.destructive)
        case .empty, .uploading:
            EmptyView()
        }
    }

    private func badgeCircle(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(white: 1))
            .frame(width: 18, height: 18)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(Color.calibre.card, lineWidth: 2))
    }

    private var isUploading: Bool {
        if case .uploading = phase { return true }
        return false
    }

    private var accessibilityText: String {
        switch phase {
        case .empty: "Add photo"
        case .uploading(let progress): "Uploading, \(Int((progress * 100).rounded())) percent"
        case .done: "Photo uploaded"
        case .failed: "Upload failed, retry"
        }
    }
}

public extension PhotoSlotRing where Thumbnail == EmptyView {
    /// Slot with no thumbnail (the empty state).
    init(phase: PhotoSlotPhase, size: CGFloat = 64) {
        self.init(phase: phase, size: size) { EmptyView() }
    }
}

@MainActor
private func demoThumbnail(_ icon: String) -> some View {
    Image(systemName: icon)
        .font(.system(size: 20))
        .foregroundStyle(Color.calibre.placeholder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.secondary)
}

@MainActor
private var demoRail: some View {
    HStack(spacing: Space.m) {
        PhotoSlotRing(phase: .done) { demoThumbnail("clock") }
        PhotoSlotRing(phase: .done) { demoThumbnail("clock.arrow.circlepath") }
        PhotoSlotRing(phase: .uploading(0.62)) { demoThumbnail("clock") }
        PhotoSlotRing(phase: .failed) { demoThumbnail("clock") }
        PhotoSlotRing(phase: .empty)
        PhotoSlotRing(phase: .empty)
    }
    .padding()
    .background(Color.calibre.background)
}

#Preview("Photo slots — light", traits: .sizeThatFitsLayout) {
    demoRail
}

#Preview("Photo slots — dark", traits: .sizeThatFitsLayout) {
    demoRail
        .preferredColorScheme(.dark)
}
