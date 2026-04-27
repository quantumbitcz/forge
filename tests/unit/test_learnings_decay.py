"""Decay transition tests for Phase 4.

CI-only. Do NOT run locally — push to feat/phase-4-learnings-dispatch-loop
and inspect test.yml job output.
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

import pytest

from hooks._py import memory_decay


UTC = timezone.utc
NOW = datetime(2026, 4, 22, 12, 0, 0, tzinfo=UTC)


def _item(**overrides):
    base = {
        "id": "demo",
        "base_confidence": 0.80,
        "type": "cross-project",
        "last_success_at": "2026-04-22T12:00:00Z",
        "source": "cross-project",
    }
    base.update(overrides)
    return base


def test_fresh_learning_reads_close_to_base():
    item = _item(base_confidence=0.75, last_success_at="2026-04-22T12:00:00Z")
    c = memory_decay.effective_confidence(item, NOW)
    assert math.isclose(c, 0.75, abs_tol=1e-9)


def test_one_half_life_halves_confidence():
    item = _item(base_confidence=0.80, last_success_at="2026-03-23T12:00:00Z")
    c = memory_decay.effective_confidence(item, NOW)
    assert math.isclose(c, 0.40, abs_tol=1e-6)


def test_success_reinforcement_hits_ceiling():
    item = _item(base_confidence=0.85)
    for _ in range(20):
        item = memory_decay.apply_success(item, NOW)
    assert item["base_confidence"] == memory_decay.MAX_BASE_CONFIDENCE
    assert item["base_confidence"] == 0.95


def test_false_positive_single_cycle_bit_exact():
    item = _item(base_confidence=0.80)
    fp = memory_decay.apply_false_positive(item, NOW)
    assert fp["base_confidence"] == 0.80 * 0.80  # bit-exact 0.64
    assert fp["pre_fp_base"] == 0.80
    v = memory_decay.apply_vindication(fp, NOW)
    assert v["base_confidence"] == 0.80  # bit-exact restore
    assert v["pre_fp_base"] is None
    assert v.get("false_positive_count", 0) == 0


def test_false_positive_N_cycles_bit_exact():
    item = _item(base_confidence=0.80, false_positive_count=0)
    for _ in range(100):
        item = memory_decay.apply_false_positive(item, NOW)
        item = memory_decay.apply_vindication(item, NOW)
    assert item["base_confidence"] == 0.80  # bit-exact ==, not isclose
    assert item["pre_fp_base"] is None
    assert item["false_positive_count"] == 0


def test_archival_floor():
    old = datetime(2025, 10, 24, 12, 0, 0, tzinfo=UTC)  # 180 days ago
    item = _item(
        base_confidence=0.30,
        type="auto-discovered",
        last_success_at=old.isoformat().replace("+00:00", "Z"),
        last_applied=None,
        first_seen=old.isoformat().replace("+00:00", "Z"),
    )
    archived, reason = memory_decay.archival_floor(item, NOW)
    assert archived is True
    assert "confidence" in reason


def test_vindicate_without_snapshot_logs_warning(caplog):
    item = _item(base_confidence=0.64, pre_fp_base=None, false_positive_count=1)
    with caplog.at_level("WARNING"):
        out = memory_decay.apply_vindication(item, NOW)
    # Defensive fallback: base × 1.25 capped at 0.95.
    assert math.isclose(out["base_confidence"], min(0.95, 0.64 * 1.25), abs_tol=1e-9)
    assert out["pre_fp_base"] is None
    assert any("pre_fp_base" in rec.message for rec in caplog.records)
