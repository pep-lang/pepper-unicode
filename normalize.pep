## Unicode normalization (UAX #15): NFC, NFD, NFKC and NFKD, and a quick
## check for text that is already normalized.

import generated;
import text;
import "lookup";

## A Unicode normalization form.
export enum Form {
    ## Canonical composition: decomposes canonically, then composes again.
    ## The usual form for storing and comparing text.
    Nfc,
    ## Canonical decomposition: every precomposed character split into its
    ## base and combining marks, the marks in canonical order.
    Nfd,
    ## Compatibility composition: as `Nfc`, after also replacing
    ## compatibility characters (ligatures, full-width forms, superscripts)
    ## with their plain equivalents.
    Nfkc,
    ## Compatibility decomposition: as `Nfd`, with compatibility characters
    ## replaced too.
    Nfkd,
}

# Hangul syllables decompose and compose by arithmetic, not by table.
const _S_BASE: uint = 0xAC00;
const _L_BASE: uint = 0x1100;
const _V_BASE: uint = 0x1161;
const _T_BASE: uint = 0x11A7;
const _L_COUNT: uint = 19;
const _V_COUNT: uint = 21;
const _T_COUNT: uint = 28;
const _N_COUNT: uint = 588;
const _S_COUNT: uint = 11172;

# The quick-check answers.
const _YES = 0;
const _NO = 1;
const _MAYBE = 2;

# NFD_QC No and NFKD_QC No: the code point has a canonical, or a
# compatibility, decomposition.
const _CANONICAL_BIT: uint = 0x100;
const _COMPATIBILITY_BIT: uint = 0x200;

## Returns `value` in normalization form `form`: `nfc`, `nfd`, `nfkc` or
## `nfkd` of it.
##
## A program that calls only `nfc` (or `nfd`) does not carry the
## compatibility data that `normalize` brings in for `Nfkc` and `Nfkd`.
##
## @param value the text to normalize; it must be valid UTF-8
## @param form the normalization form
## @returns a new String in that form
## @example
##     import unicode;
##
##     var decomposed = "e\u{301}";   # e and a combining acute accent
##     assert(unicode.normalize(decomposed) == "\u{E9}", "NFC composes é");
##     assert(unicode.normalize("\u{E9}", unicode.Form.Nfd) == decomposed, "NFD splits it");
##     assert(unicode.normalize("\u{FB01}", unicode.Form.Nfkc) == "fi", "NFKC splits the ligature");
export normalize(value: String, form: Form = Form.Nfc): String {
    match (form) {
        Nfc => {
            return nfc(value);
        }
        Nfd => {
            return nfd(value);
        }
        Nfkc => {
            return nfkc(value);
        }
        Nfkd => {
            return nfkd(value);
        }
    }
}

## Returns `value` in NFC: decomposed canonically, then composed again.
##
## Text already in NFC, all-ASCII text included, is found so by a quick
## check that decodes it once, and copied.
##
## @param value the text to normalize; it must be valid UTF-8
## @returns a new String in NFC
## @example
##     import unicode;
##
##     assert(unicode.nfc("e\u{301}") == "\u{E9}", "composes é");
export nfc(value: String): String {
    if (_quick_check(value, Form.Nfc) == _YES) {
        return value.copy();
    }
    var (points, properties) = _decompose_all(value, _CANONICAL_BIT, _canonical());
    _compose(points, properties);
    return _encode(points);
}

## Returns `value` in NFD: every precomposed character split into its base
## and combining marks, the marks in canonical order.
##
## Text already in NFD is found so by a quick check and copied.
##
## @param value the text to normalize; it must be valid UTF-8
## @returns a new String in NFD
## @example
##     import unicode;
##
##     assert(unicode.nfd("\u{E9}") == "e\u{301}", "splits é");
export nfd(value: String): String {
    if (_quick_check(value, Form.Nfd) == _YES) {
        return value.copy();
    }
    var (points, _) = _decompose_all(value, _CANONICAL_BIT, _canonical());
    return _encode(points);
}

## Returns `value` in NFKC: as `nfc`, after also replacing compatibility
## characters (ligatures, full-width forms, superscripts) with their plain
## equivalents.
##
## Text already in NFKC is found so by a quick check and copied.
##
## @param value the text to normalize; it must be valid UTF-8
## @returns a new String in NFKC
## @example
##     import unicode;
##
##     assert(unicode.nfkc("\u{FB01}") == "fi", "splits the ligature");
export nfkc(value: String): String {
    if (_quick_check(value, Form.Nfkc) == _YES) {
        return value.copy();
    }
    var (points, properties) = _decompose_all(value, _COMPATIBILITY_BIT, _compatibility());
    _compose(points, properties);
    return _encode(points);
}

## Returns `value` in NFKD: as `nfd`, with compatibility characters
## replaced by their plain equivalents too.
##
## Text already in NFKD is found so by a quick check and copied.
##
## @param value the text to normalize; it must be valid UTF-8
## @returns a new String in NFKD
## @example
##     import unicode;
##
##     assert(unicode.nfkd("\u{2460}") == "1", "a circled digit");
export nfkd(value: String): String {
    if (_quick_check(value, Form.Nfkd) == _YES) {
        return value.copy();
    }
    var (points, _) = _decompose_all(value, _COMPATIBILITY_BIT, _compatibility());
    return _encode(points);
}

## Returns whether `value` is in normalization form `form`, so that
## `normalize(value, form) == value`.
##
## Decides most text with the UAX #15 quick check, which decodes it once;
## only text with a character that may or may not compose (NFC_QC or
## NFKC_QC Maybe) is normalized to compare.
##
## @param value the text to check; it must be valid UTF-8
## @param form the normalization form
## @returns true when `value` is already in the form
## @example
##     import unicode;
##
##     assert(unicode.is_normalized("caf\u{E9}"), "NFC");
##     assert(!unicode.is_normalized("cafe\u{301}"), "not NFC");
##     assert(unicode.is_normalized("cafe\u{301}", unicode.Form.Nfd), "NFD");
export is_normalized(value: String, form: Form = Form.Nfc): bool {
    var check = _quick_check(value, form);
    if (check != _MAYBE) {
        return check == _YES;
    }
    return normalize(value, form) == value;
}

# The decompositions a canonical form reads.
_canonical(): _Decompositions {
    var canonical = _Mapping(generated._CANONICAL, generated._CANONICAL_POINTS);
    return _Decompositions(canonical, canonical);
}

# The decompositions a compatibility form reads: its own where they differ
# from the canonical ones.
_compatibility(): _Decompositions {
    return _Decompositions(
        _Mapping(generated._COMPATIBILITY, generated._COMPATIBILITY_POINTS),
        _Mapping(generated._CANONICAL, generated._CANONICAL_POINTS)
    );
}

# The full decomposition of a code point: `first`'s, else `fallback`'s.
[Value]
struct _Decompositions {
    var first: _Mapping;
    var fallback: _Mapping;

    construct(first: _Mapping, fallback: _Mapping) {
        this.first = first;
        this.fallback = fallback;
    }
}

# The normalization properties of `cp`: the canonical combining class in
# the low 8 bits, then the quick-check bits (see build.pep).
_normalization_properties(cp: uint): uint {
    return generated._NORMALIZATION_VALUES.get(generated._NORMALIZATION.get(cp) as uint) as uint;
}

# The UAX #15 quick check of `value` for `form`: _YES, _NO or _MAYBE.
_quick_check(value: String, form: Form): int {
    uint no_bit = _CANONICAL_BIT;
    uint maybe_bit = 0;
    # Every code point below this is in the form and has class 0: U+00A0
    # is the first with a compatibility decomposition, U+0300 the first
    # combining mark.
    uint plain = 0xA0;
    if (form == Form.Nfkd) {
        no_bit = _COMPATIBILITY_BIT;
    } else if (form == Form.Nfc) {
        no_bit = 0x400;
        maybe_bit = _NFC_MAYBE;
        plain = 0x300;
    } else if (form == Form.Nfkc) {
        no_bit = 0x1000;
        maybe_bit = 0x2000;
    }
    var result = _YES;
    uint last_class = 0;
    ulong offset = 0;
    var size = value.size;
    while (offset < size) {
        if (value.byte_at(offset) < 128) {
            last_class = 0;
            offset = offset + 1;
            continue;
        }
        var (cp, run) = text.Utf8.code_point_at(value, offset);
        offset = offset + run;
        if (cp < plain) {
            last_class = 0;
            continue;
        }
        var properties = _normalization_properties(cp);
        var combining = properties & 255;
        if (combining != 0 && last_class > combining) {
            return _NO;
        }
        if ((properties & no_bit) != 0) {
            return _NO;
        }
        if ((properties & maybe_bit) != 0) {
            result = _MAYBE;
        }
        last_class = combining;
    }
    return result;
}

# The full decomposition of `value`, in canonical order, and the
# normalization properties of each of its code points. `decomposes` is
# the property bit of a code point that `decompositions` decomposes.
_decompose_all(value: String, decomposes: uint, decompositions: _Decompositions): (uint[], uint[]) {
    uint[] points = [];
    uint[] properties = [];
    ulong offset = 0;
    while (offset < value.size) {
        var (cp, run) = _decode(value, offset);
        offset = offset + run;
        _decompose(cp, decomposes, decompositions, points, properties);
    }
    _reorder(points, properties);
    return (points, properties);
}

# `points` as UTF-8.
_encode(points: uint[]): String {
    var out = Array<u8>(points.count);
    for (var cp in points) {
        text.Utf8.append_code_point(out, cp);
    }
    return text.Utf8.decode_lossy(out);
}

# Appends the full decomposition of `cp` to `points`, and the
# normalization properties of each code point to `properties`.
_decompose(cp: uint, decomposes: uint, decompositions: _Decompositions, points: uint[], properties: uint[]) {
    if (cp < 128) {
        points.append(cp);
        properties.append(0);
        return;
    }
    var own = _normalization_properties(cp);
    if ((own & decomposes) == 0) {
        points.append(cp);
        properties.append(own);
        return;
    }
    if (cp >= _S_BASE && cp < _S_BASE + _S_COUNT) {
        var index = cp - _S_BASE;
        points.append(_L_BASE + index / _N_COUNT);
        points.append(_V_BASE + (index % _N_COUNT) / _T_COUNT);
        # Medial vowels and final consonants compose (NFC_QC Maybe).
        properties.append(0);
        properties.append(_NFC_MAYBE);
        if (index % _T_COUNT != 0) {
            points.append(_T_BASE + index % _T_COUNT);
            properties.append(_NFC_MAYBE);
        }
        return;
    }
    var start = points.count;
    if (!decompositions.first.append_to(cp, points)) {
        decompositions.fallback.append_to(cp, points);
    }
    for (var i in start..points.count) {
        properties.append(_normalization_properties(points[i]));
    }
}

# NFC_QC Maybe: a code point that may compose with the one before it.
const _NFC_MAYBE: uint = 0x800;

# Puts each run of non-starters in canonical order: a stable sort by
# combining class.
_reorder(points: uint[], properties: uint[]) {
    for (var i in 1..points.count) {
        var moving = properties[i];
        var combining = moving & 255;
        if (combining == 0) {
            continue;
        }
        var j = i;
        while (j > 0 && (properties[j - 1] & 255) > combining) {
            var point = points[j];
            points[j] = points[j - 1];
            points[j - 1] = point;
            properties[j] = properties[j - 1];
            properties[j - 1] = moving;
            j = j - 1;
        }
    }
}

# Composes decomposed, ordered text in place: each code point that is not
# blocked from the last starter and forms a primary composite with it
# replaces the starter.
_compose(points: uint[], properties: uint[]) {
    var count = points.count;
    if (count == 0) {
        return;
    }
    ulong starter = 0;
    uint last_class = properties[0] & 255;
    var has_starter = last_class == 0;
    ulong kept = 1;
    for (var i in 1..count) {
        var cp = points[i];
        var combining = properties[i] & 255;
        # Only an NFC_QC Maybe code point is the second of a composite.
        if (has_starter && (properties[i] & _NFC_MAYBE) != 0 && (last_class < combining || last_class == 0)) {
            var composite = _composite(points[starter], cp);
            if (composite != 0) {
                points[starter] = composite;
                continue;
            }
        }
        if (combining == 0) {
            starter = kept;
            has_starter = true;
        }
        last_class = combining;
        points[kept] = cp;
        properties[kept] = properties[i];
        kept = kept + 1;
    }
    points.resize(kept, 0);
    properties.resize(kept, 0);
}

# The primary composite of `first` and `second`, or 0 when they have none.
_composite(first: uint, second: uint): uint {
    if (first >= _L_BASE && first < _L_BASE + _L_COUNT && second >= _V_BASE && second < _V_BASE + _V_COUNT) {
        return _S_BASE + ((first - _L_BASE) * _V_COUNT + (second - _V_BASE)) * _T_COUNT;
    }
    if (first >= _S_BASE
        && first < _S_BASE + _S_COUNT
        && (first - _S_BASE) % _T_COUNT == 0
        && second > _T_BASE
        && second < _T_BASE + _T_COUNT) {
        return first + (second - _T_BASE);
    }
    var start = generated._COMPOSITION.get(first) as ulong;
    if (start == 0) {
        return 0;
    }
    # The pairs of `first`: (second, composite), its last second marked.
    var at = start - 1;
    while (true) {
        var unit = _unit(generated._COMPOSITION_PAIRS, at);
        if ((unit & _CODE_POINT) == second) {
            return _unit(generated._COMPOSITION_PAIRS, at + 1);
        }
        if ((unit & _LAST) != 0) {
            return 0;
        }
        at = at + 2;
    }
    return 0;
}
