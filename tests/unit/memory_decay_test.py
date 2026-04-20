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
