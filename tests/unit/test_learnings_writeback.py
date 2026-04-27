"""Retrospective write-back tests — event log → v2 frontmatter mutation."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from hooks._py.learnings_writeback import apply_events_to_file


NOW = datetime(2026, 4, 22, 12, 0, 0, tzinfo=timezone.utc)


def _make_v2(tmp_path: Path, item_id: str, **overrides) -> Path:
    base = {
        "base_confidence": "0.80",
        "applied_count": "0",
        "false_positive_count": "0",
        "pre_fp_base": "null",
        "archived": "false",
    }
    base.update({k: str(v) for k, v in overrides.items()})
    dst = tmp_path / "t.md"
    dst.write_text(
        "---\nschema_version: 2\nitems:\n"
        f'  - id: "{item_id}"\n'
        f'    base_confidence: {base["base_confidence"]}\n'
        '    half_life_days: 30\n'
        f'    applied_count: {base["applied_count"]}\n'
        '    last_applied: null\n'
        '    first_seen: "2026-04-20T00:00:00Z"\n'
        f'    false_positive_count: {base["false_positive_count"]}\n'
        '    last_false_positive_at: null\n'
        f'    pre_fp_base: {base["pre_fp_base"]}\n'
        '    applies_to: ["implementer"]\n'
        '    domain_tags: ["spring"]\n'
        '    source: "cross-project"\n'
        f'    archived: {base["archived"]}\n'
        '    body_ref: "x"\n'
        "---\n# body\n",
        encoding="utf-8",
    )
    return dst


def test_applied_event_reinforces(tmp_path):
    f = _make_v2(tmp_path, "foo", base_confidence=0.80, applied_count=2)
    events = [{"type": "forge.learning.applied", "forge.learning.id": "foo"}]
    changed = apply_events_to_file(f, events, NOW)
    assert changed is True
    txt = f.read_text()
    assert "base_confidence: 0.85" in txt
    assert "applied_count: 3" in txt


def test_fp_event_decrements_with_snapshot(tmp_path):
    f = _make_v2(tmp_path, "foo", base_confidence=0.80)
    events = [{"type": "forge.learning.fp", "forge.learning.id": "foo"}]
    apply_events_to_file(f, events, NOW)
    txt = f.read_text()
    assert "base_confidence: 0.6400000000000001" in txt or "base_confidence: 0.64" in txt
    assert "pre_fp_base: 0.8" in txt


def test_vindicate_restores_snapshot(tmp_path):
    f = _make_v2(tmp_path, "foo", base_confidence=0.64, pre_fp_base=0.80,
                 false_positive_count=1)
    events = [{"type": "forge.learning.vindicated", "forge.learning.id": "foo"}]
    apply_events_to_file(f, events, NOW)
    txt = f.read_text()
    assert "base_confidence: 0.8" in txt
    assert "pre_fp_base: null" in txt
    assert "false_positive_count: 0" in txt


def test_critical_finding_without_marker_is_no_op(tmp_path):
    f = _make_v2(tmp_path, "foo", base_confidence=0.80)
    events: list[dict] = []  # no learning.* events; AC9 case (a)
    changed = apply_events_to_file(f, events, NOW)
    assert changed is False
    assert "base_confidence: 0.8" in f.read_text()


def test_archival_floor_marks_archived(tmp_path):
    # Very low base, no recent apply, >90 days idle → archived.
    old = "2025-01-01T00:00:00Z"
    f = tmp_path / "old.md"
    f.write_text(
        "---\nschema_version: 2\nitems:\n"
        '  - id: "tiny"\n'
        '    base_confidence: 0.05\n'
        '    half_life_days: 14\n'
        '    applied_count: 0\n'
        '    last_applied: null\n'
        f'    first_seen: "{old}"\n'
        '    false_positive_count: 0\n'
        '    last_false_positive_at: null\n'
        '    pre_fp_base: null\n'
        '    applies_to: ["implementer"]\n'
        '    domain_tags: ["spring"]\n'
        '    source: "auto-discovered"\n'
        '    archived: false\n'
        '    body_ref: "x"\n'
        "---\n# body\n",
        encoding="utf-8",
    )
    apply_events_to_file(f, [], NOW)
    assert "archived: true" in f.read_text()
