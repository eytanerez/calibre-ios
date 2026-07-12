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
                .fill(Color.calibre.borderBright)
                .frame(width: 36, height: 5)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)

            if let title {
                Text(title)
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
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
        .presentationBackground(Color.calibre.card)
        .presentationCornerRadius(Radius.overlay)
    }
}

private struct SheetScaffoldPreviewHost: View {
    @State private var presented = true

    var body: some View {
        Color.calibre.background
            .ignoresSafeArea()
            .sheet(isPresented: $presented) {
                SheetScaffold(title: "Make an offer") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        Text("Rolex Submariner Date · Ref. 116610LN")
                            .font(CalibreType.body)
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Text("$12,400")
                            .font(CalibreType.priceLarge)
                            .foregroundStyle(Color.calibre.foreground)
                        Button("Send Offer") {}
                            .buttonStyle(.calibre(.primary, fullWidth: true))
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
