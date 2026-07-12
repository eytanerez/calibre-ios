import SwiftUI

/// Brand type scale. Playfair Display carries identity moments — titles and
/// prices, always normal case (never uppercase serif). Geist carries the
/// working UI. All styles scale with Dynamic Type via `relativeTo`.
public enum CalibreType {
    /// Hero moments — success screens, intro. Playfair 34.
    public static var display: Font { serif(.semiBold, 34, relativeTo: .largeTitle) }
    /// Page titles. Playfair 28.
    public static var title: Font { serif(.semiBold, 28, relativeTo: .title) }
    /// Section headers. Playfair 22.
    public static var sectionTitle: Font { serif(.semiBold, 22, relativeTo: .title2) }
    /// PDP hero price. Playfair 28 — serif prices are the signature.
    public static var priceLarge: Font { serif(.semiBold, 28, relativeTo: .title) }
    /// Card/list price. Playfair 20.
    public static var price: Font { serif(.semiBold, 20, relativeTo: .title3) }
    /// Inline/compact price. Playfair 17.
    public static var priceSmall: Font { serif(.semiBold, 17, relativeTo: .body) }
    /// Editorial serif body (Journal pull quotes). Playfair italic 19.
    public static var editorialQuote: Font { custom(CalibreFonts.Name.serifItalic, 19, relativeTo: .title3) }

    /// Default body. Geist 15.
    public static var body: Font { sans(.regular, 15, relativeTo: .body) }
    /// Emphasized body — card titles, row leads. Geist Medium 15.
    public static var bodyMedium: Font { sans(.medium, 15, relativeTo: .body) }
    /// Buttons and strong labels. Geist SemiBold 15.
    public static var bodySemiBold: Font { sans(.semiBold, 15, relativeTo: .body) }
    /// Form labels, badges, secondary rows. Geist Medium 13.
    public static var label: Font { sans(.medium, 13, relativeTo: .footnote) }
    /// Metadata and timestamps. Geist 12.
    public static var caption: Font { sans(.regular, 12, relativeTo: .caption) }
    /// The single sanctioned uppercase style — apply via `Eyebrow`, not directly.
    public static var eyebrow: Font { sans(.medium, 11, relativeTo: .caption2) }
    /// Tracking that pairs with `eyebrow` (0.18em at 11pt).
    public static let eyebrowTracking: CGFloat = 1.98

    public enum SerifWeight { case regular, medium, semiBold, bold }
    public enum SansWeight { case regular, medium, semiBold }

    public static func serif(_ weight: SerifWeight, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .regular: CalibreFonts.Name.serifRegular
        case .medium: CalibreFonts.Name.serifMedium
        case .semiBold: CalibreFonts.Name.serifSemiBold
        case .bold: CalibreFonts.Name.serifBold
        }
        return custom(name, size, relativeTo: style)
    }

    public static func sans(_ weight: SansWeight, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .regular: CalibreFonts.Name.sansRegular
        case .medium: CalibreFonts.Name.sansMedium
        case .semiBold: CalibreFonts.Name.sansSemiBold
        }
        return custom(name, size, relativeTo: style)
    }

    private static func custom(_ name: String, _ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        CalibreFonts.register()
        return .custom(name, size: size, relativeTo: style)
    }
}
