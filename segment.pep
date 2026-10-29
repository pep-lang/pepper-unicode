## Text segmentation (UAX #29): extended grapheme clusters, the
## user-perceived characters, and word boundaries.

import generated;
import "lookup";

# Grapheme_Cluster_Break values, numbered as the generator numbers them.
const _G_OTHER: uint = 0;
const _G_CR: uint = 1;
const _G_LF: uint = 2;
const _G_CONTROL: uint = 3;
const _G_EXTEND: uint = 4;
const _G_ZWJ: uint = 5;
const _G_REGIONAL: uint = 6;
const _G_PREPEND: uint = 7;
const _G_SPACING_MARK: uint = 8;
const _G_L: uint = 9;
const _G_V: uint = 10;
const _G_T: uint = 11;
const _G_LV: uint = 12;
const _G_LVT: uint = 13;
# The bits above the break value.
const _PICTOGRAPHIC: uint = 16;
const _INCB_LINKER: uint = 1;
const _INCB_CONSONANT: uint = 2;
const _INCB_EXTEND: uint = 3;

# Word_Break values.
const _W_CR: uint = 1;
const _W_LF: uint = 2;
const _W_NEWLINE: uint = 3;
const _W_EXTEND: uint = 4;
const _W_ZWJ: uint = 5;
const _W_REGIONAL: uint = 6;
const _W_FORMAT: uint = 7;
const _W_KATAKANA: uint = 8;
const _W_HEBREW: uint = 9;
const _W_LETTER: uint = 10;
const _W_SINGLE_QUOTE: uint = 11;
const _W_DOUBLE_QUOTE: uint = 12;
const _W_MID_NUM_LET: uint = 13;
const _W_MID_LETTER: uint = 14;
const _W_MID_NUM: uint = 15;
const _W_NUMERIC: uint = 16;
const _W_EXTEND_NUM_LET: uint = 17;
const _W_SPACE: uint = 18;
const _W_PICTOGRAPHIC: uint = 32;

## An `Iterator<String>` over the extended grapheme clusters of a String,
## each one a new String: what a reader sees as one character, such as a
## letter with its accents, a Hangul syllable written in jamo, a flag, or an
## emoji sequence joined by U+200D. Make it with `graphemes`: a
## default-constructed `Graphemes()` has no text to walk.
##
## @example
##     import unicode;
##
##     var count = 0;
##     for (var cluster in unicode.graphemes("e\u{301}🇫🇷")) {
##         count = count + 1;   # "é", then the flag
##     }
##     assert(count == 2, "two clusters");
[Value]
export struct Graphemes {
    String _text;
    ulong _start;
    ulong _end;

    ## Advances to the next cluster.
    ##
    ## @returns true when positioned on a cluster, false at the end
    next(): bool {
        _start = _end;
        if (_start >= _text.size) {
            return false;
        }
        _end = _next_grapheme_break(_text, _start);
        return true;
    }

    ## Returns the cluster `next()` moved to, as a new String.
    ##
    ## @returns the cluster's text
    current(): String {
        return _text.substr_bytes(_start, _end - _start);
    }

    ## The byte offset in the text where the current cluster starts.
    var offset: ulong {
        get {
            return _start;
        }
    }
}

extend Graphemes with Iterator<String>;

## Returns an iterator over the extended grapheme clusters of `value`
## (UAX #29, Unicode 16), in order. Their texts joined give `value` back.
##
## @param value the text to split; it must be valid UTF-8
## @returns an iterator positioned before the first cluster
## @example
##     import unicode;
##
##     var clusters = unicode.graphemes("ka\u{308}!").to_array();
##     assert(clusters.count == 3 && clusters[1] == "a\u{308}", "k, ä, !");
export graphemes(value: String): Graphemes {
    var it = Graphemes();
    it._text = value;
    return it;
}

# The grapheme properties of `cp`: the break value in the low 4 bits,
# then Extended_Pictographic, then Indic_Conjunct_Break.
_grapheme_properties(cp: uint): uint {
    if (cp < 127) {
        if (cp >= 32) {
            return _G_OTHER;
        }
        if (cp == 13) {
            return _G_CR;
        }
        if (cp == 10) {
            return _G_LF;
        }
        return _G_CONTROL;
    }
    if (cp >= 0xAC00 && cp <= 0xD7A3) {
        if ((cp - 0xAC00) % 28 == 0) {
            return _G_LV;
        }
        return _G_LVT;
    }
    return generated._GRAPHEME.get(cp) as uint;
}

# The byte offset of the first grapheme cluster boundary after `start`.
_next_grapheme_break(value: String, start: ulong): ulong {
    var (first, first_run) = _decode(value, start);
    var offset = start + first_run;
    var previous = _grapheme_properties(first);
    # GB9c: 1 after a consonant and its extends, 2 once a linker follows.
    uint conjunct = 0;
    if (previous >> 5 == _INCB_CONSONANT) {
        conjunct = 1;
    }
    # GB11: 1 after a pictograph and its extends, 2 once a ZWJ follows.
    uint emoji = 0;
    if ((previous & _PICTOGRAPHIC) != 0) {
        emoji = 1;
    }
    # GB12 and GB13: the regional indicators in the run so far.
    ulong regional = 0;
    if ((previous & 15) == _G_REGIONAL) {
        regional = 1;
    }
    while (offset < value.size) {
        var (cp, run) = _decode(value, offset);
        var next = _grapheme_properties(cp);
        if (_grapheme_breaks(previous, next, conjunct, emoji, regional)) {
            break;
        }
        var kind = next & 15;
        var incb = next >> 5;
        if (incb == _INCB_CONSONANT) {
            conjunct = 1;
        } else if (conjunct != 0 && incb == _INCB_LINKER) {
            conjunct = 2;
        } else if (incb != _INCB_EXTEND) {
            conjunct = 0;
        }
        if ((next & _PICTOGRAPHIC) != 0) {
            emoji = 1;
        } else if (emoji == 1 && kind == _G_ZWJ) {
            emoji = 2;
        } else if (!(emoji == 1 && kind == _G_EXTEND)) {
            emoji = 0;
        }
        if (kind == _G_REGIONAL) {
            regional = regional + 1;
        } else {
            regional = 0;
        }
        previous = next;
        offset = offset + run;
    }
    return offset;
}

# Whether UAX #29's grapheme rules put a boundary between code points with
# properties `previous` and `next`, given the state before `next`.
_grapheme_breaks(previous: uint, next: uint, conjunct: uint, emoji: uint, regional: ulong): bool {
    var p = previous & 15;
    var n = next & 15;
    if (p == _G_CR && n == _G_LF) {
        return false;
    }
    if (p == _G_CR || p == _G_LF || p == _G_CONTROL || n == _G_CR || n == _G_LF || n == _G_CONTROL) {
        return true;
    }
    if (p == _G_L && (n == _G_L || n == _G_V || n == _G_LV || n == _G_LVT)) {
        return false;
    }
    if ((p == _G_LV || p == _G_V) && (n == _G_V || n == _G_T)) {
        return false;
    }
    if ((p == _G_LVT || p == _G_T) && n == _G_T) {
        return false;
    }
    if (n == _G_EXTEND || n == _G_ZWJ || n == _G_SPACING_MARK || p == _G_PREPEND) {
        return false;
    }
    if (conjunct == 2 && next >> 5 == _INCB_CONSONANT) {
        return false;
    }
    if (p == _G_ZWJ && emoji == 2 && (next & _PICTOGRAPHIC) != 0) {
        return false;
    }
    if (p == _G_REGIONAL && n == _G_REGIONAL && regional % 2 == 1) {
        return false;
    }
    return true;
}

## An `Iterator<String>` over the pieces of a String between UAX #29 word
## boundaries, each one a new String. Every piece is yielded: words and
## numbers, but also each run of spaces and each punctuation mark, so the
## pieces joined give the text back. Keep the ones that hold a letter or a
## digit to get only the words. Make it with `words`: a default-constructed
## `Words()` has no text to walk.
##
## It reads the whole text's word properties when it is made.
##
## @example
##     import unicode;
##
##     var pieces = unicode.words("can't stop").to_array();
##     assert(pieces.count == 3 && pieces[0] == "can't", "can't, space, stop");
[Value]
export struct Words {
    String _text;
    # The byte offset of each code point, and the text's size after them.
    ulong[] _offsets;
    # The word properties of each code point.
    uint[] _properties;
    # The current piece, as code point indexes.
    ulong _start;
    ulong _end;

    ## Advances to the next piece.
    ##
    ## @returns true when positioned on a piece, false at the end
    next(): bool {
        _start = _end;
        var count = _properties.count;
        if (_start >= count) {
            return false;
        }
        _end = _start + 1;
        while (_end < count && !_word_breaks(_properties, _end)) {
            _end = _end + 1;
        }
        return true;
    }

    ## Returns the piece `next()` moved to, as a new String.
    ##
    ## @returns the piece's text
    current(): String {
        var from = _offsets[_start];
        return _text.substr_bytes(from, _offsets[_end] - from);
    }

    ## The byte offset in the text where the current piece starts.
    var offset: ulong {
        get {
            return _offsets[_start];
        }
    }
}

extend Words with Iterator<String>;

## Returns an iterator over the pieces of `value` between word boundaries
## (UAX #29, Unicode 16), in order. The pieces joined give `value` back.
##
## @param value the text to split; it must be valid UTF-8
## @returns an iterator positioned before the first piece
## @example
##     import unicode;
##
##     var pieces = unicode.words("3.14 is π.").to_array();
##     # "3.14", " ", "is", " ", "π", "."
##     assert(pieces.count == 6 && pieces[0] == "3.14", "a number with its point");
export words(value: String): Words {
    # shortcut: 12 bytes per code point for the whole text, so the rules can
    # look both ways; move to a sliding window if huge texts need splitting.
    var it = Words();
    it._text = value;
    it._offsets = Array<ulong>();
    it._properties = Array<uint>();
    ulong offset = 0;
    while (offset < value.size) {
        var (cp, run) = _decode(value, offset);
        it._offsets.append(offset);
        it._properties.append(_word_properties(cp));
        offset = offset + run;
    }
    it._offsets.append(offset);
    return it;
}

# The word properties of `cp`: the break value in the low 5 bits, then
# Extended_Pictographic.
_word_properties(cp: uint): uint {
    if (cp < 128) {
        if ((cp >= 'a' as uint && cp <= 'z' as uint) || (cp >= 'A' as uint && cp <= 'Z' as uint)) {
            return _W_LETTER;
        }
        if (cp >= '0' as uint && cp <= '9' as uint) {
            return _W_NUMERIC;
        }
    }
    return generated._WORD.get(cp) as uint;
}

# Extend, Format and ZWJ, which WB4 attaches to what comes before them.
_ignored(properties: uint): bool {
    var kind = properties & 31;
    return kind == _W_EXTEND || kind == _W_FORMAT || kind == _W_ZWJ;
}

_letter(kind: uint): bool {
    return kind == _W_LETTER || kind == _W_HEBREW;
}

_mid_num_let_q(kind: uint): bool {
    return kind == _W_MID_NUM_LET || kind == _W_SINGLE_QUOTE;
}

# Whether UAX #29's word rules put a boundary before code point `at`
# (0 < at < count) of text with these word `properties`.
_word_breaks(properties: uint[], at: ulong): bool {
    var previous = properties[at - 1];
    var next = properties[at];
    var p = previous & 31;
    var n = next & 31;
    if (p == _W_CR && n == _W_LF) {
        return false;
    }
    if (p == _W_NEWLINE || p == _W_CR || p == _W_LF || n == _W_NEWLINE || n == _W_CR || n == _W_LF) {
        return true;
    }
    if (p == _W_ZWJ && (next & _W_PICTOGRAPHIC) != 0) {
        return false;
    }
    if (p == _W_SPACE && n == _W_SPACE) {
        return false;
    }
    if (_ignored(next)) {
        return false;
    }
    # WB4: from here on, what came before is the last code point that is
    # not Extend, Format or ZWJ, unless the text starts with those.
    var before = at - 1;
    while (before > 0 && _ignored(properties[before])) {
        before = before - 1;
    }
    p = properties[before] & 31;
    uint pp = 0;
    if (before > 0) {
        var earlier = before - 1;
        while (earlier > 0 && _ignored(properties[earlier])) {
            earlier = earlier - 1;
        }
        if (!_ignored(properties[earlier])) {
            pp = properties[earlier] & 31;
        }
    }
    uint nn = 0;
    var after = at + 1;
    while (after < properties.count && _ignored(properties[after])) {
        after = after + 1;
    }
    if (after < properties.count) {
        nn = properties[after] & 31;
    }
    if (_letter(p) && _letter(n)) {
        return false;
    }
    if (_letter(p) && (n == _W_MID_LETTER || _mid_num_let_q(n)) && _letter(nn)) {
        return false;
    }
    if (_letter(pp) && (p == _W_MID_LETTER || _mid_num_let_q(p)) && _letter(n)) {
        return false;
    }
    if (p == _W_HEBREW && n == _W_SINGLE_QUOTE) {
        return false;
    }
    if (p == _W_HEBREW && n == _W_DOUBLE_QUOTE && nn == _W_HEBREW) {
        return false;
    }
    if (pp == _W_HEBREW && p == _W_DOUBLE_QUOTE && n == _W_HEBREW) {
        return false;
    }
    if ((p == _W_NUMERIC || _letter(p)) && n == _W_NUMERIC) {
        return false;
    }
    if (p == _W_NUMERIC && _letter(n)) {
        return false;
    }
    if (pp == _W_NUMERIC && (p == _W_MID_NUM || _mid_num_let_q(p)) && n == _W_NUMERIC) {
        return false;
    }
    if (p == _W_NUMERIC && (n == _W_MID_NUM || _mid_num_let_q(n)) && nn == _W_NUMERIC) {
        return false;
    }
    if (p == _W_KATAKANA && n == _W_KATAKANA) {
        return false;
    }
    if ((_letter(p) || p == _W_NUMERIC || p == _W_KATAKANA || p == _W_EXTEND_NUM_LET) && n == _W_EXTEND_NUM_LET) {
        return false;
    }
    if (p == _W_EXTEND_NUM_LET && (_letter(n) || n == _W_NUMERIC || n == _W_KATAKANA)) {
        return false;
    }
    if (p == _W_REGIONAL && n == _W_REGIONAL) {
        # WB15 and WB16: break after each pair of regional indicators.
        ulong run = 0;
        var index = before + 1;
        while (index > 0) {
            index = index - 1;
            var kind = properties[index] & 31;
            if (kind == _W_REGIONAL) {
                run = run + 1;
            } else if (!_ignored(properties[index])) {
                break;
            }
        }
        return run % 2 == 0;
    }
    return true;
}
