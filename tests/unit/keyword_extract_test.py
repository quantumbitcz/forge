import pytest
from hooks._py.keyword_extract import extract_keywords


def test_lowercases_and_strips_punctuation():
    out = extract_keywords("Fix NullPointer in PlanService.validate()!")
    assert "nullpointer" in out
    assert "planservice" in out
    assert "validate" in out


def test_drops_stopwords_short_and_numeric():
    out = extract_keywords("the and it 42 go ok foobar")
    assert out == ["foobar"]


def test_top_20_by_frequency_ties_by_first_occurrence():
    # Note: deviation from plan — used range(30) so w10..w29 (20 tokens of len>=3)
    # plus alpha/beta/gamma/delta yields 24 distinct keep-able tokens; the cap-to-20
    # behavior can then be verified. Plan's range(25) only produces 19 keep-ables
    # because w0..w9 are dropped by the len<3 filter, masking the cap.
    text = "alpha beta alpha gamma beta delta " + " ".join(f"w{i}" for i in range(30))
    out = extract_keywords(text)
    assert len(out) == 20
    assert out[0] == "alpha"
    assert out[1] == "beta"


def test_deterministic():
    text = "plan service validate null pointer repository controller"
    assert extract_keywords(text) == extract_keywords(text)


def test_empty_input_returns_empty_list():
    assert extract_keywords("") == []
    assert extract_keywords("   ") == []
