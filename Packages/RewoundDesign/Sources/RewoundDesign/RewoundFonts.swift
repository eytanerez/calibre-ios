import CoreText
import SwiftUI

/// Registers the bundled brand fonts (Rewound Serif, Geist, Caveat) with
/// Core Text.
/// Idempotent; call once at app launch. Token accessors also trigger it lazily
/// so package previews work without app-side setup.
public enum RewoundFonts {
    /// PostScript names as they exist inside the bundled TTFs.
    enum Name {
        // Rewound Serif is Playfair Display with lining figures as the default
        // digits (Fonts/RewoundSerif-OFL.txt, Scripts/make-rewound-serif.py).
        // Playfair's own figures are old-style, so "$12,450" read as uneven, and
        // SwiftUI cannot switch on `lnum` without giving up Dynamic Type.
        static let serifRegular = "RewoundSerif-Regular"
        static let serifMedium = "RewoundSerif-Medium"
        static let serifSemiBold = "RewoundSerif-SemiBold"
        static let serifBold = "RewoundSerif-Bold"
        static let serifItalic = "RewoundSerif-Italic"
        static let serifSemiBoldItalic = "RewoundSerif-SemiBoldItalic"
        static let sansRegular = "Geist-Regular"
        static let sansMedium = "Geist-Medium"
        static let sansSemiBold = "Geist-SemiBold"
        static let hand = "Caveat-Regular"
    }

    private static let registration: Void = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
              !urls.isEmpty else {
            assertionFailure("RewoundDesign font resources missing from bundle")
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
                assertionFailure("RewoundDesign font registration failed: \(failures)")
            }
            return true
        }
    }()

    public static func register() {
        _ = registration
    }
}
