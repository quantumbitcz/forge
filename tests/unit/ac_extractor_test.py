# tests/unit/ac_extractor_test.py
"""Tests for shared/ac-extractor.py — autonomous AC extractor.

The module file uses a hyphen (`shared/ac-extractor.py`) per the spec.
Python's normal import system rejects hyphenated module names, so this
test loads it via importlib.util.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "ac-extractor.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("ac_extractor", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["ac_extractor"] = module
    spec.loader.exec_module(module)
    return module


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
- must A
""".strip()
    result = ac_extractor.extract_acs(text)
    # Numbered "A" and "B" are extracted; "must A" picks up " A" (with leading space) which
    # after strip becomes "A" — duplicate suppressed. Order: A first, B second.
    assert result["acceptance_criteria"][0] == "A"
    assert result["acceptance_criteria"][1] == "B"


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
