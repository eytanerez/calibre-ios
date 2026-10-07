import RewatchKit

/// The listing wizard's (?) help, for the fields sellers get stuck on:
/// reference, stock number, year, the condition grades, returns and the six
/// photo angles. Brand, model and price have none on purpose.
///
/// Copied verbatim from `frontend/src/content/sellFieldHelp.ts`
/// (`SELL_FIELD_HELP`, `SELL_GRADE_PART_HELP`, `SELL_PHOTO_HELP`), which is the
/// source: change a sentence there and here together, never here alone.
/// `SharedWordingParityTests` holds the two to each other.
enum SellFieldHelp {
    static let reference =
        "The model number the maker gives this exact version, for example 126610LN. It is usually engraved between the lugs or on the case back, and printed on the papers. Buyers search by it, and WPB Watch Co checks your watch against it."
    /// The wizard's "Seller SKU" field. The site calls the same `seller_sku`
    /// column the seller's stock number.
    static let stockNumber =
        "Your own number for this watch, if you keep an inventory. Buyers never see it. A spreadsheet upload matches on it, so one watch never becomes two listings. Leave it blank if you don't need it."
    static let year =
        "The year the watch was made. The papers or the warranty card usually say. If you are not sure, choose Unknown rather than guess."
    /// On the Condition heading: how the scale works. The five definitions
    /// (`ConditionGrades`) follow it.
    static let grades =
        "Grade each part as it looks today, then the watch as a whole. WPB Watch Co checks every grade when the watch arrives, so an honest grade is the fastest way to a finished sale."
    static let returns =
        "Whether a buyer can send the watch back, and how long they have after delivery: 24, 48 or 72 hours. Taking returns can help a watch sell, but you are paid when the window closes rather than when the watch passes authentication."
    static let photos =
        "WPB Watch Co compares the watch it receives against these six photos, and buyers see them first. Use even light, no filters, and the whole watch in frame."

    /// `SELL_FIELD_HELP`, under the site's own keys.
    static let fields: [String: String] = [
        "reference": reference,
        "stockNumber": stockNumber,
        "year": year,
        "grades": grades,
        "returns": returns,
        "photos": photos,
    ]

    /// `SELL_GRADE_PART_HELP`, keyed by condition part as the sell form and
    /// the server name them (`ConditionPart.rawValue`).
    static let gradeParts: [String: String] = [
        "case": "The metal body of the watch, lugs included. Look for scratches, dents and signs of polishing.",
        "dial": "The face under the crystal. Look for spots, fading, marks or damage to the printing.",
        "bezel": "The ring around the crystal. Look for scratches, dents, fading, and whether it turns cleanly if it should.",
        "crystal": "The glass over the dial. Look for scratches, chips and cracks.",
        "bracelet": "The bracelet or strap. Look for stretch between the links, scratches, dents and wear.",
        "clasp": "The buckle that closes the bracelet or strap. Look for scratches and check that it closes firmly.",
        "caseback": "The back of the case. Look for scratches, dents and wear to any engraving.",
        "overall": "The watch as a whole, as a buyer would see it on the wrist.",
    ]

    /// `SELL_PHOTO_HELP`, keyed by photo category
    /// (`ListingImageCategory.rawValue`). Left profile is the crown side, as
    /// the camera guide (`ListingImageCategory.instruction`) has always said.
    static let photoAngles: [String: String] = [
        "front": "The dial straight on, with the whole watch in frame and no glare on the crystal.",
        "caseback": "The back of the case, straight on.",
        "left_profile": "The crown side of the case, straight on, showing the crown, any pushers and the lugs.",
        "right_profile": "The side opposite the crown, straight on, showing the case edge and the lugs.",
        "clasp": "The clasp or buckle, closed, so its condition and any logo are clear.",
        "full_set": "Everything that comes with the watch, together: box, papers, booklets, spare links.",
    ]

    static func gradePart(_ part: ConditionPart) -> String? {
        gradeParts[part.rawValue]
    }

    static func photoAngle(_ category: ListingImageCategory) -> String? {
        photoAngles[category.rawValue]
    }
}
