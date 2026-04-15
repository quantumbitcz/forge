# Phase 4: Quality & Scoring Improvements

**Status:** Approved  
**Date:** 2026-04-15  
**Depends on:** Phase 1 (transition logic in Python files), Phase 3 (v1.6.0 schema migration infrastructure)  
**Unlocks:** Phase 5

## Problem

1. **Unfixable INFO formula flawed:** `effective_target = max(pass_threshold, min(target_score, 100 - 2 * unfixable_info_count))` — the inner `min` is redundant and confusing. When `unfixable_info_count > 5` (for target=90), the formula computes `min(90, 100-12) = 88`, which is correct but the double-nesting obscures intent.

2. **Float comparison without epsilon:** Score deltas are compared with exact equality/inequality (e.g., `gain > 0 AND gain <= 2`). Floating-point arithmetic can produce values like `1.9999999` or `2.0000001`, causing incorrect plateau/improvement classification.

3. **Top-20 dedup cap loses findings:** When >20 findings exist from previous batches, 30+ findings are hidden from subsequent reviewers. Domain affinity filtering already scopes findings per reviewer — the cap is redundant and causes re-reporting.

4. **Circuit breaker lacks flapping protection:** If failures alternate (success, failure, success, failure), the circuit oscillates between OPEN and HALF_OPEN indefinitely, wasting recovery budget on probe attempts that always fail.

## Solution

### 1. Fix unfixable INFO formula

**File:** `shared/convergence-engine.md` line 273

**Before:**
```
effective_target = max(pass_threshold, min(target_score, 100 - 2 * unfixable_info_count))
```

**After:**
```
effective_target = max(pass_threshold, target_score - 2 * unfixable_info_count)
```

**Rationale:** The new formula directly expresses intent: lower the target by 2 points per unfixable INFO, but never below `pass_threshold`. The `min(target_score, 100 - 2*N)` was equivalent but harder to reason about.

**Example:** target=90, pass=80, 8 unfixable INFOs → `max(80, 90 - 16) = max(80, 74) = 80`. The pipeline accepts at pass_threshold when many INFOs are unfixable, rather than chasing an unreachable target.

### 2. Add epsilon comparison for float deltas

**File:** `shared/python/state_transitions.py` (created in Phase 1)

Add at module level:
```python
SCORE_EPSILON = 0.001

def score_gt(a, b):
    """a > b with epsilon tolerance."""
    return float(a) - float(b) > SCORE_EPSILON

def score_le(a, b):
    """a <= b with epsilon tolerance."""
    return float(a) - float(b) <= SCORE_EPSILON

def score_eq(a, b):
    """a == b with epsilon tolerance."""
    return abs(float(a) - float(b)) < SCORE_EPSILON
```

Use these in transition guards where score deltas are compared. Specifically:
- Row 37 (`score_regressing`): `abs(int(g('delta', 0)))` → use `abs(float(g('delta', 0)))` with `score_gt`
- Rows 31-36 (`score_improving`, `score_plateau`): ensure delta comparisons use epsilon-aware helpers
- Row 50 (`score_diminishing`): ensure `diminishing_count` comparison uses integer (already is)

**File:** `shared/convergence-engine.md`

Add documentation:
```markdown
### Floating-Point Score Handling

Score deltas may be non-integer due to weighted scoring. All delta comparisons use epsilon tolerance (0.001):
- "Score improved" = delta > EPSILON (not delta > 0)
- "Score plateaued" = |delta| <= EPSILON
- "Score regressed" = delta < -EPSILON

This prevents floating-point artifacts from causing incorrect convergence classification.
```

### 3. Remove top-20 dedup cap

**File:** `shared/agent-communication.md` lines 62-67

**Before:**
```markdown
Cap dedup hints at **top 20 findings by severity** (all CRITICALs first, then WARNINGs, then INFOs by line number). If previous batches produced > 20 findings, include note:

    Previous batch findings ({N} total, showing top 20 for dedup):
    ...
    ({N-20} additional findings omitted — focus on your domain, post-hoc dedup will catch overlaps)
```

**After:**
```markdown
Include **all** previous batch findings in dedup hints. Domain affinity filtering (§Domain-Scoped Deduplication Hints) already ensures each reviewer receives only findings relevant to its domain — no global cap is needed.

**Token management:** If a reviewer's domain-filtered findings exceed 50, compress format to single-line entries:

    Previous batch findings ({N} domain-relevant, compressed format):
    SEC-AUTH-003: controller.kt:15
    SEC-INJECT-001: query.kt:88
    ...

This preserves dedup accuracy while managing token cost. The quality gate performs post-hoc dedup regardless, but minimizing re-reports reduces noise and saves review tokens.
```

### 4. Add circuit breaker flapping detection

**File:** `shared/recovery/recovery-engine.md` — circuit breaker section (lines 323-407)

Add to the state machine description:

```markdown
### Flapping Detection

A circuit breaker "flaps" when it repeatedly transitions OPEN → HALF_OPEN → OPEN without ever reaching CLOSED. This indicates a persistent failure that wastes probe attempts.

**Tracking:**
- Add `flapping_count` field to circuit breaker schema (integer, default 0)
- When HALF_OPEN → OPEN (probe failed): increment `flapping_count`
- When HALF_OPEN → CLOSED (probe succeeded): reset `flapping_count = 0`

**Lock threshold:**
- When `flapping_count >= 3`: set `locked: true` on the circuit breaker
- Locked circuits remain OPEN indefinitely — no HALF_OPEN probes are attempted
- Log: `"Circuit locked open after {flapping_count} flapping cycles for {category}"`
- The orchestrator surfaces this as a WARNING to the user

**Unlocking:**
- Locked circuits are cleared by:
  - `/forge-repair-state` (manual intervention)
  - `/forge-reset` (clears all state)
  - Starting a new pipeline run (fresh state.json)
- Locked circuits are NOT cleared by `/forge-resume` (the underlying issue persists)
```

**Schema update** (add to circuit breaker JSON — `flapping_count` and `locked` are per-circuit-breaker entry fields, initialized to `0` and `false` when a circuit breaker entry is first created for a category):
```json
{
  "recovery": {
    "circuit_breakers": {
      "build": {
        "state": "OPEN",
        "failures_count": 3,
        "last_failure_timestamp": "2026-04-15T10:30:00Z",
        "cooldown_seconds": 300,
        "jitter_seconds": 42,
        "flapping_count": 3,
        "locked": true
      }
    }
  }
}
```

**New pipeline runs:** A new pipeline run (`/forge-run`) starts with fresh `state.json` (v1.6.0 via `state_init.py`), which has empty `circuit_breakers: {}`. Locked circuits from a previous failed run do NOT carry over — each run starts clean. `/forge-resume` preserves existing state including locked circuits (the underlying issue may persist).

**Update transition timing check** (line 387-397): Add locked check before OPEN → HALF_OPEN:
```
if state == OPEN and locked:
    # Skip probe — circuit is locked open
    return ESCALATE with reason "circuit_breaker_locked: {category}"
if state == OPEN and elapsed >= cooldown:
    state = HALF_OPEN
```

## Files Changed

| File | Action |
|------|--------|
| `shared/convergence-engine.md` | **Modify** — fix INFO formula, add epsilon docs |
| `shared/python/state_transitions.py` | **Modify** — add `score_gt`/`score_le`/`score_eq` helpers, use in guards |
| `shared/agent-communication.md` | **Modify** — remove top-20 cap, add compression format |
| `shared/recovery/recovery-engine.md` | **Modify** — add flapping detection section, update schema |
| `shared/state-schema.md` | **Modify** — add `flapping_count` and `locked` to circuit breaker schema |

## Testing

- Existing convergence tests (`tests/unit/convergence-arithmetic.bats`, `tests/unit/convergence-engine-advanced.bats`) must pass
- New tests:
  - `tests/unit/score-epsilon.bats`:
    - Delta of 0.0001 treated as plateau (not improvement)
    - Delta of 0.01 treated as improvement
    - Delta of -5.0001 treated as regression
  - `tests/unit/circuit-breaker-flapping.bats`:
    - 3 OPEN→HALF_OPEN→OPEN cycles → circuit locked
    - Locked circuit returns ESCALATE without probe
    - Successful probe resets flapping_count to 0
  - `tests/contract/dedup-no-cap.bats`:
    - 60 findings from batch 1 → all 60 passed to batch 2 (domain-filtered)
    - >50 domain-relevant findings → compressed format used

## Risks

- **Epsilon too small/large:** 0.001 was chosen because scores are typically integers or tenths. If weighted scoring produces deltas at the 0.0001 level, EPSILON may need adjustment. Mitigation: log actual deltas for monitoring.
- **Locked circuit too aggressive:** Locking after 3 flaps means a transient issue that resolves on the 4th probe would be missed. Mitigation: 3 is conservative (each flap = full cooldown cycle, so 3 flaps = 15+ minutes of failure). Users can `/forge-repair-state` to unlock.

## Success Criteria

1. Unfixable INFO formula uses the simplified `max(pass_threshold, target - 2*count)` form
2. All score delta comparisons use epsilon-aware helpers
3. Dedup hints include all findings (domain-filtered, no global cap)
4. Circuit breakers lock after 3 flapping cycles
5. All existing scoring/convergence tests pass
