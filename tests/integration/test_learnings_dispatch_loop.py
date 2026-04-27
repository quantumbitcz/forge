"""End-to-end learnings dispatch loop. CI-only.

Runs a scripted orchestrator-ish flow:
  1. Seed a v2 fixture with one item.
  2. Call learnings_io.load_all → select_for_dispatch → render.
  3. Emit forge.learning.injected for each selected item.
  4. Simulate a subagent returning `LEARNING_APPLIED: <id>` in stage notes.
  5. Parse markers, emit forge.learning.applied events.
  6. Run learnings_writeback.apply_events_to_file.
  7. Reload and assert applied_count incremented, base_confidence bumped.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from hooks._py import learnings_format, learnings_io, learnings_markers
from hooks._py.learnings_selector import select_for_dispatch
from hooks._py import learnings_writeback


NOW = datetime(2026, 4, 22, 12, 0, 0, tzinfo=timezone.utc)


def _seed(tmp_path: Path) -> Path:
    dst = tmp_path / "seed.md"
    dst.write_text(
        "---\nschema_version: 2\nitems:\n"
        '  - id: "tx-scope"\n'
        '    base_confidence: 0.80\n'
        '    half_life_days: 30\n'
        '    applied_count: 2\n'
        '    last_applied: "2026-04-15T00:00:00Z"\n'
        '    first_seen: "2026-01-01T00:00:00Z"\n'
        '    false_positive_count: 0\n'
        '    last_false_positive_at: null\n'
        '    pre_fp_base: null\n'
        '    applies_to: ["implementer"]\n'
        '    domain_tags: ["spring", "persistence"]\n'
        '    source: "cross-project"\n'
        '    archived: false\n'
        '    body_ref: "#tx-scope"\n'
        "---\n"
        "# body\n"
        "<a id=\"tx-scope\"></a>\n"
        "The persistence layer tends to leak @Transactional boundaries.\n",
        encoding="utf-8",
    )
    return dst


def test_full_loop_reinforces_on_applied_marker(tmp_path):
    seed = _seed(tmp_path)
    items = learnings_io.load_all([tmp_path], now=NOW)
    assert len(items) == 1

    selected = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring", "persistence"], component="api",
        candidates=items, now=NOW,
    )
    assert [i.id for i in selected] == ["tx-scope"]
    block = learnings_format.render(selected)
    assert "## Relevant Learnings" in block

    subagent_notes = "... LEARNING_APPLIED: tx-scope ..."
    markers = learnings_markers.parse_markers(subagent_notes)
    events = [
        {"type": "forge.learning.applied", "forge.learning.id": iid}
        for kind, iid, _ in markers if kind == "applied"
    ]
    learnings_writeback.apply_events_to_file(seed, events, NOW)

    reloaded = learnings_io.load_all([tmp_path], now=NOW)
    assert reloaded[0].applied_count == 3
    assert reloaded[0].base_confidence == 0.85


def test_critical_without_marker_no_change(tmp_path):
    """AC9 case (a): CRITICAL in same domain without marker → no mutation."""
    seed = _seed(tmp_path)
    events: list[dict] = []  # simulate: reviewer raised CRITICAL but no LEARNING_FP
    changed = learnings_writeback.apply_events_to_file(seed, events, NOW)
    assert changed is False
    reloaded = learnings_io.load_all([tmp_path], now=NOW)
    assert reloaded[0].base_confidence == 0.80
    assert reloaded[0].applied_count == 2


def test_fp_marker_applies_penalty_and_snapshot(tmp_path):
    """AC9 case (b): LEARNING_FP marker → *= 0.80 and pre_fp_base set."""
    seed = _seed(tmp_path)
    events = [{
        "type": "forge.learning.fp",
        "forge.learning.id": "tx-scope",
        "forge.learning.reason": "not applicable for this task",
    }]
    learnings_writeback.apply_events_to_file(seed, events, NOW)
    raw = seed.read_text()
    assert "pre_fp_base: 0.8" in raw
    # 0.80 * 0.80 = 0.64 (may serialise as 0.64 or 0.6400000000000001)
    assert "base_confidence: 0.64" in raw or "base_confidence: 0.6400000000000001" in raw
