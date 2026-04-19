# Phase 13 — Memory Decay (Ebbinghaus) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Forge's counter-based PREEMPT decay with a time-aware Ebbinghaus exponential forgetting curve (`confidence(t) = base × 2^(-Δt / half_life)`) with per-type half-lives (auto-discovered 14d, cross-project 30d, canonical 90d).

**Architecture:** Pure-Python stdlib module at `hooks/_py/memory_decay.py` exports the formula, tier mapping, reinforcement/penalty helpers, and a one-shot migrator. `fg-700-retrospective` writes authoritative confidence + tier at LEARN; the PREFLIGHT loader in `fg-100-orchestrator` calls it read-only. A single on-disk warm-start migrator stamps legacy items with `last_success_at = now`. A canonical spec lives at `shared/learnings/decay.md`; every other doc points at it.

**Tech Stack:** Python 3.10+ stdlib only (`math`, `datetime`, `json`); BATS for harness; markdown for contract docs; no third-party deps. Depends on Phase 02 (Python hooks) for `hooks/_py/` directory and `python3` runner.

**No backwards compatibility.** Legacy fields (`runs_since_last_hit`, `decay_multiplier`) are deleted by migrator. Every task commits independently using Conventional Commits.

---

## File Structure

### New files
- `hooks/_py/memory_decay.py` — decay math, half-life map, tier function, reinforcement/penalty, migrator, Δt clamp. Stdlib-only.
- `shared/learnings/decay.md` — canonical prose contract: formula, half-lives, thresholds, reinforcement rules, lazy-read / authoritative-write touchpoints, tuning warning.
- `tests/unit/memory_decay_test.py` — pure-Python pytest-style unit tests (10 tests per §8 of spec + one extra for clock-skew clamp + one for `base_confidence` ceiling at 0.95).
- `tests/evals/memory_decay_eval.sh` — shell harness running a synthetic fixture through `memory_decay.py --dry-run-recompute` and asserting tier grid.
- `tests/evals/fixtures/memory_decay/` — JSON fixture directory (fresh/mid/stale × 3 types + legacy-field fixtures + false-positive fixture).

### Modified files
- `agents/fg-700-retrospective.md` — LEARN stage: call `apply_success`, `apply_false_positive`, compute effective confidence + tier, archive demoted items, emit summary line (including `last_false_positive_at`-derived "last FP in last 7d: K" counter). Remove `runs_since_last_hit` / `decay_multiplier`.
- `agents/fg-100-orchestrator.md` — PREFLIGHT PREEMPT loader calls `effective_confidence` + `tier` read-only; filters ARCHIVED; on-first-load passes records missing `last_success_at` through `migrate_item`.
- `shared/learnings/README.md` — §PREEMPT Lifecycle replaced with pointer to `decay.md`; old table struck-through with supersession note.
- `shared/learnings/memory-discovery.md` — §Promotion and Decay rewritten to cite `decay.md`; "5 unused runs" and `decay_multiplier: 2` tables removed; MEDIUM→HIGH-after-3-successes promotion preserved.
- `shared/learnings/rule-promotion.md` — §Decay Rules: "5 inactive runs → demote" replaced with tier-threshold reference to `decay.md`.
- `shared/knowledge-base.md` — one-line pointer replacing "10 unused runs" phrasing.
- `shared/agent-communication.md` — two call-sites (L273, L302) updated: `false positive = 3 unused runs` removed, replaced with `confidence *= 0.8` language and reference to `decay.md`.
- `shared/domain-detection.md` — text references to "per-domain PREEMPT decay" clarified; formula unchanged (decay still keys on domain bucketing).
- `CLAUDE.md` — §Gotchas bullet "PREEMPT decay: 10 unused → ..." replaced with one-line pointer to `shared/learnings/decay.md`. Version note bumped to reflect Phase 13 change.
- `DEPRECATIONS.md` — L91 entry "PREEMPT decay: 10 unused cycles → ..." updated with Phase-13 supersession reference.
- `benchmarks/prompts.json` — prompt at L15 and `required_facts` at L16 updated so the evaluation benchmark describes the Ebbinghaus model (not the legacy counter model).
- Every `shared/learnings/*.md` file that ships PREEMPT items in frontmatter — hand-stamp `last_success_at`, `base_confidence`, `type` on each item.

---

## Review-feedback integration (non-blocking suggestions)

1. **Cap `base_confidence` at 0.95 (not 1.0)** — Issue 1 of the review. Addressed in Task 4 below (constant `MAX_BASE_CONFIDENCE = 0.95`) and exercised in Task 5 unit test `test_apply_success_caps_at_0_95`.
2. **Add a reader for `last_false_positive_at`** — Issue 2. Addressed in Task 10: `fg-700` summary line includes `last FP in last 7d: K items`. Unit test `test_count_recent_false_positives` in Task 11.
3. **Tuning warning on `success_bonus` vs `false_positive_penalty` polarity** — Issue 3. Addressed in Task 3 when writing `shared/learnings/decay.md` §Tuning warning, and reiterated as a comment block in the default `forge-config.md` snippet referenced from that doc.

---

## Task 1: Create decay module skeleton with formula + constants

**Files:**
- Create: `hooks/_py/memory_decay.py`
- Test: `tests/unit/memory_decay_test.py`

- [ ] **Step 1: Write the failing formula test**

```python
# tests/unit/memory_decay_test.py
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: `ModuleNotFoundError: No module named 'hooks._py.memory_decay'` (test collection fails).

- [ ] **Step 3: Create the package and write minimal implementation**

```bash
mkdir -p hooks/_py tests/unit
touch hooks/_py/__init__.py tests/unit/__init__.py
```

```python
# hooks/_py/memory_decay.py
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/__init__.py hooks/_py/memory_decay.py tests/unit/__init__.py tests/unit/memory_decay_test.py
git commit -m "feat(phase13): add Ebbinghaus decay formula with half-life map"
```

---

## Task 2: Add tier mapping + clock-skew clamp tests

**Files:**
- Modify: `hooks/_py/memory_decay.py` (append)
- Test: `tests/unit/memory_decay_test.py` (append)

- [ ] **Step 1: Append failing tier tests**

```python
# tests/unit/memory_decay_test.py (append)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v -k "tier or clock_skew"`
Expected: `AttributeError: module 'hooks._py.memory_decay' has no attribute 'tier'` for the tier tests. Clock-skew tests should already pass from Task 1 (verify they do).

- [ ] **Step 3: Implement `tier()` in the module**

```python
# hooks/_py/memory_decay.py (append)
def tier(confidence: float) -> str:
    """Map a decayed confidence to its discrete tier."""
    if confidence >= THRESHOLDS["high"]:
        return "HIGH"
    if confidence >= THRESHOLDS["medium"]:
        return "MEDIUM"
    if confidence >= THRESHOLDS["low"]:
        return "LOW"
    return "ARCHIVED"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: all 6 tests pass (3 from Task 1 + tier + 2 clock-skew).

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/memory_decay.py tests/unit/memory_decay_test.py
git commit -m "feat(phase13): add tier mapping and clock-skew Δt clamp"
```

---

## Task 3: Write canonical `shared/learnings/decay.md` contract

**Files:**
- Create: `shared/learnings/decay.md`

- [ ] **Step 1: Write the canonical contract doc**

Write the file with these required sections. All numerics match `memory_decay.py` constants — any deviation is a bug.

```markdown
# Memory Decay — Ebbinghaus Exponential Curve

**Status:** Active (Phase 13, 2026-04-19).
**Supersedes:** Counter-based decay in `shared/learnings/README.md` §PREEMPT Lifecycle.

## 1. Formula

    confidence(t) = base_confidence × 2^(-Δt_days / half_life_days)

where `Δt_days = (now - last_success_at) / 86_400` (seconds), clamped to `[0, 365]`.

## 2. Per-type half-lives

| Type             | Half-life (days) | Rationale                                                     |
|------------------|-----------------:|---------------------------------------------------------------|
| auto-discovered  |               14 | Cheap to re-discover; archive quickly if not reinforced.      |
| cross-project    |               30 | Module-generic wisdom; framework APIs shift on monthly cadence.|
| canonical        |               90 | Human-validated; halve only after a quarter of disuse.        |

Type resolution: explicit `type` field wins; else `source: auto-discovered` → auto-discovered;
else `source: user-confirmed` or `state: ACTIVE` → canonical; else path under
`shared/learnings/` → cross-project; else cross-project (default).

## 3. Thresholds

| Confidence `c`   | Tier     | Behavior                                       |
|-----------------:|----------|------------------------------------------------|
| `c ≥ 0.75`       | HIGH     | Loaded, weighted normally.                     |
| `0.5 ≤ c < 0.75` | MEDIUM   | Loaded, weighted normally.                     |
| `0.3 ≤ c < 0.5`  | LOW      | Loaded, ranked last in dedup tie-breaks.       |
| `c < 0.3`        | ARCHIVED | Not loaded. Moved to archive block of forge-log.md.|

## 4. Reinforcement + penalty

- Success: `base_confidence = min(0.95, base_confidence + 0.05)`, `last_success_at = now`.
- False positive: `base_confidence *= 0.80`, `last_success_at = now`, `last_false_positive_at = now`.

The 0.95 cap (not 1.0) preserves the effectiveness of the 20 % false-positive haircut: a fully
ratcheted item still demotes meaningfully on a single false positive.

## 5. Lazy-read / authoritative-write

- **PREFLIGHT** (read-only): loader calls `memory_decay.effective_confidence(item, now)` and
  `memory_decay.tier(c)`. Decayed values are *not* written back.
- **LEARN** (authoritative): `fg-700-retrospective` applies reinforcement/penalty from the run,
  computes `effective_confidence` + `tier`, writes results back, and archives items whose tier = ARCHIVED.

Between runs, records sit untouched — time elapses "for free" in storage.

## 6. Migration

On first PREFLIGHT after upgrade, any record missing `last_success_at` is passed through
`memory_decay.migrate_item(item, now)`:

- `last_success_at := now` (warm start).
- `last_false_positive_at := null`.
- `base_confidence := 1.0 → 0.95` (HIGH), `0.75` (MEDIUM), `0.5` (LOW), `0.3` (ARCHIVED). HIGH is
  clamped to 0.95 to match the post-migration ceiling.
- `type` derived per §2.
- Legacy fields `runs_since_last_hit` and `decay_multiplier` are deleted.

Migrator is idempotent: running it on a migrated record is a no-op.

## 7. Tuning warning

The config knobs in `forge-config.md` (`memory.decay.half_life_days`, `curve`,
`reinforcement.success_bonus`, `reinforcement.false_positive_penalty`) are **invariants** of the
decay model. In particular, setting `success_bonus > false_positive_penalty` **inverts** stale-memory
protection — false positives would no longer demote items below their fresh-learned state.
Change only with matching threshold tuning and telemetry validation.

## 8. Observability

`fg-700-retrospective` emits one summary line per run:

    decay: N demoted, M archived, K reinforced, J false-positives (last 7d: L)

where `L` = count of items with `last_false_positive_at` within the 7 days preceding `now`. This
is the reader for `last_false_positive_at` — the field is *always* written by `apply_false_positive`
and *always* read by this summary.

## 9. References

- Spec: `docs/superpowers/specs/2026-04-19-13-memory-decay-ebbinghaus-design.md`
- Module: `hooks/_py/memory_decay.py`
- Tests: `tests/unit/memory_decay_test.py`, `tests/evals/memory_decay_eval.sh`
```

- [ ] **Step 2: Commit**

```bash
git add shared/learnings/decay.md
git commit -m "docs(phase13): add canonical Ebbinghaus decay contract"
```

---

## Task 4: Implement `apply_success` with 0.95 ceiling + test

**Files:**
- Modify: `hooks/_py/memory_decay.py`
- Test: `tests/unit/memory_decay_test.py`

- [ ] **Step 1: Append failing success tests**

```python
# tests/unit/memory_decay_test.py (append)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v -k "apply_success"`
Expected: `AttributeError: module 'hooks._py.memory_decay' has no attribute 'apply_success'`.

- [ ] **Step 3: Implement `apply_success`**

```python
# hooks/_py/memory_decay.py (append)
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


def _format_iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: all tests pass (previous + 3 new `apply_success` tests).

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/memory_decay.py tests/unit/memory_decay_test.py
git commit -m "feat(phase13): add apply_success with 0.95 confidence ceiling"
```

---

## Task 5: Implement `apply_false_positive` + test

**Files:**
- Modify: `hooks/_py/memory_decay.py`
- Test: `tests/unit/memory_decay_test.py`

- [ ] **Step 1: Append failing FP tests**

```python
# tests/unit/memory_decay_test.py (append)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v -k "false_positive"`
Expected: `AttributeError: module 'hooks._py.memory_decay' has no attribute 'apply_false_positive'`.

- [ ] **Step 3: Implement `apply_false_positive`**

```python
# hooks/_py/memory_decay.py (append)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/memory_decay.py tests/unit/memory_decay_test.py
git commit -m "feat(phase13): add apply_false_positive with clock reset"
```

---

## Task 6: Implement migrator + tests (warm start, idempotent)

**Files:**
- Modify: `hooks/_py/memory_decay.py`
- Test: `tests/unit/memory_decay_test.py`

- [ ] **Step 1: Append failing migrator tests**

```python
# tests/unit/memory_decay_test.py (append)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v -k "migrate or type_inference"`
Expected: all migrator tests fail with `AttributeError: 'migrate_item'`.

- [ ] **Step 3: Implement `migrate_item`**

```python
# hooks/_py/memory_decay.py (append)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: all tests pass (~18 tests).

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/memory_decay.py tests/unit/memory_decay_test.py
git commit -m "feat(phase13): add idempotent warm-start migrator"
```

---

## Task 7: Add per-type half-life regression test

**Files:**
- Test: `tests/unit/memory_decay_test.py`

- [ ] **Step 1: Append test**

```python
# tests/unit/memory_decay_test.py (append)
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
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `python3 -m pytest tests/unit/memory_decay_test.py::test_type_half_life_selection_differs_for_same_age -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/memory_decay_test.py
git commit -m "test(phase13): assert per-type half-life differentiates decay"
```

---

## Task 8: Add CLI dry-run recompute flag

**Files:**
- Modify: `hooks/_py/memory_decay.py`

- [ ] **Step 1: Write the failing CLI test**

```python
# tests/unit/memory_decay_test.py (append)
import json
import subprocess
import sys
from pathlib import Path


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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest tests/unit/memory_decay_test.py::test_cli_dry_run_recompute_prints_tier_per_item -v`
Expected: `subprocess.CalledProcessError` because the module has no `__main__` handler.

- [ ] **Step 3: Add the CLI entry point**

```python
# hooks/_py/memory_decay.py (append)
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
```

Also add `import json` at the top of the module (next to `import math`).

- [ ] **Step 4: Run test to verify pass**

Run: `python3 -m pytest tests/unit/memory_decay_test.py::test_cli_dry_run_recompute_prints_tier_per_item -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/memory_decay.py tests/unit/memory_decay_test.py
git commit -m "feat(phase13): add --dry-run-recompute CLI for eval harness"
```

---

## Task 9: Add `count_recent_false_positives` reader (closes review Issue 2)

**Files:**
- Modify: `hooks/_py/memory_decay.py`
- Test: `tests/unit/memory_decay_test.py`

- [ ] **Step 1: Append failing reader tests**

```python
# tests/unit/memory_decay_test.py (append)
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v -k "count_recent"`
Expected: `AttributeError: module 'hooks._py.memory_decay' has no attribute 'count_recent_false_positives'`.

- [ ] **Step 3: Implement the reader**

```python
# hooks/_py/memory_decay.py (append)
def count_recent_false_positives(
    items: "list[Dict[str, Any]]", now: datetime, window_days: int = 7
) -> int:
    """Count items whose last_false_positive_at is within the last `window_days`.

    Review Issue 2: this is the designated reader for last_false_positive_at so
    the field is not write-only. fg-700-retrospective calls this to emit the
    'last FP in last 7d: K' summary line.
    """
    count = 0
    for item in items:
        fp = item.get("last_false_positive_at")
        if not fp:
            continue
        ts = _parse_iso(fp)
        delta_days = (now - ts).total_seconds() / 86400.0
        # Future timestamps (clock skew) → delta_days < 0 → not counted.
        if 0 <= delta_days <= window_days:
            count += 1
    return count
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/memory_decay.py tests/unit/memory_decay_test.py
git commit -m "feat(phase13): add count_recent_false_positives reader"
```

---

## Task 10: Rewrite `fg-700-retrospective` LEARN logic

**Files:**
- Modify: `agents/fg-700-retrospective.md`

- [ ] **Step 1: Read the existing agent file to locate the LEARN/decay section**

Run: `grep -n "runs_since_last_hit\|decay_multiplier\|PREEMPT_SKIPPED\|PREEMPT_APPLIED" agents/fg-700-retrospective.md` (via the Grep tool) and record the line numbers. Also locate the "summary line" emission section.

- [ ] **Step 2: Edit the agent file**

Replace every occurrence of `runs_since_last_hit`, `decay_multiplier`, and the "5/10 unused runs" language with the new decay contract. Concrete edits (use Edit tool on each):

1. In the LEARN-stage instruction block, replace the old decay pseudocode with:

```
For each PREEMPT item referenced in this run's stage notes:
  if PREEMPT_APPLIED(item.id):
    item = memory_decay.apply_success(item, now)
  elif PREEMPT_SKIPPED(item.id, reason="false_positive"):
    item = memory_decay.apply_false_positive(item, now)
  # Lazy records: untouched items simply skip this branch.

After reinforcement, for every PREEMPT item (touched or not):
  c = memory_decay.effective_confidence(item, now)
  item.tier = memory_decay.tier(c)
  if item.tier == "ARCHIVED":
    move to forge-log.md archive block
  else:
    persist back to forge-log.md / .forge/memory/

Reference: shared/learnings/decay.md
```

2. Replace any existing "summary line" / post-run log emission with:

```
Emit one summary line per run:

  decay: {N} demoted, {M} archived, {K} reinforced, {J} false-positives (last 7d: {L})

Where:
  N = items whose tier dropped this run (e.g., HIGH→MEDIUM).
  M = items whose tier became ARCHIVED this run.
  K = items reinforced via apply_success.
  J = items penalised via apply_false_positive this run.
  L = memory_decay.count_recent_false_positives(all_items, now, window_days=7)
```

3. Remove any remaining instructions referencing `runs_since_last_hit` or `decay_multiplier` — those fields no longer exist.

- [ ] **Step 3: Verify the agent has no stale references**

Run: `grep -n "runs_since_last_hit\|decay_multiplier\|10 unused\|5 unused\|3 unused" agents/fg-700-retrospective.md` (via Grep tool).
Expected: zero matches.

- [ ] **Step 4: Validate plugin structure**

Run: `./tests/validate-plugin.sh`
Expected: PASS (no structural regressions from the doc edits).

- [ ] **Step 5: Commit**

```bash
git add agents/fg-700-retrospective.md
git commit -m "feat(phase13): fg-700 uses Ebbinghaus decay + last-FP reader"
```

---

## Task 11: Wire PREFLIGHT loader in `fg-100-orchestrator`

**Files:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Locate the PREEMPT-injection block**

Run: `grep -n "PREEMPT\|preempt\|forge-log" agents/fg-100-orchestrator.md` via the Grep tool. Identify where items are loaded and ranked at PREFLIGHT.

- [ ] **Step 2: Edit the PREFLIGHT section**

Replace the old "load items, filter by HIGH/MEDIUM tier string, apply 10-run decay" block with:

```
At PREFLIGHT, when loading PREEMPT items from forge-log.md / .forge/memory/:

1. For each record lacking `last_success_at`, call
   memory_decay.migrate_item(record, now) and persist back (one-time warm
   start — idempotent, so safe to call on every PREFLIGHT).
2. For each record, call
     c = memory_decay.effective_confidence(record, now)
     t = memory_decay.tier(c)
   Read-only — do NOT write `c` or `t` back (they are recomputed every time).
3. Filter out records whose tier == "ARCHIVED".
4. Rank the remaining records: HIGH first, MEDIUM second, LOW last (tie-break
   among LOW uses decayed `c` descending).

Reference: shared/learnings/decay.md
```

- [ ] **Step 3: Validate**

Run: `./tests/validate-plugin.sh`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat(phase13): orchestrator PREFLIGHT loader uses decay module"
```

---

## Task 12: Replace legacy decay prose in `shared/learnings/*.md`

**Files:**
- Modify: `shared/learnings/README.md`
- Modify: `shared/learnings/memory-discovery.md`
- Modify: `shared/learnings/rule-promotion.md`

- [ ] **Step 1: Rewrite `README.md` §PREEMPT Lifecycle**

Use Edit tool to find the §PREEMPT Lifecycle section. Replace its content with:

```markdown
### PREEMPT Lifecycle

Every PREEMPT item has a confidence in `[0, 1]` that decays on an Ebbinghaus
exponential curve with per-type half-lives. See `shared/learnings/decay.md` for
the canonical contract, formula, thresholds, reinforcement/penalty rules, and
tuning warnings.

~~**Legacy (superseded 2026-04-19 by Phase 13):** counter-based decay — HIGH → MEDIUM
after 10 unused runs, 1 false positive counted as 3 unused. Replaced by the
Ebbinghaus exponential curve.~~
```

- [ ] **Step 2: Rewrite `memory-discovery.md` §Promotion and Decay**

Find the §Promotion and Decay section and any `decay_multiplier: 2` / "5 unused runs"
tables. Replace with:

```markdown
### Promotion and Decay

**Decay** — all auto-discovered items carry `type: auto-discovered` and decay
on a 14-day half-life per `shared/learnings/decay.md`. The legacy
`decay_multiplier: 2` and "5 unused runs → demote" rules are removed; the
14-day half-life is the replacement (roughly 2× faster than the 30-day
cross-project half-life, matching the original intent).

**Promotion** — unchanged from prior behaviour: after 3 successful applications,
an auto-discovered item may be promoted to MEDIUM via `rule-promotion.md`'s
flow. Each successful application calls `memory_decay.apply_success` (which
adds +0.05 to `base_confidence`, capped at 0.95).
```

- [ ] **Step 3: Rewrite `rule-promotion.md` §Decay Rules**

Find the §Decay Rules section. Replace with:

```markdown
### Decay Rules

A rule is demoted when its PREEMPT representation falls below the tier
threshold specified in `shared/learnings/decay.md`:

- `c < 0.30` → ARCHIVED (demoted out of active use).
- Below MEDIUM cutoff after N successful applications → re-evaluated per
  `decay.md` §4 reinforcement/penalty rules.

The legacy "5 inactive runs → demote" rule is removed. Demotion is now
time-aware: a rule that hasn't fired in N days decays by `2^(-N / half_life)`.
```

- [ ] **Step 4: Verify no stale references remain**

Run: `grep -rn "runs_since_last_hit\|decay_multiplier\|5 unused\|5 inactive\|10 unused\|3 unused" shared/learnings/` via the Grep tool.
Expected: zero matches.

- [ ] **Step 5: Validate plugin structure**

Run: `./tests/validate-plugin.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shared/learnings/README.md shared/learnings/memory-discovery.md shared/learnings/rule-promotion.md
git commit -m "docs(phase13): point learnings docs at decay.md contract"
```

---

## Task 13: Update remaining shared/ references + top-level docs

**Files:**
- Modify: `shared/knowledge-base.md`
- Modify: `shared/agent-communication.md`
- Modify: `shared/domain-detection.md`
- Modify: `CLAUDE.md`
- Modify: `DEPRECATIONS.md`
- Modify: `benchmarks/prompts.json`

- [ ] **Step 1: Edit `shared/knowledge-base.md` L56**

Find the line:
```
- Any to ARCHIVED: 10 unused runs (standard PREEMPT decay; learned rules follow standard decay rates).
```

Replace with:
```
- Any to ARCHIVED: `confidence < 0.3` per `shared/learnings/decay.md` (Ebbinghaus half-life-driven demotion; learned rules use the same decay contract).
```

- [ ] **Step 2: Edit `shared/agent-communication.md`**

Find two lines (approx L273 and L302):

L273: `2. Records false positives for confidence decay acceleration (false positive = 3 unused runs toward decay)`

Replace with:
```
2. Records false positives for confidence decay acceleration (each false positive applies `base_confidence *= 0.80` and resets the elapsed-time clock per `shared/learnings/decay.md`).
```

L302: `- false_positives — times the item was marked PREEMPT_SKIPPED with reason indicating inapplicability (each false positive counts as 3 unused runs toward decay)`

Replace with:
```
- false_positives — times the item was marked PREEMPT_SKIPPED with reason indicating inapplicability (each false positive applies `base_confidence *= 0.80` per `shared/learnings/decay.md`).
```

- [ ] **Step 3: Edit `shared/domain-detection.md`**

Find any prose referencing "per-domain PREEMPT decay" that still implies a run-counter (approx L5 and L70). Replace "PREEMPT decay" wording with:

```
PREEMPT decay (time-aware Ebbinghaus, see `shared/learnings/decay.md`) keys on `state.json.domain_area`. ...
```

No semantic change — just wording.

- [ ] **Step 4: Edit `CLAUDE.md` L352**

Find:
```
- PREEMPT decay: 10 unused → HIGH→MEDIUM→LOW→ARCHIVED. 1 false positive = 3 unused.
```

Replace with:
```
- PREEMPT decay: time-aware Ebbinghaus curve per `shared/learnings/decay.md` (half-lives: auto-discovered 14d, cross-project 30d, canonical 90d; 0.95 ceiling; false positive drops base by 20 %).
```

- [ ] **Step 5: Edit `DEPRECATIONS.md` L91**

Find:
```
- PREEMPT decay: 10 unused cycles → HIGH→MEDIUM→LOW→ARCHIVED
```

Replace with:
```
- PREEMPT decay: 10-unused-cycle rule superseded by Phase 13 Ebbinghaus curve (2026-04-19). See `shared/learnings/decay.md`.
```

- [ ] **Step 6: Edit `benchmarks/prompts.json` L15–L16**

Find the object with `"text": "Explain the PREEMPT decay mechanism..."`.

Replace the `text` value with:
```
"Explain the PREEMPT decay mechanism: the Ebbinghaus half-life per item type, the tier thresholds, and what triggers demotion."
```

Replace `required_facts` with:
```
["half-life", "HIGH", "MEDIUM", "LOW", "ARCHIVED", "false positive", "14", "30", "90"]
```

- [ ] **Step 7: Verify no legacy counter language remains in modified files**

Run: `grep -n "10 unused\|3 unused\|5 unused\|runs_since_last_hit\|decay_multiplier" CLAUDE.md DEPRECATIONS.md benchmarks/prompts.json shared/knowledge-base.md shared/agent-communication.md shared/domain-detection.md` via the Grep tool.
Expected: zero matches.

- [ ] **Step 8: Validate plugin structure**

Run: `./tests/validate-plugin.sh`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add CLAUDE.md DEPRECATIONS.md benchmarks/prompts.json shared/knowledge-base.md shared/agent-communication.md shared/domain-detection.md
git commit -m "docs(phase13): replace legacy counter-decay references"
```

---

## Task 14: Hand-stamp `shared/learnings/*.md` frontmatter

**Files:**
- Modify: every `shared/learnings/*.md` file whose frontmatter contains PREEMPT items.

- [ ] **Step 1: Enumerate affected files**

Run: `grep -l "preempt\|PREEMPT\|runs_since_last_hit\|decay_multiplier" shared/learnings/*.md` via the Grep tool. Record the list.

- [ ] **Step 2: For each file, inspect frontmatter**

Open each file in the list and find its YAML frontmatter (the opening `---` block). Items under a `preempts:` (or similar) list need `last_success_at`, `base_confidence`, and `type` keys added.

- [ ] **Step 3: Stamp each item**

For every PREEMPT-list item in frontmatter, add the three keys. Example before:

```yaml
---
preempts:
  - id: spring-constructor-injection
    pattern: "@Autowired on field"
    confidence: HIGH
---
```

After:

```yaml
---
preempts:
  - id: spring-constructor-injection
    pattern: "@Autowired on field"
    base_confidence: 0.95
    last_success_at: "2026-04-19T00:00:00Z"
    last_false_positive_at: null
    type: cross-project
---
```

Rules for the stamp:
- `base_confidence`: 0.95 if old was `confidence: HIGH`, 0.75 if MEDIUM, 0.5 if LOW, 0.3 if ARCHIVED, 0.75 if missing.
- `last_success_at`: `"2026-04-19T00:00:00Z"` (the migration date) for every item.
- `last_false_positive_at`: always `null` at migration time.
- `type`: `cross-project` (every file under `shared/learnings/` is cross-project by §4.1 inference).
- Remove the legacy `confidence:` string key, `runs_since_last_hit`, `decay_multiplier`.

- [ ] **Step 4: Sanity check**

Run: `grep -n "confidence: HIGH\|confidence: MEDIUM\|confidence: LOW\|runs_since_last_hit\|decay_multiplier" shared/learnings/*.md` via the Grep tool.
Expected: zero matches.

Run: `./tests/validate-plugin.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shared/learnings/
git commit -m "chore(phase13): hand-stamp decay frontmatter on shipped learnings"
```

---

## Task 15: Build eval harness with fixture grid

**Files:**
- Create: `tests/evals/memory_decay_eval.sh`
- Create: `tests/evals/fixtures/memory_decay/` (nine JSON files — `{auto|cross|canon}_{fresh|mid|stale}.json` — plus `legacy_high.json`, `fp_victim.json`).

- [ ] **Step 1: Create the fixture directory and nine age × type JSON files**

Run: `mkdir -p tests/evals/fixtures/memory_decay`

Create these 11 files (content shown for three representative ones — repeat the pattern for all nine grid cells + two extras):

```json
// tests/evals/fixtures/memory_decay/auto_fresh.json
{
  "id": "auto_fresh",
  "type": "auto-discovered",
  "base_confidence": 0.75,
  "last_success_at": "2026-04-19T12:00:00Z",
  "last_false_positive_at": null
}
```

```json
// tests/evals/fixtures/memory_decay/canon_stale.json — 270 days old (3× HL for canonical)
{
  "id": "canon_stale",
  "type": "canonical",
  "base_confidence": 0.75,
  "last_success_at": "2025-07-23T12:00:00Z",
  "last_false_positive_at": null
}
```

```json
// tests/evals/fixtures/memory_decay/legacy_high.json — unmigrated
{
  "id": "legacy_high",
  "pattern": "old-style record",
  "confidence": "HIGH",
  "source": "auto-discovered",
  "runs_since_last_hit": 4,
  "decay_multiplier": 2
}
```

Grid cells and their `last_success_at` (relative to `now = 2026-04-19T12:00:00Z`):

| File | Type | Age | last_success_at |
|---|---|---|---|
| `auto_fresh.json` | auto-discovered | 0d | 2026-04-19T12:00:00Z |
| `auto_mid.json` | auto-discovered | 14d | 2026-04-05T12:00:00Z |
| `auto_stale.json` | auto-discovered | 42d | 2026-03-08T12:00:00Z |
| `cross_fresh.json` | cross-project | 0d | 2026-04-19T12:00:00Z |
| `cross_mid.json` | cross-project | 30d | 2026-03-20T12:00:00Z |
| `cross_stale.json` | cross-project | 90d | 2026-01-19T12:00:00Z |
| `canon_fresh.json` | canonical | 0d | 2026-04-19T12:00:00Z |
| `canon_mid.json` | canonical | 90d | 2026-01-19T12:00:00Z |
| `canon_stale.json` | canonical | 270d | 2025-07-23T12:00:00Z |
| `legacy_high.json` | (legacy) | — | — |
| `fp_victim.json` | auto-discovered, `last_false_positive_at` 2 days ago | 2d | 2026-04-17T12:00:00Z |

All three `fresh` cells use `base_confidence: 0.75`; mid/stale same. `fp_victim` has `base_confidence: 0.60` and `last_false_positive_at: "2026-04-17T12:00:00Z"`.

- [ ] **Step 2: Write the eval harness**

```bash
# tests/evals/memory_decay_eval.sh
#!/usr/bin/env bash
# Phase 13 — memory decay eval harness.
# Usage: ./tests/evals/memory_decay_eval.sh
# Runs the dry-run-recompute CLI against the fixture grid and asserts each
# item lands in the expected tier (fresh → HIGH, 1× HL → MEDIUM, 3× HL → ARCHIVED).
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)/fixtures/memory_decay"
NOW="2026-04-19T12:00:00Z"

output=$(python3 -m hooks._py.memory_decay --dry-run-recompute "$FIXTURE_DIR" --now "$NOW")

assert_tier() {
  local id="$1" expected="$2"
  local line
  line=$(printf '%s\n' "$output" | awk -v id="$id" '$1==id {print $2}')
  if [ "$line" != "$expected" ]; then
    echo "FAIL: $id expected $expected, got '$line'"
    exit 1
  fi
  echo "OK: $id → $expected"
}

# Fresh (Δt=0) → full base (0.75) → MEDIUM (per thresholds, 0.75 is exactly HIGH boundary).
assert_tier auto_fresh HIGH
assert_tier cross_fresh HIGH
assert_tier canon_fresh HIGH
# One half-life → base/2 = 0.375 → LOW.
assert_tier auto_mid LOW
assert_tier cross_mid LOW
assert_tier canon_mid LOW
# Three half-lives → base/8 = 0.09375 → ARCHIVED.
assert_tier auto_stale ARCHIVED
assert_tier cross_stale ARCHIVED
assert_tier canon_stale ARCHIVED
# Legacy record: migrator stamps now → fresh → HIGH (warm start).
assert_tier legacy_high HIGH
# FP victim: 2 days old, auto-discovered, base 0.60.
# c = 0.60 * 2^(-2/14) ≈ 0.5434 → MEDIUM.
assert_tier fp_victim MEDIUM

echo "All tier assertions passed."
```

```bash
chmod +x tests/evals/memory_decay_eval.sh
```

- [ ] **Step 3: Run the harness**

Run: `./tests/evals/memory_decay_eval.sh`
Expected: `All tier assertions passed.` with 11 `OK` lines.

- [ ] **Step 4: Commit**

```bash
git add tests/evals/memory_decay_eval.sh tests/evals/fixtures/memory_decay/
git commit -m "test(phase13): eval harness with type×age tier grid"
```

---

## Task 16: Wire eval harness into CI

**Files:**
- Modify: `.github/workflows/test.yml` (or the equivalent CI config that runs `tests/evals/`).

- [ ] **Step 1: Locate the CI config**

Run: `grep -rln "tests/evals\|eval_.*\.sh" .github/workflows/ 2>/dev/null` via the Grep tool. If `tests/evals/` has an existing runner, reuse it; otherwise add a new step.

- [ ] **Step 2: Add the step to the test job**

Add this step to the existing test job (after unit tests, before structural checks):

```yaml
      - name: Run memory decay eval harness
        run: ./tests/evals/memory_decay_eval.sh
```

If there is a `tests/evals/run-all.sh` or similar wrapper, add `memory_decay_eval.sh` to its list instead.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci(phase13): run memory decay eval harness on PRs"
```

---

## Task 17: Update `forge-config.md` defaults

**Files:**
- Modify: `forge-config.md` (plugin-level default config)

- [ ] **Step 1: Locate the config file and existing memory-related section**

Run: `grep -n "memory\|preempt\|decay" forge-config.md` via the Grep tool.

- [ ] **Step 2: Add the memory.decay block**

If no `memory:` block exists, add one near the other learning-related config sections:

```yaml
memory:
  decay:
    curve: ebbinghaus          # ebbinghaus | linear | power_law (only ebbinghaus implemented in v1)
    half_life_days:
      auto_discovered: 14
      cross_project: 30
      canonical: 90
    base_confidence_default: 0.75
    base_confidence_max: 0.95  # ceiling (see shared/learnings/decay.md §4)
    thresholds:
      high: 0.75
      medium: 0.5
      low: 0.3
      # archived = below low
    reinforcement:
      success_bonus: 0.05             # additive, capped at base_confidence_max
      false_positive_penalty: 0.20    # multiplicative: new_base = base * (1 - penalty)
      # WARNING: success_bonus > false_positive_penalty inverts stale-memory protection.
      # See shared/learnings/decay.md §7 Tuning warning.
```

- [ ] **Step 3: Validate**

Run: `./tests/validate-plugin.sh`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add forge-config.md
git commit -m "chore(phase13): add memory.decay defaults to forge-config.md"
```

---

## Task 18: Final integration pass — run full test suite + self-check

**Files:**
- (none modified; verification only)

- [ ] **Step 1: Run full unit test suite**

Run: `python3 -m pytest tests/unit/memory_decay_test.py -v`
Expected: all tests pass (~22 tests).

- [ ] **Step 2: Run eval harness**

Run: `./tests/evals/memory_decay_eval.sh`
Expected: `All tier assertions passed.`

- [ ] **Step 3: Run plugin validator**

Run: `./tests/validate-plugin.sh`
Expected: 73+ checks PASS.

- [ ] **Step 4: Global grep for legacy wording**

Run via Grep tool:
`grep -rn "runs_since_last_hit\|decay_multiplier\|10 unused runs\|5 unused runs\|3 unused runs" --include="*.md" --include="*.json" --include="*.py" .`

Expected: zero matches outside `docs/superpowers/specs/`, `docs/superpowers/reviews/`, and `shared/learnings/README.md` (historical struck-through note).

- [ ] **Step 5: Verify decay.md is referenced everywhere it should be**

Run via Grep tool:
`grep -rln "shared/learnings/decay.md" --include="*.md" .`

Expected: CLAUDE.md, DEPRECATIONS.md, forge-config.md, agents/fg-100-orchestrator.md, agents/fg-700-retrospective.md, shared/learnings/README.md, shared/learnings/memory-discovery.md, shared/learnings/rule-promotion.md, shared/knowledge-base.md, shared/agent-communication.md, shared/domain-detection.md.

- [ ] **Step 6: Final commit (if anything surfaced by the sweep)**

If Step 4 or 5 found gaps, fix them now and commit:

```bash
git add <paths>
git commit -m "docs(phase13): final sweep — align decay references"
```

Otherwise no commit needed.

---

## Appendix: Module constant reference

These live in `hooks/_py/memory_decay.py` and are the single source of numeric truth. Changing any of them without updating `shared/learnings/decay.md` and `forge-config.md` is a bug.

| Constant | Value | Meaning |
|---|---|---|
| `HALF_LIFE_DAYS["auto-discovered"]` | 14 | Half-life for auto-discovered items. |
| `HALF_LIFE_DAYS["cross-project"]` | 30 | Half-life for shared/learnings items. |
| `HALF_LIFE_DAYS["canonical"]` | 90 | Half-life for user-confirmed / ACTIVE items. |
| `THRESHOLDS["high"]` | 0.75 | HIGH/MEDIUM boundary. |
| `THRESHOLDS["medium"]` | 0.50 | MEDIUM/LOW boundary. |
| `THRESHOLDS["low"]` | 0.30 | LOW/ARCHIVED boundary. |
| `DEFAULT_BASE_CONFIDENCE` | 0.75 | New item default. |
| `MAX_BASE_CONFIDENCE` | 0.95 | Ratchet ceiling (review Issue 1 fix). |
| `SUCCESS_BONUS` | 0.05 | Additive reinforcement. |
| `FALSE_POSITIVE_PENALTY` | 0.20 | Multiplicative haircut (`base *= 0.80`). |
| `DELTA_T_MAX_DAYS` | 365 | Clock-skew clamp upper bound. |
| `DELTA_T_MIN_DAYS` | 0 | Clock-skew clamp lower bound. |
