# pepper-unicode

The Unicode algorithms the [Pepper](https://github.com/pep-lang/pepper)
runtime leaves out: normalization, grapheme cluster and word segmentation,
terminal display width, and full case folding. For comparing strings and
identifiers correctly, moving a cursor by user-perceived characters, and
lining up text in a terminal. Pure Pepper with Unicode **16.0.0** data, no
dependencies beyond the runtime.

One module, **`unicode`**:

- **`normalize(text, form = Form.Nfc)`** returns `text` in a normalization
  form (UAX #15): `Form.Nfc`, `Form.Nfd`, `Form.Nfkc` or `Form.Nfkd`.
- **`is_normalized(text, form = Form.Nfc)`** says whether `text` is already
  in that form, with the UAX #15 quick check (it normalizes only for the
  few characters whose answer is "maybe").
- **`graphemes(text)`** iterates over the extended grapheme clusters of
  `text` (UAX #29), each a `String`; the iterator's `offset` is where the
  current one starts.
- **`words(text)`** iterates over the pieces between UAX #29 word
  boundaries: words, numbers, and each run of spaces and punctuation mark,
  so the pieces joined give the text back. Keep the pieces holding a letter
  or digit to get only the words.
- **`display_width(text)`** and **`code_point_width(cp)`** count terminal
  columns as `wcswidth` and `wcwidth` do (see below).
- **`case_fold(text)`** applies full case folding (CaseFolding.txt's C and
  F mappings): `"Straße"` folds to `"strasse"`.
- **`equals_ignoring_case(a, b)`** is Unicode's canonical caseless match,
  `NFD(case_fold(NFD(x)))` compared, so case and precomposed or decomposed
  accents do not matter.
- **`UNICODE_VERSION`** is `"16.0.0"`.

```pepper
import unicode;

main(): int {
    var word = "cafe\u{301}";                                   # e + combining acute
    print(unicode.normalize(word) == "caf\u{E9}");              # true
    print(unicode.normalize("\u{FB01}", unicode.Form.Nfkc));    # fi
    print(unicode.is_normalized(word));                         # false
    print(unicode.graphemes("e\u{301}🇫🇷!").to_array().count);  # 3
    print("|".join(unicode.words("can't stop").to_array()));    # can't| |stop
    print(unicode.display_width("日本語ab"));                   # 8
    print(unicode.case_fold("ΣΊΣΥΦΟΣ"));                        # σίσυφοσ
    print(unicode.equals_ignoring_case("Café", "CAFE\u{301}")); # true
    return 0;
}
```

The text is a `String`, which holds UTF-8; the package reads it with the
runtime's `text.Utf8` and builds on `String.lower()` for ASCII. It panics on
invalid UTF-8, as `text.Utf8.code_point_at` does.

## Display width

`code_point_width` follows `wcwidth` (Markus Kuhn's rules) with Unicode
16.0 data:

- **2** for East Asian Wide (W) and Fullwidth (F) characters, the reserved
  code points EastAsianWidth.txt marks W, and every Emoji_Presentation
  character (which adds the regional indicators to the W set);
- **0** for combining marks (Mn, Me), format characters (Cf) except the
  soft hyphen U+00AD, U+200B ZERO WIDTH SPACE, Hangul medial vowels and
  final consonants (U+1160 to U+11FF, U+D7B0 to U+D7FF), and control
  characters (Cc, NUL included), where `wcwidth` gives -1;
- **1** for everything else, East Asian Ambiguous and unassigned code points
  included.

`display_width` is the sum over the code points, as `wcswidth` counts, not
a count per grapheme cluster: an emoji ZWJ sequence counts each emoji it
joins (`👨‍👩‍👧` is 6), a flag of two regional indicators counts 4, and a
text-presentation emoji followed by U+FE0F counts 1. Terminals differ on
these sequences; for the rest they agree with `wcwidth`.

## Conformance

The tests run the Unicode 16.0 conformance files, committed in
`tests/fixtures/`, and every case passes:

- `NormalizationTest.txt`: each line's invariants for all four forms, plus
  `is_normalized` agreeing with them, plus every code point the file's part
  1 does not list staying the same in all four forms;
- `GraphemeBreakTest.txt` and `WordBreakTest.txt`: the boundaries of every
  line.

## Data

`tables.pep` holds the data, made from the Unicode Character Database by
`generate/main.pep` (run by hand, see its header; tests/run.sh builds it so
it keeps working). Nothing is downloaded at build time. Each table is a
string constant of base-64 digits, so it costs only its bytes in the binary
and no start-up work:

- property tables (combining class and quick-check values, grapheme and
  word break values, width) list the code point where each run of one value
  starts, with an index of 64-code-point blocks below U+20000 that narrows
  each lookup to one block's runs;
- mapping tables (full canonical and compatibility decompositions, full
  case folding, canonical compositions) list sorted keys and point into one
  shared list of code points. Hangul syllables decompose and compose by
  arithmetic.

The tables are 140 KB of source. A hello world that calls
`unicode.normalize` is 113 KB larger than one that does not (281 KB against
168 KB at `-O` on Windows, Pepper 0.11.1): it carries the normalization
tables only, since unused table constants are dropped (pep-lang/pepper#271).
One that also folds case, measures width and segments text is 342 KB.
The code is about 1,000 lines.

## Performance

Best of 9, `-O`, Windows 11, Pepper 0.10.1:

| | MB/s |
| --- | --- |
| NFC of ASCII text (560 KB) | 510 |
| NFC of mixed text already in NFC (1 MB of French, Greek, Japanese, Korean, emoji) | 62 |
| NFC of that text in NFD | 16 |
| NFD of the mixed text | 19 |
| NFKC of the mixed text | 52 |
| `display_width` of the mixed text | 97 |
| `case_fold` of the mixed text | 29 |
| `graphemes` / `words` of the mixed text, to an array | 28 / 22 |

All-ASCII text is in every form, so `normalize` only scans its bytes and
copies it. Text that passes the quick check (most text, in NFC) is copied
too; only text that fails it is decomposed and composed again.

## Limits

- No locale-specific behavior: no Turkish or Lithuanian case folding, and no
  UAX #29 tailorings (dictionary-based word breaking for Thai, Chinese or
  Japanese: those scripts break by the default rules).
- No sentence or line breaking (UAX #14), no collation (UCA), no
  NFKC_Casefold, and no uppercasing or lowercasing for display.
- `words` reads the whole text's word properties when it is made.

## Using it

This repository is a package: `pep.toml` marks its root, and its root
`module.pep` is the `unicode` module. Add it to a project under the name
`unicode`:

```sh
pepper package add pep-lang/pepper-unicode --name unicode
```

which writes

```toml
[dependencies]
unicode = { github = "pep-lang/pepper-unicode" }
```

Without a project, put a folder named `unicode` that holds (or links to)
this repository on the import path: `pepper build -I packages main.pep`.

## Tests

```sh
tests/run.sh path/to/pepper
```

runs the `[Test]` functions in `tests/` with `pepper test`: the
conformance files above and the API's own cases. A package only the tests
use goes in `[dev-dependencies]` (`pepper package add --dev OWNER/name`):
projects that depend on this one do not fetch it.

## Releasing

CI (`.github/workflows/ci.yml`) runs the tests on Linux, macOS and
Windows for every push to `main` and every pull request, and, when
`pep.toml` sets `minimum_toolchain`, on Linux with that toolchain too, so
the minimum it states stays true. It builds with `PEPPER_LOCKED=1`, the
same as `pepper test --locked`: a `pep.lock` out of date with `pep.toml`
fails the run, so commit `pep.lock` after changing a dependency. To
release, set `version` in `pep.toml`, merge, then push the matching tag
(`git tag v1.0.0 && git push origin v1.0.0`): CI tests the tag and
publishes a GitHub release for it. `pepper package add` and `pepper
package update` find versions by their tags.

## License

Apache-2.0; see [LICENSE](LICENSE). The data in `tables.pep` and
`tests/fixtures/` comes from the Unicode Character Database, under the
Unicode License v3; see [LICENSE-UNICODE](LICENSE-UNICODE).
