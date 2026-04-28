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
    # Built keys are a subset of ALLOWED (None values filtered out).
    assert set(built).issubset(set(ALLOWED_KEYS))
    for forbidden_substr in (
        "FORBIDDEN", "plan_notes", "implementation_diff", "stage_4_notes",
    ):
        assert forbidden_substr not in repr(built)


def test_smuggling_via_runtime_config_blocked(tmp_path, monkeypatch):
    """Caller tries to hide plan text inside a non-prose allow-listed key."""
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "clean prose",
        "runtime_config": {"hint": "stage_2_notes_20260422 hidden here"},
        "ac_list": [],
        "mode": "standard",
    }
    with pytest.raises(IntentContextLeak):
        build_intent_verifier_context(snapshot)


def test_smuggling_via_dict_key_blocked(tmp_path, monkeypatch):
    """A forbidden marker hidden in a DICT KEY (not a value) must trip."""
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "ok",
        "runtime_config": {"git_diff_payload": "anything"},  # marker in key
        "ac_list": [],
        "mode": "standard",
    }
    with pytest.raises(IntentContextLeak):
        build_intent_verifier_context(snapshot)


def test_smuggling_via_tuple_blocked(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "ok",
        "runtime_config": {"items": ("safe", "leaked stage_4_notes here")},
        "ac_list": [],
        "mode": "standard",
    }
    with pytest.raises(IntentContextLeak):
        build_intent_verifier_context(snapshot)


def test_smuggling_via_bytes_blocked(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "ok",
        "runtime_config": {"blob": b"hidden tdd_history payload"},
        "ac_list": [],
        "mode": "standard",
    }
    with pytest.raises(IntentContextLeak):
        build_intent_verifier_context(snapshot)


def test_smuggling_via_set_blocked(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "ok",
        "runtime_config": {"flags": frozenset({"safe", "stage_6_notes"})},
        "ac_list": [],
        "mode": "standard",
    }
    with pytest.raises(IntentContextLeak):
        build_intent_verifier_context(snapshot)


def test_unsupported_container_type_fails_closed(tmp_path, monkeypatch):
    """An unrecognized container type should fail closed — masking it would
    silently bypass the leak walker."""
    monkeypatch.chdir(tmp_path)

    class Opaque:
        def __repr__(self) -> str:
            return "<opaque>"

    snapshot = {
        "requirement_text": "ok",
        "runtime_config": {"weird": Opaque()},
        "ac_list": [],
        "mode": "standard",
    }
    with pytest.raises(IntentContextLeak):
        build_intent_verifier_context(snapshot)


def test_requirement_text_exempt_from_substring_check(tmp_path, monkeypatch):
    """User prose may legitimately mention marker names ("the prior_findings
    showed...") without carrying their payloads; the leak check must NOT
    trip on requirement_text."""
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": (
            "Make sure the new endpoint reproduces the git_diff regressions "
            "from prior_findings reports filed last week."
        ),
        "ac_list": [],
        "mode": "standard",
    }
    built = build_intent_verifier_context(snapshot)
    assert "git_diff" in built["requirement_text"]
    assert "prior_findings" in built["requirement_text"]


def test_empty_ac_list_ok(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    snapshot = {"requirement_text": "x", "ac_list": [], "mode": "standard"}
    built = build_intent_verifier_context(snapshot)
    assert built["ac_list"] == []


def test_none_values_filtered(tmp_path, monkeypatch):
    """Missing keys should not appear as None in the built context."""
    monkeypatch.chdir(tmp_path)
    snapshot = {"requirement_text": "x", "mode": "standard"}
    built = build_intent_verifier_context(snapshot)
    assert "active_spec_slug" not in built
    assert "runtime_config" not in built
    assert "probe_sandbox" not in built


def test_persisted_brief_has_no_forbidden_substrings(tmp_path, monkeypatch):
    """AC-702 surface: built context, serialized to disk, greps clean.

    requirement_text is exempt from the substring check, so we use clean
    prose here that the AC-702 grep target would normally see.
    """
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
