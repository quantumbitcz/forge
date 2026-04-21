# Memory Decay — Ebbinghaus Exponential Curve

**Status:** Active (2026-04-19).
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

- Module: `hooks/_py/memory_decay.py`
- Tests: `tests/unit/memory_decay_test.py`, `tests/evals/memory_decay_eval.sh`
