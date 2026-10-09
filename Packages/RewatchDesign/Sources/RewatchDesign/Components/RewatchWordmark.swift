import SwiftUI

/// The ReWatch wordmark: the R mark as the first letter of "ReWatch", then
/// the rest of the name in Comfortaa 500, outlined into one vector (the site's
/// `public/rewatch-wordmark.svg`, here as a template image in the asset
/// catalog). The outlines spell "eWatch": the capital W was a redraw of that
/// SVG from its own generator (same font, same kerning), copied in here, so
/// the letters are never an edit to this view. Tinted chocolate on light
/// and cream on dark, and sized by its height; the width follows the drawing.
/// The site's header uses it 28 pt tall and its sign-in pages 24 pt.
///
/// Places that show only the R mark (the logo turn, the spinners, the wax
/// seal) keep `RewatchLogoMark`; this is for the R + "ReWatch" lockup.
public struct RewatchWordmark: View {
    /// The drawing's own proportions (viewBox 4371.8 by 882).
    public static let aspectRatio: CGFloat = 4371.8 / 882.0

    let height: CGFloat

    public init(height: CGFloat = 28) {
        self.height = height
    }

    public var body: some View {
        Image("RewatchWordmark", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(width: height * Self.aspectRatio, height: height)
            .foregroundStyle(Color.rewatch.wordmark)
            .accessibilityElement()
            .accessibilityLabel("ReWatch")
            .accessibilityAddTraits(.isImage)
    }
}

#Preview {
    VStack(spacing: 24) {
        RewatchWordmark(height: 24)
        RewatchWordmark(height: 28)
        RewatchWordmark(height: 40)
    }
    .padding()
}
