# Convergence Walkthrough Examples

These scenarios illustrate the convergence algorithm from `convergence-engine.md` with concrete score calculations from `scoring.md` and state transitions from `state-transitions.md`.

## Scenario 1: Clean Implementation → PASS

**Requirement:** "Add email validation to user registration"
**Risk:** LOW | **Confidence:** HIGH (0.82)

### Stage 4 (IMPLEMENT)

fg-300 implements with TDD. 3 tasks, all pass inner-loop.

| Field | Value |
|-------|-------|
| `implementer_fix_cycles` | 0 |

### Stage 5 (VERIFY) — Phase A

Tests: 47 passed, 0 failed. Build: OK. Lint: 0 issues.
→ Phase A: **PASS** (no build/lint/test failures)

| Field | Value |
|-------|-------|
| `verify_fix_count` | 0 |

### Stage 5 (VERIFY) — Phase B (perfection), Cycle 1

fg-400 dispatches quick review (3 agents): fg-410, fg-411, fg-412.

**Findings:** 1 WARNING (QUAL-NAMING), 0 CRITICAL, 0 INFO

**Score calculation:**
```
score = max(0, 100 - 20×CRITICAL - 5×WARNING - 2×INFO)
score = max(0, 100 - 20×0 - 5×1 - 2×0)
score = 95
```

**Verdict:** PASS (95 ≥ pass_threshold 80)

**Convergence evaluation:**
- `phase_iterations` = 1 (first cycle)
- No previous score → delta not applicable
- Phase: **IMPROVING** (first cycle always IMPROVING)
- Score ≥ pass_threshold AND no unresolved CRITICAL → **Phase B complete**

→ Proceed to Stage 7 (DOCUMENTING) → Stage 8 (SHIPPING)

| Field | Final Value |
|-------|-------------|
| `total_iterations` | 1 |
| `quality_cycles` | 1 |
| `phase_iterations` | 1 |
| `score` | 95 |
| **Verdict** | **PASS** |

**State transitions used:** C5 (verify_pass → perfection phase), C6 (score_target_reached with score 95 >= target_score 90 → safety_gate), C11 (verify_pass in safety_gate → CONVERGED).

---

## Scenario 2: Review Findings → Fix Loop → PASS

**Requirement:** "Add rate limiting to public API endpoints"
**Risk:** MEDIUM | **Confidence:** HIGH (0.71)

### Stage 5 (VERIFY) — Phase A

Tests: 52 passed, 0 failed. Build: OK. Lint: 2 issues.
→ fg-300 fixes lint issues in inner loop. Lint re-run: 0 issues.
→ Phase A: **PASS** after lint fix.

| Field | Value |
|-------|-------|
| `verify_fix_count` | 1 |

### Stage 5 (VERIFY) — Phase B, Cycle 1

fg-400 dispatches full review (8 agents).

**Findings:** 2 CRITICAL (SEC-INJECTION, ARCH-BOUNDARY), 3 WARNING, 1 INFO

**Score calculation:**
```
score = max(0, 100 - 20×2 - 5×3 - 2×1)
score = max(0, 100 - 40 - 15 - 2)
score = 43
```

**Verdict:** FAIL (43 < 60, plus unresolved CRITICAL)

**Convergence evaluation:**
- `phase_iterations` = 1 (first cycle)
- Phase: **IMPROVING** (first cycle, no previous score for comparison)
- Dispatch CRITICAL findings to fg-300 for fixes (LOW-confidence excluded)

| Field | Value |
|-------|-------|
| `total_iterations` | 1 |
| `quality_cycles` | 1 |

### Stage 5 (VERIFY) — Phase B, Cycle 2

fg-300 fixes both CRITICAL findings. fg-400 re-dispatches full review.

**Findings:** 0 CRITICAL, 2 WARNING, 3 INFO

**Score calculation:**
```
score = max(0, 100 - 20×0 - 5×2 - 2×3)
score = max(0, 100 - 0 - 10 - 6)
score = 84
```

**Verdict:** PASS (84 ≥ 80, no unresolved CRITICAL)

**Convergence evaluation:**
- `phase_iterations` = 2 (now eligible for plateau check)
- Delta: 84 - 43 = +41
- Smoothed delta: 41 (only 1 delta, use raw per `compute_smoothed_delta`)
- Phase: **IMPROVING** (delta 41 >> plateau_threshold 2)
- Score ≥ pass_threshold AND no CRITICAL → **Phase B complete**

→ Proceed to DOCUMENTING → SHIPPING

| Field | Final Value |
|-------|-------------|
| `total_iterations` | 2 |
| `quality_cycles` | 2 |
| `phase_iterations` | 2 |
| `score` | 84 |
| **Verdict** | **PASS** |

**State transitions used:** Row 31 (score_improving in REVIEWING, cycle 1 — dispatches implementer with CRITICAL findings), then row 30 (score_target_reached in REVIEWING, cycle 2 — score 84 meets target) → C6 (perfection → safety_gate) → C11 (safety_gate verify_pass → CONVERGED).

---

## Scenario 3: Oscillating Score → Plateau → Safety Gate

**Requirement:** "Refactor authentication to use OAuth2 PKCE flow"
**Risk:** HIGH | **Confidence:** MEDIUM (0.55)

### Stage 5 (VERIFY) — Phase B, Cycle 1

**Score: 72** | Verdict: CONCERNS
- `score_history` = [72]
- `phase_iterations` = 1
- `compute_smoothed_delta`: len(score_history) < 2 → return 0
- Phase: **IMPROVING** (first cycle always IMPROVING)
- Dispatch findings to fg-300

### Phase B, Cycle 2

**Score: 78** | Delta: +6
- `score_history` = [72, 78]
- `phase_iterations` = 2
- `compute_smoothed_delta`: len == 2 → raw delta = 78 - 72 = 6
- Smoothed delta: 6
- Phase: **IMPROVING** (delta 6 > plateau_threshold 2)
- Still below pass_threshold (78 < 80) → continue

### Phase B, Cycle 3

**Score: 75** | Delta: -3
- `score_history` = [72, 78, 75]
- `phase_iterations` = 3
- Raw delta: -3. |delta| = 3 ≤ oscillation_tolerance (5) → **NOT REGRESSING**
  (within tolerance, per convergence-engine.md oscillation rules)
- `compute_smoothed_delta`: len == 3 → 2-point weighted average
  - d1 = 75 - 78 = -3 (most recent, weight 0.6)
  - d2 = 78 - 72 = +6 (previous, weight 0.4)
  - smoothed = (-3 × 0.6) + (6 × 0.4) = -1.8 + 2.4 = **0.6**
- 0.6 ≤ plateau_threshold (2) → **PLATEAU detected**
- `plateau_count` = 1 (first observation)
- `plateau_count` (1) < `plateau_patience` (2) → not yet confirmed
- Phase: still **IMPROVING** (plateau needs patience confirmation)
- Continue fixing

### Phase B, Cycle 4

**Score: 76** | Delta: +1
- `score_history` = [72, 78, 75, 76]
- `phase_iterations` = 4
- Raw delta: +1. Not negative → not regressing
- `compute_smoothed_delta`: len == 4 → 3-point weighted average
  - d1 = 76 - 75 = +1 (most recent, weight 0.5)
  - d2 = 75 - 78 = -3 (previous, weight 0.3)
  - d3 = 78 - 72 = +6 (oldest, weight 0.2)
  - smoothed = (1 × 0.5) + (-3 × 0.3) + (6 × 0.2) = 0.5 - 0.9 + 1.2 = **0.8**
- 0.8 ≤ plateau_threshold (2) → **PLATEAU continues**
- `plateau_count` = 2
- `plateau_count` (2) ≥ `plateau_patience` (2) → **PLATEAU CONFIRMED**

**Escalation decision:**
- Score 76 < pass_threshold (80) → **PLATEAUED below pass_threshold**
- Score 76 ≥ concerns_threshold (60) → CONCERNS band
- Escalate to user with options:

```
Score plateaued at 76 (CONCERNS). Unlikely to improve further.
Options:
  1. Keep trying (risk: more iterations without progress)
  2. Fix manually (pause pipeline, user fixes, resume from VERIFY)
  3. Abort (/forge-abort)
```

| Field | Final Value |
|-------|-------------|
| `total_iterations` | 4 |
| `quality_cycles` | 4 |
| `phase_iterations` | 4 |
| `plateau_count` | 2 |
| `score` | 76 |
| **Phase** | **PLATEAUED** |

**If user chooses option 1:** Reset `plateau_count` to 0, `convergence_state` to `"IMPROVING"`, continue iterating. `total_iterations` is NOT reset — global cap still applies. First cycle after restart is exempt from plateau detection.

**If user chooses option 3:** `/forge-abort` → state transitions to ABORTED.

**State transitions used:** C7 (score_improving, cycles 1-2), C10 (score_plateau with plateau_count < plateau_patience, cycle 3), C8 (score_plateau with plateau_count >= plateau_patience, cycle 4 → ESCALATED per score escalation ladder).

---

## Scenario 4: Score Regression → Escalation

**Requirement:** "Migrate auth from JWT to OAuth2 session tokens"
**Risk:** HIGH | **Confidence:** MEDIUM (0.48)

### Stage 5 (VERIFY) — Phase B, Cycle 1

**Score: 82** | Verdict: PASS
- `phase_iterations` = 1
- Phase: **IMPROVING** (first cycle, score above pass_threshold)
- Not yet at target_score (82 < 90) → continue perfection phase

### Phase B, Cycle 2

**Score: 68** | Delta: -14
- `phase_iterations` = 2
- Raw delta: -14. |delta| = 14 > oscillation_tolerance (5)
- **REGRESSING detected** — score dropped significantly
- → Escalate immediately to user:

```
Score REGRESSING: 82 → 68 (delta -14, tolerance 5).
Fix attempt introduced regressions. Options:
  1. Revert last fix and retry with different approach
  2. Continue (risk: further regression)
  3. Abort (/forge-abort)
```

| Field | Final Value |
|-------|-------------|
| `total_iterations` | 2 |
| `quality_cycles` | 2 |
| `phase_iterations` | 2 |
| `score` | 68 |
| **Phase** | **REGRESSING** |

**State transitions used:** C7 (score_improving, cycle 1 — first cycle treated as IMPROVING), C9 (score_regressing with |delta| > oscillation_tolerance, cycle 2 → ESCALATED).

---

## Quick Reference

| Scenario | Cycles | Final Score | Final Phase | Key Mechanism |
|----------|--------|-------------|-------------|---------------|
| 1: Clean | 1 | 95 | PASS | Single-cycle pass |
| 2: Fix loop | 2 | 84 | PASS | CRITICAL fix → re-review |
| 3: Plateau | 4 | 76 | PLATEAUED | Smoothed delta ≤ threshold × patience |
| 4: Regression | 2 | 68 | REGRESSING | Raw |delta| > oscillation_tolerance |
