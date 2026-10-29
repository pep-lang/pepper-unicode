## The Unicode algorithms the runtime leaves out, with Unicode 16.0 data:
## normalization, grapheme and word segmentation, display width, and case
## folding.
##
## Bring it in with `import unicode`.
##
## - `normalize`, `nfc`, `nfd`, `nfkc`, `nfkd`, `is_normalized`, `Form`: NFC,
##   NFD, NFKC and NFKD (UAX #15)
## - `graphemes`, `Graphemes`: extended grapheme clusters (UAX #29)
## - `words`, `Words`: the pieces between word boundaries (UAX #29)
## - `display_width`, `code_point_width`: terminal columns, as `wcwidth`
## - `case_fold`, `equals_ignoring_case`: full case folding and caseless matching
## - `UNICODE_VERSION`: the version of the data
##
## @example
##     import unicode;
##
##     main(): int {
##         var word = "cafe\u{301}";
##         assert(unicode.normalize(word) == "caf\u{E9}", "NFC composes the accent");
##         assert(unicode.graphemes(word).to_array().count == 4, "four characters");
##         assert(unicode.display_width("日本") == 4, "two wide characters");
##         assert(unicode.equals_ignoring_case("Café", "CAFE\u{301}"), "a caseless match");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "case";
import "lookup";
import "normalize";
import "segment";
import "width";

export Form;
export normalize;
export nfc;
export nfd;
export nfkc;
export nfkd;
export is_normalized;
export Graphemes;
export graphemes;
export Words;
export words;
export code_point_width;
export display_width;
export case_fold;
export equals_ignoring_case;
export UNICODE_VERSION;
