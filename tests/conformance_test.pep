# The Unicode 16.0 conformance tests, from tests/fixtures/ (copies of the
# UCD's NormalizationTest.txt, GraphemeBreakTest.txt and WordBreakTest.txt):
# every case must pass.

import io;
import text;
import unicode;

# The contents of `tests/fixtures/<name>`; tests/run.sh runs from the
# package's root.
fixture(name: String): String {
    return io.File.read_to_string(io.Path("tests").join("fixtures").join(name)).value();
}

# The text of space-separated hexadecimal code points.
decode_hex(field: String): String {
    var out = Array<u8>();
    for (var part in field.trim().split(" ")) {
        text.Utf8.append_code_point(out, uint.parse(part, 16).value());
    }
    return text.Utf8.decode_lossy(out);
}

# Records a failure, printing the first few.
fail(failures: ulong[], message: String) {
    if (failures[0] < 10) {
        print(message);
    }
    failures[0] = failures[0] + 1;
}

# Checks `normalize(source, form) == expected`, and that `is_normalized`
# agrees with it.
check_form(failures: ulong[], line: ulong, source: String, form: unicode.Form, expected: String) {
    var actual = unicode.normalize(source, form);
    if (actual != expected) {
        fail(failures, $"NormalizationTest.txt:{line}: form {form as int} gave the wrong text");
    }
    if (unicode.is_normalized(source, form) != (source == expected)) {
        fail(failures, $"NormalizationTest.txt:{line}: is_normalized(form {form as int}) was wrong");
    }
}

[Test]
normalization_conformance() {
    ulong[] failures = [0];
    bool[] listed = [];
    listed.resize(0x110000, false);
    var part = "";
    ulong cases = 0;
    var number: ulong = 0;
    for (var line in fixture("NormalizationTest.txt").lines()) {
        number = number + 1;
        if (line.starts_with("@")) {
            part = line;
            continue;
        }
        if (line.starts_with("#") || line.trim().size == 0) {
            continue;
        }
        var fields = line.split(";");
        String[] c = [];
        for (var i in 0..5) {
            c.append(decode_hex(fields[i]));
        }
        if (part.starts_with("@Part1")) {
            listed[uint.parse(fields[0].trim(), 16).value() as ulong] = true;
        }
        # The invariants NormalizationTest.txt states for each line.
        for (var i in 0..3) {
            check_form(failures, number, c[i], unicode.Form.Nfc, c[1]);
            check_form(failures, number, c[i], unicode.Form.Nfd, c[2]);
        }
        for (var i in 3..5) {
            check_form(failures, number, c[i], unicode.Form.Nfc, c[3]);
            check_form(failures, number, c[i], unicode.Form.Nfd, c[4]);
        }
        for (var i in 0..5) {
            check_form(failures, number, c[i], unicode.Form.Nfkc, c[3]);
            check_form(failures, number, c[i], unicode.Form.Nfkd, c[4]);
        }
        cases = cases + 1;
    }
    expect_true(cases > 19000);
    # Every code point Part 1 does not list is the same in every form.
    for (var cp in 0..0x110000) {
        if (listed[cp] || (cp >= 0xD800 && cp < 0xE000)) {
            continue;
        }
        var out = Array<u8>();
        text.Utf8.append_code_point(out, cp as uint);
        var single = text.Utf8.decode_lossy(out);
        check_form(failures, 0, single, unicode.Form.Nfc, single);
        check_form(failures, 0, single, unicode.Form.Nfd, single);
        check_form(failures, 0, single, unicode.Form.Nfkc, single);
        check_form(failures, 0, single, unicode.Form.Nfkd, single);
    }
    expect_equal(failures[0], 0);
}

# Runs a UAX #29 test file: each line is code points with `÷` (a boundary)
# or `×` (none) between them. `split` cuts text into pieces; their sizes
# give the boundaries found.
check_breaks(name: String, split: (String) => String[]) {
    ulong[] failures = [0];
    ulong cases = 0;
    var number: ulong = 0;
    for (var line in fixture(name).lines()) {
        number = number + 1;
        var cut = line.find("#");
        if (cut >= 0) {
            line = line.substr_bytes(0, cut as ulong);
        }
        if (line.trim().size == 0) {
            continue;
        }
        var source = Array<u8>();
        var expected = "";
        for (var token in line.trim().split(" ")) {
            if (token == "÷") {
                expected = expected + to_string(source.count) + " ";
            } else if (token != "×") {
                text.Utf8.append_code_point(source, uint.parse(token, 16).value());
            }
        }
        var actual = "0 ";
        ulong at = 0;
        for (var piece in split(text.Utf8.decode_lossy(source))) {
            at = at + piece.size;
            actual = actual + to_string(at) + " ";
        }
        if (actual != expected) {
            fail(failures, $"{name}:{number}: boundaries {actual}, expected {expected}");
        }
        cases = cases + 1;
    }
    expect_true(cases > 1000);
    expect_equal(failures[0], 0);
}

[Test]
grapheme_conformance() {
    check_breaks("GraphemeBreakTest.txt", (value) => unicode.graphemes(value).to_array());
}

[Test]
word_conformance() {
    check_breaks("WordBreakTest.txt", (value) => unicode.words(value).to_array());
}
