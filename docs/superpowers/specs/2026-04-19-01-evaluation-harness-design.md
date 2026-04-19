# Phase 01 — Pipeline Evaluation Harness Design

> **Phase:** 01 (of the forge A+ roadmap)
> **Priority:** P0 — foundational for all subsequent phases
> **Status:** Approved (requirements pre-approved by maintainer; no Q&A loop)
> **Audience:** forge maintainers, CI owners, Phase 02+ authors

---

## 1. Goal

Build a pipeline-level evaluation harness (`tests/evals/pipeline/`) with 10 frozen scenarios that run forge end-to-end against itself on every PR and emit per-commit score / token / elapsed / overlap metrics so quality regressions are caught in CI before merge.

---

## 2. Motivation

Audit finding **W1 — forge has no self-evaluation.** The existing `tests/evals/` tree covers *agent-level* reviewer I/O (static pattern matching), not *pipeline-level* outcomes. That gap means `fg-700-retrospective` tunes on in-run scores rather than held-out task performance, and every config change is one commit away from silently eroding quality across all modes.

Every mature 2026 agentic system ships an eval harness:

- **Anthropic skill-creator (Mar 2026)** ships a trigger-description optimizer backed by a frozen eval set — https://perevillega.com/posts/2026-04-01-claude-code-skills-2-what-changed-what-works-what-to-watch-out-for/
- **OpenHands Index (Jan 2026)** — public leaderboard of agent systems scored on frozen tasks — https://openhands.dev/blog/openhands-index
- **Princeton HAL harness** — reference architecture for holistic agent evals — https://github.com/princeton-pli/hal-harness
- **SWE-CI paper (2026)** — CI-integrated eval for code-editing agents — https://arxiv.org/html/2603.03823v1

Shipping evals is table stakes. Phase 01 is the foundation every subsequent phase depends on: without it, no later phase can prove it did not regress the pipeline.

---

## 3. Scope

### In scope

- Scenario format (directory per scenario; `prompt.md` + `expected.yaml` + optional `fixtures/`)
- Python 3.10+ runner (aligned with Phase 02 hook migration) at `tests/evals/pipeline/runner/`
- 10 frozen scenarios covering `standard`, `bugfix`, `migration`, and `bootstrap` pipeline modes
- Composite scoring: `0.5 × pipeline_score + 0.25 × token_budget_adherence + 0.25 × elapsed_adherence`
- Touched-files overlap as a secondary reporting-only metric (not part of composite)
- GitHub Actions workflow `.github/workflows/evals.yml` triggered on every PR and on push to `master`
- Regression gate: fail CI when composite drops >3 points vs the stored `master` baseline
- Results artifact `.forge/eval-results.jsonl` (one record per scenario per run)
- Auto-generated `tests/evals/pipeline/leaderboard.md` committed by the CI bot on `master` pushes only
- New scoring categories `EVAL-*` for harness-emitted findings
- New `forge-config.md` section `evals:` and new `state-schema.md` field `eval_run`

### Out of scope (deferred to later phases)

- Cross-plugin benchmarking (forge vs openhands vs anthropic skill-creator)
- User-supplied scenarios from consuming projects
- Live-API reviewer evaluation (`--live` mode — already a placeholder in agent eval README)
- Cost-per-finding optimization beyond reporting
- Scenario sandbox isolation via Docker (initial harness runs in CI ephemeral VM only)

---

## 4. Architecture

### High-level shape

```
tests/evals/pipeline/
  runner/
    __main__.py          # python -m tests.evals.pipeline.runner
    scenarios.py         # discovery + schema validation
    executor.py          # worktree setup, forge invocation, capture
    scoring.py           # composite score math
    baseline.py          # master baseline fetch + diff
    report.py            # leaderboard + jsonl writer
    schema.py            # pydantic models (Scenario, Expected, Result)
  scenarios/
    01-ts-microservice-greenfield/
      prompt.md
      expected.yaml
      fixtures/starter.tar.gz       (optional)
    02-python-bugfix/ ...
    ...
    10-php-security-fix/
  leaderboard.md         # auto-generated, committed by CI on master only
  README.md              # how to run locally, how to add scenarios
```

The runner is a single-responsibility Python package. Each module owns one concern (discovery / execution / scoring / baseline / reporting), so a future phase can swap any piece (e.g. replace the filesystem baseline with a SQLite one) without touching the others.

### Per-scenario flow

1. **Discover** — `scenarios.py` enumerates `scenarios/*/expected.yaml`, validates each against the pydantic schema, and rejects the run at collection time if any scenario is malformed. Fail-fast; no partial runs.
2. **Isolate** — `executor.py` creates a temp directory, extracts `fixtures/starter.tar.gz` (if present) or `git init`s an empty repo, symlinks the current forge plugin checkout into `.claude/plugins/forge`, and runs `/forge-init` non-interactively to seed config.
3. **Execute** — invokes `/forge-run --eval-mode <scenario_id>` (new flag) with the prompt from `prompt.md`. `--eval-mode` disables Linear sync, Slack, and interactive prompts and forces `autonomous: true`. Wall-clock and token counters are captured from `.forge/state.json` after completion.
4. **Score** — `scoring.py` reads `state.json`, computes each component (see §6), and emits a `Result` record.
5. **Aggregate** — `report.py` writes JSONL, generates the leaderboard markdown, and (on PR runs) diffs against the stored baseline.

### Baseline and regression gate

On every push to `master`, CI runs the full suite and uploads `eval-results.jsonl` as a workflow artifact tagged with the commit SHA. The latest `master` artifact is the baseline. On PR runs, the runner downloads the latest `master` artifact, computes `composite_delta = mean(pr_composite) - mean(master_composite)`, and fails the job when `composite_delta < -3.0`. The 3-point tolerance absorbs routine variance from non-deterministic LLM calls while still catching material regressions.

### Alternatives considered

**A. Bash harness extending `tests/run-all.sh`.** Rejected. Existing suite is bats/bash for structural checks at sub-second granularity. Scenario runs take 3-10 minutes each and need JSON parsing, HTTP artifact fetches, and schema validation. Python is a better fit and aligns with Phase 02's planned hook-migration target (Python 3.10+), avoiding a second language in the eval path.

**B. Live-API agent evals (extend existing `tests/evals/agents/`).** Rejected for Phase 01. Agent evals measure *reviewer* behavior in isolation; pipeline evals measure *orchestrator + all agents + inner loops* on a realistic task. They answer different questions. Live agent evals remain valuable and are deliberately left as-is; this harness complements them rather than replacing them.

---

## 5. Components

### Creates

- `tests/evals/pipeline/runner/__init__.py`
- `tests/evals/pipeline/runner/__main__.py` — CLI entry (`python -m tests.evals.pipeline.runner`)
- `tests/evals/pipeline/runner/scenarios.py` — scenario discovery + schema validation
- `tests/evals/pipeline/runner/executor.py` — worktree setup + forge invocation
- `tests/evals/pipeline/runner/scoring.py` — composite score math
- `tests/evals/pipeline/runner/baseline.py` — fetch + diff against master baseline
- `tests/evals/pipeline/runner/report.py` — JSONL + leaderboard writer
- `tests/evals/pipeline/runner/schema.py` — pydantic models
- `tests/evals/pipeline/runner/requirements.txt` — pinned deps (`pydantic>=2`, `pyyaml`, `requests`)
- `tests/evals/pipeline/scenarios/01-ts-microservice-greenfield/{prompt.md,expected.yaml}` — TypeScript + Express greenfield (`standard` mode)
- `tests/evals/pipeline/scenarios/02-python-bugfix/{prompt.md,expected.yaml,fixtures/starter.tar.gz}` — FastAPI off-by-one (`bugfix` mode)
- `tests/evals/pipeline/scenarios/03-kotlin-spring-migration/{prompt.md,expected.yaml,fixtures/starter.tar.gz}` — Spring Boot 2→3 (`migration` mode)
- `tests/evals/pipeline/scenarios/04-react-bootstrap/{prompt.md,expected.yaml}` — React + Vite + Vitest (`bootstrap` mode)
- `tests/evals/pipeline/scenarios/05-go-performance-fix/{prompt.md,expected.yaml,fixtures/starter.tar.gz}` — N+1 HTTP loop (`bugfix` mode)
- `tests/evals/pipeline/scenarios/06-rust-refactor/{prompt.md,expected.yaml,fixtures/starter.tar.gz}` — extract trait (`standard` mode, `refactor` overlay)
- `tests/evals/pipeline/scenarios/07-python-mlops-pipeline/{prompt.md,expected.yaml,fixtures/starter.tar.gz}` — DVC + MLflow stub (`standard` mode)
- `tests/evals/pipeline/scenarios/08-flask-spike/{prompt.md,expected.yaml}` — single-file Flask throwaway (`standard` mode, small scope)
- `tests/evals/pipeline/scenarios/09-swift-concurrency/{prompt.md,expected.yaml,fixtures/starter.tar.gz}` — actor-based race-condition fix (`bugfix` mode)
- `tests/evals/pipeline/scenarios/10-php-security-fix/{prompt.md,expected.yaml,fixtures/starter.tar.gz}` — SQL injection patch (`bugfix` mode)
- `tests/evals/pipeline/leaderboard.md` — initial empty skeleton; CI overwrites on `master`
- `tests/evals/pipeline/README.md` — local invocation, add-a-scenario guide, schema reference
- `.github/workflows/evals.yml` — PR + `master` workflow
- `shared/checks/eval-categories.md` — registry documentation for the new `EVAL-*` category family

### Modifies

- `tests/run-all.sh` — add new tier `pipeline-eval` (documented but NOT run in the default local flow; CI-only per project norm)
- `shared/checks/category-registry.json` — add `EVAL-*` wildcard family
- `shared/scoring.md` — append `EVAL-*` row to the shared categories table
- `shared/state-schema.md` — document new root field `eval_run` (see §6)
- `agents/fg-100-orchestrator.md` — recognize `--eval-mode <id>` flag; disable Linear/Slack/AskUserQuestion when set; force `autonomous: true`
- `CLAUDE.md` — add one-line pointer under "Validation" section linking to `tests/evals/pipeline/README.md`

### Deletes

None. This is purely additive — the existing `tests/evals/agents/` tree is untouched.

---

## 6. Data, State & Config

### New `forge-config.md` keys

```yaml
evals:
  enabled: true                    # CI reads this to decide whether to run the job
  composite_weights:
    pipeline_score: 0.5
    token_adherence: 0.25
    elapsed_adherence: 0.25
  regression_tolerance: 3.0        # composite-point drop that fails CI
  baseline_branch: master          # branch whose artifact is the baseline
  scenario_timeout_seconds: 900    # 15-minute hard cap per scenario
  total_budget_seconds: 2700       # 45-minute hard cap for whole suite
  emit_overlap_metric: true        # touched-files Jaccard, reporting-only
```

PREFLIGHT constraints (added to `shared/preflight-constraints.md`):

- `composite_weights.*` must sum to 1.0 (±0.01 tolerance)
- `regression_tolerance` must be in `[0, 20]`
- `scenario_timeout_seconds` must be in `[60, 1800]`
- `total_budget_seconds` must be >= `scenario_timeout_seconds`

### New `state-schema.md` field

Root-level `eval_run` object — present only when the orchestrator was invoked with `--eval-mode`:

```json
{
  "eval_run": {
    "scenario_id": "01-ts-microservice-greenfield",
    "started_at": "<ISO-8601>",
    "ended_at": "<ISO-8601>",
    "mode": "standard",
    "expected_token_budget": 150000,
    "expected_elapsed_seconds": 600,
    "touched_files_expected": ["src/server.ts", "src/routes/users.ts"]
  }
}
```

State-schema version bump: `1.6.0 → 1.7.0`.

### `expected.yaml` schema

```yaml
id: 01-ts-microservice-greenfield
mode: standard                     # standard|bugfix|migration|bootstrap
token_budget: 150000               # upper bound; over-budget degrades adherence linearly
elapsed_budget_seconds: 600
min_pipeline_score: 85
required_verdict: PASS             # PASS|CONCERNS (never FAIL in frozen scenarios)
touched_files:                     # used for overlap metric, not composite
  - src/server.ts
  - src/routes/users.ts
must_not_touch:                    # hard-fail if the pipeline edits any of these
  - .claude/**
  - tests/evals/**
notes: "Greenfield TS microservice; PASS expected on first convergence iteration."
```

### Composite scoring formula

```
token_adherence    = clamp01(2 - actual_tokens / expected_token_budget)
elapsed_adherence  = clamp01(2 - actual_elapsed / expected_elapsed_budget)
composite          = 100 * (
                       0.50 * (pipeline_score / 100)
                     + 0.25 * token_adherence
                     + 0.25 * elapsed_adherence
                   )
```

`clamp01` floors at 0 and ceilings at 1. Going under budget is rewarded up to 2× (full credit at half the budget); going over is penalized linearly (zero credit at 2× the budget). Hitting budget exactly yields 1.0 on that axis.

Overlap is computed as Jaccard similarity of `touched_files_expected` vs actual files changed and reported only — it is diagnostic, not gating, because file layout decisions are legitimately author-driven.

### New `EVAL-*` scoring categories

| Code | Severity | Meaning |
|---|---|---|
| `EVAL-REGRESSION` | CRITICAL | Composite dropped more than `regression_tolerance` vs baseline |
| `EVAL-TIMEOUT` | CRITICAL | Scenario exceeded `scenario_timeout_seconds` |
| `EVAL-MUST-NOT-TOUCH` | CRITICAL | Pipeline modified a path listed in `must_not_touch` |
| `EVAL-VERDICT-MISMATCH` | WARNING | Actual verdict worse than `required_verdict` |
| `EVAL-BUDGET-OVER` | WARNING | Tokens or elapsed over budget (even if adherence still > 0) |
| `EVAL-OVERLAP-LOW` | INFO | Jaccard(touched_expected, touched_actual) < 0.5 |

`EVAL-*` findings are excluded from pipeline-internal scoring (they are metadata about the eval itself, not about code quality) and live only in `eval-results.jsonl` and the leaderboard.

---

## 7. Compatibility

**No backwards compatibility guarantee is offered** — the project explicitly waives it (per maintainer standing policy restated in the task brief). That said, the changes here are additive:

- New directories, new workflow, new config keys with safe defaults.
- `--eval-mode` is a new orchestrator flag; without it, behavior is unchanged.
- `state-schema.md` bump to 1.7.0 adds an optional root field; existing `.forge/state.json` readers that ignore unknown fields are unaffected.
- The existing `tests/evals/agents/` agent-eval tree is untouched. The name collision is resolved by placing the new harness at `tests/evals/pipeline/` — the two trees live side-by-side.

No breaking changes. No data migrations. No deprecations.

---

## 8. Testing Strategy

**CI-only** per project policy — no local test execution. The harness validates itself via three layers inside `.github/workflows/evals.yml`:

1. **Static collection (fast, ~5 s).** Run `python -m tests.evals.pipeline.runner --collect-only`. Discovers every scenario, parses each `expected.yaml` through the pydantic schema, and fails if any is malformed. No forge invocation. This is the equivalent of `pytest --collect-only` and catches 100% of scenario authoring mistakes before burning a 15-minute run.
2. **Dry-run smoke (medium, ~60 s).** Run scenario `01-ts-microservice-greenfield` with `--dry-run`. Exercises the full runner plumbing (worktree setup, forge init, state.json parsing, scoring math, JSONL write, leaderboard render) without triggering the full pipeline. This is the "does the harness itself work" gate.
3. **Full suite (slow, ~30 min wall-clock budget with parallel execution).** All 10 scenarios run in parallel batches of 3. Fails the job if composite drops >3 points vs master baseline, if any scenario times out, if any `must_not_touch` path is modified, or if any scenario's verdict is worse than `required_verdict`.

The harness is self-validating: a deliberately-broken scenario (`expected.yaml` with an unknown `mode:` value) in a throwaway branch must fail collection. This is documented in `tests/evals/pipeline/README.md` as a "sanity check" the maintainer can run when adjusting the runner. No local execution required.

Unit coverage for `scoring.py`, `baseline.py`, and `schema.py` lives in `tests/evals/pipeline/runner/tests/` and runs under the existing `unit` tier — these are pure-Python functions and execute in milliseconds alongside the other unit tests.

---

## 9. Rollout

Single-PR rollout, merged in this order within the PR:

1. **Commit 1 — Scaffolding.** Runner skeleton, schema, three scenarios (01, 04, 08 — the cheapest), README, config keys, state-schema bump, `EVAL-*` registry entry. No CI yet.
2. **Commit 2 — Runner pass.** Executor, scoring, baseline-diff, report modules. Unit tests under `tests/evals/pipeline/runner/tests/`. CI workflow added but in `workflow_dispatch`-only mode so it can be triggered manually before enforcement.
3. **Commit 3 — Scenarios 02, 03, 05, 06, 07, 09, 10.** Seven remaining scenarios with fixtures. Leaderboard regenerated.
4. **Commit 4 — Orchestrator `--eval-mode` flag.** Edit to `agents/fg-100-orchestrator.md`. First commit that can regress live runs; kept isolated for easy revert.
5. **Commit 5 — Enforcement.** Flip `.github/workflows/evals.yml` to run on every PR and `master` push with the 3-point regression gate active. Commit the first `master` baseline artifact.

Merge order rationale: every commit is independently testable, and the PR can be trimmed back to commits 1-3 if commit 4 or 5 exposes a problem. Commit 5 is the point of no return for CI gating; if the baseline turns out to be unstable, it is reverted in isolation without losing the harness.

Post-merge: Phase 02 begins immediately and uses this harness to prove non-regression.

---

## 10. Risks & Open Questions

### Risks

- **R1 — LLM non-determinism blows past 3-point tolerance.** The tolerance was chosen by engineering judgment, not measurement. Mitigation: commits 2-3 ship the harness in dispatch-only mode; run it 5× against `master` to measure actual variance before enabling enforcement in commit 5. If variance exceeds 3 points, raise `regression_tolerance` or move to multi-seed median scoring before gating.
- **R2 — Scenario fixtures drift from upstream ecosystems.** Spring Boot 2→3 is a moving target; a fixture frozen today may become trivial or impossible in 6 months. Mitigation: pin every fixture to specific versions in its `prompt.md`, and add a quarterly "scenario refresh" issue to the backlog (out of scope for Phase 01 delivery).
- **R3 — CI wall-clock budget pressure.** 10 scenarios × 10 minutes = 100 compute-minutes; parallelism of 3 yields ~35 real minutes. GitHub free-tier runners cap at 6 hours, so we fit, but the harness will eat a meaningful fraction of the CI bill. Mitigation: `evals.enabled: false` is the emergency kill-switch; scenarios are tagged so a future `--tier=smoke` flag can run only 01/04/08 for draft PRs.
- **R4 — `--eval-mode` flag leaks into production invocations.** Silently disabling Linear/Slack/AskUserQuestion is dangerous if a user invokes it. Mitigation: orchestrator refuses `--eval-mode` unless env var `FORGE_EVAL=1` is also set (the CI workflow sets this); standalone CLI use errors out.

### Open questions

- **Q1 — Where does the `master` baseline artifact live?** Options: GitHub Actions artifacts (cheapest, 90-day retention), committed JSON in `tests/evals/pipeline/baselines/` (versioned with code, noisy diffs), or an S3 bucket. Recommendation: Actions artifacts for Phase 01; revisit if retention becomes a problem.
- **Q2 — Should the leaderboard include a "runs since last regression" counter?** Cheap signal, valuable for morale, but adds state to the markdown that must be parsed+re-written rather than regenerated. Deferred to Phase 02.
- **Q3 — Who authors scenarios 07 (ML-ops) and 09 (Swift concurrency)?** These require domain expertise outside the core maintainer set. Recommendation: ship stub scenarios that exercise the harness in commit 3, then replace with production-quality prompts in a follow-up PR. Stubs are explicitly marked `notes: "STUB — replace before Phase 03"`.

---

## 11. Success Criteria

All must be true before Phase 01 is marked complete:

- **SC1** — Full harness completes in ≤15 minutes wall-clock on the GitHub Actions `ubuntu-latest` runner, measured as the p90 of 10 consecutive `master` runs after enforcement is enabled.
- **SC2** — All 10 scenarios produce `composite >= 70` on `master` across 5 consecutive runs. Any scenario stuck below 70 is either fixed or replaced before enforcement is enabled.
- **SC3** — A deliberately regression-inducing PR (e.g. a patch that forces the orchestrator to skip the VERIFY stage) fails CI with a clear `EVAL-REGRESSION` finding. Validated manually before merge.
- **SC4** — `tests/evals/pipeline/leaderboard.md` is auto-generated on every `master` push and lists all 10 scenarios with composite, pipeline score, tokens, elapsed, and overlap columns.
- **SC5** — `python -m tests.evals.pipeline.runner --collect-only` runs in <5 seconds and catches every malformed `expected.yaml` in a test-broken scenario.
- **SC6** — Zero touches to `tests/evals/agents/` (verified by `git diff` scope check in the PR review).

---

## 12. References

- Audit finding W1 (internal, forge A+ roadmap document)
- Anthropic skill-creator eval harness — https://perevillega.com/posts/2026-04-01-claude-code-skills-2-what-changed-what-works-what-to-watch-out-for/
- OpenHands Index — https://openhands.dev/blog/openhands-index
- Princeton HAL harness — https://github.com/princeton-pli/hal-harness
- SWE-CI paper — https://arxiv.org/html/2603.03823v1
- Existing agent-level eval README — `/Users/denissajnar/IdeaProjects/forge/tests/evals/README.md`
- `fg-700-retrospective` — `/Users/denissajnar/IdeaProjects/forge/agents/fg-700-retrospective.md`
- Scoring reference — `/Users/denissajnar/IdeaProjects/forge/shared/scoring.md`
- State schema — `/Users/denissajnar/IdeaProjects/forge/shared/state-schema.md`
- PREFLIGHT constraints — `/Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md`
- Mode overlays — `/Users/denissajnar/IdeaProjects/forge/shared/modes/`
