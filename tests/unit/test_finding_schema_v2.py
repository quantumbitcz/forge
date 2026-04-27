"""Phase 7 Wave 1 Task 1 — finding schema v2 nullability + conditional ac_id."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, ValidationError

SCHEMA_PATH = (
    Path(__file__).parent.parent.parent
    / "shared"
    / "checks"
    / "finding-schema.json"
)
SCHEMA = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
V = Draft202012Validator(SCHEMA)


def test_intent_finding_null_file_line_passes():
    V.validate({
        "category": "INTENT-MISSED",
        "severity": "CRITICAL",
        "description": "GET /users returned {}.",
        "fix_hint": "Implement list endpoint.",
        "file": None,
        "line": None,
        "ac_id": "AC-042",
    })


def test_reviewer_finding_with_file_line_passes():
    V.validate({
        "category": "SEC-INJECTION-USER-INPUT",
        "severity": "CRITICAL",
        "description": "Unsanitized input.",
        "fix_hint": "Use parameterized query.",
        "file": "src/api/users.py",
        "line": 42,
    })


def test_reviewer_finding_missing_file_fails():
    with pytest.raises(ValidationError):
        V.validate({
            "category": "SEC-INJECTION-USER-INPUT",
            "severity": "CRITICAL",
            "description": "Unsanitized input.",
            "fix_hint": "Use parameterized query.",
            "line": 42,
        })


def test_intent_finding_missing_ac_id_fails():
    with pytest.raises(ValidationError):
        V.validate({
            "category": "INTENT-MISSED",
            "severity": "CRITICAL",
            "description": "GET /users returned {}.",
            "fix_hint": "Implement list endpoint.",
            "file": None,
            "line": None,
        })
