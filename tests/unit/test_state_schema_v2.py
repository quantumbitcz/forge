"""Phase 7 Wave 1 Task 3 — state-schema.md documents intent_verification_results + impl_vote_history."""

from __future__ import annotations

import re
from pathlib import Path

SCHEMA_MD_PATH = (
    Path(__file__).parent.parent.parent
    / "shared"
    / "state-schema.md"
)
SCHEMA_MD = SCHEMA_MD_PATH.read_text(encoding="utf-8")


def test_version_is_v2():
    m = re.search(r"\*\*Version:\*\*\s*([\d.]+)", SCHEMA_MD)
    assert m and m.group(1) == "2.1.0"


def test_intent_fields_documented():
    assert "intent_verification_results" in SCHEMA_MD
    assert "impl_vote_history" in SCHEMA_MD
    assert "Phase 5 / 6 / 7 coordinated bump" in SCHEMA_MD
