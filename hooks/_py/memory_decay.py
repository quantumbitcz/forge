"""Ebbinghaus-curve memory decay for Forge PREEMPT items.

All I/O-free. Callers supply records, save them. Stdlib-only.
"""
from __future__ import annotations

import json
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


def apply_success(item: Dict[str, Any], now: datetime) -> Dict[str, Any]:
    """Return a new item reflecting a successful reinforcement.

    Cap is MAX_BASE_CONFIDENCE (0.95), NOT 1.0 — review Issue 1. Keeping a
    headroom of 0.05 ensures the 20 % FP penalty still drops a maxed-out item
    down to 0.76, which lands in the HIGH band but close to the MEDIUM cutoff.
    """
    out = dict(item)
    out["base_confidence"] = min(
        MAX_BASE_CONFIDENCE,
        float(item.get("base_confidence", DEFAULT_BASE_CONFIDENCE)) + SUCCESS_BONUS,
    )
    out["last_success_at"] = _format_iso(now)
    return out


def apply_false_positive(item: Dict[str, Any], now: datetime) -> Dict[str, Any]:
    """Return a new item reflecting a confirmed false positive.

    Penalty is multiplicative (base *= 0.80). We reset last_success_at = now so
    the penalty shows as a fresh new base, not as a compounded base × decay
    value. This is intentional (§4.2 of the spec) — it prevents over-punishment
    combining the penalty with stale-decay on the same event.
    """
    out = dict(item)
    out["base_confidence"] = (
        float(item.get("base_confidence", DEFAULT_BASE_CONFIDENCE))
        * (1.0 - FALSE_POSITIVE_PENALTY)
    )
    stamp = _format_iso(now)
    out["last_success_at"] = stamp
    out["last_false_positive_at"] = stamp
    return out


def _format_iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


_LEGACY_TIER_TO_BASE: Dict[str, float] = {
    "HIGH": MAX_BASE_CONFIDENCE,  # 0.95 — clamped so migration respects the ceiling.
    "MEDIUM": 0.75,
    "LOW": 0.50,
    "ARCHIVED": 0.30,
}


def migrate_item(item: Dict[str, Any], now: datetime) -> Dict[str, Any]:
    """One-time migrator. Idempotent: already-migrated items pass through unchanged.

    Warm-start: every pre-existing item receives `last_success_at = now` so the
    first post-migration PREFLIGHT does not mass-archive. §7 of the spec.
    """
    if "last_success_at" in item and "base_confidence" in item:
        return dict(item)  # already migrated — copy and return.

    out = dict(item)
    legacy_tier = str(out.pop("confidence", "MEDIUM")).upper()
    out["base_confidence"] = _LEGACY_TIER_TO_BASE.get(legacy_tier, DEFAULT_BASE_CONFIDENCE)
    out["last_success_at"] = _format_iso(now)
    out["last_false_positive_at"] = None
    out["type"] = _resolve_type(out)
    out.pop("runs_since_last_hit", None)
    out.pop("decay_multiplier", None)
    return out


def _cli_dry_run_recompute(directory: str, now: datetime) -> int:
    """Read every *.json in `directory`, recompute tier, print 'id\\ttier\\tconfidence'."""
    import os
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(directory, name)
        with open(path, "r", encoding="utf-8") as fh:
            item = json.load(fh)
        if "last_success_at" not in item:
            item = migrate_item(item, now)
        c = effective_confidence(item, now)
        t = tier(c)
        print(f"{item['id']}\t{t}\t{c:.6f}")
    return 0


def _main(argv: list) -> int:
    import argparse
    parser = argparse.ArgumentParser(description="Memory decay recompute tool.")
    parser.add_argument("--dry-run-recompute", metavar="DIR", help="Directory of JSON items")
    parser.add_argument("--now", metavar="ISO", help="Override now (ISO 8601 UTC)")
    args = parser.parse_args(argv)
    if args.now:
        now = _parse_iso(args.now)
    else:
        now = datetime.now(tz=timezone.utc)
    if args.dry_run_recompute:
        return _cli_dry_run_recompute(args.dry_run_recompute, now)
    parser.print_help()
    return 1


if __name__ == "__main__":
    import sys as _sys
    _sys.exit(_main(_sys.argv[1:]))
