import CoreText
import SwiftUI

/// Registers the bundled brand fonts (Playfair Display, Geist, Caveat) with
/// Core Text.
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
        static let hand = "Caveat-Regular"
    }

    private static let registration: Void = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
              !urls.isEmpty else {
            assertionFailure("CalibreDesign font resources missing from bundle")
            return
        }
        // The callback used to throw its errors away. A face that fails to
        // register silently falls back to the system font, which is how a
        // brand screen ships in the wrong typeface with nothing in the log to
        // say so — and how a Dynamic Type check passes against a face the app
        // is not actually drawing. Errors arrive incrementally, so trap on any
        // non-empty batch rather than waiting for the `done` pass, and always
        // return true so the faces that did register still come through.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { errors, _ in
            let failures = errors as? [Error] ?? []
            if !failures.isEmpty {
                assertionFailure("CalibreDesign font registration failed: \(failures)")
            }
            return true
        }
    }()

    public static func register() {
        _ = registration
    }
}
