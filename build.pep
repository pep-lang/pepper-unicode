# The package's build script: builds the normalization properties and the
# display widths of every code point, from the Unicode Character Database
# files in ucd/, into StaticTries, and writes them as the package's
# generated module (`generated._NORMALIZATION`, `generated._WIDTH`).

import [File, Path] from io;
import os;
import trie;
import "generate/ucd";

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

main(): int {
    var folder = Path("ucd");
    var (coded, palette) = _palette(normalization_values(folder));
    var out = StringBuilder();
    out.append("## The Unicode data the package reads as StaticTries, made by build.pep\n");
    out.append("## from ucd/.\n\nimport trie;\n\n");
    out.append("## Each code point's number in `_NORMALIZATION_VALUES`.\n");
    out.append("export const _NORMALIZATION = ").append(_trie(coded, "u8")).append(";\n\n");
    out.append("## The normalization properties, by number: the canonical combining\n");
    out.append("## class in the low 8 bits, then NFD_QC=No, NFKD_QC=No, NFC_QC=No,\n");
    out.append("## NFC_QC=Maybe, NFKC_QC=No and NFKC_QC=Maybe.\n");
    out.append("export const _NORMALIZATION_VALUES = ").append(_trie(palette, "u16")).append(";\n\n");
    out.append("## Display width in columns.\n");
    out.append("export const _WIDTH = ").append(_trie(width_values(folder), "u8")).append(";\n");
    File.write_text(Path(os.environment("PEP_OUT_DIR").value()).join(Path("module.pep")), out.to_string()).value();
    print("pep:rerun-if-changed=ucd");
    return 0;
}
