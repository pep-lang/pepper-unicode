# The package's build script: builds the package's data from the Unicode
# Character Database files in ucd/ and writes it as the generated module
# (`generated._NORMALIZATION` and the rest). Each property is a
# StaticTrie; each mapping is a StaticTrie whose values point into packed
# code points, as ICU's normalization data does.

import [File, Path] from io;
import os;
import text;
import trie;
import "generate/ucd";

# The mapping data's code points take 18 bits; bit 18 marks the last one of
# a sequence (see `_unit` in lookup.pep).
const _LAST: uint = 0x40000;
const _HEX = "0123456789ABCDEF";

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
# than 128 distinct values take one byte each in a trie, not two.
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

# `units` as a string literal: three bytes each, 7 bits a byte, low first.
# shortcut: 7 bits a byte, because stable Pepper keeps only bytes up to
# 0x7F in a string constant; use 8 once a stable release has
# pep-lang/pepper#298 (and change `_unit` in lookup.pep with it; #5).
_literal(units: uint[]): String {
    var out = Array<u8>();
    out.append('"' as u8);
    for (var unit in units) {
        for (var i in 0..3) {
            var b = ((unit >> (7 * i) as uint) & 127) as u8;
            if (b == '"' as u8 || b == '\\' as u8) {
                out.append('\\' as u8);
                out.append(b);
            } else if (b >= 0x20 && b < 0x7F) {
                out.append(b);
            } else {
                out.append('\\' as u8);
                out.append('x' as u8);
                out.append(_HEX.byte_at((b >> 4) as ulong) as u8);
                out.append(_HEX.byte_at((b & 15) as ulong) as u8);
            }
        }
    }
    out.append('"' as u8);
    return text.Utf8.decode_lossy(out);
}

# A mapping as two constants: `<name>`, a trie whose value for each key is
# 1 plus the unit its code points start at in `<name>_POINTS` (0 for a key
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
    out.append(comment);
    out.append($"export const {name} = ").append(_trie(values, "uint")).append(";\n\n");
    out.append($"## The code points `{name}` points into.\n");
    out.append($"export const {name}_POINTS = ").append(_literal(units)).append(";\n\n");
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
    out.append("## Canonical compositions by first code point: 1 plus where its\n");
    out.append("## (second, composite) pairs start in `_COMPOSITION_PAIRS`, or 0.\n");
    out.append("export const _COMPOSITION = ").append(_trie(values, "uint")).append(";\n\n");
    out.append("## The composition pairs of each first code point; its last second is\n");
    out.append("## marked (bit 18).\n");
    out.append("export const _COMPOSITION_PAIRS = ").append(_literal(units)).append(";\n\n");
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
