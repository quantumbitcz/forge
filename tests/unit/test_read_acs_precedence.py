"""Unit test: _read_acs honors brainstorm-spec precedence per Mega-spec §14."""
from __future__ import annotations

import json
from pathlib import Path

from hooks._py.handoff.intent_context import (
    _read_acs,
    build_intent_verifier_context,
)


def test_brainstorm_spec_path_wins_when_present(tmp_path, monkeypatch):
    spec = tmp_path / "spec.md"
    spec.write_text(
        "# Feature spec\n\n"
        "## Acceptance criteria\n\n"
        "- AC-001: list users returns 200\n"
        "- **AC-002**: empty list returns []\n"
        "- AC-003. pagination respects ?limit=\n"
    )
    monkeypatch.chdir(tmp_path)
    state = {
        "brainstorm": {"spec_path": str(spec)},
        "active_spec_slug": "users-api",  # would normally hit index.json
    }
    acs = _read_acs(state)
    assert [a["ac_id"] for a in acs] == ["AC-001", "AC-002", "AC-003"]
    assert acs[0]["text"].startswith("list users")


def test_falls_back_to_index_when_spec_path_missing(tmp_path, monkeypatch):
    forge = tmp_path / ".forge" / "specs"
    forge.mkdir(parents=True)
    (forge / "index.json").write_text(json.dumps({
        "specs": {
            "users-api": {
                "acceptance_criteria": [
                    {"ac_id": "AC-101", "text": "from index"},
                    {"ac_id": "AC-102", "text": "also from index"},
                ]
            }
        }
    }))
    monkeypatch.chdir(tmp_path)
    state = {
        "brainstorm": {"spec_path": None},  # null is safe
        "active_spec_slug": "users-api",
    }
    acs = _read_acs(state)
    assert [a["ac_id"] for a in acs] == ["AC-101", "AC-102"]


def test_falls_back_when_brainstorm_key_absent(tmp_path, monkeypatch):
    forge = tmp_path / ".forge" / "specs"
    forge.mkdir(parents=True)
    (forge / "index.json").write_text(json.dumps({
        "specs": {"slug-x": {"acceptance_criteria": [{"ac_id": "AC-500", "text": "fallback"}]}}
    }))
    monkeypatch.chdir(tmp_path)
    # No "brainstorm" key at all — bugfix mode, never brainstormed.
    state = {"active_spec_slug": "slug-x"}
    acs = _read_acs(state)
    assert acs == [{"ac_id": "AC-500", "text": "fallback"}]


def test_falls_back_when_spec_path_file_missing(tmp_path, monkeypatch):
    forge = tmp_path / ".forge" / "specs"
    forge.mkdir(parents=True)
    (forge / "index.json").write_text(json.dumps({
        "specs": {"slug-y": {"acceptance_criteria": [{"ac_id": "AC-700", "text": "ok"}]}}
    }))
    monkeypatch.chdir(tmp_path)
    state = {
        "brainstorm": {"spec_path": str(tmp_path / "does-not-exist.md")},
        "active_spec_slug": "slug-y",
    }
    acs = _read_acs(state)
    assert [a["ac_id"] for a in acs] == ["AC-700"]


def test_returns_empty_when_neither_source_resolves(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)  # no spec, no index.json
    assert _read_acs({}) == []
    assert _read_acs({"brainstorm": None, "active_spec_slug": None}) == []


def test_brainstorm_with_no_acs_in_spec_falls_back_to_index(tmp_path, monkeypatch):
    """Spec exists but contains no AC bullets — fall back rather than empty."""
    spec = tmp_path / "empty-spec.md"
    spec.write_text("# Spec with no ACs yet\n\n## Goals\n- ship it\n")
    forge = tmp_path / ".forge" / "specs"
    forge.mkdir(parents=True)
    (forge / "index.json").write_text(json.dumps({
        "specs": {"slug-z": {"acceptance_criteria": [{"ac_id": "AC-900", "text": "from index"}]}}
    }))
    monkeypatch.chdir(tmp_path)
    state = {"brainstorm": {"spec_path": str(spec)}, "active_spec_slug": "slug-z"}
    acs = _read_acs(state)
    assert [a["ac_id"] for a in acs] == ["AC-900"]


def test_build_context_uses_brainstorm_spec(tmp_path, monkeypatch):
    """Surface test: full build_intent_verifier_context honors precedence."""
    spec = tmp_path / "spec.md"
    spec.write_text("- AC-001: works\n")
    monkeypatch.chdir(tmp_path)
    snapshot = {
        "requirement_text": "do the thing",
        "brainstorm": {"spec_path": str(spec)},
        "active_spec_slug": "should-be-ignored",
        "runtime_config": {"api_base_url": "http://localhost"},
        "probe_sandbox": "<handle>",
        "mode": "standard",
    }
    built = build_intent_verifier_context(snapshot)
    assert [a["ac_id"] for a in built["ac_list"]] == ["AC-001"]
