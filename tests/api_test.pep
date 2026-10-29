# The unicode package's API beyond the conformance files: display width,
# case folding, the iterators' offsets, and edge cases.

import unicode;

[Test]
normalizes_the_examples() {
    expect_equal(unicode.normalize("cafe\u{301}"), "caf\u{E9}");
    expect_equal(unicode.normalize("caf\u{E9}", unicode.Form.Nfd), "cafe\u{301}");
    expect_equal(unicode.normalize("\u{FB01}", unicode.Form.Nfkc), "fi");
    expect_equal(unicode.normalize("\u{FB01}", unicode.Form.Nfc), "\u{FB01}");
    # Hangul composes and decomposes by arithmetic.
    expect_equal(unicode.normalize("\u{D55C}", unicode.Form.Nfd), "\u{1112}\u{1161}\u{11AB}");
    expect_equal(unicode.normalize("\u{1112}\u{1161}\u{11AB}"), "\u{D55C}");
    # Marks are put in canonical order: dot below (220) before acute (230).
    expect_equal(unicode.normalize("a\u{301}\u{323}", unicode.Form.Nfd), "a\u{323}\u{301}");
    expect_equal(unicode.normalize(""), "");
    expect_equal(unicode.normalize("plain ASCII"), "plain ASCII");
}

# Each form's own function gives what `normalize` gives for the form.
[Test]
normalizes_with_each_forms_function() {
    expect_equal(unicode.nfc("cafe\u{301}"), "caf\u{E9}");
    expect_equal(unicode.nfd("caf\u{E9}"), "cafe\u{301}");
    expect_equal(unicode.nfkc("\u{FB01}\u{2460}"), "fi1");
    expect_equal(unicode.nfkd("\u{1E9B}\u{323}"), "s\u{323}\u{307}");
    expect_equal(unicode.nfc("\u{1E9B}\u{323}"), "\u{1E9B}\u{323}");
    for (var sample in ["plain", "\u{D55C}", "a\u{301}\u{323}", "\u{FB01}", "\u{2126}", ""]) {
        expect_equal(unicode.nfc(sample), unicode.normalize(sample, unicode.Form.Nfc));
        expect_equal(unicode.nfd(sample), unicode.normalize(sample, unicode.Form.Nfd));
        expect_equal(unicode.nfkc(sample), unicode.normalize(sample, unicode.Form.Nfkc));
        expect_equal(unicode.nfkd(sample), unicode.normalize(sample, unicode.Form.Nfkd));
    }
}

[Test]
normalize_returns_a_copy() {
    var source = "abc";
    var result = unicode.normalize(source);
    result.append("d");
    expect_equal(source, "abc");
}

[Test]
checks_normalization() {
    expect_true(unicode.is_normalized("caf\u{E9}"));
    expect_false(unicode.is_normalized("cafe\u{301}"));
    expect_true(unicode.is_normalized("cafe\u{301}", unicode.Form.Nfd));
    expect_false(unicode.is_normalized("\u{FB01}", unicode.Form.Nfkd));
    # A combining mark after a plain letter is NFC_QC Maybe: decided by normalizing.
    expect_true(unicode.is_normalized("q\u{301}"));
    expect_false(unicode.is_normalized("e\u{301}"));
}

[Test]
measures_display_width() {
    expect_equal(unicode.display_width(""), 0);
    expect_equal(unicode.display_width("hello"), 5);
    expect_equal(unicode.display_width("日本語"), 6);
    expect_equal(unicode.display_width("ｈｉ"), 4);
    expect_equal(unicode.display_width("e\u{301}"), 1);
    expect_equal(unicode.display_width("tab\there\n"), 7);
    expect_equal(unicode.display_width("😀"), 2);
    # Sequences count per code point, as wcswidth does.
    expect_equal(unicode.display_width("👨‍👩‍👧"), 6);
    expect_equal(unicode.display_width("🇫🇷"), 4);
    expect_equal(unicode.display_width("\u{263A}\u{FE0F}"), 1);
    # U+263A is a text-presentation emoji; East Asian Ambiguous counts 1.
    expect_equal(unicode.display_width("\u{263A}\u{A1}"), 2);
    expect_equal(unicode.code_point_width(0xAD), 1);
    expect_equal(unicode.code_point_width(0x200B), 0);
    expect_equal(unicode.code_point_width(0x1160), 0);
    expect_equal(unicode.code_point_width(0x7F), 0);
    expect_equal(unicode.code_point_width(0x9F), 0);
    expect_equal(unicode.code_point_width(0x3400), 2);
    expect_equal(unicode.code_point_width(0x1F1E6), 2);
}

[Test]
folds_case() {
    expect_equal(unicode.case_fold("Hello"), "hello");
    expect_equal(unicode.case_fold("Straße"), "strasse");
    expect_equal(unicode.case_fold("ΣΊΣΥΦΟΣ"), "σίσυφοσ");
    expect_equal(unicode.case_fold("\u{212A}elvin"), "kelvin");
    expect_equal(unicode.case_fold("\u{130}"), "i\u{307}");
    expect_equal(unicode.case_fold(""), "");
}

[Test]
compares_ignoring_case() {
    expect_true(unicode.equals_ignoring_case("HTTP", "http"));
    expect_false(unicode.equals_ignoring_case("http", "https"));
    expect_true(unicode.equals_ignoring_case("STRASSE", "straße"));
    expect_true(unicode.equals_ignoring_case("\u{C5}ngstr\u{F6}m", "a\u{30A}ngstro\u{308}m"));
    expect_true(unicode.equals_ignoring_case("\u{212B}", "\u{E5}"));
    expect_false(unicode.equals_ignoring_case("é", "e"));
}

[Test]
iterates_graphemes_with_offsets() {
    String[] pieces = [];
    ulong[] offsets = [];
    for (var cluster in unicode.graphemes("e\u{301}🇫🇷👨‍👩‍👧\r\n!")) {
        pieces.append(cluster);
    }
    var it = unicode.graphemes("ab\u{308}c");
    while (it.next()) {
        offsets.append(it.offset);
    }
    expect_equal(pieces.count, 5);
    expect_equal(pieces[0], "e\u{301}");
    expect_equal(pieces[2], "👨‍👩‍👧");
    expect_equal(pieces[3], "\r\n");
    expect_equal(offsets.count, 3);
    expect_equal(offsets[2], 4);
    expect_equal(unicode.graphemes("").to_array().count, 0);
}

[Test]
iterates_words_with_offsets() {
    var pieces = unicode.words("The quick (\"brown\") fox can't jump 32.3 feet, right?").to_array();
    var joined = "|".join(pieces);
    expect_equal(joined, "The| |quick| |(|\"|brown|\"|)| |fox| |can't| |jump| |32.3| |feet|,| |right|?");
    var it = unicode.words("a  b");
    ulong[] offsets = [];
    while (it.next()) {
        offsets.append(it.offset);
    }
    expect_equal(offsets.count, 3);
    expect_equal(offsets[2], 3);
    expect_equal(unicode.words("").to_array().count, 0);
}

[Test]
names_the_unicode_version() {
    expect_equal(unicode.UNICODE_VERSION, "16.0.0");
}
