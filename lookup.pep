## Reading the tables of `tables.pep`, and decoding text one code point at
## a time.

import text;

# Records per line of a table's text.
const _PER_LINE: ulong = 16;

# A table of `count` records of `width` base-64 digits each, 16 to a line.
# A digit is one of 64 ASCII characters from '#' (0) up, skipping '\', so
# the text is a string constant: it costs no allocation and no start-up
# work, and only its bytes in the binary. Lines may end in "\r\n" when a
# checkout converts line endings.
[Value]
struct _Table {
    var text: StringConstant;
    var width: ulong;
    var count: ulong;

    construct(text: StringConstant, width: ulong, count: ulong) {
        this.text = text;
        this.width = width;
        this.count = count;
    }

    # The `size`-digit number at digit `offset` of record `index`.
    read(index: ulong, offset: ulong, size: ulong): ulong {
        __ptr<char> data = text.c_str();
        var line = width * _PER_LINE;
        var stride = line + 1;
        if (text.size > line && data[line] == '\r') {
            stride = line + 2;
        }
        var at = (index / _PER_LINE) * stride + (index % _PER_LINE) * width + offset;
        ulong value = 0;
        for (var i in 0..size) {
            var c = data[at + i] as ulong;
            var d = c - 35;
            if (c > 92) {
                d = d - 1;
            }
            value = (value << 6) | d;
        }
        return value;
    }

    # The value of a property table (records of a 4-digit first code point
    # and a `size`-digit value) for the run that holds `cp`. `index` is the
    # table's `_INDEX`: the record each block of 64 code points below
    # U+20000 starts in, which narrows the search to that block's runs.
    property(cp: uint, size: ulong, index: _Table): uint {
        ulong low = 0;
        var high = count;
        if (cp < 0x20000) {
            var block = (cp >> 6) as ulong;
            low = index.read(block, 0, 2);
            if (block + 1 < index.count) {
                high = index.read(block + 1, 0, 2) + 1;
            }
        }
        while (high - low > 1) {
            var middle = (low + high) / 2;
            if (read(middle, 0, 4) <= cp) {
                low = middle;
            } else {
                high = middle;
            }
        }
        return read(low, 4, size) as uint;
    }

    # The record whose first `size` digits are `key`, or `count` when none is.
    find(key: ulong, size: ulong): ulong {
        ulong low = 0;
        var high = count;
        while (low < high) {
            var middle = (low + high) / 2;
            var at = read(middle, 0, size);
            if (at == key) {
                return middle;
            }
            if (at < key) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        return count;
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
