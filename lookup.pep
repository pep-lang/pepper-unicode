## Reading the mapping data build.pep generates, and decoding text one
## code point at a time.

import text;
import trie;

## The version of Unicode the package follows.
export const UNICODE_VERSION = "16.0.0";

# Bit 18 of a mapping unit: the last code point of a sequence.
const _LAST: uint = 0x40000;
const _CODE_POINT: uint = 0x3FFFF;

# The unit of mapping data at byte `at` (a code point, with `_LAST`), and
# the byte after it: 2 bytes below U+4000, 3 above (see `_pack` in
# build.pep).
_unit(data: StringConstant, at: ulong): (uint, ulong) {
    var bytes = unsafe_cast<__ptr<u8>>(data.c_str());
    var second = bytes[at + 1] as uint;
    var unit = (bytes[at] as uint) | ((second & 0x3F) << 8) | ((second & 0x40) << 12);
    if ((second & 0x80) == 0) {
        return (unit, at + 2);
    }
    return (unit | ((bytes[at + 2] as uint) << 14), at + 3);
}

# A mapping: a trie whose value for each code point is 1 plus where its
# sequence starts in `points`, or 0 when it has none.
[Value]
struct _Mapping {
    var keys: trie.StaticTrie<uint>;
    var points: StringConstant;

    construct(keys: trie.StaticTrie<uint>, points: StringConstant) {
        this.keys = keys;
        this.points = points;
    }

    # Appends the code points `cp` maps to; returns false, appending
    # nothing, when it has none.
    append_to(cp: uint, out: uint[]): bool {
        var start = keys.get(cp) as ulong;
        if (start == 0) {
            return false;
        }
        var at = start - 1;
        while (true) {
            var (unit, next) = _unit(points, at);
            out.append(unit & _CODE_POINT);
            if ((unit & _LAST) != 0) {
                return true;
            }
            at = next;
        }
    }
}

# The code point at byte `offset` of `value`, and the bytes it takes.
_decode(value: String, offset: ulong): (uint, ulong) {
    var b = value.byte_at(offset);
    if (b < 128) {
        return (b as uint, 1);
    }
    return text.Utf8.code_point_at(value, offset);
}
