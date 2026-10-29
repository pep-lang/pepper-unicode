## Full case folding and caseless comparison.

import generated;
import text;
import "lookup";
import "normalize";

## Returns `value` with full case folding (CaseFolding.txt's C and F
## mappings) applied: the form to compare text in without regard to case.
## Folding is not lowercasing for display: `ß` folds to `ss`, and the
## Cherokee letters fold to their uppercase forms.
##
## ASCII text is folded by `String.lower()`.
##
## @param value the text to fold; it must be valid UTF-8
## @returns a new String, case-folded
## @example
##     import unicode;
##
##     assert(unicode.case_fold("Straße") == "strasse", "ß folds to ss");
##     assert(unicode.case_fold("ΣΊΣΥΦΟΣ") == "σίσυφοσ", "every sigma folds to σ");
export case_fold(value: String): String {
    if (text.Ascii.is_ascii(value)) {
        return value.lower();
    }
    var out = Array<u8>(value.size);
    var folding = _Mapping(generated._FOLDING, generated._FOLDING_POINTS);
    uint[] folded = [];
    ulong offset = 0;
    while (offset < value.size) {
        var (cp, run) = _decode(value, offset);
        offset = offset + run;
        if (cp >= 'A' as uint && cp <= 'Z' as uint) {
            out.append((cp + 32) as u8);
            continue;
        }
        folded.clear();
        if (cp < 128 || !folding.append_to(cp, folded)) {
            text.Utf8.append_code_point(out, cp);
            continue;
        }
        for (var part in folded) {
            text.Utf8.append_code_point(out, part);
        }
    }
    return text.Utf8.decode_lossy(out);
}

## Returns whether `a` and `b` are the same text without regard to case:
## Unicode's canonical caseless match, which compares
## `NFD(case_fold(NFD(x)))`, so precomposed and decomposed accents match
## too.
##
## @param a the first text
## @param b the second text
## @returns true when the two match without regard to case
## @example
##     import unicode;
##
##     assert(unicode.equals_ignoring_case("STRASSE", "straße"), "ß matches ss");
##     assert(unicode.equals_ignoring_case("\u{C5}ngstr\u{F6}m", "a\u{30A}ngstro\u{308}m"), "accents match decomposed");
export equals_ignoring_case(a: String, b: String): bool {
    if (text.Ascii.is_ascii(a) && text.Ascii.is_ascii(b)) {
        return a.size == b.size && a.lower() == b.lower();
    }
    return _caseless(a) == _caseless(b);
}

# The canonical caseless form of `value`.
_caseless(value: String): String {
    return nfd(case_fold(nfd(value)));
}
