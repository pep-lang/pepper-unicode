## Reading the mapping data build.pep generates, and decoding text one
## code point at a time.

import text;
import trie;

## The version of Unicode the package follows.
export const UNICODE_VERSION = "16.0.0";

# Bit 18 of a mapping unit: the last code point of a sequence.
const _LAST: uint = 0x40000;
const _CODE_POINT: uint = 0x3FFFF;

# Unit `index` of mapping data: three bytes, 7 bits each, low first (see
# `_literal` in build.pep).
# shortcut: 7 bits a byte until a stable Pepper has pep-lang/pepper#298;
# then 8, with `_literal` (#5).
_unit(data: StringConstant, index: ulong): uint {
    __ptr<char> bytes = data.c_str();
    var at = index * 3;
    return (bytes[at] as uint) | ((bytes[at + 1] as uint) << 7) | ((bytes[at + 2] as uint) << 14);
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
            var unit = _unit(points, at);
            out.append(unit & _CODE_POINT);
            if ((unit & _LAST) != 0) {
                return true;
            }
            at = at + 1;
        }
        return true;
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
