## Display width: how many terminal columns text takes, as `wcwidth` and
## `wcswidth` count them.

import "lookup";
import "tables";

## Returns how many columns `cp` takes in a terminal, following `wcwidth`
## (Markus Kuhn's rules, with Unicode 16 data):
##
## - 2 for East Asian Wide and Fullwidth characters and for emoji with
##   Emoji_Presentation;
## - 0 for combining marks (Mn, Me), format characters (Cf) except the soft
##   hyphen U+00AD, U+200B ZERO WIDTH SPACE, Hangul medial vowels and final
##   consonants (U+1160 to U+11FF, U+D7B0 to U+D7FF), and control
##   characters, NUL included (where `wcwidth` gives -1);
## - 1 for everything else, East Asian Ambiguous characters and unassigned
##   code points included.
##
## @param cp the code point
## @returns 0, 1 or 2
## @example
##     import unicode;
##
##     assert(unicode.code_point_width('a' as uint) == 1, "narrow");
##     assert(unicode.code_point_width(0x4E2D) == 2, "中 is wide");
##     assert(unicode.code_point_width(0x301) == 0, "a combining accent");
export code_point_width(cp: uint): ulong {
    if (cp < 127) {
        if (cp < 32) {
            return 0;
        }
        return 1;
    }
    return _WIDTH.property(cp, 1, _WIDTH_INDEX) as ulong;
}

## Returns how many columns `value` takes in a terminal: the sum of
## `code_point_width` over its code points, as `wcswidth` counts, so an
## emoji sequence joined by U+200D counts each emoji it joins. Controls,
## tabs and newlines count 0.
##
## @param value the text to measure; it must be valid UTF-8
## @returns the width in columns
## @example
##     import unicode;
##
##     assert(unicode.display_width("hello") == 5, "ASCII");
##     assert(unicode.display_width("日本語") == 6, "wide");
##     assert(unicode.display_width("e\u{301}") == 1, "the accent takes no column");
export display_width(value: String): ulong {
    ulong width = 0;
    ulong offset = 0;
    while (offset < value.size) {
        var (cp, run) = _decode(value, offset);
        offset = offset + run;
        width = width + code_point_width(cp);
    }
    return width;
}
