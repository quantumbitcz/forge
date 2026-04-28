# tests/unit/ac_extractor_test.py
"""Tests for shared/ac-extractor.py — autonomous AC extractor.

The module file uses a hyphen (`shared/ac-extractor.py`) per the spec.
Python's normal import system rejects hyphenated module names, so we load
it via the conftest helper.
"""
from __future__ import annotations

import pytest

from tests.unit.conftest import load_hyphenated_module


def _load_module():
    return load_hyphenated_module("shared/ac-extractor.py", "ac_extractor")


@pytest.fixture(scope="module")
def ac_extractor():
    return _load_module()


def test_extracts_numbered_list_acs(ac_extractor):
    text = """
1. The system MUST authenticate users.
2. Sessions expire after 30 minutes.
3. Users can reset password via email.
""".strip()
    result = ac_extractor.extract_acs(text)
    assert set(result.keys()) == {"objective", "acceptance_criteria", "confidence"}
    assert len(result["acceptance_criteria"]) == 3
    assert result["confidence"] == "medium"


def test_extracts_given_when_then_acs(ac_extractor):
    text = """
Add OAuth login.

Given a user with valid credentials
When they hit /login
Then a session token is returned
""".strip()
    result = ac_extractor.extract_acs(text)
    assert len(result["acceptance_criteria"]) == 3
    assert any("valid credentials" in ac for ac in result["acceptance_criteria"])
    assert result["confidence"] == "medium"


def test_extracts_imperative_bullets(ac_extractor):
    text = """
- must reject empty passwords
- should expose a /health endpoint
- will accept JSON over POST
""".strip()
    result = ac_extractor.extract_acs(text)
    assert len(result["acceptance_criteria"]) == 3
    assert result["confidence"] == "medium"


def test_low_confidence_when_under_2_acs(ac_extractor):
    result = ac_extractor.extract_acs("Just one bullet point: do something.")
    assert len(result["acceptance_criteria"]) <= 1
    assert result["confidence"] == "low"


def test_high_confidence_with_five_or_more_acs(ac_extractor):
    text = """
1. The API MUST authenticate every request.
2. Sessions expire after 30 minutes of idle.
3. Password reset goes via email.
4. Failed login attempts trigger rate limiting after 5 tries.
5. All endpoints return JSON, never HTML.
6. Errors include a stable error code.
""".strip()
    result = ac_extractor.extract_acs(text)
    assert len(result["acceptance_criteria"]) >= 5
    assert result["confidence"] == "high"


def test_dedup_preserves_first_occurrence_order(ac_extractor):
    text = """
1. A
2. B
- must do X
- must do X
""".strip()
    result = ac_extractor.extract_acs(text)
    # Numbered "A" and "B" + imperative "must do X" (deduped one occurrence).
    assert result["acceptance_criteria"] == ["A", "B", "must do X"]


def test_extracts_in_source_line_order(ac_extractor):
    text = """
- must do X
1. do Y
- must do Z
""".strip()
    result = ac_extractor.extract_acs(text)
    assert result["acceptance_criteria"] == ["must do X", "do Y", "must do Z"]


def test_empty_input_returns_low_confidence(ac_extractor):
    result = ac_extractor.extract_acs("")
    assert result["objective"] == ""
    assert result["acceptance_criteria"] == []
    assert result["confidence"] == "low"


def test_objective_truncated_to_200_chars(ac_extractor):
    long_first_line = "x" * 500
    result = ac_extractor.extract_acs(long_first_line + "\n1. foo\n2. bar")
    assert len(result["objective"]) == 200
    assert result["objective"] == "x" * 200


def test_non_string_input_raises_typeerror(ac_extractor):
    with pytest.raises(TypeError):
        ac_extractor.extract_acs(None)  # type: ignore[arg-type]


@pytest.mark.parametrize(
    "count,expected",
    [
        (0, "low"),
        (1, "low"),
        (2, "medium"),
        (3, "medium"),
        (4, "medium"),
        (5, "high"),
        (6, "high"),
    ],
)
def test_confidence_boundaries(ac_extractor, count, expected):
    text = "\n".join(f"{i + 1}. AC {i + 1}" for i in range(count))
    result = ac_extractor.extract_acs(text)
    assert result["confidence"] == expected
