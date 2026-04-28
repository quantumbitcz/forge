# Phase 3: Correctness Proofs — Design

## Goal

Close four latent correctness gaps in the forge pipeline so that behavior believed to be proven by the current test tiers is actually proven, automatically, on every push:

1. Eliminate the boundary livelock in the convergence engine's REGRESSING check.
2. Add a single, real, end-to-end smoke that spawns a minimal project and drives `/forge` → `/forge run --dry-run` to VALIDATED on all three OSes.
3. Introduce mutation testing over the `shared/state-transitions.md` table so under-covered transitions are visible in CI.
4. Publish a machine-generated scenario-coverage report for the transition table, with CI thresholds.

Each gap is independent; each ships with tests for the test harness itself.

## Problem Statement

**Gap 1 — convergence boundary livelock.**
In `shared/convergence-engine.md` line 112, the REGRESSING guard is written as:

```
ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance:
```

The same strictly-greater-than semantics appear in:

- `shared/convergence-engine.md:252` (prose "REGRESSING takes priority" paragraph)
- `shared/state-transitions.md:62` (row 37, `abs(delta) > oscillation_tolerance`)
- `shared/state-transitions.md:140` (row C9)
- `shared/scoring.md:373-374` (Consecutive Dip Rule, uses `<=` / `>` pair symmetrically)
- `shared/convergence_engine_sim.py:75` (`abs(delta) > oscillation_tolerance`)
- `shared/convergence-examples.md:167` (Scenario 3 narration: `|delta| = 3 ≤ oscillation_tolerance (5) → NOT REGRESSING`)

With default `oscillation_tolerance = 5` and scores oscillating 82 → 87 → 82 → 87 …, every delta has `abs(delta) == 5`, the guard is `false`, plateau detection uses `smoothed_delta ≈ 0` which is `<= plateau_threshold (2)`, but `plateau_count` only increments on cycles where smoothed delta is actually sub-threshold — with a perfectly-balanced oscillator that is every cycle after cycle 3, so plateau *does* fire eventually. But with asymmetric drift (82 → 87 → 82 → 88 → 82) the smoothed delta stays positive-ish and neither REGRESSING nor PLATEAUED fires. The pipeline iterates until `max_iterations` — a 30+ minute walk through an unproductive fix loop that the engine is specifically designed to prevent.

The fix is a single-character change: `>` → `>=` at the boundary. This makes delta = tolerance count as REGRESSING rather than "tolerable wobble." We lose nothing: a legitimate single-cycle dip of exactly the tolerance is not noise — it is the defining edge the parameter names. The current Consecutive Dip Rule at `scoring.md:373` already treats `<= oscillation_tolerance` as "minor regression, log WARNING, continue" — the asymmetry between that rule and the convergence engine is the actual bug.

**Gap 2 — no true e2e test.**
`tests/scenario/e2e-dry-run.bats` and `tests/scenario/pipeline-dry-run-e2e.bats` exist, but both simulate the pipeline against fabricated `.forge/state.json` fixtures inside bats — no real `/forge`, no real fg-100, no real plan. `tests/run-all.sh` runs structural + unit + contract + scenario + evals; none spawn a project tree and run a skill. Windows CI was added in Phase 1 but exercises only the bats tiers, which don't touch `/forge`.

**Gap 3 — orchestrator state logic is prose.**
`agents/fg-100-orchestrator.md` is 1557 lines. `shared/state-transitions.md` has 52 numbered pipeline rows, 9 error rows (E1-E9), 3 rewind rows (R1-R3), and 13+ convergence rows (C1-C13). `tests/unit/convergence-engine.bats` and `tests/scenario/convergence-phase-transitions.bats` exist, but a reader cannot tell *which* table rows are exercised. If row 47 (`pr_rejected → PLANNING`) silently regresses to `IMPLEMENTING`, the scenario tests may still pass because they don't target that row.

**Gap 4 — scenario coverage is invisible.**
`tests/scenario/` contains ~55 bats files. No script maps them to state-transitions rows. A new row added to the table carries no signal that it is untested.

## Non-Goals

- Not rewriting the convergence algorithm. The `>` → `>=` change is surgical.
- Not adding new scoring categories or changing score math.
- Not touching real-project integration tests or pipeline evals (`tests/evals/pipeline/`). Those stay CI-only and manual.
- Not replacing `tests/scenario/*.bats`. Coverage reporter reads them, does not regenerate them.
- Not introducing a mutation-testing framework dependency (mutmut, cosmic-ray). Stdlib-only hand-rolled harness.
- Not backfilling coverage below 80% in this phase — just measuring and gating.

## Approach

Three approaches considered for the convergence fix (per `superpowers:brainstorming` discipline):

**A) Runtime assertions — log oscillation, don't block.**
Add a metric that counts "boundary delta observed at tolerance" and emit it at retrospective. Rejected: silent bugs persist. The livelock already logs `smoothed_delta` each cycle; adding another log entry does not change the outcome, only the size of the postmortem.

**B) Strict `>=` at the boundary + executable examples + deterministic simulator tests.** (Recommended.)
One-character algorithm change, documented with three canonical scenarios in `convergence-examples.md`, proven by simulator-driven unit tests seeded deterministically. Symmetrical with `scoring.md:373-374` where `<=` tolerance = "minor, continue" and `>` is "escalate" — the boundary belongs to one side; it should be the escalation side to match the `IMPROVING → REGRESSING` transition name.

**C) Replace the convergence engine with a new algorithm.**
EMA or change-point detection (CUSUM). Rejected: scope creep. The current algorithm's smoothed-delta + patience design is sound; the boundary is off-by-one.

**We pick B.** The patch touches one operator in `convergence_engine_sim.py`, one algorithm line in `convergence-engine.md`, the two transition-table guards in `state-transitions.md`, and the prose paragraph at `convergence-engine.md:252`. Examples and tests anchor the change. `convergence-examples.md` already exists with 4 scenarios; we extend Scenario 3 (oscillation) and add an explicit boundary scenario.

For gaps 2-4, the approach is "one thin, deterministic Python tool per gap, each with its own tests." No new third-party deps. `pyproject.toml` is stdlib-only outside the `otel` extras group — we keep it that way.

## Components

### 1. Convergence boundary fix (strict `>=`)

Scope:

- `shared/convergence_engine_sim.py:75` — change `abs(delta) > oscillation_tolerance` to `abs(delta) >= oscillation_tolerance`.
- `shared/convergence-engine.md:112` — update algorithm pseudocode to `abs(delta) >= oscillation_tolerance`.
- `shared/convergence-engine.md:252` — update the prose note to match.
- `shared/state-transitions.md:62` (row 37) and `:140` (row C9) — guards become `abs(delta) >= oscillation_tolerance`.
- `shared/convergence-examples.md:167` — narration updated: `|delta| = 3 < oscillation_tolerance (5) → NOT REGRESSING`, and add a fifth scenario:
  - **Scenario 5: Boundary oscillation.** `scores = [87, 82, 87, 82, 87]`, tolerance 5. Under old `>`: continues indefinitely. Under new `>=`: REGRESSING fires at cycle 2 (delta = -5).
- No config change. `oscillation_tolerance = 0` still means "any drop escalates" (unchanged behavior; delta = 0 is never negative).

No other `shared/**.md` file uses the `> oscillation_tolerance` semantics in an algorithmically meaningful way; `scoring.md:374` uses `>` for an analogous Consecutive Dip Rule but operates within a single convergence iteration — its semantics are already consistent with the new convergence engine boundary because the matched `<=` clause at `scoring.md:373` does not escalate. We leave `scoring.md` alone and add a note explaining the asymmetry is intentional (inner-loop warning vs. outer-loop escalation).

### 2. Python simulator + unit tests

Extend `tests/unit/test_convergence_engine_sim.py` (file exists, asserts on last-line decision/phase). Add:

- `test_oscillation_at_boundary_escalates_by_cycle_5`: 10 synthetic cycles oscillating `[82, 87, 82, 87, 82, 87, 82, 87, 82, 87]`, assert a REGRESSING / ESCALATE decision appears on or before cycle 5.
- `test_monotonic_improvement_never_regresses`: `[40, 55, 70, 85, 95]`, assert no cycle emits `REGRESSING`.
- `test_oscillation_within_tolerance_does_not_regress`: `[82, 84, 82, 84, 82]`, tolerance 5, assert no cycle emits `REGRESSING` (deltas are 2, all strictly less than 5).
- `test_boundary_delta_equals_tolerance_escalates`: `[85, 80]`, tolerance 5, assert `REGRESSING`. (Under old semantics: `IMPROVING`. Under new: `REGRESSING`.)

All scores are hardcoded lists — no randomness, so determinism is trivial. Tests live in the existing file; the suite runs under pytest via `tests/run-all.sh unit` indirectly (bats shell-outs Python for this file) and directly via `pytest tests/unit/test_convergence_engine_sim.py` when run by humans. CI-only per `feedback_no_local_tests`.

Platform note: `windows-latest` matrix already runs bats via Git Bash (its default shell), and Python is on PATH — `tests/run-all.sh` and the unit-test harness have been shelling out to `sys.executable` on Windows since Phase 1 without issue. The new mutation and e2e components rely on the same assumption. If a future bats tier invocation on Windows fails to locate Python, the plan's task list should add a one-shot `python -c "import sys; print(sys.executable)"` smoke at job start to surface the problem early.

The `convergence_engine_sim.py` port is already done (Windows-compatible, no `bc`). No second port needed.

### 3. E2E dry-run smoke (`tests/e2e/dry-run-smoke.py`)

New directory: `tests/e2e/`. New script: `tests/e2e/dry-run-smoke.py`. New fixture: `tests/e2e/fixtures/ts-vitest/`.

Fixture contents (the minimum that `/forge` detects as a typescript+vitest project):

```
tests/e2e/fixtures/ts-vitest/
  package.json
  tsconfig.json
  vitest.config.ts
  src/index.ts
  src/index.test.ts
```

`package.json`:

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
    "typescript": "<!-- TODO: plan-writer must WebSearch latest stable at plan time -->",
    "vitest": "<!-- TODO: plan-writer must WebSearch latest stable at plan time -->"
  }
}
```

Note: version strings in the fixture `package.json` are deliberately left unpinned in this spec per `feedback_version_freshness`. The plan-writer MUST run a WebSearch for the latest stable release of `typescript` and `vitest` at plan-authoring time and pin those versions in the plan (and the committed fixture file) — not values from this spec or training data.

`src/index.ts` exports `export const health = () => ({ status: 'ok' } as const);`. `src/index.test.ts` imports and asserts. `tsconfig.json` is minimal (`"target": "es2022", "module": "esnext", "strict": true`). `vitest.config.ts` uses defaults.

Test steps (`dry-run-smoke.py`):

1. `tempfile.TemporaryDirectory()`; copy fixture into it.
2. `git init && git add -A && git commit -m 'fixture'` (forge-init expects a git repo).
3. Symlink the plugin root in: `mkdir -p .claude/plugins && ln -s <forge-root> .claude/plugins/forge`. On Windows, use a directory junction via `subprocess.run(['cmd', '/c', 'mklink', '/J', ...])` fallback if symlinks fail.
4. Run `/forge` — simulated via a direct Python shim that calls `hooks._py.forge_init.detect_and_write_config(project_dir: Path) -> dict` (the deterministic detection + `forge.local.md` write path), since we cannot spawn Claude Code in CI. The acceptance is scoped honestly as a **detection + config-write smoke**, not an end-to-end pipeline smoke; it does not exercise LLM routing. (This is the spec's biggest pragmatic choice — see Open Questions.)
5. Assert `.forge/forge.local.md` exists and declares `language: typescript` and `testing: vitest`.
6. Run the dry-run equivalent: invoke `shared/forge-sim.sh --dry-run "add health endpoint"` (existing harness — verified present; uses only `set -uo pipefail`, no bash 4+ features like `mapfile` / `declare -A`) against the temp dir. The Windows matrix executes this via Git Bash (the default shell on `windows-latest` GitHub runners), so the bash harness runs uniformly on all three OSes.
7. Assert `.forge/state.json` exists and `state.story_state in {VALIDATED, COMPLETE}` (dry-run row D1 routes VALIDATING → COMPLETE).
8. Assert `state.story_state` never equals any of E1-E4 error states (`ESCALATED` with those event classifications in `events.jsonl`).

Teardown: `TemporaryDirectory` context manager guarantees cleanup on exception.

Budget: <90s per platform on Linux/macOS. Setup uses `npm ci --no-audit --no-fund` (not `npm install`) for deterministic, lock-file-pinned installs from a cold cache. The 90s budget includes the `npm ci` step. **Windows exception:** cold-cache `npm ci` on `windows-latest` is consistently slower due to NTFS small-file overhead; the Windows job uses a 180s `timeout-minutes` for this step only. If this proves insufficient even at 180s, fall back to shrinking the fixture (skip `npm ci` entirely — detection only needs the `package.json`/`tsconfig.json`/`vitest.config.ts` files on disk, not installed node_modules).

CI wiring: add a job `e2e` to `.github/workflows/test.yml` with `runs-on: ${{ matrix.os }}`, matrix `[ubuntu-latest, macos-latest, windows-latest]`, `timeout-minutes: 5` (ubuntu/macos) or `timeout-minutes: 8` (windows, to absorb the npm-install headroom). Runs `python tests/e2e/dry-run-smoke.py`. Script exits 0 on PASS, 77 on SKIP (network/perms), non-zero on FAIL.

### 4. Mutation harness (`tests/mutation/state_transitions.py`)

New directory. Stdlib-only. No `unidiff` or mutmut — hand-rolled.

Operation:

1. Parse `shared/state-transitions.md`. Extract the three transition tables (normal flow, error, convergence) via a regex on `| N | ... |` markdown rows. Emit a typed dict per row: `{id, current_state, event, guard, next_state, action}`.
2. For each of the 5 seed high-risk rows, load the row and pick a deliberately-wrong `next_state` alternative from the finite state enum (e.g., row 47 `pr_rejected → PLANNING` becomes `pr_rejected → IMPLEMENTING` — matches row 46's target, which is the likely human error).
3. The harness is a **meta-test**, not a hot-patcher. It does not modify production files or `state-transitions.md` on disk. Instead, it exports a `MUTATE_ROW=<id>` env var and invokes the targeted bats scenario. Participating seed-row bats files read `$MUTATE_ROW` and, when set, flip their *own* expected-`next_state` assertion to the mutated value. This keeps the rewiring inside the test files that already own the assertion; no production code reads `MUTATE_ROW`.
4. Run the targeted scenario test (`MUTATE_ROW=<id> bats tests/scenario/<name>.bats`). Expect **failure** (the scenario asserts the real next_state; under mutation it should see the wrong one and fail). If it passes, the row is under-covered — the scenario did not actually exercise the transition.
5. Emit a markdown report `tests/mutation/REPORT.md` with columns `| row_id | mutation | scenario | survived? |`.

Seed rows (high-risk, 5 for Phase 3):

- Row 37 — `score_regressing` target (ESCALATED). Mutation: → `IMPLEMENTING`. Scenario: `oscillation.bats`.
- Row 28 — `safety_gate_fail` with `< 2` failures (IMPLEMENTING, restart semantics). Mutation: → `DOCUMENTING`. Scenario: `safety-gate.bats`.
- Row E3 — circuit breaker open (ESCALATED). Mutation: → `<prior>`. Scenario: `circuit-breaker.bats`.
- Row 47 — PR rejected, design classification (PLANNING). Mutation: → `IMPLEMENTING`. Scenario: `feedback-loop.bats`.
- Row 48 — `feedback_loop_count >= 2` escalation. Mutation: guard becomes `>= 3`. Scenario: `feedback-loop.bats`.

Implementation steps within bats scenario files: each scenario that participates declares at the top `# mutation_row: 37` as a comment. The harness scans for this comment, intersects with its seed list, and runs the right scenario. Scenarios without the comment are not mutation-covered (and get a note in the report). The five seed-row bats files (`oscillation.bats`, `safety-gate.bats`, `circuit-breaker.bats`, `feedback-loop.bats`) must be updated to read `$MUTATE_ROW` at the top of the scenario and conditionally swap their expected `next_state` assertion when the env var matches their `# mutation_row:` header.

Report format (committed to `tests/mutation/REPORT.md` via CI auto-regeneration):

```markdown
| row_id | row_description | scenario | mutation_applied | survived |
| 37 | score_regressing → ESCALATED | oscillation.bats | → IMPLEMENTING | NO |
| 28 | safety_gate_fail<2 → IMPLEMENTING | safety-gate.bats | → DOCUMENTING | NO |
...
```

CI: `tests/mutation/state_transitions.py` runs on ubuntu-latest only (saves matrix budget; the harness is OS-agnostic). Posts the report as a PR comment via `gh pr comment` (existing CI patterns). If any survivor exists, fail with exit 1 and print the row.

### 5. Scenario coverage report (`tests/scenario/report_coverage.py`)

Stdlib-only. Parses `shared/state-transitions.md`'s rows and `tests/scenario/*.bats` files.

**Coverage-mapping approach — declarative header.** Each scenario declares its covered rows at the top:

```bash
# Covers: T-037, T-047, C-09
```

Rationale: inferring from filename (`oscillation.bats` → row 37) is brittle — some scenarios cover multiple rows, some cover rows not reflected in the name (e.g., `convergence-phase-transitions.bats` covers all C rows). Naming-based inference compounds errors silently. An explicit header is a one-line declaration that makes intent auditable. We pick the simpler-to-audit approach even though it requires a one-time backfill (`tests/scenario/*.bats` get `# Covers:` headers, empty if none).

Script steps:

1. Parse **actual present** row numbers from each of the four tables in `state-transitions.md` — do not assume dense `1..N` numbering. Today the normal-flow table has a gap at row 20 (rows 1..19, 21..52 present). Ignore/skip any missing numbers; the coverage denominator is the count of present rows, not `max(id)`. Emit IDs as `T-<n>`, `E-<n>`, `R-<n>`, `C-<n>` using the numbers that actually appear.
2. Walk `tests/scenario/*.bats`, extract `# Covers: ` headers, aggregate row → scenario(s) mapping.
3. Produce `tests/scenario/COVERAGE.md`:

```markdown
# Scenario Coverage

| row_id | description | covered_by | covered? |
| T-01 | PREFLIGHT + preflight_complete + dry_run==false | pipeline-dry-run-e2e.bats | YES |
| T-37 | REVIEWING + score_regressing | oscillation.bats | YES |
| T-51 | REVIEWING + score_plateau + max_iters | — | NO |
...

**Coverage: 42 / 78 rows (53.8%) — below 60% threshold → CI FAILURE**
```

4. CI integration: `.github/workflows/test.yml` adds a `coverage` job. Regenerates `COVERAGE.md` and `git diff --exit-code tests/scenario/COVERAGE.md` — if it differs from the committed version, fail with "stale coverage report; run `python tests/scenario/report_coverage.py` and commit."
5. Compute coverage percentage. `>= 80%` passes. `60-80%` prints a CI warning (`::warning::`). `< 60%` fails the job.

Below 60 is the hard gate; between 60 and 80 is a visible warning. Matches the gap we're in today (the initial measurement is likely around 50-55%).

**Coverage scope split.** The 60% gate applies to the **normal-flow `T-*` rows only** (pipeline transitions — the happy path and stage-to-stage moves that scenarios naturally target). The `E-*` (error recovery), `R-*` (rewind), and `D-*` (dry-run) rows will initially show much lower coverage (~50% expected) because they represent recovery paths that few scenarios exercise. These are **excluded from the 60% hard gate** and tracked separately in a second section of `COVERAGE.md` titled `## Recovery & Rewind Coverage` with its own percentage. Raising coverage on those rows is a follow-up phase. The split keeps Phase 3 honest — we gate what scenarios already target, and make the recovery-coverage gap visible without blocking.

## Data / File Layout

**New files:**

- `tests/e2e/dry-run-smoke.py` (new)
- `tests/e2e/fixtures/ts-vitest/package.json`
- `tests/e2e/fixtures/ts-vitest/tsconfig.json`
- `tests/e2e/fixtures/ts-vitest/vitest.config.ts`
- `tests/e2e/fixtures/ts-vitest/src/index.ts`
- `tests/e2e/fixtures/ts-vitest/src/index.test.ts`
- `tests/mutation/state_transitions.py` (new)
- `tests/mutation/REPORT.md` (generated, committed)
- `tests/mutation/test_harness_canary.py` (new — canary for mutation harness)
- `tests/mutation/test_coverage_canary.py` (new — canary for coverage reporter)
- `tests/mutation/fixtures/` (new directory holding canary inputs)
- `tests/mutation/fixtures/synthetic-state-transitions.md` (new — 4-row synthetic table for coverage-canary)
- `tests/mutation/fixtures/synthetic-scenario-a.bats` (new — covers 2 synthetic rows)
- `tests/mutation/fixtures/synthetic-scenario-b.bats` (new — covers 1 synthetic row)
- `tests/scenario/report_coverage.py` (new)
- `tests/scenario/COVERAGE.md` (generated, committed)

**Modified files:**

- `shared/convergence-engine.md` (algorithm line 112, prose line 252)
- `shared/convergence_engine_sim.py` (line 75)
- `shared/convergence-examples.md` (Scenario 3 narration + new Scenario 5)
- `shared/state-transitions.md` (rows 37, C9 guards)
- `tests/unit/test_convergence_engine_sim.py` (4 new tests)
- `tests/scenario/*.bats` (~55 files — add `# Covers: ...` header; empty if no coverage claim)
- `tests/scenario/oscillation.bats`, `tests/scenario/safety-gate.bats`, `tests/scenario/circuit-breaker.bats`, `tests/scenario/feedback-loop.bats` (add `# mutation_row: <id>` header + `$MUTATE_ROW` conditional on expected `next_state` assertion for mutation harness participation)
- `.github/workflows/test.yml` (add `e2e`, `mutation`, `coverage` jobs)
- `CLAUDE.md` (§Testing strategy, §Convergence & review)
- `README.md` (testing section)
- `tests/README.md` (new file — document the tiers including e2e/mutation/coverage)

**Untouched:** `agents/fg-100-orchestrator.md` prose stays as is; the mutation harness reads the table, not the agent. No production code changes beyond `convergence_engine_sim.py`.

## Error Handling

- **Fixture unreachable (network/perms).** `dry-run-smoke.py` catches `PermissionError`, `OSError(errno=ENOSPC)`, and network exceptions during the simulated `/forge`; logs and exits 77 (standard "skip"). CI treats 77 as `neutral` via `if: steps.e2e.outcome == 'skipped'`.
- **Malformed transition table.** The parser in `state_transitions.py` and `report_coverage.py` asserts each row matches the exact `| N | state | event | guard | next | action |` schema. On mismatch: raise `TransitionTableError(f"malformed row at {path}:{lineno}: {line!r}")` and exit 2. CI surfaces the exception traceback.
- **Missing `# Covers:` header in a bats file.** Treated as no coverage claim, not an error. The coverage report lists the scenario under "unmapped scenarios" for humans to triage.
- **Windows junction fallback.** `dry-run-smoke.py` tries `os.symlink` first, catches `OSError(errno=EPERM)` or `NotImplementedError`, falls back to `subprocess.run(['cmd', '/c', 'mklink', '/J', ...])`. If both fail: exit 77.
- **Mutation harness: row not in seed list but referenced by scenario.** Harmless; the scenario still runs normally outside the harness. Log INFO.

## Testing Strategy

- **Convergence fix:** the simulator's new unit tests are the proof. The existing `convergence-arithmetic.bats` and `convergence-engine-advanced.bats` regression-guard the other arithmetic paths.
- **E2E smoke:** self-test — `tests/e2e/dry-run-smoke.py` has a `--self-test` flag that runs against a known-good baked-in state.json fixture and asserts the script's own assertion logic. Catches the class of bug where the script always returns green.
- **Mutation harness:** a "canary test" — one mutation intentionally applied to a *covered* row must produce `survived=NO`. If that canary shows `survived=YES`, the harness is not actually running the scenario, which is a harness bug. Implemented as `tests/mutation/test_harness_canary.py`.
- **Coverage reporter:** given a synthetic `shared/state-transitions.md` with 4 rows and a synthetic `tests/scenario/` with 2 bats files that cover 3 of them, assert the reporter outputs `75%` and a single `NO` row. Implemented as `tests/mutation/test_coverage_canary.py` (same directory, since it's the same class of meta-test).
- **Platform matrix:** all four components run on `[ubuntu-latest, macos-latest, windows-latest]`, except the mutation harness which runs on ubuntu-latest only (it's pure Python and table-driven — no OS-dependent behavior). E2E is the critical cross-platform test.
- **Determinism:** all simulator inputs are hardcoded lists; no time/UUID/randint usage. If any is added later, it must be seeded (`random.seed(0)`).

## Documentation Updates

- **`CLAUDE.md`:**
  - §Convergence & review — add bullet: "REGRESSING fires when `abs(delta) >= oscillation_tolerance` (inclusive). A delta equal to tolerance is not noise."
  - §Testing strategy — add line: "E2E smoke at `tests/e2e/`. Mutation harness at `tests/mutation/`. Coverage report regenerated per PR."
- **`shared/convergence-engine.md`:** algorithm + prose update as described in Component 1.
- **`shared/state-transitions.md`:** rows 37 and C9 updated. Add a "See mutation report" footer link to `tests/mutation/REPORT.md`.
- **`README.md`:** add a `Testing` section with the tier matrix (structural, unit, contract, scenario, eval, e2e, mutation, coverage).
- **`tests/README.md`:** new file. Document each test tier, how to run locally (even though `feedback_no_local_tests` says we don't — the docs exist for debugging), and the failure modes.
- **`.github/workflows/test.yml`:** three new jobs (`e2e`, `mutation`, `coverage`). `e2e` on full matrix; `mutation` ubuntu only; `coverage` ubuntu only.
- **Version bump.** `plugin.json` 3.6.0 → 3.7.0 (minor — no breaking behavior; the convergence fix is observable only in adversarial oscillation scenarios that today livelock).

## Acceptance Criteria

1. `shared/convergence_engine_sim.py` line 75 reads `abs(delta) >= oscillation_tolerance`.
2. `shared/convergence-engine.md` algorithm line and "REGRESSING takes priority" paragraph read `>=`.
3. `shared/state-transitions.md` rows 37 and C9 guards read `abs(delta) >= oscillation_tolerance`.
4. `shared/convergence-examples.md` contains a new Scenario 5 (boundary oscillation) and Scenario 3 narration updated to strict `<`.
5. `tests/unit/test_convergence_engine_sim.py` contains 4 new tests named exactly `test_oscillation_at_boundary_escalates_by_cycle_5`, `test_monotonic_improvement_never_regresses`, `test_oscillation_within_tolerance_does_not_regress`, `test_boundary_delta_equals_tolerance_escalates` — all pass under pytest.
6. `tests/e2e/dry-run-smoke.py` exists, runs in CI on all 3 OSes, completes in < 90s per OS, asserts VALIDATED or COMPLETE final state, and exits 77 on detected environmental skip.
7. `tests/mutation/state_transitions.py` parses all pipeline/error/convergence rows from `state-transitions.md`, applies the 5 seed mutations, and emits `tests/mutation/REPORT.md`. CI fails if any seed row shows `survived=YES`.
8. `tests/scenario/report_coverage.py` emits `tests/scenario/COVERAGE.md` with row-by-row coverage. CI fails if the committed file is stale (diff non-empty). CI fails if coverage < 60%, warns if < 80%.
9. Canary tests `tests/mutation/test_harness_canary.py` and `tests/mutation/test_coverage_canary.py` exist and pass.
10. `.github/workflows/test.yml` gains `e2e`, `mutation`, `coverage` jobs and they all run on `master` pushes and PRs.
11. `plugin.json` and `marketplace.json` bumped to 3.7.0; `CHANGELOG.md` notes the convergence fix and the new test tiers.

## Open Questions

1. **E2E `/forge` simulation depth.** Can we invoke `/forge` in CI without spawning Claude Code? The spec proposes a Python shim that reproduces the deterministic parts (module detection, `forge.local.md` writing). This exercises ~80% of init's surface but not the LLM-routed greenfield detection. Acceptable for Phase 3; real `/forge` coverage belongs to pipeline evals. If this proves too shallow, an alternative is to record a Claude Code fixture transcript once and replay — deferred.
2. **Coverage backfill. — RESOLVED.** Per `feedback_no_backcompat`, forge does not do baseline-minus-N ratchets or opt-in rollouts. Resolution: measure coverage in a draft PR against the unpinned reporter. Commit the real **60% gate** in the first shipping PR. If measured coverage is below 60%, add `# Covers:` headers to enough existing scenarios to clear the bar in the same PR. No staged/temporary gate. No ratchet.
3. **Row naming convention.** Currently the rows use bare `| 37 |`. Harness and coverage report use `T-37` / `E-3` / `C-9` / `R-1`. Should `state-transitions.md` itself adopt these prefixes in the table for grep-ability? Proposed: yes, in a follow-up editorial pass — not blocking Phase 3.
4. **Mutation scope.** 5 seed rows is starter coverage. Full 78-row mutation matrix would take 5-10 CI minutes sequentially. Deferred — ratchet up in Phase 3.2.
