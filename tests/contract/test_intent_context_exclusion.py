"""Contract test: fg-540 dispatch context excludes forbidden keys (Layer 1)."""
from __future__ import annotations

import json

import pytest

from hooks._py.handoff.intent_context import (
    ALLOWED_KEYS,
    IntentContextLeak,
    build_intent_verifier_context,
)


def test_shallow_allow_list(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "List all users",
        "active_spec_slug": "users-api",
        "ac_list": [{"ac_id": "AC-001", "text": "GET /users returns list"}],
        "runtime_config": {"api_base_url": "http://localhost:8080"},
        "probe_sandbox": "<handle>",
        "mode": "standard",
        "plan_notes": "FORBIDDEN CONTENT PLAN",
        "implementation_diff": "FORBIDDEN DIFF",
        "stage_4_notes": "FORBIDDEN TDD",
    }
    built = build_intent_verifier_context(snapshot)
    assert set(built) == set(ALLOWED_KEYS)
    for forbidden_substr in (
        "FORBIDDEN", "plan_notes", "implementation_diff", "stage_4_notes",
    ):
        assert forbidden_substr not in repr(built)


def test_nested_smuggling_blocked(tmp_path, monkeypatch):
    """Caller tries to hide plan text inside requirement_text."""
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "Users API. Plan stage_2_notes_20260422 says...",
        "ac_list": [],
        "mode": "standard",
    }
    with pytest.raises(IntentContextLeak):
        build_intent_verifier_context(snapshot)


def test_empty_ac_list_ok(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    snapshot = {"requirement_text": "x", "ac_list": [], "mode": "standard"}
    built = build_intent_verifier_context(snapshot)
    assert built["ac_list"] == []


def test_persisted_brief_has_no_forbidden_substrings(tmp_path, monkeypatch):
    """AC-702 surface: built context, serialized to disk, greps clean."""
    monkeypatch.chdir(tmp_path)
    built = build_intent_verifier_context({
        "requirement_text": "clean requirement",
        "ac_list": [{"ac_id": "AC-001", "text": "clean AC"}],
        "mode": "standard",
    })
    path = tmp_path / "fg-540-2026.json"
    path.write_text(json.dumps(built))
    txt = path.read_text()
    for sub in (
        "stage_2_notes", "test_code", "implementation_diff",
        "tdd_history", "prior_findings", "git_diff",
    ):
        assert sub not in txt.lower(), f"forbidden substring {sub!r} leaked"
