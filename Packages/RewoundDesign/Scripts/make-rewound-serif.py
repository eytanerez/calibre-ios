"""Rewound Serif: Playfair Display with lining figures as the default digits.

Playfair's default figures are old-style and it has no tabular set; the web turns on
`lnum` in CSS, but SwiftUI cannot enable a font feature without giving up Dynamic
Type. So the cmap entries for 0-9 point at the `.lf` glyphs the font already carries.
Playfair is OFL with Reserved Font Name "Playfair Display", so the modified faces are
renamed.

Run from Sources/RewoundDesign/Fonts with the upstream PlayfairDisplay-*.ttf files
present: `../../../../../../Backend/venv/bin/python ../../../Scripts/make-rewound-serif.py`
(any Python with fontTools works).
"""
import sys
from fontTools.ttLib import TTFont

SRC_TO_DST = {
    "PlayfairDisplay-Regular.ttf": "RewoundSerif-Regular.ttf",
    "PlayfairDisplay-Medium.ttf": "RewoundSerif-Medium.ttf",
    "PlayfairDisplay-SemiBold.ttf": "RewoundSerif-SemiBold.ttf",
    "PlayfairDisplay-Bold.ttf": "RewoundSerif-Bold.ttf",
    "PlayfairDisplay-RegularItalic.ttf": "RewoundSerif-Italic.ttf",
    "PlayfairDisplay-SemiBoldItalic.ttf": "RewoundSerif-SemiBoldItalic.ttf",
}
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

for src, dst in SRC_TO_DST.items():
    font = TTFont(src)
    glyphs = set(font.getGlyphOrder())
    missing = [d for d in DIGITS if f"{d}.lf" not in glyphs]
    if missing:
        sys.exit(f"{src}: no lining glyphs for {missing}")
    for table in font["cmap"].tables:
        if not table.isUnicode():
            continue
        for i, name in enumerate(DIGITS):
            cp = 0x30 + i
            if cp in table.cmap:
                table.cmap[cp] = f"{name}.lf"
    for rec in font["name"].names:
        if rec.nameID in (1, 3, 4, 6, 16, 18, 21):
            text = rec.toUnicode()
            text = text.replace("Playfair Display", "Rewound Serif").replace("PlayfairDisplay", "RewoundSerif")
            rec.string = text
    font.save(dst)
    check = TTFont(dst)
    cmap = check.getBestCmap()
    ps = check["name"].getDebugName(6)
    print(dst, ps, [cmap[0x30 + i] for i in range(10)][:4], "...")
