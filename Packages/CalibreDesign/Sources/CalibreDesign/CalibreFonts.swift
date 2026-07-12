import CoreText
import SwiftUI

/// Registers the bundled brand fonts (Playfair Display + Geist) with Core Text.
/// Idempotent; call once at app launch. Token accessors also trigger it lazily
/// so package previews work without app-side setup.
public enum CalibreFonts {
    /// PostScript names as they exist inside the bundled TTFs.
    enum Name {
        static let serifRegular = "PlayfairDisplay-Regular"
        static let serifMedium = "PlayfairDisplay-Medium"
        static let serifSemiBold = "PlayfairDisplay-SemiBold"
        static let serifBold = "PlayfairDisplay-Bold"
        static let serifItalic = "PlayfairDisplay-Italic"
        static let serifSemiBoldItalic = "PlayfairDisplay-SemiBoldItalic"
        static let sansRegular = "Geist-Regular"
        static let sansMedium = "Geist-Medium"
        static let sansSemiBold = "Geist-SemiBold"
    }

    private static let registration: Void = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
              !urls.isEmpty else {
            assertionFailure("CalibreDesign font resources missing from bundle")
            return
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { _, _ in true }
    }()

    public static func register() {
        _ = registration
    }
}
