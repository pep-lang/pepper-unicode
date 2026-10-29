## Reading the Unicode Character Database for the package's build script
## (`build.pep`): the property values and mappings it makes into
## `StaticTrie`s.

import io;

## The number of code points.
export const LIMIT: uint = 0x110000;

# The text of `name` in `folder`.
export read(folder: io.Path, name: String): String {
    return io.File.read_to_string(folder.join(name)).value();
}

export hex(text: String): uint {
    return uint.parse(text.trim(), 16).value();
}

# The data lines of a UCD file, without comments, split at `;` and trimmed.
export records(text: String): String[][] {
    String[][] result = [];
    for (var line in text.lines()) {
        var cut = line.find("#");
        if (cut >= 0) {
            line = line.substr_bytes(0, cut as ulong);
        }
        if (line.trim().size == 0) {
            continue;
        }
        String[] fields = [];
        for (var field in line.split(";")) {
            fields.append(field.trim());
        }
        result.append(fields);
    }
    return result;
}

# The first and last code point of a field `XXXX` or `XXXX..YYYY`.
export code_range(field: String): (uint, uint) {
    var dots = field.find("..");
    if (dots < 0) {
        var only = hex(field);
        return (only, only);
    }
    var at = dots as ulong;
    return (hex(field.substr_bytes(0, at)), hex(field.substr_bytes(at + 2, field.size - at - 2)));
}

# A value per code point, "" where the file lists none: the second field of
# each line of a `range ; value` file.
export property_values(text: String): String[] {
    String[] values = [];
    values.resize(LIMIT as ulong, "");
    for (var fields in records(text)) {
        var (first, last) = code_range(fields[0]);
        for (var cp in first..>last) {
            values[cp as ulong] = fields[1];
        }
    }
    return values;
}

# Whether each code point has binary property `name` in a `range ; name` file.
export flags(text: String, name: String): bool[] {
    bool[] result = [];
    result.resize(LIMIT as ulong, false);
    for (var fields in records(text)) {
        if (fields[1] == name) {
            var (first, last) = code_range(fields[0]);
            for (var cp in first..>last) {
                result[cp as ulong] = true;
            }
        }
    }
    return result;
}

# The normalization properties of each code point: the canonical combining
# class in the low 8 bits, then NFD_QC=No, NFKD_QC=No, NFC_QC=No,
# NFC_QC=Maybe, NFKC_QC=No and NFKC_QC=Maybe.
export normalization_values(folder: io.Path): uint[] {
    uint[] values = [];
    values.resize(LIMIT as ulong, 0);
    for (var fields in records(read(folder, "UnicodeData.txt"))) {
        values[hex(fields[0]) as ulong] = uint.parse(fields[3]).value();
    }
    for (var fields in records(read(folder, "DerivedNormalizationProps.txt"))) {
        var (first, last) = code_range(fields[0]);
        uint bit = 0;
        if (fields[1] == "NFD_QC") {
            bit = 0x100;
        } else if (fields[1] == "NFKD_QC") {
            bit = 0x200;
        } else if (fields[1] == "NFC_QC") {
            bit = 0x400;
        } else if (fields[1] == "NFKC_QC") {
            bit = 0x1000;
        } else {
            continue;
        }
        if (fields[2] == "M") {
            bit = bit * 2;
        }
        for (var cp in first..>last) {
            values[cp as ulong] = values[cp as ulong] | bit;
        }
    }
    return values;
}

# Display width in columns, wcwidth's rules (see width.pep).
export width_values(folder: io.Path): uint[] {
    var general = property_values(read(folder, "DerivedGeneralCategory.txt"));
    var east_asian = property_values(read(folder, "EastAsianWidth.txt"));
    var presentation = flags(read(folder, "emoji-data.txt"), "Emoji_Presentation");
    uint[] values = [];
    values.resize(LIMIT as ulong, 1);
    for (var cp in 0..values.count) {
        if (east_asian[cp] == "W" || east_asian[cp] == "F" || presentation[cp]) {
            values[cp] = 2;
        }
        var category = general[cp];
        if (category == "Mn" || category == "Me" || category == "Cc" || (category == "Cf" && cp != 0xAD)) {
            values[cp] = 0;
        }
    }
    values[0x200B] = 0;
    for (var cp in 0x1160..>0x11FF) {
        values[cp as ulong] = 0;
    }
    for (var cp in 0xD7B0..>0xD7FF) {
        values[cp as ulong] = 0;
    }
    return values;
}

# Grapheme_Cluster_Break values, in the order segment.pep numbers them.
const _GRAPHEME_NAMES = "Other CR LF Control Extend ZWJ Regional_Indicator Prepend SpacingMark L V T LV LVT";
# Word_Break values, likewise.
const _WORD_NAMES = "Other CR LF Newline Extend ZWJ Regional_Indicator Format Katakana Hebrew_Letter ALetter Single_Quote Double_Quote MidNumLet MidLetter MidNum Numeric ExtendNumLet WSegSpace";

# The position of `name` in the space-separated `names`.
_index_of(names: String, name: String): uint {
    var all = names.split(" ");
    for (var i in 0..all.count) {
        if (all[i] == name) {
            return i as uint;
        }
    }
    panic("unknown property value '" + name + "'");
    return 0;
}

# Whether each code point is Extended_Pictographic.
export pictographic(folder: io.Path): bool[] {
    return flags(read(folder, "emoji-data.txt"), "Extended_Pictographic");
}

# The grapheme properties of each code point: Grapheme_Cluster_Break in the
# low 4 bits, then Extended_Pictographic, then Indic_Conjunct_Break (Linker
# 1, Consonant 2, Extend 3). Hangul syllables all read LV; segment.pep
# works out LV and LVT.
export grapheme_values(folder: io.Path, pictographic: bool[]): uint[] {
    var gcb = property_values(read(folder, "GraphemeBreakProperty.txt"));
    uint[] incb = [];
    incb.resize(LIMIT as ulong, 0);
    for (var fields in records(read(folder, "DerivedCoreProperties.txt"))) {
        if (fields.count < 3 || fields[1] != "InCB") {
            continue;
        }
        uint value = 96;
        if (fields[2] == "Linker") {
            value = 32;
        } else if (fields[2] == "Consonant") {
            value = 64;
        }
        var (first, last) = code_range(fields[0]);
        for (var cp in first..>last) {
            incb[cp as ulong] = value;
        }
    }
    uint[] values = [];
    values.resize(LIMIT as ulong, 0);
    for (var cp in 0..values.count) {
        uint value = 0;
        if (gcb[cp].size > 0) {
            value = _index_of(_GRAPHEME_NAMES, gcb[cp]);
        }
        if (pictographic[cp]) {
            value = value | 16;
        }
        values[cp] = value | incb[cp];
    }
    for (var cp in 0xAC00..>0xD7A3) {
        values[cp as ulong] = 12;
    }
    return values;
}

# The word properties of each code point: Word_Break in the low 5 bits,
# then Extended_Pictographic.
export word_values(folder: io.Path, pictographic: bool[]): uint[] {
    var wb = property_values(read(folder, "WordBreakProperty.txt"));
    uint[] values = [];
    values.resize(LIMIT as ulong, 0);
    for (var cp in 0..values.count) {
        uint value = 0;
        if (wb[cp].size > 0) {
            value = _index_of(_WORD_NAMES, wb[cp]);
        }
        if (pictographic[cp]) {
            value = value | 32;
        }
        values[cp] = value;
    }
    return values;
}

# Appends the code points `cp` maps to, in full: each one replaced by its
# own mapping until none has one. `compatibility` follows both kinds of
# decomposition, otherwise only canonical ones.
_expand(out: uint[], cp: uint, mappings: HashMap<uint, uint[]>, compat: bool[], compatibility: bool) {
    var mapping = mappings.try_get(cp);
    if (mapping.is_value() && (compatibility || !compat[cp as ulong])) {
        for (var part in mapping.value()) {
            _expand(out, part, mappings, compat, compatibility);
        }
    } else {
        out.append(cp);
    }
}

# The normalization mappings of UnicodeData.txt: the full canonical
# decompositions (Hangul syllables excluded: they decompose by arithmetic),
# the full compatibility decompositions where they differ from the
# canonical one, and the primary composites as (first, second, composite),
# less the composition exclusions.
export struct Mappings {
    var canonical: (uint, uint[])[] = [];
    var compatibility: (uint, uint[])[] = [];
    var compositions: (uint, uint, uint)[] = [];
}

export mappings(folder: io.Path): Mappings {
    bool[] compat = [];
    compat.resize(LIMIT as ulong, false);
    var mappings = HashMap<uint, uint[]>();
    uint[] keys = [];
    for (var fields in records(read(folder, "UnicodeData.txt"))) {
        var cp = hex(fields[0]);
        var decomposition = fields[5];
        if (decomposition.size == 0) {
            continue;
        }
        if (decomposition.starts_with("<")) {
            compat[cp as ulong] = true;
            var close = decomposition.find(">") as ulong;
            decomposition = decomposition.substr_bytes(close + 1, decomposition.size - close - 1).trim();
        }
        uint[] parts = [];
        for (var part in decomposition.split(" ")) {
            parts.append(hex(part));
        }
        mappings[cp] = parts;
        keys.append(cp);
    }
    var result = Mappings();
    for (var cp in keys) {
        uint[] full = [];
        _expand(full, cp, mappings, compat, false);
        if (full.count != 1 || full[0] != cp) {
            result.canonical.append((cp, full));
        }
        uint[] full_compat = [];
        _expand(full_compat, cp, mappings, compat, true);
        var same = full_compat.count == full.count;
        if (same) {
            for (var i in 0..full.count) {
                same = same && full[i] == full_compat[i];
            }
        }
        if (!same) {
            result.compatibility.append((cp, full_compat));
        }
    }
    var excluded = flags(read(folder, "DerivedNormalizationProps.txt"), "Full_Composition_Exclusion");
    for (var cp in keys) {
        var mapping = mappings[cp];
        if (!compat[cp as ulong] && mapping.count == 2 && !excluded[cp as ulong]) {
            result.compositions.append((mapping[0], mapping[1], cp));
        }
    }
    return result;
}

# Full case folding: CaseFolding.txt's C and F mappings, by code point.
export foldings(folder: io.Path): (uint, uint[])[] {
    (uint, uint[])[] result = [];
    for (var fields in records(read(folder, "CaseFolding.txt"))) {
        if (fields[1] != "C" && fields[1] != "F") {
            continue;
        }
        uint[] sequence = [];
        for (var part in fields[2].split(" ")) {
            sequence.append(hex(part));
        }
        result.append((hex(fields[0]), sequence));
    }
    return result;
}
