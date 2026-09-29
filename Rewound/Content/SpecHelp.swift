/// What each row of a listing's details table means, shown behind the (?)
/// beside its label.
///
/// Copied verbatim from `frontend/src/content/specHelp.ts`, which is the
/// source: change a sentence there and here together, never here alone.
/// `SharedWordingParityTests` holds the two to each other.
///
/// Keyed by the server's spec key (`REFERENCE_SPEC_FIELDS`, which
/// `ListingSpecs` decodes), plus `reference`, `year` and the box, papers and
/// booklets rows, the listing facts that share the table. Brand and model get
/// no (?): they explain themselves.
enum SpecHelp {
    static let sentences: [String: String] = [
        "reference":
            "The maker's model number for this exact version of the watch. It is the surest way to compare prices and to know what you are buying.",
        "year": "The year the watch was made, as far as the seller knows. Papers or a warranty card usually confirm it.",
        "material": "What the case is made of, such as stainless steel, gold, platinum or titanium.",
        "bezel":
            "The ring around the crystal. Some turn, to time a dive or show a second time zone; others are fixed and only decorate.",
        "glass": "The crystal over the dial. Sapphire resists scratches best. Acrylic marks more easily but can be polished clean.",
        "back": "The back of the case. A solid back seals the movement in; a display back has a window so you can watch it run.",
        "shape": "The outline of the case: round, square, rectangular, cushion or tonneau.",
        "diameter_mm": "How wide the case is, measured across without the crown. It is the main sign of how big a watch wears.",
        "finish": "How the metal is worked: polished to a shine, brushed into fine satin lines, or a mix of the two.",
        "dial": "The face of the watch: its color and its texture.",
        "indexes": "The hour markers on the dial, such as batons, dots, Arabic or Roman numerals.",
        "hands": "The shape of the hands that show the hours, minutes and seconds.",
        "movement":
            "What powers the watch. Automatic winds itself as you wear it, manual is wound by hand, quartz runs on a battery, and Spring Drive is Grand Seiko's mechanical movement with electronic regulation.",
        "calibre": "The maker's name for the movement inside. It tells versions of a model apart and matters for servicing.",
        "bracelet": "What the watch is worn on: a metal bracelet, or a leather, rubber or fabric strap.",
        "thickness_mm": "How tall the case stands, from the back to the top of the crystal. Thinner watches slip under a cuff more easily.",
        "lug_width_mm": "The gap between the lugs where the strap attaches. It decides which straps and bracelets fit.",
        "water_resistance_m":
            "The pressure the case was rated for when new, written as a depth. It is a test rating, not a diving depth, and seals age, so have it tested before you swim with it.",
        "box": "The maker's own box for the watch, inner and outer.",
        "papers": "The warranty card, certificate or dated receipt that came with the watch.",
        "booklets": "The manuals and booklets the maker packed with the watch.",
        "box_papers": "Whether the maker's box and the papers, such as the warranty card, come with the watch.",
    ]
}
