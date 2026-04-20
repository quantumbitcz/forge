import math
from datetime import datetime, timezone, timedelta

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
