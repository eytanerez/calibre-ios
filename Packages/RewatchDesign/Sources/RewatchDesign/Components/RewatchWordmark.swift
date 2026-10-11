import SwiftUI

/// The ReWatch wordmark: "ReWatch" in Playfair Display Bold, shaped with the
/// font's own kerning and outlined into one vector, so no font is read at
/// runtime and the word is the same drawing on the site, in email and in every
/// app. It is a template image in the asset catalog, copied from the asset
/// generator's `rewatch-wordmark.svg` rather than redrawn. Tinted chocolate on
/// light and cream on dark (the `wordmark` token), and sized by its height;
/// the width follows the drawing.
///
/// The drawing's box is tight to the ink, so a height here reads larger than
/// the same height did under the old wordmark. Sizes at the call sites were
/// chosen by looking at a render, not carried over.
///
/// The word is also the mark wherever one stands alone — there is no initial
/// or monogram. The stamp and the wax seal press it, the sign-in screen
/// breathes it while a request is in flight, and `RewatchOpening` builds it
/// out of its two pieces at launch.
public struct RewatchWordmark: View {
    /// The drawing's own proportions (viewBox 3821 by 796).
    public static let aspectRatio: CGFloat = 3821.0 / 796.0

    let height: CGFloat

    public init(height: CGFloat = 28) {
        self.height = height
    }

    public var body: some View {
        WordmarkArt.word
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

/// The wordmark's drawings, as the asset catalog holds them. All three share
/// one viewBox (`0 0 3821 796`), so the two pieces laid in the word's frame
/// overlay to the whole word exactly — which is what the opening relies on.
enum WordmarkArt {
    /// The whole word.
    static var word: Image {
        Image("RewatchWordmark", bundle: .module).renderingMode(.template)
    }

    /// "Re" alone, where it sits in the word.
    static var re: Image {
        Image("RewatchWordmarkRe", bundle: .module).renderingMode(.template)
    }

    /// "Watch" alone, where it sits in the word.
    static var watch: Image {
        Image("RewatchWordmarkWatch", bundle: .module).renderingMode(.template)
    }
}

#Preview {
    VStack(spacing: 24) {
        RewatchWordmark(height: 20)
        RewatchWordmark(height: 25)
        RewatchWordmark(height: 36)
    }
    .padding()
}
