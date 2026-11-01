# The package's build script: builds the package's data from the Unicode
# Character Database files in ucd/ and writes it as the generated module
# (`generated._NORMALIZATION` and the rest). Each property is a
# StaticTrie; each mapping is a StaticTrie whose values point into packed
# code points, as ICU's normalization data does.

import [File, Path] from io;
import os;
import trie;
import "generate/ucd";

# The mapping data's code points take 18 bits; bit 18 marks the last one of
# a sequence (see `_unit` in lookup.pep).
const _LAST: uint = 0x40000;

# A StaticTrie of `values`, one per code point, as Pepper source. The small
# layout: the fast layout's index for the whole BMP costs more than it saves.
_trie(values: uint[], value_type: String): String {
    var builder = trie.StaticTrieBuilder();
    for (var cp in 0..values.count) {
        builder.set(cp as uint, values[cp]);
    }
    return builder.build(trie.StaticTrieKind.Small).source(value_type);
}

# `values` with each value replaced by its number in the palette (the
# distinct values in order of first appearance), and the palette. Fewer
# than 256 distinct values take one byte each in a trie, not two.
_palette(values: uint[]): (uint[], uint[]) {
    var numbers = HashMap<uint, uint>();
    uint[] palette = [];
    uint[] coded = [];
    for (var value in values) {
        if (!numbers.contains(value)) {
            numbers[value] = palette.count as uint;
            palette.append(value);
        }
        coded.append(numbers[value]);
    }
    return (coded, palette);
}

# `units` packed as `_unit` in lookup.pep reads them, and where each unit
# starts. A unit is 2 bytes below U+4000 and 3 above: the code point's low
# 8 bits; then bits 8 to 13, bit 6 for `_LAST` and bit 7 when a third byte
# holds bits 14 up.
_pack(units: uint[]): (u8[], uint[]) {
    u8[] bytes = [];
    uint[] starts = [];
    for (var unit in units) {
        starts.append(bytes.count as uint);
        var cp = unit & (_LAST - 1);
        var second = ((cp >> 8) & 0x3F) | ((unit & _LAST) != 0 ? 0x40 : 0);
        bytes.append((cp & 0xFF) as u8);
        if (cp < 0x4000) {
            bytes.append(second as u8);
        } else {
            bytes.append((second | 0x80) as u8);
            bytes.append((cp >> 14) as u8);
        }
    }
    return (bytes, starts);
}

# The trie of `values`, each 1 plus a unit's index, and the literal of
# `units`, with each value turned into 1 plus where its unit's bytes start.
_pointers(values: uint[], units: uint[]): (String, String) {
    var (bytes, starts) = _pack(units);
    for (var i in 0..values.count) {
        if (values[i] != 0) {
            values[i] = starts[values[i] as ulong - 1] + 1;
        }
    }
    return (_trie(values, "uint"), trie.byte_literal(bytes));
}

# A mapping as two constants: `<name>`, a trie whose value for each key is
# 1 plus the byte its code points start at in `<name>_POINTS` (0 for a key
# with no mapping), and `<name>_POINTS`, the code points, each sequence's
# last one marked `_LAST`. Equal sequences are stored once.
_mapping(out: StringBuilder, name: String, comment: String, mappings: (uint, uint[])[]) {
    uint[] values = [];
    values.resize(LIMIT as ulong, 0);
    uint[] units = [];
    var seen = HashMap<String, uint>();
    for (var (cp, sequence) in mappings) {
        var key = "";
        for (var part in sequence) {
            key = key + to_string(part) + " ";
        }
        if (!seen.contains(key)) {
            seen[key] = units.count as uint + 1;
            for (var i in 0..sequence.count) {
                units.append(i + 1 == sequence.count ? sequence[i] | _LAST : sequence[i]);
            }
        }
        values[cp as ulong] = seen[key];
    }
    var (keys, points) = _pointers(values, units);
    out.append(comment);
    out.append($"export const {name} = ").append(keys).append(";\n\n");
    out.append($"## The code points `{name}` points into.\n");
    out.append($"export const {name}_POINTS: StringConstant = ").append(points).append(";\n\n");
}

# The primary composites as two constants: `_COMPOSITION`, a trie whose
# value for each first code point is 1 plus where its pairs start in
# `_COMPOSITION_PAIRS`, and `_COMPOSITION_PAIRS`: for each first code point
# its (second, composite) pairs, its last second marked `_LAST`.
_composition(out: StringBuilder, compositions: (uint, uint, uint)[]) {
    var pairs = HashMap<uint, uint[]>();
    uint[] firsts = [];
    for (var (first, second, composite) in compositions) {
        if (!pairs.contains(first)) {
            pairs[first] = Array<uint>();
            firsts.append(first);
        }
        pairs[first].append(second);
        pairs[first].append(composite);
    }
    uint[] values = [];
    values.resize(LIMIT as ulong, 0);
    uint[] units = [];
    for (var first in firsts) {
        values[first as ulong] = units.count as uint + 1;
        var list = pairs[first];
        for (var i in 0..list.count) {
            units.append(i + 2 == list.count ? list[i] | _LAST : list[i]);
        }
    }
    var (keys, points) = _pointers(values, units);
    out.append("## Canonical compositions by first code point: 1 plus the byte its\n");
    out.append("## (second, composite) pairs start at in `_COMPOSITION_PAIRS`, or 0.\n");
    out.append("export const _COMPOSITION = ").append(keys).append(";\n\n");
    out.append("## The composition pairs of each first code point; its last second is\n");
    out.append("## marked (bit 18).\n");
    out.append("export const _COMPOSITION_PAIRS: StringConstant = ").append(points).append(";\n\n");
}

main(): int {
    var folder = Path("ucd");
    var (coded, palette) = _palette(normalization_values(folder));
    var pictographic = pictographic(folder);
    var mappings = mappings(folder);
    var out = StringBuilder();
    out.append("## The Unicode data the package reads, made by build.pep from ucd/.\n\n");
    out.append("import trie;\n\n");
    out.append("## Each code point's number in `_NORMALIZATION_VALUES`.\n");
    out.append("export const _NORMALIZATION = ").append(_trie(coded, "u8")).append(";\n\n");
    out.append("## The normalization properties, by number: the canonical combining\n");
    out.append("## class in the low 8 bits, then NFD_QC=No, NFKD_QC=No, NFC_QC=No,\n");
    out.append("## NFC_QC=Maybe, NFKC_QC=No and NFKC_QC=Maybe.\n");
    out.append("export const _NORMALIZATION_VALUES = ").append(_trie(palette, "u16")).append(";\n\n");
    _mapping(
        out,
        "_CANONICAL",
        "## Full canonical decompositions (Hangul syllables decompose by arithmetic).\n",
        mappings.canonical
    );
    _mapping(
        out,
        "_COMPATIBILITY",
        "## Full compatibility decompositions, where they differ from the canonical one.\n",
        mappings.compatibility
    );
    _composition(out, mappings.compositions);
    _mapping(out, "_FOLDING", "## Full case folding (CaseFolding.txt's statuses C and F).\n", foldings(folder));
    out.append("## Grapheme properties: Grapheme_Cluster_Break in the low 4 bits, then\n");
    out.append("## Extended_Pictographic, then Indic_Conjunct_Break (Linker 1, Consonant 2,\n");
    out.append("## Extend 3). Hangul syllables all read LV.\n");
    out.append("export const _GRAPHEME = ").append(_trie(grapheme_values(folder, pictographic), "u8"));
    out.append(";\n\n");
    out.append("## Word properties: Word_Break in the low 5 bits, then Extended_Pictographic.\n");
    out.append("export const _WORD = ").append(_trie(word_values(folder, pictographic), "u8")).append(";\n\n");
    out.append("## Display width in columns.\n");
    out.append("export const _WIDTH = ").append(_trie(width_values(folder), "u8")).append(";\n");
    File.write_text(Path(os.environment("PEP_OUT_DIR").value()).join(Path("module.pep")), out.to_string()).value();
    print("pep:rerun-if-changed=ucd");
    return 0;
}
