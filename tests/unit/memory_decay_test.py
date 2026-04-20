import json
import math
import subprocess
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

import pytest

from hooks._py import memory_decay as md


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def test_formula_at_zero_time_returns_base():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.75,
        "last_success_at": _iso(now),
        "last_false_positive_at": None,
    }
    assert md.effective_confidence(item, now) == pytest.approx(0.75, abs=1e-9)


def test_formula_at_one_half_life_is_half_base():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.75,
        "last_success_at": _iso(now - timedelta(days=14)),
        "last_false_positive_at": None,
    }
    assert md.effective_confidence(item, now) == pytest.approx(0.375, abs=1e-9)


def test_formula_at_two_half_lives_is_quarter_base():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.75,
        "last_success_at": _iso(now - timedelta(days=28)),
        "last_false_positive_at": None,
    }
    assert md.effective_confidence(item, now) == pytest.approx(0.1875, abs=1e-9)


@pytest.mark.parametrize("conf,expected", [
    (0.95, "HIGH"),
    (0.75, "HIGH"),
    (0.749, "MEDIUM"),
    (0.50, "MEDIUM"),
    (0.499, "LOW"),
    (0.30, "LOW"),
    (0.299, "ARCHIVED"),
    (0.0, "ARCHIVED"),
])
def test_tier_boundaries(conf, expected):
    assert md.tier(conf) == expected


def test_clock_skew_clamps_future_timestamp_to_zero():
    # Item's last_success_at in the future (clock skew) → Δt clamped to 0 → full base.
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.75,
        "last_success_at": _iso(now + timedelta(days=5)),
        "last_false_positive_at": None,
    }
    assert md.effective_confidence(item, now) == pytest.approx(0.75, abs=1e-9)


def test_clock_skew_clamps_ancient_timestamp_to_one_year():
    # Δt capped at 365 days even if last_success_at is 10 years old.
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    ancient = now - timedelta(days=3650)
    item = {
        "id": "x",
        "type": "auto-discovered",  # HL=14
        "base_confidence": 0.75,
        "last_success_at": _iso(ancient),
        "last_false_positive_at": None,
    }
    # Clamped Δt = 365 → 0.75 * 2^(-365/14) ≈ 1.15e-8 (not 2^(-3650/14) ≈ 0).
    expected = 0.75 * (2 ** (-365 / 14))
    assert md.effective_confidence(item, now) == pytest.approx(expected, abs=1e-12)


def test_apply_success_resets_clock_and_adds_bonus():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.75,
        "last_success_at": _iso(now - timedelta(days=100)),
        "last_false_positive_at": None,
    }
    out = md.apply_success(item, now)
    assert out["last_success_at"] == _iso(now)
    assert out["base_confidence"] == pytest.approx(0.80, abs=1e-9)


def test_apply_success_caps_at_0_95():
    """Review Issue 1: cap must be 0.95, not 1.0, to preserve FP penalty effectiveness."""
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.94,
        "last_success_at": _iso(now),
        "last_false_positive_at": None,
    }
    out = md.apply_success(item, now)
    assert out["base_confidence"] == pytest.approx(0.95, abs=1e-9)

    # Second success does not push past 0.95.
    out2 = md.apply_success(out, now)
    assert out2["base_confidence"] == pytest.approx(0.95, abs=1e-9)


def test_apply_success_returns_new_dict_not_mutation():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.75,
        "last_success_at": _iso(now - timedelta(days=10)),
        "last_false_positive_at": None,
    }
    original_base = item["base_confidence"]
    md.apply_success(item, now)
    # Input must be untouched — callers decide when to persist.
    assert item["base_confidence"] == original_base


def test_apply_false_positive_drops_and_resets():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "auto-discovered",
        "base_confidence": 0.80,
        "last_success_at": _iso(now - timedelta(days=30)),
        "last_false_positive_at": None,
    }
    out = md.apply_false_positive(item, now)
    assert out["base_confidence"] == pytest.approx(0.64, abs=1e-9)  # 0.80 * 0.80
    assert out["last_success_at"] == _iso(now)
    assert out["last_false_positive_at"] == _iso(now)


def test_apply_false_positive_on_maxed_item_drops_to_0_76():
    """Verifies the 0.95 ceiling (Task 4) still produces a meaningful demotion."""
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "type": "canonical",
        "base_confidence": 0.95,
        "last_success_at": _iso(now),
        "last_false_positive_at": None,
    }
    out = md.apply_false_positive(item, now)
    assert out["base_confidence"] == pytest.approx(0.76, abs=1e-9)  # 0.95 * 0.80


def test_migrate_legacy_high_item():
    """Legacy HIGH tier maps to base 0.95 (clamped to ceiling)."""
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    legacy = {
        "id": "legacy-1",
        "pattern": "...",
        "confidence": "HIGH",
        "source": "auto-discovered",
        "runs_since_last_hit": 4,
        "decay_multiplier": 2,
    }
    out = md.migrate_item(legacy, now)
    assert out["base_confidence"] == pytest.approx(0.95, abs=1e-9)
    assert out["last_success_at"] == _iso(now)
    assert out["last_false_positive_at"] is None
    assert out["type"] == "auto-discovered"
    # Legacy fields deleted.
    assert "runs_since_last_hit" not in out
    assert "decay_multiplier" not in out
    assert "confidence" not in out  # legacy string tier removed


def test_migrate_legacy_medium_low_archived_tiers():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    for legacy_tier, expected_base in [
        ("MEDIUM", 0.75),
        ("LOW", 0.50),
        ("ARCHIVED", 0.30),
    ]:
        item = {"id": "x", "confidence": legacy_tier, "source": "user-confirmed"}
        out = md.migrate_item(item, now)
        assert out["base_confidence"] == pytest.approx(expected_base, abs=1e-9)
        assert out["type"] == "canonical"


def test_migrate_is_idempotent():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item = {
        "id": "x",
        "confidence": "MEDIUM",
        "source": "auto-discovered",
    }
    once = md.migrate_item(item, now)
    twice = md.migrate_item(once, now)
    assert once == twice


def test_migrate_skips_already_migrated_items():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    already = {
        "id": "x",
        "type": "canonical",
        "base_confidence": 0.80,
        "last_success_at": _iso(now - timedelta(days=5)),
        "last_false_positive_at": None,
    }
    out = md.migrate_item(already, now)
    assert out == already  # no mutation


@pytest.mark.parametrize("item,expected_type", [
    ({"type": "auto-discovered"}, "auto-discovered"),
    ({"source": "auto-discovered"}, "auto-discovered"),
    ({"source": "user-confirmed"}, "canonical"),
    ({"state": "ACTIVE"}, "canonical"),
    ({"source_path": "shared/learnings/spring.md"}, "cross-project"),
    ({}, "cross-project"),
])
def test_type_inference(item, expected_type):
    # Exercise the type resolver via the migrator (sets item["type"]).
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    item.setdefault("confidence", "MEDIUM")
    out = md.migrate_item(item, now)
    assert out["type"] == expected_type


def test_type_half_life_selection_differs_for_same_age():
    """Three items, same age (14 days), three types → three distinct confidences."""
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    fourteen_days_ago = _iso(now - timedelta(days=14))
    base = 0.75
    auto = {"id": "a", "type": "auto-discovered", "base_confidence": base,
            "last_success_at": fourteen_days_ago, "last_false_positive_at": None}
    cross = {"id": "c", "type": "cross-project", "base_confidence": base,
             "last_success_at": fourteen_days_ago, "last_false_positive_at": None}
    canon = {"id": "k", "type": "canonical", "base_confidence": base,
             "last_success_at": fourteen_days_ago, "last_false_positive_at": None}

    # Auto: exactly one half-life → 0.375.
    assert md.effective_confidence(auto, now) == pytest.approx(0.375, abs=1e-9)
    # Cross: 14/30 half-lives → 0.75 * 2^(-14/30).
    assert md.effective_confidence(cross, now) == pytest.approx(0.75 * (2 ** (-14 / 30)), abs=1e-9)
    # Canon: 14/90 half-lives → 0.75 * 2^(-14/90).
    assert md.effective_confidence(canon, now) == pytest.approx(0.75 * (2 ** (-14 / 90)), abs=1e-9)

    # And they must be strictly ordered.
    auto_c = md.effective_confidence(auto, now)
    cross_c = md.effective_confidence(cross, now)
    canon_c = md.effective_confidence(canon, now)
    assert auto_c < cross_c < canon_c


def test_cli_dry_run_recompute_prints_tier_per_item(tmp_path: Path):
    """The --dry-run-recompute flag reads JSON from a directory and prints id,tier per line."""
    fixture_dir = tmp_path / "memory"
    fixture_dir.mkdir()
    (fixture_dir / "a.json").write_text(json.dumps({
        "id": "a",
        "type": "auto-discovered",
        "base_confidence": 0.75,
        "last_success_at": "2026-04-19T12:00:00Z",
        "last_false_positive_at": None,
    }))
    result = subprocess.run(
        [sys.executable, "-m", "hooks._py.memory_decay",
         "--dry-run-recompute", str(fixture_dir),
         "--now", "2026-04-19T12:00:00Z"],
        capture_output=True, text=True, check=True,
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert any("a" in line and "HIGH" in line for line in lines)


def test_count_recent_false_positives_counts_within_window():
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    items = [
        {"id": "1", "last_false_positive_at": _iso(now - timedelta(days=1))},   # in window
        {"id": "2", "last_false_positive_at": _iso(now - timedelta(days=6))},   # in window
        {"id": "3", "last_false_positive_at": _iso(now - timedelta(days=8))},   # out
        {"id": "4", "last_false_positive_at": None},                            # out
        {"id": "5"},                                                             # out (missing)
    ]
    assert md.count_recent_false_positives(items, now, window_days=7) == 2


def test_count_recent_false_positives_handles_clock_skew():
    """A timestamp in the future counts as zero, not as 'in window'."""
    now = datetime(2026, 4, 19, 12, 0, 0, tzinfo=timezone.utc)
    items = [{"id": "x", "last_false_positive_at": _iso(now + timedelta(days=3))}]
    assert md.count_recent_false_positives(items, now, window_days=7) == 0
