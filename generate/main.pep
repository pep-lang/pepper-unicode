## Writes `tables.pep`, the package's data, from the files of the Unicode
## Character Database. Run it by hand when moving to a new Unicode version:
##
##     pepper run -O generate/main.pep <ucd-folder> tables.pep
##
## `<ucd-folder>` holds, flat, these files of
## https://www.unicode.org/Public/<version>/ucd/: UnicodeData.txt,
## DerivedNormalizationProps.txt, CaseFolding.txt, EastAsianWidth.txt,
## DerivedCoreProperties.txt, auxiliary/GraphemeBreakProperty.txt,
## auxiliary/WordBreakProperty.txt, emoji/emoji-data.txt and
## extracted/DerivedGeneralCategory.txt. Update `UNICODE_VERSION` below to
## match, and copy the version's NormalizationTest.txt, GraphemeBreakTest.txt
## and WordBreakTest.txt into tests/fixtures/.
##
## Every table is a string constant of base-64 digits (see `lookup.pep`):
## property tables list the code points where a value starts, and mapping
## tables list sorted keys, each with the code points it maps to.

import io;

const UNICODE_VERSION = "16.0.0";
const LIMIT: uint = 0x110000;

# Grapheme_Cluster_Break values, in the order segment.pep numbers them.
const GRAPHEME_NAMES = "Other CR LF Control Extend ZWJ Regional_Indicator Prepend SpacingMark L V T LV LVT";
# Word_Break values, likewise.
const WORD_NAMES = "Other CR LF Newline Extend ZWJ Regional_Indicator Format Katakana Hebrew_Letter ALetter Single_Quote Double_Quote MidNumLet MidLetter MidNum Numeric ExtendNumLet WSegSpace";

main(args: String[]): int {
    if (args.count != 3) {
        print("usage: generate <ucd-folder> <tables.pep>");
        return 2;
    }
    var folder = io.Path(args[1]);
    var out = Array<u8>();
    emit(out, "## The Unicode " + UNICODE_VERSION + " data the package reads, made by\n");
    emit(out, "## `generate/main.pep` from the Unicode Character Database. Do not edit.\n\n");
    emit(out, "import \"lookup\";\n\n");
    emit(out, "## The version of Unicode the package follows.\n");
    emit(out, "export const UNICODE_VERSION = \"" + UNICODE_VERSION + "\";\n\n");
    emit(out, "# format: off\n");

    var emoji = read(folder, "emoji-data.txt");
    var pictographic = flags(emoji, "Extended_Pictographic");
    var points = CodePoints();
    normalization(folder, out, points);
    case_folding(folder, out, points);
    points.table.write(out, "# The code points the mappings above map to.\n", "_MAPPED", 3);
    grapheme(folder, out, pictographic);
    word(folder, out, pictographic);
    width(
        out,
        property_values(read(folder, "DerivedGeneralCategory.txt")),
        property_values(read(folder, "EastAsianWidth.txt")),
        flags(emoji, "Emoji_Presentation")
    );
    emit(out, "# format: on\n");
    io.File.write_bytes(io.Path(args[2]), out).value();
    return 0;
}

# The text of `name` in `folder`.
read(folder: io.Path, name: String): String {
    return io.File.read_to_string(folder.join(name)).value();
}

emit(out: u8[], value: String) {
    for (var b in value.bytes()) {
        out.append(b);
    }
}

hex(text: String): uint {
    return uint.parse(text.trim(), 16).value();
}

# The data lines of a UCD file, without comments, split at `;` and trimmed.
records(text: String): String[][] {
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
code_range(field: String): (uint, uint) {
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
property_values(text: String): String[] {
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
flags(text: String, name: String): bool[] {
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

# The position of `name` in the space-separated `names`.
index_of(names: String, name: String): uint {
    var all = names.split(" ");
    # The type is written out for toolchains before pep-lang/pepper#60 (#52).
    for (var i: ulong in 0..all.count) {
        if (all[i] == name) {
            return i as uint;
        }
    }
    panic("unknown property value '" + name + "'");
    return 0;
}

# Base-64 digits: 64 printable ASCII characters from '#', skipping '\'.
digit(value: ulong): u8 {
    var c = value + 35;
    if (c >= 92) {
        c = c + 1;
    }
    return c as u8;
}

# A table of fixed-size records, written as a string constant 16 records to
# a line (`_Table` in lookup.pep reads it).
struct Table {
    var digits: u8[] = [];
    var count: ulong = 0;

    # Appends `value` as `size` digits to the record being written.
    add(value: ulong, size: ulong) {
        assert(value >> (6 * size) == 0, "a value too large for its digits");
        var shift = 6 * size;
        while (shift > 0) {
            shift = shift - 6;
            digits.append(digit((value >> shift) & 63));
        }
    }

    # Writes the table as `const <name> = "...";` and its record count.
    write(out: u8[], comment: String, name: String, width: ulong) {
        assert(digits.count == count * width, "records of the stated width");
        emit(out, comment);
        emit(out, "const " + name + " = _Table(\"");
        for (var i in 0..digits.count) {
            if (i > 0 && i % (width * 16) == 0) {
                out.append('\n' as u8);
            }
            out.append(digits[i]);
        }
        emit(out, "\", " + to_string(width) + ", " + to_string(count) + ");\n\n");
    }
}

# A property table: a record of the code point where each run of equal
# values starts (4 digits) and the value (`size` digits). Its index,
# `<name>_INDEX`, gives for each block of 64 code points below U+20000 the
# record of the run its first code point is in (2 digits), so a lookup
# searches only the runs of one block.
write_property(out: u8[], comment: String, name: String, values: uint[], size: ulong) {
    var table = Table();
    var index = Table();
    for (var cp in 0..values.count) {
        if (cp == 0 || values[cp] != values[cp - 1]) {
            table.add(cp, 4);
            table.add(values[cp] as ulong, size);
            table.count = table.count + 1;
        }
        if (cp < 0x20000 && cp % 64 == 0) {
            index.add(table.count - 1, 2);
            index.count = index.count + 1;
        }
    }
    table.write(out, comment, name, 4 + size);
    index.write(out, "", name + "_INDEX", 2);
}

# Appends the code points `cp` maps to, in full: each one replaced by its
# own mapping until none has one. `compatibility` follows both kinds of
# decomposition, otherwise only canonical ones.
expand(out: uint[], cp: uint, mappings: HashMap<uint, uint[]>, compat: bool[], compatibility: bool) {
    var mapping = mappings.try_get(cp);
    if (mapping.is_value() && (compatibility || !compat[cp as ulong])) {
        for (var part in mapping.value()) {
            expand(out, part, mappings, compat, compatibility);
        }
    } else {
        out.append(cp);
    }
}

# The code points the mapping tables point into: 3 digits each, shared by
# every mapping table, with equal sequences stored once.
struct CodePoints {
    var table = Table();
    var seen = HashMap<String, ulong>();

    # The index of `sequence`, stored if it is new.
    place(sequence: uint[]): ulong {
        var key = "";
        for (var cp in sequence) {
            key = key + to_string(cp) + " ";
        }
        var known = seen.try_get(key);
        if (known.is_value()) {
            return known.value();
        }
        var at = table.count;
        for (var cp in sequence) {
            table.add(cp as ulong, 3);
            table.count = table.count + 1;
        }
        seen[key] = at;
        return at;
    }
}

# Adds a mapping record: the key (3 digits), where its code points start
# (3 digits) and how many there are (1 digit).
add_mapping(table: Table, points: CodePoints, key: uint, sequence: uint[]) {
    table.add(key as ulong, 3);
    table.add(points.place(sequence), 3);
    table.add(sequence.count, 1);
    table.count = table.count + 1;
}

normalization(folder: io.Path, out: u8[], points: CodePoints) {
    uint[] ccc = [];
    ccc.resize(LIMIT as ulong, 0);
    bool[] compat = [];
    compat.resize(LIMIT as ulong, false);
    var mappings = HashMap<uint, uint[]>();
    uint[] keys = [];
    for (var fields in records(read(folder, "UnicodeData.txt"))) {
        var cp = hex(fields[0]);
        ccc[cp as ulong] = uint.parse(fields[3]).value();
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

    var canonical = Table();
    var compatibility = Table();
    for (var cp in keys) {
        uint[] full = [];
        expand(full, cp, mappings, compat, false);
        if (full.count != 1 || full[0] != cp) {
            add_mapping(canonical, points, cp, full);
        }
        uint[] full_compat = [];
        expand(full_compat, cp, mappings, compat, true);
        var same = full_compat.count == full.count;
        if (same) {
            for (var i in 0..full.count) {
                same = same && full[i] == full_compat[i];
            }
        }
        if (!same) {
            add_mapping(compatibility, points, cp, full_compat);
        }
    }

    # The quick-check values, packed above the combining class.
    var properties = records(read(folder, "DerivedNormalizationProps.txt"));
    bool[] excluded = [];
    excluded.resize(LIMIT as ulong, false);
    uint[] values = [];
    values.resize(LIMIT as ulong, 0);
    for (var cp in 0..values.count) {
        values[cp] = ccc[cp];
    }
    for (var fields in properties) {
        var (first, last) = code_range(fields[0]);
        uint bit = 0;
        if (fields[1] == "Full_Composition_Exclusion") {
            for (var cp in first..>last) {
                excluded[cp as ulong] = true;
            }
            continue;
        } else if (fields[1] == "NFD_QC") {
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
    write_property(
        out,
        "# Normalization properties: the canonical combining class in the low 8\n# bits, then NFD_QC=No, NFKD_QC=No, NFC_QC=No, NFC_QC=Maybe, NFKC_QC=No\n# and NFKC_QC=Maybe.\n",
        "_NORMALIZATION",
        values,
        3
    );
    canonical.write(out, "# Full canonical decompositions, by code point (Hangul excluded).\n", "_CANONICAL", 7);
    compatibility.write(
        out,
        "# Full compatibility decompositions, by code point, where they differ\n# from the canonical one.\n",
        "_COMPATIBILITY",
        7
    );

    # Primary composites: the pairs canonical decompositions of two code
    # points give, less the composition exclusions.
    uint[] pairs = [];
    for (var cp in keys) {
        var mapping = mappings[cp];
        if (!compat[cp as ulong] && mapping.count == 2 && !excluded[cp as ulong]) {
            pairs.append(cp);
        }
    }
    pairs.sort((a, b) => compare(pair_key(mappings[a]), pair_key(mappings[b])));
    var composition = Table();
    for (var cp in pairs) {
        var mapping = mappings[cp];
        composition.add(mapping[0] as ulong, 3);
        composition.add(mapping[1] as ulong, 3);
        composition.add(cp as ulong, 3);
        composition.count = composition.count + 1;
    }
    composition.write(out, "# Canonical compositions: first, second, composite, sorted by pair.\n", "_COMPOSITION", 9);
}

# A pair's sort key: the first code point above the second.
pair_key(mapping: uint[]): ulong {
    return ((mapping[0] as ulong) << 18) | (mapping[1] as ulong);
}

# Full case folding: CaseFolding.txt's C and F mappings.
case_folding(folder: io.Path, out: u8[], points: CodePoints) {
    var folding = Table();
    for (var fields in records(read(folder, "CaseFolding.txt"))) {
        if (fields[1] != "C" && fields[1] != "F") {
            continue;
        }
        uint[] sequence = [];
        for (var part in fields[2].split(" ")) {
            sequence.append(hex(part));
        }
        add_mapping(folding, points, hex(fields[0]), sequence);
    }
    folding.write(out, "# Full case folding (statuses C and F), by code point.\n", "_FOLDING", 7);
}

grapheme(folder: io.Path, out: u8[], pictographic: bool[]) {
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
            value = index_of(GRAPHEME_NAMES, gcb[cp]);
        }
        if (pictographic[cp]) {
            value = value | 16;
        }
        values[cp] = value | incb[cp];
    }
    # Hangul syllables alternate LV and LVT; the reader works that out.
    for (var cp in 0xAC00..>0xD7A3) {
        values[cp as ulong] = 12;
    }
    write_property(
        out,
        "# Grapheme properties: Grapheme_Cluster_Break in the low 4 bits, then\n# Extended_Pictographic, then Indic_Conjunct_Break (Linker 1, Consonant 2,\n# Extend 3). Hangul syllables all read LV.\n",
        "_GRAPHEME",
        values,
        2
    );
}

word(folder: io.Path, out: u8[], pictographic: bool[]) {
    var wb = property_values(read(folder, "WordBreakProperty.txt"));
    uint[] values = [];
    values.resize(LIMIT as ulong, 0);
    for (var cp in 0..values.count) {
        uint value = 0;
        if (wb[cp].size > 0) {
            value = index_of(WORD_NAMES, wb[cp]);
        }
        if (pictographic[cp]) {
            value = value | 32;
        }
        values[cp] = value;
    }
    write_property(
        out, "# Word properties: Word_Break in the low 5 bits, then Extended_Pictographic.\n", "_WORD", values, 2
    );
}

# Display width in columns, wcwidth's rules (see width.pep).
width(out: u8[], general: String[], east_asian: String[], presentation: bool[]) {
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
    write_property(out, "# Display width in columns.\n", "_WIDTH", values, 1);
}
