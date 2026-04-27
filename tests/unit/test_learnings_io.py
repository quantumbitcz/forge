"""Learnings I/O parser tests — schema v2 only."""
from __future__ import annotations

from pathlib import Path

import pytest

from hooks._py.learnings_io import load_all, parse_file


FIXTURE = Path(__file__).parent.parent / "fixtures" / "learnings" / "spring_v2_expected.md"


def test_parse_v2_items(tmp_path):
    dst = tmp_path / "spring.md"
    dst.write_text(FIXTURE.read_text().replace("__FILE_MTIME__", "2026-04-20T00:00:00Z"))
    items = parse_file(dst)
    assert [i.id for i in items] == ["ks-preempt-001", "ks-preempt-002", "ks-preempt-003"]
    assert all(i.applied_count == 0 for i in items)
    assert all(i.archived is False for i in items)


def test_v1_file_logs_warning_and_skips(tmp_path, caplog):
    v1 = tmp_path / "old.md"
    v1.write_text("---\ndecay_tier: cross-project\n---\n# v1 file\n")
    with caplog.at_level("WARNING"):
        items = parse_file(v1)
    assert items == []
    assert any("v1 file" in rec.message for rec in caplog.records)


def test_load_all_aggregates_directories(tmp_path):
    shared = tmp_path / "shared"
    shared.mkdir()
    shared.joinpath("a.md").write_text(_v2_snippet("a-1"))
    shared.joinpath("b.md").write_text(_v2_snippet("b-1"))
    items = load_all([shared])
    assert sorted(i.id for i in items) == ["a-1", "b-1"]


def _v2_snippet(item_id: str) -> str:
    return (
        "---\nschema_version: 2\nitems:\n"
        f'  - id: "{item_id}"\n'
        '    base_confidence: 0.75\n'
        '    half_life_days: 30\n'
        '    applied_count: 0\n'
        '    last_applied: null\n'
        '    first_seen: "2026-04-20T00:00:00Z"\n'
        '    false_positive_count: 0\n'
        '    last_false_positive_at: null\n'
        '    pre_fp_base: null\n'
        '    applies_to: ["implementer"]\n'
        '    domain_tags: ["spring"]\n'
        '    source: "cross-project"\n'
        '    archived: false\n'
        '    body_ref: "a"\n'
        "---\n# body\n"
    )
