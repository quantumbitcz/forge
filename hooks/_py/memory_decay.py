"""Ebbinghaus-curve memory decay for Forge PREEMPT items.

All I/O-free. Callers supply records, save them. Stdlib-only.
"""
from __future__ import annotations

import math
from datetime import datetime, timezone
from typing import Any, Dict, Optional

HALF_LIFE_DAYS: Dict[str, int] = {
    "auto-discovered": 14,
    "cross-project": 30,
    "canonical": 90,
}

THRESHOLDS: Dict[str, float] = {
    "high": 0.75,
    "medium": 0.50,
    "low": 0.30,
}

DEFAULT_BASE_CONFIDENCE: float = 0.75
MAX_BASE_CONFIDENCE: float = 0.95  # cap <1.0 so FP penalty stays meaningful
SUCCESS_BONUS: float = 0.05
FALSE_POSITIVE_PENALTY: float = 0.20  # new_base = base * (1 - penalty)
DELTA_T_MAX_DAYS: int = 365  # clock-skew clamp
DELTA_T_MIN_DAYS: int = 0


def _parse_iso(s: str) -> datetime:
    """Parse ISO 8601 'Z' or '+00:00' form. Stdlib only."""
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s).astimezone(timezone.utc)


def effective_confidence(item: Dict[str, Any], now: datetime) -> float:
    """Compute decayed confidence. Read-only; does not mutate `item`."""
    base = float(item.get("base_confidence", DEFAULT_BASE_CONFIDENCE))
    last = _parse_iso(item["last_success_at"])
    item_type = _resolve_type(item)
    half_life = HALF_LIFE_DAYS[item_type]
    raw_delta_days = (now - last).total_seconds() / 86400.0
    # Clock-skew clamp (§10 Risk 4 of the spec).
    delta_days = max(DELTA_T_MIN_DAYS, min(DELTA_T_MAX_DAYS, raw_delta_days))
    return base * math.pow(2.0, -delta_days / half_life)


def _resolve_type(item: Dict[str, Any]) -> str:
    """Per §4.1 of the spec."""
    t = item.get("type")
    if t in HALF_LIFE_DAYS:
        return t
    source = item.get("source", "")
    if source == "auto-discovered":
        return "auto-discovered"
    if source == "user-confirmed" or item.get("state") == "ACTIVE":
        return "canonical"
    path = item.get("source_path", "")
    if "shared/learnings/" in path:
        return "cross-project"
    return "cross-project"


def tier(confidence: float) -> str:
    """Map a decayed confidence to its discrete tier."""
    if confidence >= THRESHOLDS["high"]:
        return "HIGH"
    if confidence >= THRESHOLDS["medium"]:
        return "MEDIUM"
    if confidence >= THRESHOLDS["low"]:
        return "LOW"
    return "ARCHIVED"
