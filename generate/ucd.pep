## Reading the Unicode Character Database: the helpers `main.pep` (the
## table generator) and the package's build script (`build.pep`) share, and
## the property values the build script makes into `StaticTrie`s.

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
