from solution import wrap_text


def test_returns_list_of_lines():
    assert wrap_text("hello world", 20) == ["hello world"]


def test_wraps_at_word_boundary():
    assert wrap_text("the quick brown fox", 10) == ["the quick", "brown fox"]


def test_never_exceeds_width():
    text = "alpha beta gamma delta epsilon zeta eta theta iota kappa"
    for line in wrap_text(text, 12):
        assert len(line) <= 12, f"line too long ({len(line)}): {line!r}"


def test_empty_string_gives_empty_list():
    assert wrap_text("", 10) == []


def test_whitespace_only_gives_empty_list():
    assert wrap_text("   \t  ", 10) == []


def test_word_longer_than_width_is_hard_split():
    # A 15-char word cannot fit in width 6, so it must be broken up rather
    # than emitted as an over-long line or silently dropped.
    assert wrap_text("supercalifragil", 6) == ["superc", "alifra", "gil"]


def test_long_word_mixed_with_short_ones():
    result = wrap_text("hi enormouslylongword bye", 8)
    assert all(len(line) <= 8 for line in result), result
    assert "".join(result).replace(" ", "") == "hienormouslylongwordbye"


def test_collapses_runs_of_whitespace():
    assert wrap_text("a    b", 10) == ["a b"]


def test_no_leading_or_trailing_spaces_on_lines():
    for line in wrap_text("one two three four five six", 9):
        assert line == line.strip(), f"line has stray whitespace: {line!r}"


def test_width_of_one():
    assert wrap_text("ab c", 1) == ["a", "b", "c"]


def test_raises_on_non_positive_width():
    try:
        wrap_text("hello", 0)
    except ValueError:
        return
    raise AssertionError("width=0 must raise ValueError")


def test_preserves_all_words_in_order():
    text = "keep every single one of these words in the original order please"
    joined = " ".join(wrap_text(text, 13))
    assert joined.split() == text.split()
