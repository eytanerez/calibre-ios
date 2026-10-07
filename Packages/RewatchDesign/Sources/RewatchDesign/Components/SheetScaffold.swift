import SwiftUI

/// Reusable chrome for bottom sheets — offer entry, filters, quick actions.
/// Draws the brand grabber and an optional serif title row, applies the
/// warm card background with overlay-radius top corners, and passes the
/// requested detents through so call sites stay one-liners:
/// `.sheet(isPresented:) { SheetScaffold(title:) { … } }`.
public struct SheetScaffold<Content: View>: View {
    let title: String?
    let detents: Set<PresentationDetent>
    let content: Content

    public init(
        title: String? = nil,
        detents: Set<PresentationDetent> = [.medium],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detents = detents
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.rewatch.borderBright)
                .frame(width: 36, height: 5)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)

            if let title {
                Text(title)
                    .font(RewatchType.sectionTitle)
                    .foregroundStyle(Color.rewatch.foreground)
                    // Serif and size are all that mark this as the sheet's
                    // title; the trait is what puts it in VoiceOver's heading
                    // rotor so a sheet can be identified without reading it.
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, Space.l)
            }

            content
                .padding(.horizontal, Space.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.rewatch.card)
        .presentationCornerRadius(Radius.panel)
    }
}

private struct SheetScaffoldPreviewHost: View {
    @State private var presented = true

    var body: some View {
        Color.rewatch.background
            .ignoresSafeArea()
            .sheet(isPresented: $presented) {
                SheetScaffold(title: "Make an offer") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        Text("Rolex Submariner Date · Ref. 116610LN")
                            .font(RewatchType.body)
                            .foregroundStyle(Color.rewatch.mutedForeground)
                        Text("$12,400")
                            .font(RewatchType.priceLarge)
                            .foregroundStyle(Color.rewatch.foreground)
                        Button("Send Offer") {}
                            .buttonStyle(.rewatch(.primary, fullWidth: true))
                    }
                }
            }
    }
}

#Preview("Sheet scaffold — light") {
    SheetScaffoldPreviewHost()
}

#Preview("Sheet scaffold — dark") {
    SheetScaffoldPreviewHost()
        .preferredColorScheme(.dark)
}
