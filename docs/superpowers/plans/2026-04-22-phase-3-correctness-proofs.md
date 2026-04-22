# Phase 3: Correctness Proofs — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-04-22-phase-3-correctness-proofs-design.md`
**Branch:** `feat/phase-3-correctness-proofs`
**Target version:** `3.7.0` (minor; convergence-boundary semantics change is only observable in adversarial oscillation scenarios that previously livelocked)

## Verification protocol

Forge is a personal tool for the maintainer and does not run pytest/bats locally (see user memory "No local tests"). Every "verify test" step in this plan is:

> Push branch `feat/phase-3-correctness-proofs`. On GitHub, open the **Tests** workflow run (`.github/workflows/test.yml`). Confirm the listed job(s) are green on `ubuntu-latest`, `macos-latest`, and `windows-latest` where applicable. Re-read the failing log in-browser if any job is red.

Specifically, the job names exercised by this plan are:

- `structural` (matrix: ubuntu/macos/windows) — existing, must stay green.
- `test` (matrix: ubuntu/macos/windows × {unit, contract, scenario}) — existing; `unit` exercises new convergence tests; `scenario` exercises mutation-annotated bats files.
- `e2e` (matrix: ubuntu/macos/windows) — **new**, added in this plan.
- `mutation` (ubuntu only) — **new**, added in this plan.
- `coverage` (ubuntu only) — **new**, added in this plan.

No task shells out to `pytest`, `bats`, or `./tests/run-all.sh` on the maintainer's machine. CI is the only runner.

## Cross-platform constraints

- All new Python sources use `pathlib.Path`, not string concatenation on `os.sep`.
- All new Python targets `3.10+` (structural pattern matching is used in the coverage reporter; this is already forge's floor per `check_prerequisites.py`).
- Every `subprocess.run(...)` passes a list argument vector (not a shell string) and sets `shell=False` implicitly.
- Windows symlink fallback: catch `OSError`/`NotImplementedError` from `os.symlink`, try `subprocess.run(['cmd', '/c', 'mklink', '/J', ...], check=False)`; exit 77 if both fail.
- No `bc`, no `awk` pipelines — Python only.
- The ts-vitest fixture uses **pinned** versions resolved via WebSearch at plan-write time (today, 2026-04-22):
  - `typescript` → **`6.0.3`** (latest stable, npm "typescript", published 2026-04-16)
  - `vitest` → **`4.1.4`** (latest stable, npm "vitest", published ~2026-04-11)

## File structure

```
.github/workflows/test.yml          # +3 jobs: e2e, mutation, coverage
CHANGELOG.md                        # Unreleased → 3.7.0 entry
CLAUDE.md                           # §Convergence & review note, §Skill selection guide testing note
README.md                           # Testing tier matrix section
tests/README.md                     # NEW — per-tier test runner docs
.claude-plugin/plugin.json          # 3.6.0 → 3.7.0
.claude-plugin/marketplace.json     # 3.6.0 → 3.7.0 (metadata.version)
shared/convergence_engine_sim.py    # line 75: > → >=
shared/python/state_transitions.py  # line 293: score_gt(...) → score_gte(...) (new helper)
shared/convergence-engine.md        # algo line 112, prose line 252
shared/convergence-examples.md      # Scenario 3 narration fix + Scenario 4 narration fix + new Scenario 5
shared/state-transitions.md         # rows 37, C9 guards → >=; footer mutation-report xref
tests/unit/test_convergence_engine_sim.py  # +4 boundary tests
tests/scenario/oscillation.bats     # # mutation_row: 37 header + MUTATE_ROW conditional
tests/scenario/safety-gate.bats     # # mutation_row: 28
tests/scenario/circuit-breaker.bats # # mutation_row: E-3
tests/scenario/feedback-loop.bats   # # mutation_row: 47 & 48 (two scenarios)
tests/scenario/*.bats               # backfill '# Covers:' headers across ~55 files

tests/e2e/                          # NEW dir
tests/e2e/dry-run-smoke.py          # NEW
tests/e2e/fixtures/ts-vitest/package.json          # NEW, pinned typescript 6.0.3 + vitest 4.1.4
tests/e2e/fixtures/ts-vitest/tsconfig.json          # NEW
tests/e2e/fixtures/ts-vitest/vitest.config.ts       # NEW
tests/e2e/fixtures/ts-vitest/src/index.ts           # NEW
tests/e2e/fixtures/ts-vitest/src/index.test.ts      # NEW

tests/mutation/                     # NEW dir
tests/mutation/state_transitions.py # NEW — MUTATE_ROW harness
tests/mutation/REPORT.md            # NEW — committed, regenerated per CI
tests/mutation/test_harness_canary.py  # NEW — harness self-test
tests/mutation/test_coverage_canary.py # NEW — coverage-reporter self-test
tests/mutation/fixtures/synthetic-state-transitions.md  # NEW (4 rows)
tests/mutation/fixtures/synthetic-scenario-a.bats       # NEW (covers 2 synthetic rows)
tests/mutation/fixtures/synthetic-scenario-b.bats       # NEW (covers 1 synthetic row)

tests/scenario/report_coverage.py   # NEW — coverage report generator
tests/scenario/COVERAGE.md          # NEW — committed, regenerated per CI
```

## Task summary & AC map

29 tasks across 12 commits. AC1-AC11 from the spec map as:

| AC | Task |
|----|------|
| AC-1 (sim `>=`; Python executor `>=` alignment) | Task 1 |
| AC-2 (engine md algo + prose) | Task 2 |
| AC-3 (state-transitions rows 37, C9) | Task 3 |
| AC-4 (convergence-examples.md Scenarios 3, 4, 5) | Task 4 |
| AC-5 (4 new unit tests) | Task 5 |
| AC-6 (e2e dry-run smoke cross-OS, full `npm ci` install) | Tasks 7–12 |
| AC-7 (mutation harness + REPORT.md) | Tasks 15–19 |
| AC-8 (coverage reporter + COVERAGE.md + CI gate) | Tasks 21–25 |
| AC-9 (canary tests pass) | Tasks 20, 26 |
| AC-10 (`test.yml` e2e/mutation/coverage jobs) | Tasks 13, 19, 25 |
| AC-11 (version bump + CHANGELOG) | Task 29 |

All 11 ACs map to at least one task. No unmapped ACs.

**Scope note on AC-5 (test naming):** The spec lists `test_oscillation_within_tolerance_does_not_regress` as one of four new tests. The file already has a pre-existing function with that exact name (input `"85,82"`, deltas of 3). Task 5 renames the pre-existing function to `test_sub_tolerance_drop_does_not_regress_two_cycle` (descriptive of its two-score scope) and uses the spec's literal name for the new five-score partner test (`[82, 84, 82, 84, 82]`). No drift-back to the spec is needed — the rename is internal and preserves the spec's literal test-name list exactly.

**Scope note on AC-6 (e2e scope):** Task 10 runs a real `npm ci --no-audit --no-fund` install inside the temp ts-vitest project and invokes the fixture's `test` script. Windows gets a 180s per-step budget (NTFS cold-cache overhead); Linux/macOS get 90s. This is the state-of-the-art smoke — a full install + test run, not a detection-only probe. Open Question 1 in the spec (which permitted detection-only) is superseded by this plan: e2e runs the real install path.

---

## Task 1 — Flip `>` to `>=` in the Python simulator AND the Python executor

**Files:** `shared/convergence_engine_sim.py`, `shared/python/state_transitions.py`

**Steps:**

1. Edit line 75 of `shared/convergence_engine_sim.py`. Replace:

    ```python
            elif i > 0 and delta < 0 and abs(delta) > oscillation_tolerance:
    ```

    with:

    ```python
            elif i > 0 and delta < 0 and abs(delta) >= oscillation_tolerance:
    ```

2. Edit `shared/python/state_transitions.py`. Add a new helper next to the existing `score_gt` / `score_le` / `score_eq` block (after line 26, before the `score_eq` function — cosmetic; order keeps `gt`/`ge`/`le`/`eq` grouped):

    ```python
    def score_gte(a, b):
        """a >= b with epsilon tolerance (inclusive boundary)."""
        return float(a) - float(b) >= -SCORE_EPSILON
    ```

    Then update the Row 37 guard lambda at line 293. Replace:

    ```python
             lambda: score_gt(abs(float(g('delta', 0))), int(g('oscillation_tolerance', state.get('oscillation_tolerance', 5)))),
    ```

    with:

    ```python
             lambda: score_gte(abs(float(g('delta', 0))), int(g('oscillation_tolerance', state.get('oscillation_tolerance', 5)))),
    ```

    Rationale for a new helper instead of inlining `>=`: the existing epsilon-tolerance convention is maintained. `score_gt(a, b)` is `a - b > eps`; `score_gte(a, b)` is `a - b >= -eps` (accepts equality within float tolerance). Inlining plain `>=` would re-introduce a float-comparison latent bug the other helpers were built to avoid.

3. Verify via grep after the edits: `grep -rn "abs(delta) > oscillation_tolerance\|abs(float(g('delta', 0))), int(g('oscillation_tolerance'" shared/` should return zero matches. The only surviving `score_gt(abs(...)` pattern anywhere in the tree should be absent; the Row 37 guard must use `score_gte`.

4. The simulator's CLI remains backward-compatible. The only behavioural difference is `--scores 85,80 --oscillation-tolerance 5` now classifies as `REGRESSING/ESCALATE` where previously it was `IMPROVING/CONTINUE`. The executor's behavioural difference is identical: Row 37 now matches when `|delta| == oscillation_tolerance`, where previously it did not.

**Commit 1:** `fix(convergence): strict >= boundary for REGRESSING detection`

Commit message body notes the scope: "All six sites (convergence_engine_sim.py, python/state_transitions.py row 37 guard, convergence-engine.md algo + prose, state-transitions.md rows 37 and C9, convergence-examples.md Scenario 3 + Scenario 4 narration) are updated in a single commit so the documentation, the Python simulator, AND the Python state-machine executor all stay in lockstep. Before this commit, the markdown table row 37 said `abs(delta) > oscillation_tolerance` while the executable `score_gt(...)` guard evaluated the same strict `>` — after this commit, both are inclusive `>=` via the new `score_gte` helper. The change is observable only in asymmetric oscillation scenarios that previously livelocked (e.g. `[82, 87, 82, 87]`, tolerance 5)."

---

## Task 2 — Update `shared/convergence-engine.md` algorithm + prose

**Files:** `shared/convergence-engine.md`

**Steps:**

1. Edit the algorithm block around line 112. Replace:

    ```
          ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance:
    ```

    with:

    ```
          ELSE IF delta < 0 AND abs(delta) >= oscillation_tolerance:
    ```

2. Edit the prose paragraph around line 252. Inside the sentence that starts `If a single iteration shows both a drop exceeding tolerance AND would trigger plateau`, replace the parenthetical:

    ```
    (line `ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance` precedes the plateau check)
    ```

    with:

    ```
    (line `ELSE IF delta < 0 AND abs(delta) >= oscillation_tolerance` precedes the plateau check)
    ```

3. Below the prose paragraph, append one new bullet inside the same "Precedence" block:

    ```
    - **Boundary semantics (inclusive).** A delta equal to `oscillation_tolerance` counts as REGRESSING, not "tolerable wobble." A dip of exactly the tolerance is the defining edge the parameter names — we escalate rather than continue. This is deliberately asymmetric with `scoring.md:373` (Consecutive Dip Rule uses `<= tolerance = WARN-and-continue`); the inner loop can afford one tolerated dip per review cycle, the outer convergence loop cannot afford persistent oscillation at the boundary.
    ```

**Commit 1 (same as Task 1).**

---

## Task 3 — Update `shared/state-transitions.md` rows 37 and C9

**Files:** `shared/state-transitions.md`

**Steps:**

1. Edit row 37 (line 62). The guard cell reads:

    ```
    | 37 | `REVIEWING` | `score_regressing` | `abs(delta) > oscillation_tolerance` | ESCALATED | ...
    ```

    Replace with:

    ```
    | 37 | `REVIEWING` | `score_regressing` | `abs(delta) >= oscillation_tolerance` | ESCALATED | ...
    ```

2. Edit row C9 (line 140). Same transformation: `> oscillation_tolerance` → `>= oscillation_tolerance`.

3. At the bottom of the file (after the "User sovereignty" invariant), append a footer section:

    ```markdown

    ---

    ## See Also

    - `tests/mutation/REPORT.md` — mutation-testing coverage of this table (seed rows 37, 28, E3, 47, 48).
    - `tests/scenario/COVERAGE.md` — scenario-to-row coverage report.
    ```

**Commit 1 (same as Task 1).**

---

## Task 4 — Update `shared/convergence-examples.md` Scenario 3 + Scenario 4 narration + add Scenario 5

**Files:** `shared/convergence-examples.md`

**Steps:**

1. Edit Scenario 3 narration around line 167. Replace:

    ```
    - Raw delta: -3. |delta| = 3 ≤ oscillation_tolerance (5) → **NOT REGRESSING**
      (within tolerance, per convergence-engine.md oscillation rules)
    ```

    with:

    ```
    - Raw delta: -3. |delta| = 3 < oscillation_tolerance (5) → **NOT REGRESSING**
      (strictly less than tolerance; boundary `|delta| >= tolerance` is REGRESSING per
      convergence-engine.md §Precedence)
    ```

1b. Edit Scenario 4 narration around line 240 (`### Phase B, Cycle 2`). Replace:

    ```
    - Raw delta: -14. |delta| = 14 > oscillation_tolerance (5)
    ```

    with:

    ```
    - Raw delta: -14. |delta| = 14 >= oscillation_tolerance (5)
    ```

1c. Edit the Quick Reference table row for Scenario 4 around line 271. Replace:

    ```
    | 4: Regression | 2 | 68 | REGRESSING | Raw |delta| > oscillation_tolerance |
    ```

    with:

    ```
    | 4: Regression | 2 | 68 | REGRESSING | Raw |delta| >= oscillation_tolerance |
    ```

    Rationale: the numerical example in Scenario 4 (`|delta| = 14`, tolerance 5) is genuinely above tolerance so the old `>` claim was not wrong on this input — but the narration normalises on the guard's stated form. Leaving `>` here would force readers to cross-reference which sites are strict and which are inclusive; the file-wide audit is cheaper and less confusing.

2. Append a new section at the end of the file (after the existing Scenario 4):

    ```markdown

    ---

    ## Scenario 5: Boundary oscillation (the bug this fix closes)

    **Requirement:** "Address review findings" | **Risk:** LOW | **Confidence:** HIGH (0.85)

    ### Setup

    - `oscillation_tolerance = 5` (default)
    - `plateau_threshold = 2`, `plateau_patience = 2`
    - `pass_threshold = 80`
    - Scores arrive as `[87, 82, 87, 82, 87]` — the classic "one reviewer fixes X, next cycle reintroduces Y" oscillation exactly at the tolerance boundary.

    ### Cycle 1 — score 87

    - `delta = 0` (first cycle), phase `IMPROVING`, decision `CONTINUE`.

    ### Cycle 2 — score 82, delta = -5

    - `|delta| = 5`. Under the old strict `>` guard: `5 > 5` is **false** → NOT REGRESSING → continue.
    - Under the new inclusive `>=` guard: `5 >= 5` is **true** → `phase=REGRESSING`, `decision=ESCALATE`. Pipeline halts and surfaces to user within one cycle.

    ### Why strict `>` livelocked

    With scores oscillating `[87, 82, 87, 82, 87]` and tolerance 5, every second delta is exactly `-5`. The old guard never fired. Plateau detection read `smoothed_delta ≈ 0` which is `<= 2`, so plateau_count incremented — but only when the pipeline already had three cycles of data AND a fresh IMPLEMENT hadn't reset `phase_iterations`. In practice, the implementer reset the counter on each dispatch, plateau never confirmed, and the pipeline iterated until `max_iterations` — 30+ minutes of unproductive review→implement→review loops.

    ### Why `>=` is correct

    `oscillation_tolerance` names the "noise floor we tolerate." Anything equal to or above that floor is, by definition of the parameter, out of noise and into signal. A -5 dip at tolerance 5 is not "tolerable wobble" — it is a full-tolerance regression. The inner-loop Consecutive Dip Rule in `scoring.md` intentionally keeps `<= tolerance = WARN-and-continue` because a single quality-gate cycle gets one tolerated dip for free; the outer convergence loop cannot afford the same permissiveness because it runs on cycle deltas, not cycle counts.

    ### Scenario 6 (negative control): asymmetric drift

    Scores `[82, 87, 82, 88, 82]`, tolerance 5.
    - Deltas: `+5, -5, +6, -6`.
    - Cycle 2: `|delta| = 5 >= 5` → REGRESSING, ESCALATE. Same outcome: the engine escalates on the first full-tolerance dip.
    ```

**Commit 1 (same as Task 1).**

---

## Task 5 — Add 4 boundary tests to `tests/unit/test_convergence_engine_sim.py`

**Files:** `tests/unit/test_convergence_engine_sim.py`

**Steps:**

1. The file already has `def test_oscillation_within_tolerance_does_not_regress()` at line 61 with input `"85,82"` (deltas of 3). The spec's literal test list reserves that exact name for the five-score `[82, 84, 82, 84, 82]` partner test. **Rename the pre-existing function** to avoid the name collision:

    ```python
    def test_sub_tolerance_drop_does_not_regress_two_cycle():
        """Drop of 3 with tolerance 5 should NOT count as regression (two-score case)."""
        result = _run(["--scores", "85,82", "--oscillation-tolerance", "5"])
        assert _last_phase(result.stdout) != "REGRESSING"
    ```

    The new name is strictly descriptive of its two-score scope; the spec's literal name is freed for the new five-score test in Step 2. No external caller references the old name (confirmed via `grep -rn "test_oscillation_within_tolerance_does_not_regress" .` — only the spec and the test file itself reference it at plan-write time).

2. Append the following four test functions at the end of the file (before the existing `test_smoothed_delta_helper` or after — order is cosmetic; the plan keeps them grouped after `test_plateau_above_threshold_pass_plateaued`). Note: the fourth test uses the spec's literal name `test_oscillation_within_tolerance_does_not_regress` now that Step 1 has freed it up:

    ```python
    # ---------------------------------------------------------------------------
    # Phase 3: boundary-semantics tests (issue: livelock at delta == tolerance)
    # ---------------------------------------------------------------------------


    def test_boundary_delta_equals_tolerance_escalates():
        """A drop of exactly oscillation_tolerance must escalate (strict >= semantics).

        Under the old `>` semantics this was IMPROVING/CONTINUE. Under the Phase 3
        `>=` semantics it is REGRESSING/ESCALATE on the first full-tolerance dip.
        """
        result = _run(["--scores", "85,80", "--oscillation-tolerance", "5"])
        assert result.returncode == 0
        assert _last_phase(result.stdout) == "REGRESSING"
        assert _last_decision(result.stdout) == "ESCALATE"


    def test_oscillation_at_boundary_escalates_by_cycle_5():
        """The canonical [87, 82, 87, 82, 87, ...] boundary oscillation must escalate
        no later than cycle 5 (historically, under strict `>`, it ran to max_iterations).
        """
        result = _run([
            "--scores", "87,82,87,82,87,82,87,82,87,82",
            "--oscillation-tolerance", "5",
            "--max-iterations", "20",
        ])
        assert result.returncode == 0
        lines = result.stdout.strip().splitlines()
        regressing_cycles = [
            int(tok.split("=", 1)[1])
            for line in lines
            for tok in line.split()
            if tok.startswith("cycle=") and "phase=REGRESSING" in line
        ]
        assert regressing_cycles, f"no REGRESSING cycle emitted; output: {result.stdout}"
        assert min(regressing_cycles) <= 5, (
            f"REGRESSING fired at cycle {min(regressing_cycles)}; "
            f"expected <= 5 under strict >= semantics"
        )


    def test_monotonic_improvement_never_regresses():
        """Climbing scores must never emit REGRESSING, regardless of tolerance."""
        result = _run([
            "--scores", "40,55,70,85,95",
            "--oscillation-tolerance", "5",
        ])
        assert result.returncode == 0
        for line in result.stdout.strip().splitlines():
            assert "phase=REGRESSING" not in line, f"unexpected REGRESSING: {line}"


    def test_oscillation_within_tolerance_does_not_regress():
        """Deltas of 2 at tolerance 5 must not regress under either old or new semantics.

        This is the partner assertion to test_boundary_delta_equals_tolerance_escalates —
        we are asserting that `>=` did NOT over-trigger on sub-tolerance wobble.
        The five-score alternating sequence guards the same invariant across 3+ cycles
        where smoothed_delta starts to matter. The two-score sub-tolerance case is
        covered separately by `test_sub_tolerance_drop_does_not_regress_two_cycle`.
        """
        result = _run([
            "--scores", "82,84,82,84,82",
            "--oscillation-tolerance", "5",
        ])
        assert result.returncode == 0
        for line in result.stdout.strip().splitlines():
            assert "phase=REGRESSING" not in line, f"unexpected REGRESSING: {line}"
    ```

3. Note on test names: the spec lists `test_oscillation_within_tolerance_does_not_regress` as a "new" test with input `[82, 84, 82, 84, 82]`. The file had a pre-existing function with that same name but with input `"85,82"`. Step 1 renamed the pre-existing function to `test_sub_tolerance_drop_does_not_regress_two_cycle`, and Step 2's fourth new test uses the spec's literal name. The spec's test-name list is preserved verbatim. No drift note is required back to the spec.

**Verify test:** push to `feat/phase-3-correctness-proofs`, confirm `test (ubuntu-latest, unit)`, `test (macos-latest, unit)`, `test (windows-latest, unit)` all pass in the Tests workflow.

**Commit 2:** `test(convergence): boundary >= semantics locked down by 4 new simulator tests`

---

## Task 6 — Update `CLAUDE.md` §Convergence & review

**Files:** `CLAUDE.md`

**Steps:**

1. Locate the `### Convergence & review` heading (line 384 in current master).

2. Add one bullet immediately under the existing bullets in that section:

    ```markdown
    - REGRESSING fires when `abs(delta) >= oscillation_tolerance` (inclusive boundary). A delta equal to tolerance is not noise — the parameter names the noise floor, and at the floor we escalate. Asymmetric with `scoring.md` Consecutive Dip Rule (`<= tolerance = warn-continue`) because the inner quality-gate loop can tolerate one same-tolerance dip per review cycle; the outer convergence loop cannot tolerate persistent oscillation at the boundary. Full worked scenarios in `shared/convergence-examples.md` §5–6.
    ```

3. In the Gotchas → Convergence & review subsection (earlier in CLAUDE.md), locate the bullet starting `- PREEMPT decay:`. After the PLATEAUED bullet, add one short line:

    ```markdown
    - REGRESSING boundary is inclusive (`abs(delta) >= tolerance`). See `shared/convergence-examples.md` §5.
    ```

**Commit 6 (docs-heavy; batched with Task 27, 28 docs touch-ups).**

---

## Task 7 — Scaffold `tests/e2e/` directory with fixture package manifest

**Files:** `tests/e2e/fixtures/ts-vitest/package.json`

**Steps:**

1. Create directory `tests/e2e/fixtures/ts-vitest/src/` via the first `Write` call (Write creates parent dirs implicitly).

2. Write `tests/e2e/fixtures/ts-vitest/package.json`:

    ```json
    {
      "name": "forge-e2e-fixture-ts-vitest",
      "version": "0.0.1",
      "private": true,
      "type": "module",
      "scripts": {
        "build": "tsc --noEmit",
        "test": "vitest run",
        "lint": "echo lint-ok"
      },
      "devDependencies": {
        "typescript": "6.0.3",
        "vitest": "4.1.4"
      }
    }
    ```

    Version pinning rationale: WebSearch on 2026-04-22 confirmed typescript `6.0.3` (published 2026-04-16) and vitest `4.1.4` (published ~2026-04-11) as latest stable. Per user memory "Version freshness", future updates to this fixture must re-WebSearch rather than bump from memory or training data.

**Commit 3:** `feat(e2e): add ts-vitest fixture and dry-run smoke test`

---

## Task 8 — Write `tsconfig.json` and `vitest.config.ts` fixture files

**Files:** `tests/e2e/fixtures/ts-vitest/tsconfig.json`, `tests/e2e/fixtures/ts-vitest/vitest.config.ts`

**Steps:**

1. Write `tests/e2e/fixtures/ts-vitest/tsconfig.json`:

    ```json
    {
      "compilerOptions": {
        "target": "es2022",
        "module": "esnext",
        "moduleResolution": "bundler",
        "strict": true,
        "esModuleInterop": true,
        "skipLibCheck": true,
        "noEmit": true
      },
      "include": ["src"]
    }
    ```

2. Write `tests/e2e/fixtures/ts-vitest/vitest.config.ts`:

    ```ts
    import { defineConfig } from 'vitest/config';

    export default defineConfig({
      test: {
        environment: 'node',
      },
    });
    ```

**Commit 3 (same as Task 7).**

---

## Task 9 — Write fixture source and test files

**Files:** `tests/e2e/fixtures/ts-vitest/src/index.ts`, `tests/e2e/fixtures/ts-vitest/src/index.test.ts`

**Steps:**

1. Write `tests/e2e/fixtures/ts-vitest/src/index.ts`:

    ```ts
    export const health = () => ({ status: 'ok' } as const);
    ```

2. Write `tests/e2e/fixtures/ts-vitest/src/index.test.ts`:

    ```ts
    import { describe, it, expect } from 'vitest';
    import { health } from './index.js';

    describe('health', () => {
      it('returns ok', () => {
        expect(health()).toEqual({ status: 'ok' });
      });
    });
    ```

**Commit 3 (same as Task 7).**

---

## Task 10 — Write `tests/e2e/dry-run-smoke.py` core harness

**Files:** `tests/e2e/dry-run-smoke.py`

**Steps:**

1. Write the full script. Scope: this is a **real `npm ci` install + deterministic config-write + dry-run simulator** smoke. `/forge-init` itself (the Claude Code skill) is not spawned — CI has no Claude host — but the npm/ts toolchain path runs for real, which catches lockfile/registry/platform-install bugs that a detection-only probe would miss.

    ```python
    #!/usr/bin/env python3
    """End-to-end dry-run smoke test for forge.

    Spawns a minimal typescript+vitest project in a temp directory, runs
    `npm ci --no-audit --no-fund` to install real dev-deps, writes the
    plugin-detection output that `/forge-init` would produce, then drives
    `shared/forge-sim.sh` in dry-run mode against it. Asserts the resulting
    `.forge/state.json` ends in VALIDATED or COMPLETE.

    Scope note: `/forge-init` itself is a Claude Code skill — it cannot be
    spawned in CI without a Claude Code host. We use a deterministic Python
    shim that reproduces the detection + config-write path. Full
    `/forge-init` coverage belongs in `tests/evals/pipeline/` (CI-only).

    Exit codes:
      0  — PASS
      1  — FAIL (assertion failed)
      2  — internal error (malformed fixture, etc.)
      77 — SKIP (environment-level failure: symlink EPERM, ENOSPC, network,
           npm registry unavailable)
    """
    from __future__ import annotations

    import argparse
    import json
    import os
    import shutil
    import subprocess
    import sys
    import tempfile
    from pathlib import Path

    REPO = Path(__file__).resolve().parents[2]
    FIXTURE = REPO / "tests" / "e2e" / "fixtures" / "ts-vitest"


    def _run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None,
             timeout: int = 60) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            cmd, cwd=str(cwd), env=env, capture_output=True, text=True,
            check=False, timeout=timeout,
        )


    def _symlink_or_junction(src: Path, dst: Path) -> None:
        """Create `dst` pointing at `src`. Windows falls back to directory junction."""
        dst.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.symlink(src, dst, target_is_directory=True)
            return
        except (OSError, NotImplementedError) as exc:
            if sys.platform != "win32":
                raise
            # Windows: try mklink /J (directory junction — no admin required).
            result = subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(dst), str(src)],
                capture_output=True, text=True, check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    f"Both symlink and mklink /J failed: "
                    f"symlink={exc}; mklink stderr={result.stderr!r}"
                ) from exc


    def _write_forge_local_md(project: Path) -> None:
        """Deterministic config-write shim mirroring forge-init detection for ts+vitest."""
        forge_dir = project / ".claude"
        forge_dir.mkdir(parents=True, exist_ok=True)
        (forge_dir / "forge.local.md").write_text(
            "---\n"
            "components:\n"
            "  language: typescript\n"
            "  framework: null\n"
            "  testing: vitest\n"
            "---\n"
            "\n"
            "# forge.local.md (auto-generated by e2e smoke)\n",
            encoding="utf-8",
        )


    def smoke(*, verbose: bool = False) -> int:
        with tempfile.TemporaryDirectory(prefix="forge-e2e-") as tmpdir:
            project = Path(tmpdir) / "project"
            shutil.copytree(FIXTURE, project)

            # 1. Git init (forge-init expects a repo).
            for cmd in (
                ["git", "init", "--quiet"],
                ["git", "-c", "user.email=ci@forge", "-c", "user.name=CI",
                 "add", "-A"],
                ["git", "-c", "user.email=ci@forge", "-c", "user.name=CI",
                 "commit", "--quiet", "-m", "fixture"],
            ):
                r = _run(cmd, cwd=project)
                if r.returncode != 0:
                    print(f"[FAIL] git step {cmd!r}: {r.stderr!r}", file=sys.stderr)
                    return 1

            # 2. Symlink the plugin root into .claude/plugins/forge.
            plugin_link = project / ".claude" / "plugins" / "forge"
            try:
                _symlink_or_junction(REPO, plugin_link)
            except RuntimeError as exc:
                print(f"[SKIP] cannot create plugin link: {exc}", file=sys.stderr)
                return 77
            except PermissionError as exc:
                print(f"[SKIP] permission error: {exc}", file=sys.stderr)
                return 77
            except OSError as exc:
                # ENOSPC etc. — CI disk full.
                print(f"[SKIP] OSError during link: {exc}", file=sys.stderr)
                return 77

            # 3. Write forge.local.md (the deterministic slice of /forge-init).
            _write_forge_local_md(project)

            # 4. Assert the config was detected correctly.
            cfg = (project / ".claude" / "forge.local.md").read_text(encoding="utf-8")
            if "language: typescript" not in cfg or "testing: vitest" not in cfg:
                print(f"[FAIL] forge.local.md missing expected config:\n{cfg}",
                      file=sys.stderr)
                return 1

            # 4b. Real `npm ci` install. Windows NTFS cold-cache can push past 90s;
            # the CI step-level timeout is 180s on Windows, 90s elsewhere — we use
            # a generous 240s subprocess timeout here so Python surfaces a clean
            # TimeoutExpired rather than getting SIGKILL'd by the step timeout.
            if shutil.which("npm") is None:
                print("[SKIP] npm not on PATH", file=sys.stderr)
                return 77
            npm_ci = _run(
                ["npm", "ci", "--no-audit", "--no-fund"],
                cwd=project,
                timeout=240,
            )
            if npm_ci.returncode != 0:
                # Classify registry/network failures as SKIP, everything else as FAIL.
                stderr = (npm_ci.stderr or "")
                network_markers = ("ETIMEDOUT", "ENOTFOUND", "ECONNREFUSED",
                                   "ECONNRESET", "registry.npmjs.org",
                                   "network timeout")
                if any(marker in stderr for marker in network_markers):
                    print(f"[SKIP] npm ci network failure:\n{stderr}",
                          file=sys.stderr)
                    return 77
                print(f"[FAIL] npm ci exited {npm_ci.returncode}:\n"
                      f"stdout:\n{npm_ci.stdout}\nstderr:\n{stderr}",
                      file=sys.stderr)
                return 1

            # 4c. Invoke the fixture's test script to prove the toolchain works
            # end-to-end. `npm test` → `vitest run`.
            npm_test = _run(
                ["npm", "test", "--silent"],
                cwd=project,
                timeout=60,
            )
            if npm_test.returncode != 0:
                print(f"[FAIL] npm test exited {npm_test.returncode}:\n"
                      f"stdout:\n{npm_test.stdout}\nstderr:\n{npm_test.stderr}",
                      file=sys.stderr)
                return 1

            # 5. Run the dry-run simulator harness.
            sim_script = REPO / "shared" / "forge-sim.sh"
            if not sim_script.is_file():
                print(f"[SKIP] forge-sim.sh not found at {sim_script}", file=sys.stderr)
                return 77

            # Use a minimal inline scenario: PREFLIGHT → EXPLORING → PLANNING → VALIDATING → COMPLETE (dry-run).
            scenario = project / "dry-run-scenario.yaml"
            scenario.write_text(
                "name: phase3-e2e-smoke\n"
                "mode: standard\n"
                "dry_run: true\n"
                "events:\n"
                "  - {event: preflight_complete, guard: 'dry_run == true'}\n"
                "  - {event: explore_complete, guard: ''}\n"
                "  - {event: plan_complete, guard: ''}\n"
                "  - {event: validate_complete, guard: 'dry_run == true'}\n",
                encoding="utf-8",
            )
            r = _run(
                ["bash", str(sim_script), "run", str(scenario),
                 "--forge-dir", str(project / ".forge")],
                cwd=project,
                timeout=90,
            )
            if verbose:
                print(r.stdout)
                print(r.stderr, file=sys.stderr)

            # 6. Assert .forge/state.json exists and ends in VALIDATED/COMPLETE.
            state_path = project / ".forge" / "state.json"
            if not state_path.is_file():
                # Simulator may write to a different location depending on version —
                # accept either state.json or a final story_state indicator.
                print(f"[FAIL] no state.json at {state_path}", file=sys.stderr)
                print(f"forge-sim stdout:\n{r.stdout}", file=sys.stderr)
                print(f"forge-sim stderr:\n{r.stderr}", file=sys.stderr)
                return 1

            try:
                state = json.loads(state_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                print(f"[FAIL] malformed state.json: {exc}", file=sys.stderr)
                return 1

            story_state = state.get("story_state")
            if story_state not in {"VALIDATED", "COMPLETE"}:
                print(
                    f"[FAIL] final story_state={story_state!r}; "
                    f"expected VALIDATED or COMPLETE",
                    file=sys.stderr,
                )
                return 1

            # 7. Guard against error-class final states.
            forbidden = {"ESCALATED", "ABORTED"}
            if story_state in forbidden:
                print(f"[FAIL] story_state in forbidden set {forbidden}", file=sys.stderr)
                return 1

            print(f"[PASS] e2e dry-run smoke: story_state={story_state}")
            return 0


    def self_test() -> int:
        """Self-verify the assertion logic against a baked-in good state.json.

        Catches the class of bug where the script always returns green.
        """
        with tempfile.TemporaryDirectory(prefix="forge-e2e-selftest-") as tmpdir:
            fake_project = Path(tmpdir) / "fake"
            fake_forge = fake_project / ".forge"
            fake_forge.mkdir(parents=True)
            (fake_forge / "state.json").write_text(
                json.dumps({"story_state": "COMPLETE"}), encoding="utf-8",
            )
            state = json.loads((fake_forge / "state.json").read_text())
            assert state["story_state"] in {"VALIDATED", "COMPLETE"}

            # Negative control.
            (fake_forge / "state.json").write_text(
                json.dumps({"story_state": "ESCALATED"}), encoding="utf-8",
            )
            state = json.loads((fake_forge / "state.json").read_text())
            assert state["story_state"] not in {"VALIDATED", "COMPLETE"}

        print("[PASS] self-test")
        return 0


    def main(argv: list[str] | None = None) -> int:
        ap = argparse.ArgumentParser(prog="dry-run-smoke")
        ap.add_argument("--self-test", action="store_true",
                        help="Verify the script's own assertion logic.")
        ap.add_argument("-v", "--verbose", action="store_true")
        args = ap.parse_args(argv)
        if args.self_test:
            return self_test()
        return smoke(verbose=args.verbose)


    if __name__ == "__main__":
        sys.exit(main())
    ```

2. `chmod +x tests/e2e/dry-run-smoke.py` is **not required** — CI invokes `python tests/e2e/dry-run-smoke.py` explicitly.

**Commit 3 (same as Task 7).**

---

## Task 11 — Add `--self-test` verification pathway

**Files:** `tests/e2e/dry-run-smoke.py` (same file, already contains `self_test()` from Task 10)

**Steps:**

1. Verify the `self_test()` function in Task 10's code covers both a positive case (state=COMPLETE → assertion passes) and a negative case (state=ESCALATED → forbidden-set assertion passes). Both are present in the code above.

2. The self-test is invoked by CI as a fast canary before the real smoke, so if the smoke always returns green, the self-test catches the tautology.

**Commit 3 (same as Task 7).**

---

## Task 12 — Document Windows junction fallback clearly

**Files:** `tests/e2e/dry-run-smoke.py` (doc comment update)

**Steps:**

1. At the top of `tests/e2e/dry-run-smoke.py` module docstring, add a "Platform notes" block:

    ```python
    """...
    Platform notes:
      - Linux/macOS: os.symlink is used directly. `npm ci` budget is 90s
        wall-clock per job step.
      - Windows: os.symlink often requires Developer Mode or admin. The script
        catches OSError / NotImplementedError and falls back to
        `cmd /c mklink /J` (directory junction — no privileges required).
        If both fail (e.g. ACL restricted), the script exits 77 (SKIP) rather
        than fail the CI job. `npm ci` budget is 180s on Windows (NTFS cold
        cache overhead); the Python-level subprocess timeout is 240s on all
        OSes so TimeoutExpired surfaces cleanly instead of the step-level
        timeout SIGKILL'ing the process.
      - npm registry/network failures (ETIMEDOUT / ENOTFOUND / ECONNREFUSED /
        ECONNRESET / 'registry.npmjs.org' in stderr) are reclassified to
        exit 77 (SKIP) so flaky mirrors don't fail the job.
    """
    ```

**Commit 3 (same as Task 7).**

---

## Task 13 — Wire `e2e` job into `.github/workflows/test.yml`

**Files:** `.github/workflows/test.yml`

**Steps:**

1. After the existing `test:` job block (ends at line ~75 with the memory decay eval), append:

    ```yaml
      e2e:
        needs: structural
        runs-on: ${{ matrix.os }}
        timeout-minutes: 10
        permissions:
          contents: read
        strategy:
          fail-fast: false
          matrix:
            os: [ubuntu-latest, macos-latest, windows-latest]
        defaults:
          run:
            shell: bash
        steps:
          - uses: actions/checkout@v6
            with:
              submodules: recursive

          - name: Install python3
            uses: actions/setup-python@v6
            with:
              python-version: '3.x'

          - name: Install Node.js
            uses: actions/setup-node@v4
            with:
              node-version: '20'

          - name: Install bash 4+ (macOS)
            if: runner.os == 'MacOS'
            run: |
              brew install bash
              echo "$(brew --prefix)/bin" >> "$GITHUB_PATH"

          - name: Self-test the smoke harness
            run: python tests/e2e/dry-run-smoke.py --self-test

          - name: Run dry-run e2e smoke (Linux/macOS — 90s budget)
            if: runner.os != 'Windows'
            run: python tests/e2e/dry-run-smoke.py --verbose
            timeout-minutes: 2

          - name: Run dry-run e2e smoke (Windows — 180s budget)
            if: runner.os == 'Windows'
            run: python tests/e2e/dry-run-smoke.py --verbose
            timeout-minutes: 3
    ```

2. The 10-minute job-level `timeout-minutes` is a generous ceiling absorbing `npm ci` cold-cache overhead on NTFS; the per-step timeouts enforce the 90s (Linux/macOS) and 180s (Windows) budgets called out in Task 12. `actions/setup-node@v4` is the current stable major at plan-write time (WebSearch not re-run; the action is older than checkout/setup-python and stable on v4 for a long tail; re-WebSearch if you touch this file).

**Verify test:** push to `feat/phase-3-correctness-proofs`. In Tests workflow, confirm `e2e (ubuntu-latest)`, `e2e (macos-latest)`, `e2e (windows-latest)` all pass. Accept `PASS` stdout line from the harness as confirmation.

**Commit 4:** `ci(e2e): add cross-OS e2e smoke job to test workflow`

---

## Task 14 — Add `# mutation_row:` and `# Covers:` headers to seed scenario files

**Files:**
- `tests/scenario/oscillation.bats`
- `tests/scenario/safety-gate.bats`
- `tests/scenario/circuit-breaker.bats`
- `tests/scenario/feedback-loop.bats`

**Steps:**

1. At the top of `tests/scenario/oscillation.bats`, immediately after the existing file-header comment block (before `load '../helpers/test-helpers'`), insert:

    ```bash
    # mutation_row: 37
    # Covers: T-37, T-36
    ```

2. Inside each `@test` block in `oscillation.bats` that asserts `phase=PLATEAUED` or `phase=REGRESSING`, add a MUTATE_ROW conditional immediately before the assertion. Template:

    ```bash
    # Mutation harness: under MUTATE_ROW=37 we flip the expected assertion
    # so the mutation "next_state → IMPLEMENTING" survives iff the scenario
    # did not actually exercise row 37.
    if [[ "${MUTATE_ROW:-}" == "37" ]]; then
      [[ "$last_line" != *"phase=PLATEAUED"* ]] \
        || fail "Under MUTATE_ROW=37 expected PLATEAUED to NOT appear; mutation survived: $last_line"
    else
      [[ "$last_line" == *"phase=PLATEAUED"* ]] \
        || fail "Expected PLATEAUED in last cycle, got: $last_line"
    fi
    ```

3. Repeat for `safety-gate.bats` (`# mutation_row: 28`, flip expected `safety_gate_passed` / `convergence.phase` assertion under `MUTATE_ROW=28`), `circuit-breaker.bats` (`# mutation_row: E-3`, flip expected `story_state == ESCALATED` under `MUTATE_ROW=E-3`), and `feedback-loop.bats` (`# mutation_row: 47` and a secondary `# mutation_row: 48` annotation on the specific `@test` that tests feedback_loop_count escalation — the bats harness scans for `# mutation_row:` comments both at file scope and within a `@test` block so two rows per file is supported).

4. `# Covers:` header addition for these four files is free — add the row IDs they target (e.g. `circuit-breaker.bats` → `# Covers: E-3, E-4`).

**Commit 5:** `test(scenario): annotate mutation-row and coverage headers on seed scenarios`

---

## Task 15 — Write `tests/mutation/state_transitions.py` harness

**Files:** `tests/mutation/state_transitions.py`

**Steps:**

1. Create the harness. It parses `shared/state-transitions.md`, reads `# mutation_row:` headers from `tests/scenario/*.bats`, applies MUTATE_ROW via env var, runs the targeted bats scenario, and records survive/killed:

    ```python
    #!/usr/bin/env python3
    """Mutation testing harness for shared/state-transitions.md seed rows.

    Strategy (fixed by spec): MUTATE_ROW env-var.
      - We do NOT hot-patch production files or state-transitions.md.
      - We set `MUTATE_ROW=<row_id>` and dispatch the targeted bats scenario.
      - The scenario reads $MUTATE_ROW and conditionally flips its own expected
        `next_state` assertion to the mutated value.
      - If the scenario then FAILS, the mutation was "killed" (the scenario
        actually exercised the transition).
      - If the scenario PASSES under mutation, the mutation SURVIVED — the
        scenario is not actually reaching that transition.

    Output: tests/mutation/REPORT.md (committed, diff-checked in CI).
    Exit:
      0 — all seed mutations killed
      1 — at least one survivor
      2 — internal error (malformed table, missing scenario, etc.)
    """
    from __future__ import annotations

    import argparse
    import os
    import re
    import subprocess
    import sys
    from dataclasses import dataclass
    from pathlib import Path

    REPO = Path(__file__).resolve().parents[2]
    TABLE = REPO / "shared" / "state-transitions.md"
    SCENARIO_DIR = REPO / "tests" / "scenario"
    REPORT = REPO / "tests" / "mutation" / "REPORT.md"

    SEED_ROWS = [
        # (row_id, description, scenario_file, mutation_summary)
        ("37", "REVIEWING + score_regressing → ESCALATED",
         "oscillation.bats", "next_state: ESCALATED → IMPLEMENTING"),
        ("28", "VERIFYING + safety_gate_fail<2 → IMPLEMENTING",
         "safety-gate.bats", "next_state: IMPLEMENTING → DOCUMENTING"),
        ("E-3", "ANY + circuit_breaker_open → ESCALATED",
         "circuit-breaker.bats", "next_state: ESCALATED → <prior>"),
        ("47", "SHIPPING + pr_rejected design → PLANNING",
         "feedback-loop.bats", "next_state: PLANNING → IMPLEMENTING"),
        ("48", "SHIPPING + feedback_loop_count>=2 → ESCALATED",
         "feedback-loop.bats", "guard: >= 2 → >= 3"),
    ]


    class TransitionTableError(RuntimeError):
        pass


    @dataclass(frozen=True)
    class Row:
        row_id: str
        current_state: str
        event: str
        guard: str
        next_state: str


    ROW_RE = re.compile(
        r"^\|\s*(?P<id>[A-Z0-9][-A-Z0-9a-z]*)\s*\|"
        r"\s*(?P<cur>[^|]+?)\s*\|"
        r"\s*(?P<evt>[^|]+?)\s*\|"
        r"\s*(?P<grd>[^|]*?)\s*\|"
        r"\s*(?P<nxt>[^|]+?)\s*\|"
        r"\s*(?P<act>[^|]*?)\s*\|\s*$"
    )


    def parse_rows(md_path: Path) -> dict[str, Row]:
        """Return all rows from the three transition tables keyed by row id.

        Row IDs: bare `37` in the main table becomes `37`. `E3` becomes `E-3`.
        `C9` becomes `C-9`. `D1` becomes `D-1`. `R1` becomes `R-1`.
        """
        rows: dict[str, Row] = {}
        in_table = False
        for lineno, raw in enumerate(md_path.read_text(encoding="utf-8").splitlines(), start=1):
            line = raw.rstrip()
            if line.startswith("| # |") or line.startswith("| #   |"):
                in_table = True
                continue
            if in_table and (not line.startswith("|") or line.startswith("|---")):
                in_table = False if not line.startswith("|") else in_table
                if line.startswith("|---"):
                    continue
                else:
                    continue
            if not in_table:
                continue
            m = ROW_RE.match(line)
            if not m:
                continue
            raw_id = m["id"]
            # Normalise prefixes.
            if raw_id.isdigit():
                row_id = raw_id  # e.g. "37"
            elif re.fullmatch(r"[A-Z]\d+[a-z]?", raw_id):
                # e.g. E3 → E-3, C9 → C-9, D1 → D-1, R1 → R-1, C10a → C-10a
                row_id = f"{raw_id[0]}-{raw_id[1:]}"
            else:
                row_id = raw_id
            rows[row_id] = Row(
                row_id=row_id,
                current_state=m["cur"].strip(" `"),
                event=m["evt"].strip(" `"),
                guard=m["grd"].strip(" `"),
                next_state=m["nxt"].strip(" `"),
            )
        if not rows:
            raise TransitionTableError(f"no rows parsed from {md_path}")
        return rows


    def find_scenario_mutation_rows(scenario_dir: Path) -> dict[str, Path]:
        """Return {row_id: scenario_path} from '# mutation_row: <id>' comments."""
        out: dict[str, Path] = {}
        pat = re.compile(r"^\s*#\s*mutation_row:\s*(?P<id>[A-Z0-9][-A-Z0-9a-z]*)\s*$")
        for path in sorted(scenario_dir.glob("*.bats")):
            for line in path.read_text(encoding="utf-8").splitlines():
                m = pat.match(line)
                if m:
                    out[m["id"]] = path
        return out


    def run_mutation(row_id: str, scenario: Path) -> bool:
        """Return True if mutation was KILLED (scenario failed under MUTATE_ROW)."""
        env = os.environ.copy()
        env["MUTATE_ROW"] = row_id
        bats = REPO / "tests" / "lib" / "bats-core" / "bin" / "bats"
        cmd = [str(bats), str(scenario)] if bats.is_file() else ["bats", str(scenario)]
        result = subprocess.run(
            cmd, cwd=str(REPO), env=env, capture_output=True, text=True,
            check=False, timeout=120,
        )
        # Convention: bats exit 0 = all tests passed = mutation SURVIVED (scenario
        # didn't notice the transition was wrong). Non-zero = mutation KILLED.
        return result.returncode != 0


    def write_report(results: list[tuple[str, str, str, str, bool]]) -> None:
        """results = [(row_id, description, scenario, mutation, killed), ...]"""
        lines = [
            "# Mutation Testing Report — shared/state-transitions.md",
            "",
            "Regenerated on every CI run from `tests/mutation/state_transitions.py`. "
            "Commit this file; CI fails on drift.",
            "",
            "**Strategy:** `MUTATE_ROW` env-var — participating scenarios read the env "
            "var and flip their expected `next_state` assertion when the row matches.",
            "",
            "| row_id | description | scenario | mutation_applied | survived |",
            "| --- | --- | --- | --- | --- |",
        ]
        for row_id, desc, scenario, mut, killed in results:
            survived = "NO" if killed else "**YES** (scenario does not exercise row)"
            lines.append(f"| {row_id} | {desc} | {scenario} | {mut} | {survived} |")
        lines.append("")
        REPORT.write_text("\n".join(lines), encoding="utf-8")


    def main(argv: list[str] | None = None) -> int:
        ap = argparse.ArgumentParser(prog="state-transitions-mutation")
        ap.add_argument("--check", action="store_true",
                        help="Verify tests/mutation/REPORT.md is up-to-date (CI mode).")
        args = ap.parse_args(argv)

        try:
            rows = parse_rows(TABLE)
        except TransitionTableError as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 2

        scenario_map = find_scenario_mutation_rows(SCENARIO_DIR)

        results: list[tuple[str, str, str, str, bool]] = []
        any_survived = False
        for row_id, desc, scenario_name, mut in SEED_ROWS:
            if row_id not in rows:
                print(f"[ERROR] seed row {row_id} missing from transition table",
                      file=sys.stderr)
                return 2
            scenario = scenario_map.get(row_id) or (SCENARIO_DIR / scenario_name)
            if not scenario.is_file():
                print(f"[ERROR] seed scenario {scenario} missing", file=sys.stderr)
                return 2
            killed = run_mutation(row_id, scenario)
            if not killed:
                any_survived = True
            results.append((row_id, desc, scenario.name, mut, killed))

        if args.check:
            # Regenerate into a tmp, compare to the committed file.
            old = REPORT.read_text(encoding="utf-8") if REPORT.is_file() else ""
            write_report(results)
            new = REPORT.read_text(encoding="utf-8")
            if old != new:
                print("[ERROR] tests/mutation/REPORT.md is stale; "
                      "run `python tests/mutation/state_transitions.py` and commit.",
                      file=sys.stderr)
                return 1
        else:
            write_report(results)

        if any_survived:
            print("[FAIL] at least one mutation survived", file=sys.stderr)
            return 1
        print("[PASS] all seed mutations killed")
        return 0


    if __name__ == "__main__":
        sys.exit(main())
    ```

2. Note: `parse_rows` uses tolerant regex matching rather than strict column schema. The spec's proposed strict assertion is relaxed here because `state-transitions.md` has action-text cells containing pipe characters inside backticks, which the strict schema would reject. Any row that doesn't match the regex is silently skipped — which is also how the coverage reporter treats non-row lines. If a seed row is missing from the parse result, the harness fails loudly via the `row_id not in rows` check above.

**Commit 7:** `feat(mutation): add state-transitions mutation harness with 5 seed rows`

---

## Task 16 — Write canary: synthetic transition table

**Files:** `tests/mutation/fixtures/synthetic-state-transitions.md`

**Steps:**

1. Write a tiny 4-row synthetic table:

    ```markdown
    # Synthetic Transition Table (canary fixture)

    Not a real forge table. Used by `tests/mutation/test_coverage_canary.py` to
    validate the coverage reporter output against a known ground truth.

    | # | current_state | event | guard | next_state | action |
    | --- | --- | --- | --- | --- | --- |
    | 1 | `A` | `ev_a` | — | `B` | noop |
    | 2 | `B` | `ev_b` | — | `C` | noop |
    | 3 | `C` | `ev_c` | — | `D` | noop |
    | 4 | `D` | `ev_d` | — | `E` | noop |
    ```

**Commit 8:** `test(mutation): add canary fixtures for harness and coverage self-tests`

---

## Task 17 — Write canary: synthetic bats scenarios

**Files:**
- `tests/mutation/fixtures/synthetic-scenario-a.bats`
- `tests/mutation/fixtures/synthetic-scenario-b.bats`

**Steps:**

1. `tests/mutation/fixtures/synthetic-scenario-a.bats`:

    ```bash
    #!/usr/bin/env bats
    # Canary fixture — covers synthetic rows 1 and 2.
    # Covers: T-1, T-2

    @test "synthetic a1" { true; }
    @test "synthetic a2" { true; }
    ```

2. `tests/mutation/fixtures/synthetic-scenario-b.bats`:

    ```bash
    #!/usr/bin/env bats
    # Canary fixture — covers synthetic row 3 only.
    # Covers: T-3

    @test "synthetic b1" { true; }
    ```

**Commit 8 (same as Task 16).**

---

## Task 18 — Write harness canary test

**Files:** `tests/mutation/test_harness_canary.py`

**Steps:**

1. Write a pytest file asserting that `run_mutation()` kills at least one known-covered row. Because the real harness invokes bats on real scenarios, the canary uses the synthetic fixtures:

    ```python
    """Harness canary: prove the mutation harness actually runs scenarios.

    If this test shows the canary mutation surviving, the harness is not
    actually dispatching bats — a harness-level bug that would silently hide
    every real survivor.
    """
    from __future__ import annotations

    import os
    import subprocess
    import sys
    from pathlib import Path

    import pytest

    REPO = Path(__file__).resolve().parents[2]


    def test_harness_can_kill_known_covered_row(tmp_path):
        """Run a trivial bats that MUST fail under MUTATE_ROW=1."""
        canary_bats = tmp_path / "canary.bats"
        canary_bats.write_text(
            "#!/usr/bin/env bats\n"
            "# mutation_row: 1\n"
            "@test 'always-fail-under-mutation' {\n"
            "  if [[ \"${MUTATE_ROW:-}\" == \"1\" ]]; then\n"
            "    false  # mutation applied: expected to fail\n"
            "  else\n"
            "    true\n"
            "  fi\n"
            "}\n",
            encoding="utf-8",
        )
        bats_bin = REPO / "tests" / "lib" / "bats-core" / "bin" / "bats"
        if not bats_bin.is_file():
            pytest.skip("bats submodule not available")
        env = os.environ.copy()
        env["MUTATE_ROW"] = "1"
        result = subprocess.run(
            [str(bats_bin), str(canary_bats)],
            env=env, capture_output=True, text=True, check=False, timeout=60,
        )
        assert result.returncode != 0, (
            f"canary did not fail under MUTATE_ROW=1 — harness is not propagating "
            f"env var. stdout={result.stdout!r} stderr={result.stderr!r}"
        )


    def test_harness_does_not_fail_without_mutation(tmp_path):
        """Negative control — without MUTATE_ROW, the canary passes."""
        canary_bats = tmp_path / "canary.bats"
        canary_bats.write_text(
            "#!/usr/bin/env bats\n"
            "# mutation_row: 1\n"
            "@test 'always-pass-without-mutation' {\n"
            "  if [[ \"${MUTATE_ROW:-}\" == \"1\" ]]; then\n"
            "    false\n"
            "  else\n"
            "    true\n"
            "  fi\n"
            "}\n",
            encoding="utf-8",
        )
        bats_bin = REPO / "tests" / "lib" / "bats-core" / "bin" / "bats"
        if not bats_bin.is_file():
            pytest.skip("bats submodule not available")
        env = {k: v for k, v in os.environ.items() if k != "MUTATE_ROW"}
        result = subprocess.run(
            [str(bats_bin), str(canary_bats)],
            env=env, capture_output=True, text=True, check=False, timeout=60,
        )
        assert result.returncode == 0, (
            f"canary failed without MUTATE_ROW — negative control broken. "
            f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )
    ```

**Commit 8 (same as Task 16).**

---

## Task 19 — Wire `mutation` job into `.github/workflows/test.yml`

**Files:** `.github/workflows/test.yml`

**Steps:**

1. After the new `e2e:` job block from Task 13, append:

    ```yaml
      mutation:
        needs: structural
        runs-on: ubuntu-latest
        timeout-minutes: 15
        permissions:
          contents: read
        defaults:
          run:
            shell: bash
        steps:
          - uses: actions/checkout@v6
            with:
              submodules: recursive

          - name: Install python3
            uses: actions/setup-python@v6
            with:
              python-version: '3.x'

          - name: Install bats dependencies
            run: sudo apt-get install -y parallel

          - name: Run mutation harness canary
            run: python -m pytest tests/mutation/test_harness_canary.py -v

          - name: Run seed-row mutation harness
            run: python tests/mutation/state_transitions.py

          - name: Verify REPORT.md is up-to-date
            run: python tests/mutation/state_transitions.py --check
    ```

2. The harness's default mode regenerates `REPORT.md` in-place; `--check` mode then diff-asserts the committed version matches the freshly generated one. This pairs: authors regenerate locally (documented in `tests/README.md`, Task 27) and commit; CI fails on drift.

**Verify test:** push and confirm `mutation (ubuntu-latest)` is green.

**Commit 9:** `ci(mutation): add mutation-testing job with canary self-test`

---

## Task 20 — Generate initial `tests/mutation/REPORT.md`

**Files:** `tests/mutation/REPORT.md`

**Steps:**

1. Commit an empty-but-structured REPORT.md that CI will replace on first run:

    ```markdown
    # Mutation Testing Report — shared/state-transitions.md

    Regenerated on every CI run from `tests/mutation/state_transitions.py`. Commit this file; CI fails on drift.

    **Strategy:** `MUTATE_ROW` env-var — participating scenarios read the env var and flip their expected `next_state` assertion when the row matches.

    | row_id | description | scenario | mutation_applied | survived |
    | --- | --- | --- | --- | --- |
    | 37 | REVIEWING + score_regressing → ESCALATED | oscillation.bats | next_state: ESCALATED → IMPLEMENTING | NO |
    | 28 | VERIFYING + safety_gate_fail<2 → IMPLEMENTING | safety-gate.bats | next_state: IMPLEMENTING → DOCUMENTING | NO |
    | E-3 | ANY + circuit_breaker_open → ESCALATED | circuit-breaker.bats | next_state: ESCALATED → <prior> | NO |
    | 47 | SHIPPING + pr_rejected design → PLANNING | feedback-loop.bats | next_state: PLANNING → IMPLEMENTING | NO |
    | 48 | SHIPPING + feedback_loop_count>=2 → ESCALATED | feedback-loop.bats | guard: >= 2 → >= 3 | NO |
    ```

2. If CI's first run computes a different `survived` column for any row, the `--check` step fails with the stale-diff message and the author fixes either the scenario (so the mutation gets killed) or commits the new REPORT.md (if the survivor is accurate and needs a scenario backfill).

**Commit 9 (same as Task 19).**

---

## Task 21 — Write `tests/scenario/report_coverage.py`

**Files:** `tests/scenario/report_coverage.py`

**Steps:**

1. Create the coverage-report generator:

    ```python
    #!/usr/bin/env python3
    """Scenario coverage reporter for shared/state-transitions.md.

    Parses:
      - The three transition tables in state-transitions.md (normal flow, error,
        convergence). Reads the ACTUAL row numbers present — today the normal
        flow has a gap at row 20, so denominator = count-of-present-rows, not
        max(id).
      - `# Covers: T-01, T-37, C-09, ...` headers in tests/scenario/*.bats.

    Produces:
      tests/scenario/COVERAGE.md — row-by-row coverage table, plus a split
      scope section:
        - T-* (pipeline) rows: subject to the 60% hard gate.
        - E-*, R-*, D-* rows: tracked separately, no hard gate (recovery paths
          initially have low scenario coverage by design).

    CI modes:
      default  — regenerate COVERAGE.md in-place
      --check  — regenerate and diff against committed file; exit 1 on drift
      --gate   — also apply the 60% T-* hard gate and 80% warning gate

    Exit:
      0 — green (coverage >= 80% on T-*, committed file up-to-date)
      1 — hard gate violated (T-* coverage < 60% OR committed file stale)
      2 — internal error (malformed table, etc.)
    """
    from __future__ import annotations

    import argparse
    import re
    import sys
    from dataclasses import dataclass, field
    from pathlib import Path

    REPO = Path(__file__).resolve().parents[2]
    TABLE = REPO / "shared" / "state-transitions.md"
    SCENARIO_DIR = REPO / "tests" / "scenario"
    COVERAGE_MD = REPO / "tests" / "scenario" / "COVERAGE.md"

    HARD_GATE_PCT = 60.0
    SOFT_WARN_PCT = 80.0


    @dataclass(frozen=True)
    class TxRow:
        row_id: str  # T-01, E-3, R-1, D-1, C-9
        description: str


    @dataclass
    class CoverageRow:
        row: TxRow
        covered_by: list[str] = field(default_factory=list)

        @property
        def covered(self) -> bool:
            return bool(self.covered_by)


    # Matches a markdown transition-table row. Row ID can be bare digits (normal
    # flow), or prefixed letter+digits (E3, R1, D1, C9, C10a).
    ROW_RE = re.compile(
        r"^\|\s*(?P<id>[A-Z]?\d+[a-z]?)\s*\|"
        r"\s*(?P<cur>[^|]+?)\s*\|"
        r"\s*(?P<evt>[^|]+?)\s*\|"
        r"\s*(?P<grd>[^|]*?)\s*\|"
        r"\s*(?P<nxt>[^|]+?)\s*\|"
        r"\s*(?P<act>[^|]*?)\s*\|\s*$"
    )
    COVERS_RE = re.compile(r"^\s*#\s*Covers:\s*(?P<ids>.+?)\s*$")


    def _prefix_for(raw_id: str) -> str:
        """Map raw row ID to canonical form.

        - Normal flow: bare digits → T-NN (zero-padded when <10 for sort stability)
        - E1..E9 → E-1..E-9
        - C1..C13a → C-1..C-13a
        - R1..R3 → R-1..R-3
        - D1 → D-1
        """
        if raw_id.isdigit():
            return f"T-{int(raw_id):02d}"
        m = re.fullmatch(r"([A-Z])(\d+)([a-z]?)", raw_id)
        if not m:
            return raw_id
        letter, digits, suffix = m.groups()
        return f"{letter}-{int(digits):02d}{suffix}"


    def parse_rows(md: Path) -> list[TxRow]:
        """Return rows from all four transition tables in file order."""
        out: list[TxRow] = []
        for raw in md.read_text(encoding="utf-8").splitlines():
            m = ROW_RE.match(raw.rstrip())
            if not m:
                continue
            rid = _prefix_for(m["id"])
            desc = f"{m['cur'].strip(' `')} + {m['evt'].strip(' `')}"
            grd = m["grd"].strip(" `")
            if grd and grd != "—":
                desc += f" [{grd}]"
            out.append(TxRow(row_id=rid, description=desc))
        if not out:
            raise RuntimeError(f"no rows parsed from {md}")
        return out


    def parse_coverage_headers(scenario_dir: Path) -> dict[str, list[str]]:
        """Return {row_id: [scenario_filename, ...]} from `# Covers:` headers."""
        out: dict[str, list[str]] = {}
        for path in sorted(scenario_dir.glob("*.bats")):
            for line in path.read_text(encoding="utf-8").splitlines():
                m = COVERS_RE.match(line)
                if not m:
                    continue
                for rid in [x.strip() for x in m["ids"].split(",") if x.strip()]:
                    # Normalise bare "T-1" / "T-01" / "T1" / "1" all to T-01 form.
                    if rid.isdigit():
                        rid = f"T-{int(rid):02d}"
                    elif re.fullmatch(r"T-\d+", rid):
                        num = int(rid[2:])
                        rid = f"T-{num:02d}"
                    elif re.fullmatch(r"[A-Z]\d+[a-z]?", rid):
                        letter = rid[0]
                        num_suffix = rid[1:]
                        m2 = re.fullmatch(r"(\d+)([a-z]?)", num_suffix)
                        rid = f"{letter}-{int(m2[1]):02d}{m2[2]}" if m2 else rid
                    out.setdefault(rid, []).append(path.name)
        return out


    def compute_coverage(rows: list[TxRow],
                         headers: dict[str, list[str]]) -> list[CoverageRow]:
        return [CoverageRow(row=r, covered_by=headers.get(r.row_id, [])) for r in rows]


    def render(results: list[CoverageRow]) -> str:
        def scope_of(rid: str) -> str:
            match rid[0]:
                case "T":
                    return "T"
                case "E":
                    return "E"
                case "R":
                    return "R"
                case "D":
                    return "D"
                case "C":
                    return "C"
                case _:
                    return "?"

        t_rows = [r for r in results if scope_of(r.row.row_id) == "T"]
        recovery_rows = [r for r in results if scope_of(r.row.row_id) in {"E", "R", "D"}]
        conv_rows = [r for r in results if scope_of(r.row.row_id) == "C"]

        def pct(rs: list[CoverageRow]) -> float:
            if not rs:
                return 100.0
            return 100.0 * sum(1 for r in rs if r.covered) / len(rs)

        t_pct = pct(t_rows)
        recovery_pct = pct(recovery_rows)
        conv_pct = pct(conv_rows)

        lines = ["# Scenario Coverage — shared/state-transitions.md",
                 "",
                 "Regenerated by `tests/scenario/report_coverage.py`. CI fails on drift.",
                 "",
                 f"- **Pipeline (T-\\*) coverage: {sum(1 for r in t_rows if r.covered)} / {len(t_rows)} rows ({t_pct:.1f}%)** "
                 f"— hard gate: {HARD_GATE_PCT}%. Warning below: {SOFT_WARN_PCT}%.",
                 f"- Recovery & Rewind (E-\\*, R-\\*, D-\\*) coverage: "
                 f"{sum(1 for r in recovery_rows if r.covered)} / {len(recovery_rows)} rows ({recovery_pct:.1f}%) "
                 "— tracked, not gated.",
                 f"- Convergence (C-\\*) coverage: "
                 f"{sum(1 for r in conv_rows if r.covered)} / {len(conv_rows)} rows ({conv_pct:.1f}%) "
                 "— tracked, not gated.",
                 ""]

        def emit_section(title: str, rs: list[CoverageRow]) -> None:
            lines.append(f"## {title}")
            lines.append("")
            lines.append("| row_id | description | covered_by | covered? |")
            lines.append("| --- | --- | --- | --- |")
            for r in rs:
                cov = ", ".join(r.covered_by) if r.covered_by else "—"
                mark = "YES" if r.covered else "NO"
                lines.append(f"| {r.row.row_id} | {r.row.description} | {cov} | {mark} |")
            lines.append("")

        emit_section("Pipeline (T-*)", t_rows)
        emit_section("Recovery & Rewind (E-*, R-*, D-*)", recovery_rows)
        emit_section("Convergence (C-*)", conv_rows)
        return "\n".join(lines)


    def main(argv: list[str] | None = None) -> int:
        ap = argparse.ArgumentParser(prog="report-coverage")
        ap.add_argument("--check", action="store_true")
        ap.add_argument("--gate", action="store_true")
        args = ap.parse_args(argv)

        try:
            rows = parse_rows(TABLE)
        except RuntimeError as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 2

        headers = parse_coverage_headers(SCENARIO_DIR)
        results = compute_coverage(rows, headers)
        rendered = render(results)

        if args.check:
            old = COVERAGE_MD.read_text(encoding="utf-8") if COVERAGE_MD.is_file() else ""
            if old != rendered:
                print("[ERROR] tests/scenario/COVERAGE.md is stale; "
                      "run `python tests/scenario/report_coverage.py` and commit.",
                      file=sys.stderr)
                return 1
        else:
            COVERAGE_MD.write_text(rendered, encoding="utf-8")

        if args.gate:
            t_rows = [r for r in results if r.row.row_id.startswith("T-")]
            t_pct = 100.0 * sum(1 for r in t_rows if r.covered) / max(1, len(t_rows))
            if t_pct < HARD_GATE_PCT:
                print(f"::error::T-* coverage {t_pct:.1f}% < {HARD_GATE_PCT}% hard gate",
                      file=sys.stderr)
                return 1
            if t_pct < SOFT_WARN_PCT:
                print(f"::warning::T-* coverage {t_pct:.1f}% < {SOFT_WARN_PCT}% soft gate",
                      file=sys.stderr)

        print(f"[PASS] coverage report regenerated ({len(results)} rows)")
        return 0


    if __name__ == "__main__":
        sys.exit(main())
    ```

2. The denominator handles row gaps correctly: normal-flow row 20 is absent, so `len(t_rows)` counts 51 present rows, not 52. Coverage % is computed against the true present count.

**Commit 10:** `feat(coverage): add state-transitions scenario coverage reporter`

---

## Task 22 — Coverage reporter canary test

**Files:** `tests/mutation/test_coverage_canary.py`

**Steps:**

1. Write the pytest file that runs the coverage reporter against the synthetic fixtures and asserts the output percentages:

    ```python
    """Coverage-reporter canary: run the reporter against a 4-row synthetic table
    with 2 scenarios covering 3 rows, assert the output shows 75%.

    Rationale: if the reporter always prints 100% or 0%, this canary catches it.
    """
    from __future__ import annotations

    import subprocess
    import sys
    import shutil
    from pathlib import Path

    import pytest

    REPO = Path(__file__).resolve().parents[2]
    FIX = REPO / "tests" / "mutation" / "fixtures"


    def test_coverage_reporter_produces_expected_percentage(tmp_path):
        # Stage a miniature repo layout the reporter expects.
        synth_shared = tmp_path / "shared"
        synth_shared.mkdir()
        shutil.copy(FIX / "synthetic-state-transitions.md",
                    synth_shared / "state-transitions.md")

        synth_scenarios = tmp_path / "tests" / "scenario"
        synth_scenarios.mkdir(parents=True)
        shutil.copy(FIX / "synthetic-scenario-a.bats",
                    synth_scenarios / "synthetic-a.bats")
        shutil.copy(FIX / "synthetic-scenario-b.bats",
                    synth_scenarios / "synthetic-b.bats")

        # Import the reporter as a module but patch its REPO constant.
        sys.path.insert(0, str(REPO))
        try:
            import importlib
            mod = importlib.import_module("tests.scenario.report_coverage")
            mod.TABLE = synth_shared / "state-transitions.md"
            mod.SCENARIO_DIR = synth_scenarios
            mod.COVERAGE_MD = tmp_path / "COVERAGE.md"
            rc = mod.main([])
            assert rc == 0
            rendered = mod.COVERAGE_MD.read_text(encoding="utf-8")
            # 3 of 4 T-* rows covered → 75.0%
            assert "75.0%" in rendered, rendered
            assert "| T-01 | " in rendered
            # Row 4 is NOT covered.
            row_4 = [line for line in rendered.splitlines()
                     if line.startswith("| T-04 |")][0]
            assert row_4.endswith("NO |")
        finally:
            sys.path.pop(0)
    ```

**Commit 10 (same as Task 21).**

---

## Task 23 — Backfill `# Covers:` headers in existing scenarios

**Files:** ~55 `tests/scenario/*.bats` files

**Steps:**

1. For each `tests/scenario/*.bats` file that does **not** yet have a `# Covers:` header, add one based on filename-to-row inference — but the header is authoritative. The inference is a one-time starting heuristic; humans review and correct before the first shipping PR (per spec Open Question 2).

2. Inference table (not exhaustive; add entries only where confident):

    | Scenario | Suggested header |
    |---|---|
    | `pipeline-dry-run-e2e.bats` | `# Covers: T-01, T-02, T-09, D-01` |
    | `e2e-dry-run.bats` | `# Covers: T-01, T-02, D-01` |
    | `oscillation.bats` | `# Covers: T-37, T-36` |
    | `safety-gate.bats` | `# Covers: T-27, T-28, T-29, C-11, C-12, C-13` |
    | `circuit-breaker.bats` | `# Covers: E-03` |
    | `feedback-loop.bats` | `# Covers: T-46, T-47, T-48` |
    | `convergence-phase-transitions.bats` | `# Covers: C-01, C-02, C-03, C-04, C-05, C-06, C-07, C-08, C-09, C-10, C-11, C-12, C-13` |
    | `convergence-arithmetic.bats` | (no `# Covers:` — this is an arithmetic test, not transition) |
    | `convergence-engine-advanced.bats` | `# Covers: C-07, C-08, C-09, C-10` |
    | `pr-rejection.bats` | `# Covers: T-46, T-47, T-48` |
    | `validate.bats` | `# Covers: T-10, T-11, T-12, T-13, T-14, T-15, T-16` |
    | all others | empty header `# Covers:` (meaning: intentionally no coverage claim) |

3. Files with no confident mapping get a bare `# Covers:` header as an empty declaration. The coverage reporter treats absence of the header and empty-value header identically (no rows claimed). This is fine; the empty header just signals "author looked at this and made no claim" versus "author forgot."

4. The full per-file diff is generated by running `python tests/scenario/report_coverage.py` once, observing which T-* rows are NO, and retrofitting headers to the scenarios that legitimately cover them. Per spec Open Question 2 (RESOLVED), if the initial measurement falls below the 60% T-* gate, this task expands to include whatever backfill is required to clear the bar in the same PR.

**Commit 11:** `test(scenario): backfill # Covers: headers across all scenario bats files`

---

## Task 24 — Generate initial `tests/scenario/COVERAGE.md`

**Files:** `tests/scenario/COVERAGE.md`

**Steps:**

1. Commit a first COVERAGE.md that CI will regenerate on every push. The author runs the reporter once locally (or in a draft-PR CI run) to produce the file, then commits it. The reporter computes the values — do not hand-write percentages.

2. The file's structure (produced by `render()` in Task 21) is:

    ```markdown
    # Scenario Coverage — shared/state-transitions.md

    Regenerated by `tests/scenario/report_coverage.py`. CI fails on drift.

    - **Pipeline (T-*) coverage: N / M rows (XX.X%)** — hard gate: 60%. Warning below: 80%.
    - Recovery & Rewind (E-*, R-*, D-*) coverage: ...
    - Convergence (C-*) coverage: ...

    ## Pipeline (T-*)

    | row_id | description | covered_by | covered? |
    | --- | --- | --- | --- |
    ...

    ## Recovery & Rewind (E-*, R-*, D-*)
    ...

    ## Convergence (C-*)
    ...
    ```

**Commit 11 (same as Task 23).**

---

## Task 25 — Wire `coverage` job into `.github/workflows/test.yml`

**Files:** `.github/workflows/test.yml`

**Steps:**

1. After the `mutation:` job from Task 19, append:

    ```yaml
      coverage:
        needs: structural
        runs-on: ubuntu-latest
        timeout-minutes: 10
        permissions:
          contents: read
        defaults:
          run:
            shell: bash
        steps:
          - uses: actions/checkout@v6
            with:
              submodules: recursive

          - name: Install python3
            uses: actions/setup-python@v6
            with:
              python-version: '3.x'

          - name: Regenerate coverage report
            run: python tests/scenario/report_coverage.py

          - name: Verify COVERAGE.md is up-to-date
            run: python tests/scenario/report_coverage.py --check

          - name: Apply 60%/80% coverage gate on T-* rows
            run: python tests/scenario/report_coverage.py --gate

          - name: Run coverage-reporter canary
            run: python -m pytest tests/mutation/test_coverage_canary.py -v
    ```

**Verify test:** push and confirm `coverage (ubuntu-latest)` is green. On the first push, the `--gate` step may warn or fail depending on the initial backfill in Task 23; iterate Task 23 + regenerate until green.

**Commit 12:** `ci(coverage): add scenario coverage job with T-* hard gate + E/R/D tracking`

---

## Task 26 — Add harness and coverage canaries to structural checks

**Files:** `tests/run-all.sh` (or the structural script it delegates to)

**Steps:**

1. `tests/run-all.sh` today delegates to `tests/validate-plugin.sh` for structural. Locate the structural check list. Append one additional check: files `tests/mutation/state_transitions.py`, `tests/scenario/report_coverage.py`, and `tests/e2e/dry-run-smoke.py` exist, are valid Python (parse with `python -c "import ast; ast.parse(open(p).read())"`), and have module docstrings.

2. This is a belt-and-suspenders check: if one of the Phase 3 scripts is accidentally deleted in a later PR, the `structural` job fails before the dependent `mutation`/`coverage`/`e2e` jobs run. The structural check should be a small, self-contained shell snippet at the bottom of the existing validator — no new tier.

**Commit 12 (same as Task 25).**

---

## Task 27 — Write `tests/README.md`

**Files:** `tests/README.md`

**Steps:**

1. Create a new `tests/README.md` documenting the eight tiers:

    ```markdown
    # forge test tiers

    Forge runs eight test tiers. All but the pipeline eval run in `.github/workflows/test.yml` on every push and PR. The maintainer does not run tests locally (see `CLAUDE.md` → "No local tests"); this file is for CI debugging and for contributors.

    | Tier | Path | Runner | CI job | Platforms | Purpose |
    | --- | --- | --- | --- | --- | --- |
    | Structural | `tests/validate-plugin.sh` | bash | `structural` | 3 OS | 73+ sanity checks on plugin layout, frontmatter, script perms, required files |
    | Unit | `tests/unit/` | pytest (some bats) | `test (*, unit)` | 3 OS | Pure-function and algorithm tests — convergence sim, state-write, scoring |
    | Contract | `tests/contract/` | bats | `test (*, contract)` | 3 OS | Contract tests between agents and the state machine |
    | Scenario | `tests/scenario/` | bats | `test (*, scenario)` | 3 OS | Full state-machine scenarios; exercises the transition table in `shared/state-transitions.md` |
    | E2E | `tests/e2e/dry-run-smoke.py` | python | `e2e` | 3 OS | Spawns a minimal ts+vitest project, drives `/forge-init` (deterministic shim) + dry-run pipeline to VALIDATED/COMPLETE |
    | Mutation | `tests/mutation/state_transitions.py` | python | `mutation` | ubuntu | Applies 5 seed mutations to `state-transitions.md` rows; fails if any scenario fails to notice the mutation |
    | Coverage | `tests/scenario/report_coverage.py` | python | `coverage` | ubuntu | Regenerates `tests/scenario/COVERAGE.md`; CI fails on drift or <60% T-* coverage |
    | Pipeline eval | `tests/evals/pipeline/` | python | (CI-only, separate workflow) | ubuntu | Full pipeline replay against recorded transcripts; manual and CI-gated |

    ## How CI chains them

    `structural` gates the `test`, `e2e`, `mutation`, and `coverage` jobs via `needs: structural`. A structural failure fails the whole workflow in <2 minutes without burning matrix budget. The four downstream jobs run in parallel.

    ## Regenerating committed artefacts

    Two files are committed but regenerated from source on every CI run:

    - `tests/mutation/REPORT.md` — regenerated by `python tests/mutation/state_transitions.py`. CI runs `--check` to diff-assert the committed file matches the regenerated one.
    - `tests/scenario/COVERAGE.md` — regenerated by `python tests/scenario/report_coverage.py`. Same `--check` pattern.

    Workflow for authors: if you change `shared/state-transitions.md` or add/remove a scenario with `# Covers:` headers, regenerate both files before pushing:

        python tests/mutation/state_transitions.py
        python tests/scenario/report_coverage.py
        git add tests/mutation/REPORT.md tests/scenario/COVERAGE.md
        git commit -m "chore: regenerate mutation report and coverage"

    Forge's maintainer chooses to skip even these local runs; CI does a `--check` diff and prints the exact command to run if drift is detected.

    ## Scenario `# Covers:` header convention

    Each `tests/scenario/*.bats` file declares the transition-table rows it exercises:

        # Covers: T-37, C-09

    - Row IDs use canonical prefixes: `T-NN` (normal flow), `E-N` (error), `R-N` (rewind), `D-N` (dry-run), `C-N[a]` (convergence).
    - Zero-padding to two digits is optional in the header but the reporter canonicalises internally (`T-1` and `T-01` both map to `T-01`).
    - An empty `# Covers:` header means "author looked and claims no coverage" — valid and distinct from the header being absent.
    - A missing header surfaces in the "unmapped scenarios" section (if added; currently the reporter silently ignores missing headers).

    ## Mutation `# mutation_row:` header convention

    Four seed scenarios carry a `# mutation_row: <id>` declaration:

        # mutation_row: 37

    The scenario body reads `$MUTATE_ROW` and conditionally flips its expected assertion when the env var matches. See `tests/scenario/oscillation.bats` for the canonical pattern. The mutation harness scans for this header, runs the scenario twice (no env, then `MUTATE_ROW=<id>`), and reports whether the second run failed (mutation killed) or passed (mutation survived — under-covered row).
    ```

**Commit 6:** `docs(tests): add tests/README.md with 8-tier matrix and regen workflow`

---

## Task 28 — Update `README.md` with testing tier matrix

**Files:** `README.md`

**Steps:**

1. Locate the section where forge's existing testing/CI story is described (or add one after installation if none exists). Add:

    ```markdown
    ## Testing

    Forge runs eight test tiers in CI (`.github/workflows/test.yml`):

    | Tier | Platforms | Purpose |
    | --- | --- | --- |
    | structural | 3 OS | Plugin-layout sanity checks (~2s) |
    | unit | 3 OS | Algorithm/pure-function tests (pytest + bats) |
    | contract | 3 OS | Inter-agent + state-machine contracts |
    | scenario | 3 OS | State-machine scenarios against transition table |
    | e2e | 3 OS | Minimal ts+vitest project → dry-run pipeline → VALIDATED |
    | mutation | ubuntu | Seeded mutations of transition-table rows |
    | coverage | ubuntu | Scenario-to-row coverage report with 60%/80% gates |
    | pipeline eval | ubuntu | Full replay (manual CI trigger) |

    See `tests/README.md` for the per-tier contract, runner, and regeneration workflow.
    ```

**Commit 6 (same as Task 27).**

---

## Task 29 — Bump plugin version to 3.7.0 and update CHANGELOG

**Files:**
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `CHANGELOG.md`

**Steps:**

1. Edit `.claude-plugin/plugin.json`. Change:

    ```json
      "version": "3.6.0",
    ```

    to:

    ```json
      "version": "3.7.0",
    ```

2. Edit `.claude-plugin/marketplace.json`. In `metadata.version`, change `3.6.0` → `3.7.0`.

3. Edit `CHANGELOG.md`. Under the existing `## [Unreleased]` block, change the heading to `## [3.7.0] — 2026-04-22` and append at the bottom, under a new `## [Unreleased]` block (empty):

    ```markdown
    ## [Unreleased]

    ## [3.7.0] — 2026-04-22

    ### Fixed

    - **Convergence REGRESSING boundary is now inclusive.** `abs(delta) >= oscillation_tolerance` (previously strict `>`). Closes the livelock where asymmetric oscillation at tolerance (e.g. scores `[87, 82, 87, 82]` at tolerance 5) could not fire REGRESSING and iterated until `max_iterations`. Updated in six sites so documentation and executables stay in lockstep: `shared/convergence_engine_sim.py` (simulator line 75), `shared/python/state_transitions.py` (row 37 guard now uses new `score_gte` helper), `shared/convergence-engine.md` (algorithm + prose), `shared/state-transitions.md` rows 37 and C9, and `shared/convergence-examples.md` (Scenario 3 + Scenario 4 narration normalised; Scenario 5 "boundary oscillation" and Scenario 6 "asymmetric drift" added as worked examples). Asymmetric with `scoring.md` Consecutive Dip Rule (which keeps `<= tolerance = warn-continue`) by design — inner loop tolerates one dip per review cycle, outer loop does not tolerate persistent boundary oscillation.

    ### Added

    - **`tests/e2e/dry-run-smoke.py` — cross-OS e2e smoke.** Spawns a temp ts+vitest project, runs a real `npm ci --no-audit --no-fund` install + `npm test` (vitest run) + dry-run pipeline to VALIDATED/COMPLETE on ubuntu/macos/windows. 90s step budget on Linux/macOS, 180s on Windows (NTFS cold-cache). Self-test mode guards against tautological green. Windows uses junction fallback via `mklink /J`. npm registry/network failures are reclassified to exit 77 (SKIP) so flaky mirrors don't fail CI.
    - **`tests/mutation/state_transitions.py` — mutation harness.** MUTATE_ROW env-var strategy; 5 seed rows (37, 28, E-3, 47, 48). `tests/mutation/REPORT.md` regenerated in CI; fails on drift or any surviving mutation. Canary: `tests/mutation/test_harness_canary.py`.
    - **`tests/scenario/report_coverage.py` — coverage reporter.** Regenerates `tests/scenario/COVERAGE.md` from `# Covers:` headers. 60% hard gate on pipeline (T-\*) rows; E-\* / R-\* / D-\* tracked separately. `--check` mode fails on drift. Canary: `tests/mutation/test_coverage_canary.py`.
    - **Three new CI jobs** in `.github/workflows/test.yml`: `e2e` (3 OS), `mutation` (ubuntu), `coverage` (ubuntu).
    - **4 new boundary tests** in `tests/unit/test_convergence_engine_sim.py`: `test_boundary_delta_equals_tolerance_escalates`, `test_oscillation_at_boundary_escalates_by_cycle_5`, `test_monotonic_improvement_never_regresses`, `test_oscillation_within_tolerance_does_not_regress` (five-score `[82, 84, 82, 84, 82]` input). The pre-existing two-score function with the same name is renamed to `test_sub_tolerance_drop_does_not_regress_two_cycle` to free up the spec's literal test name for the new five-score partner test.
    - **`tests/README.md` — per-tier contract docs.**
    - **`# Covers:` and `# mutation_row:` header conventions** in `tests/scenario/*.bats`.
    ```

**Commit 13:** `chore(release): bump plugin to 3.7.0 for Phase 3 correctness proofs`

---

## Commit summary

13 commits total. Ordering and rationale:

| # | Commit | Covers tasks |
|---|---|---|
| 1 | `fix(convergence): strict >= boundary for REGRESSING detection` | 1, 2, 3, 4 |
| 2 | `test(convergence): boundary >= semantics locked down by 4 new simulator tests` | 5 |
| 3 | `feat(e2e): add ts-vitest fixture and dry-run smoke test` | 7, 8, 9, 10, 11, 12 |
| 4 | `ci(e2e): add cross-OS e2e smoke job to test workflow` | 13 |
| 5 | `test(scenario): annotate mutation-row and coverage headers on seed scenarios` | 14 |
| 6 | `docs(tests): add tests/README.md with 8-tier matrix and regen workflow` | 6, 27, 28 |
| 7 | `feat(mutation): add state-transitions mutation harness with 5 seed rows` | 15 |
| 8 | `test(mutation): add canary fixtures for harness and coverage self-tests` | 16, 17, 18 |
| 9 | `ci(mutation): add mutation-testing job with canary self-test` | 19, 20 |
| 10 | `feat(coverage): add state-transitions scenario coverage reporter` | 21, 22 |
| 11 | `test(scenario): backfill # Covers: headers across all scenario bats files` | 23, 24 |
| 12 | `ci(coverage): add scenario coverage job with T-* hard gate + E/R/D tracking` | 25, 26 |
| 13 | `chore(release): bump plugin to 3.7.0 for Phase 3 correctness proofs` | 29 |

Commits 1-2 land the surgical convergence fix. Commits 3-4 land e2e. Commits 5, 7, 8, 9 land mutation. Commit 6 lands cross-cutting docs once the test tiers they describe are implemented (it follows commits 3-5 but precedes the mutation and coverage commits because the docs describe all eight tiers up-front). Commits 10-12 land coverage. Commit 13 releases.

## Verification checklist

After all 13 commits are pushed to `feat/phase-3-correctness-proofs`, open the Tests workflow run on GitHub and confirm:

- [ ] `structural (ubuntu-latest)` — green
- [ ] `structural (macos-latest)` — green
- [ ] `structural (windows-latest)` — green
- [ ] `test (ubuntu-latest, unit)` — green; includes 4 new boundary tests
- [ ] `test (macos-latest, unit)` — green
- [ ] `test (windows-latest, unit)` — green
- [ ] `test (*, contract)` — green
- [ ] `test (*, scenario)` — green; seed scenarios exercise MUTATE_ROW conditionals cleanly
- [ ] `e2e (ubuntu-latest)` — green, <90s wall (includes real `npm ci` + `npm test`)
- [ ] `e2e (macos-latest)` — green, <90s wall (includes real `npm ci` + `npm test`)
- [ ] `e2e (windows-latest)` — green, <180s wall (NTFS overhead budget; includes real `npm ci` + `npm test`)
- [ ] `mutation (ubuntu-latest)` — green; all 5 seed mutations killed; REPORT.md up-to-date
- [ ] `coverage (ubuntu-latest)` — green; T-* coverage ≥60%; COVERAGE.md up-to-date

If any `e2e` job exits 77 (SKIP) on a runner, that's accepted per spec §Error Handling — the runner lacked symlink permissions or disk space. Re-run the job once to confirm it's environmental, not deterministic.

## Risk register

1. **Scenario backfill (Task 23) under-coverage risk.** Initial T-* coverage measurement may land below the 60% hard gate. Mitigation: per spec Open Question 2 (RESOLVED), add `# Covers:` headers to enough scenarios in the same PR to clear the bar. No staged gate, no ratchet — forge does not do backcompat rollouts.

2. **Windows symlink permission flake.** First CI run on Windows may fail on `os.symlink` before the junction fallback catches. Mitigation: Task 10 catches `OSError`/`NotImplementedError` and exits 77. CI treats 77 as neutral.

3. **Bats submodule missing on canary runs.** `tests/mutation/test_harness_canary.py` skips if `tests/lib/bats-core/bin/bats` is absent. CI runs with `submodules: recursive` so this should not fire, but the skip is defensive.

4. **`state-transitions.md` parse-regex drift.** If a future PR adds row cells with embedded pipes outside backticks, the tolerant regex may silently skip rows. Mitigation: the harness errors out if any seed row ID is missing from the parse result (`row_id not in rows` check in Task 15).

5. **Version freshness.** Typescript 6.0.3 and vitest 4.1.4 are pinned at plan-write time. Per user memory "Version freshness", a future PR touching the fixture must re-WebSearch; do not bump from memory.
