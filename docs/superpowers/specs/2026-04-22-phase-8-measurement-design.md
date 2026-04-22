# Phase 8: Measurement — Design

## Goal

Turn "state of the art" from an unverifiable claim into a weekly, trended, cross-platform **number**. Extend the existing `tests/evals/pipeline/` harness with a curated benchmark corpus of 10–20 of the user's own real past features, a scheduled multi-OS/multi-model runner, a committed-to-repo ASCII scorecard, and a frozen baseline with a hard regression gate.

## Problem Statement

The phrase "state of the art" appears in roadmap language, release notes, and the README, but no artifact in the repository quantifies it. The existing eval harness (`tests/evals/pipeline/runner/`, per `tests/evals/pipeline/README.md:61–86`) is **explicitly gated off** in CI — both `full-suite` and `pr-suite` jobs in `.github/workflows/evals.yml:77` / `:126` carry `if: ${{ false }}` because GitHub-hosted runners do not ship the `claude` CLI that `executor.py:72-77` shells into. Even when un-gated it runs 10 synthetic scenarios (`scenarios/01-ts-microservice-greenfield` through `scenarios/10-php-security-fix`) plus one A/B scenario — none of which originate from a user project. Synthetic scenarios validate plumbing; they cannot substantiate a solve-rate claim.

Meanwhile the peer bar is public and numeric: **SWE-bench Verified** reports single-agent solve rates in the 50–70% range (Anthropic, OpenAI, and DeepMind submissions); **OpenHands** publishes 50%+ on its leaderboard; **SWE-agent** lists ~45% on its canonical benchmark page. Those are comparable numbers. Forge has none. As the user framed it: *"until a number exists, 'state of the art' is aspiration, not status."*

Phase 8 produces the number. It does **not** claim to beat SWE-bench (that is Phase 8.5, a stretch goal). It produces a repeatable, PII-scrubbed, user-owned benchmark that lives in-repo, runs weekly, and fails CI when the forge regresses.

## Non-Goals

- **No public hosting.** `SCORECARD.md` lives in the repo. No separate site, no Pages deploy, no dashboard.
- **No peer comparison in v1.** A placeholder row exists in the scorecard; cells are filled manually when the user chooses to update them. No automated scraping of SWE-bench/OpenHands/SWE-agent.
- **No per-commit benchmark.** Weekly schedule only. Per-commit is cost-prohibitive (≥10 corpus entries × up to 90 min × 6-way matrix).
- **No new model introduction.** The matrix tests whichever models `shared/model-routing.md` currently configures.
- **No historical replay.** The corpus is rerun fresh each week against the current forge tree. We do not snapshot past forge versions.
- **No auto-scraping of the user's private data.** Curation is interactive and user-assisted.
- **No migration shims from the existing pipeline harness.** Phase 8 extends `tests/evals/pipeline/runner/` by importing its modules; it does not duplicate or fork them. Per the project's no-backcompat stance (`docs/adr/0008-no-backwards-compatibility-stance.md`) shared code is edited in place if refactoring helps.

## Approach

**Three alternatives considered.**

**A. Extend the existing `tests/evals/pipeline/` harness in place** — add a parallel `tests/evals/benchmark/` tree that imports `runner/executor.py`, `runner/schema.py`, and `runner/scoring.py` from pipeline, introduces its own `corpus/` + `results/` + scorecard renderer, and wires a separate CI workflow. *Recommended.*

Defence: the existing harness already solves ~70% of what Phase 8 needs — subprocess isolation, starter-tarball extraction, `state.json` parsing, must-not-touch globs, timeout handling, JSONL result writing. Re-using those modules is ~400 LOC cheaper than forking. The pipeline harness's **frozen scenarios** remain the fast-smoke tier (collect-only + dry-run on every PR); the benchmark is the **slow truth tier** (weekly cron). Two distinct purposes, one shared executor.

**B. Dedicated benchmark repository** (`quantumbitcz/forge-bench`). *Rejected.* Forge is a personal tool (per user memory). A second repo multiplies CI secrets, `.github/CODEOWNERS`, release coordination, and release-branch back-ports. The corpus being in-repo also means `git blame` on `corpus/<entry>/requirement.md` traces back to the real commit where forge was invoked on that request — an audit trail that survives as long as the repo.

**C. Third-party service (e.g. Weights & Biases, Braintrust).** *Rejected.* Introduces SaaS coupling, account provisioning, per-run spend outside `forge-config.md`'s cost ceiling, and a new secret class. Personal-tool inertia wins: a JSONL file + a Markdown renderer + a GitHub Actions cron is sufficient.

## Components

### 1. Benchmark corpus + curation script

**Location:** `tests/evals/benchmark/corpus/<YYYY-MM-DD>-<slug>/`

Each corpus entry is a directory with exactly six artefacts (schema in §Data Model):

```
tests/evals/benchmark/corpus/
  2025-11-14-session-handoff-mcp/
    requirement.md
    acceptance-criteria.yaml
    seed-project.tar.gz
    expected-deliverables.yaml
    metadata.yaml
  2025-12-03-bun-build-to-python/
    ...
```

**Selection criteria:**
- Drawn from the user's own past runs via `.forge/run-history.db` (schema: `shared/run-history/migrations/001-initial.sql`).
- Target distribution: ~40% S (<4h human), ~40% M (4h–1d), ~20% L (1d–3d). Minimum 3 distinct languages and 3 distinct frameworks across the corpus.
- Only runs where `runs.verdict IN ('PASS', 'CONCERNS')` AND `runs.score >= 70` are eligible — the premise is "features we have shipped," so a failed historical run is not a valid corpus entry.
- User-assisted approval is mandatory. The script does not scrape; it presents candidates and asks.

**Support scripts in `tests/evals/benchmark/`:**

- `curate.py` — corpus curation (Critical #1 below).
- `runner.py` — benchmark runner (Component 2).
- `scoring.py` — `solved` predicate.
- `render_scorecard.py` — trend aggregation → `SCORECARD.md`.
- `refresh_baseline.py` — baseline freeze/refresh (Component 5).
- `write_forge_model_overrides.py` — writes matrix-cell `model_routing.overrides` fragment into the ephemeral project tempdir before `/forge-run`, per §Component 3 "Model selection wiring".

**Curation script:** `tests/evals/benchmark/curate.py` (Python 3.10+, stdlib only + `pyyaml`).

Flow:
1. Query `.forge/run-history.db` for candidate runs (eligibility SQL in §Data Flow).
2. For each candidate, print a summary: requirement preview (first 200 chars), language, framework, score, verdict, branch, PR URL.
3. Prompt: *"Include in corpus? [y/N/s(skip to next)/q(uit)]"*. If `y`, prompt for a slug, a complexity bucket (S/M/L), and comma-separated domain tags.
4. For each accepted candidate:
   - Resolve the commit SHA forge was run against (from `runs.config_snapshot` or `runs.branch_name` + git reflog).
   - Create a shallow tarball of that SHA into `seed-project.tar.gz` via `git archive --format=tar.gz`. Exclude `.forge/`, `node_modules/`, `__pycache__/`, `.venv/`, `target/`, `dist/`, `build/`, `*.min.js`, `*.map`.
   - Strip `requirement.md` of PII before write (patterns enumerated in §Data Model).
   - Seed `acceptance-criteria.yaml` from Phase 7's `.forge/specs/index.json` (`specs.<slug>.ac_list[]`) if the run produced a spec; else leave an empty `ac_list: []` for the user to hand-write.
   - Write `expected-deliverables.yaml` from the run's touched files + state fingerprints (never the diff contents — only file paths + endpoint names + test counts).
   - Write `metadata.yaml` with complexity, domains, language, framework, source_run_id (for traceability, not replay).

**Contract:** Curation script never writes outside `tests/evals/benchmark/corpus/`. Exits non-zero on tarball-size > 50 MB, missing SHA, or PII regex tripwire that the user did not acknowledge.

### 2. Benchmark runner harness

**Location:** `tests/evals/benchmark/runner.py` (Python module entry: `python -m tests.evals.benchmark.runner`).

Imports from `tests.evals.pipeline.runner`:
- `executor.execute_scenario` — reused verbatim for subprocess + starter extraction
- `schema.RawRunMetrics` — extended into `BenchmarkResult` (see §Data Model)
- Custom scoring logic in `tests/evals/benchmark/scoring.py` (the `solved` predicate)

**Per-entry flow:**
1. Read `metadata.yaml`, `acceptance-criteria.yaml`, `expected-deliverables.yaml`.
2. Extract `seed-project.tar.gz` to a tempdir (reuses `executor._extract_starter`).
3. Symlink forge plugin into `.claude/plugins/forge` (reuses `executor._symlink_plugin`).
4. Invoke `claude code --non-interactive /forge-init` then `/forge-run --eval-mode <entry-id>` with the requirement text.
   - **Live-session constraint:** The current `executor.py:72` requires the `claude` CLI. The existing `tests/evals/pipeline/README.md:71–83` already documents the blocker and the unlock path (install Claude Code on the runner, provision `CLAUDE_CODE_OAUTH_TOKEN`). Phase 8 inherits that dependency and does not invent a synthetic mode. The workflow below includes the same install step. If the install fails, the benchmark job fails (as it should — there is nothing to measure).
5. Parse `.forge/state.json` post-run, read `.forge/runs/<run_id>/findings/*.jsonl`, and apply `solved` predicate.
6. Emit one `BenchmarkResult` to `tests/evals/benchmark/results/<YYYY-MM-DD>/<entry-id>.json`.

**"Solved" predicate:**

A corpus entry is **solved** when all three hold:
1. `pipeline_verdict ∈ {SHIP, CONCERNS}` — forge reached a shippable state.
2. `partial_ac_pct >= 0.9` — at least 90% of acceptance criteria passed per Phase 7's fg-540 intent verifier (`INTENT-MISSED` or `INTENT-CONTRACT-VIOLATION` in findings counts as failed AC; `INTENT-UNVERIFIABLE` counts as failed for solve-rate math but is flagged separately in the scorecard).
3. `critical_findings == 0` — no unresolved CRITICAL findings in the final review batch.

**Defence of the 0.9 threshold:** Hard 1.0 punishes corpus entries whose `acceptance-criteria.yaml` over-specifies edge cases the original human run also skipped — the corpus is human-authored and imperfect. A 0.5–0.8 window admits partial-work-shipped runs that would not pass human review. 0.9 preserves the signal: most ACs succeeded, no criticals lingering, verdict at least CONCERNS.

**Defence of counting CONCERNS as solved.** The `solved` predicate treats `pipeline_verdict ∈ {SHIP, CONCERNS}` as success because CONCERNS reflects WARNING-level quality issues (addressable, non-blocking) rather than fundamental intent failures (CRITICAL). This is intentionally a **weaker bar** than Phase 7's SHIP gate (which requires `verified_pct >= 100%` of ACs and zero intent-missed findings). The benchmark and the SHIP gate answer different questions:

- Benchmark `solved`: *"Did forge build something that works?"* — the industry-comparable metric, aligned with SWE-bench Verified's "did the patch resolve the issue" framing.
- Phase 7 SHIP gate: *"Did forge build exactly what the user asked for?"* — the in-pipeline release bar, stricter.

Both signals are tracked independently. `SCORECARD.md` reports **both** `solve_rate` (the benchmark number) and `ship_rate` (count of entries where `pipeline_verdict == SHIP` ∧ `partial_ac_pct == 1.0` ∧ `critical_findings == 0`) so a divergence between the two — e.g. the benchmark trending up while ship rate flattens — is immediately visible. A widening gap signals that forge is solving but over-permissively shipping, which is itself a useful diagnostic.

**Timeouts (per complexity bucket):**

| Complexity | Timeout | Rationale |
|---|---|---|
| S | 900 s (15 min) | matches existing pipeline harness `scenario_timeout_seconds` |
| M | 2700 s (45 min) | covers the 2700-s total budget the pipeline harness uses for ten scenarios |
| L | 5400 s (90 min) | absorbs migrations, multi-service refactors |

Exceeding the bucket timeout sets `timeout: true` on the result; the entry is not counted as solved.

**Parallelism:** `--parallel N` defaults to 4. Implementation: `concurrent.futures.ProcessPoolExecutor` around `execute_scenario`. Each child gets a **distinct tempdir**, a **distinct forge worktree**, and a **distinct `.forge/runs/<id>`** — no shared mutable state. Matrix workflow (§Component 3) pins `--parallel 1` per matrix cell because the matrix itself is the parallelism axis.

**Docker-optional entries:** An entry with `metadata.yaml: requires_docker: true` is skipped on runners without Docker. The runner emits a WARNING finding `BENCH-DOCKER-SKIPPED` and excludes the entry from solve-rate denominator for that run — the entry simply does not contribute to the week's numbers on that OS. Cross-platform note: `windows-latest` runners do **not** ship Docker Desktop for licensing reasons,[^docker-license] so Docker-required entries always skip on Windows (documented in §Error Handling).

[^docker-license]: Docker Desktop licensing requires a paid Docker Business subscription for companies with >$10M annual revenue or >250 employees. Forge is a personal tool so the licensing constraint is N/A for the repo itself. GitHub-hosted `ubuntu-latest` runners use Docker Engine directly on Linux (no Desktop, no licensing issue); `macos-latest` runners ship Docker Desktop under GitHub's enterprise licence; `windows-latest` runners do not ship Docker Desktop by default.

### 3. Weekly CI workflow + cross-OS matrix

**File:** `.github/workflows/benchmark.yml`

Triggers:
```yaml
on:
  schedule:
    - cron: '0 6 * * 1'   # Monday 06:00 UTC
  workflow_dispatch:
    inputs:
      corpus_filter:
        description: 'Glob (optional) to restrict corpus entries'
        required: false
        default: ''
```

Matrix (6 cells):
```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    claude-model:
      - claude-sonnet-4-6
      - claude-opus-4-7
```

**Model matrix rationale:** Sonnet 4.6 is the user's workhorse default; Opus 4.7 validates whether SotA claims hold on the premium tier. **Haiku 4.5 is intentionally excluded** from the default matrix — the benchmark is a quality measurement, and tier-1-fast routing is only used for specific delegated agents (reviewers, scaffolders) inside the pipeline. Adding a haiku row would tell us "does the cheap model also do the work?" which answers a different question. The user is on Claude Pro; cost is not the gate here, quality signal is. A `workflow_dispatch` input `--extra-models` may include haiku for spot checks. *(Open question: see §Open Questions — revisit if haiku becomes the tier-2 default.)*

**Matrix model IDs** are sourced from user memory: `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`.

**Model selection wiring.** `shared/model-routing.md:13` fixes the Agent tool's `model` parameter to the aliases `haiku | sonnet | opus` — it does **not** accept full model IDs like `claude-sonnet-4-6`. A full-ID env var (`ANTHROPIC_MODEL`) is not read anywhere in `tests/evals/pipeline/runner/executor.py`. Env-only propagation is therefore insufficient; without an explicit wiring step every matrix cell would degenerate to whatever the runner's default-routed alias resolves to, collapsing the 3 OS × 2 model matrix to 3 OS × 1 routing.

The concrete mechanism Phase 8 uses: before each matrix cell invokes `runner.py`, a helper script writes a `forge.local.md` fragment into the **ephemeral tempdir project root** (not the forge repo) containing:

```yaml
model_routing:
  overrides:
    fast:     claude-{matrix.claude-model}
    standard: claude-{matrix.claude-model}
    premium:  claude-{matrix.claude-model}
```

All three tiers are pinned to the same full ID so the cell exercises exactly that model end-to-end (the alias → ID resolution happens inside forge's own dispatch layer, which already supports `model_routing.overrides.<tier>` as a full-ID override). Any agent that would otherwise haiku-route still routes to the matrix cell's model. This is a deliberate quality-measurement choice — the benchmark asks "what can model X solve?", not "what can the default tier-mix solve?".

Patching `shared/model-routing.md` tier aliases at runner-entry time was considered and rejected: it mutates a repo-tracked contract file, risks contaminating other concurrent uses, and creates a cleanup obligation on signal failure.

Helper: `tests/evals/benchmark/write_forge_model_overrides.py` (Python, stdlib only). Called by `runner.py` per entry before `/forge-run` is invoked. Signature: `write_overrides(project_root: Path, model_id: str) -> Path` returning the written path for logging. Contract: writes into the ephemeral tempdir only; refuses if `project_root` equals or is an ancestor of the forge repo root.

**Per-cell job:**
1. Check out forge at `${{ github.sha }}`.
2. Install `uv` (cross-platform, fast) and resolve Python 3.10+.
3. Install deps: `uv pip install -r tests/evals/benchmark/requirements.txt` (inherits the pipeline runner's deps plus `pyyaml`, `jsonschema`).
4. **Install the `claude` CLI.** Step is identical to the one outlined in `tests/evals/pipeline/README.md:77–82`. Reuses `secrets.CLAUDE_CODE_OAUTH_TOKEN`.
5. Run the benchmark:
   ```bash
   python -m tests.evals.benchmark.runner \
     --corpus-root tests/evals/benchmark/corpus \
     --results-root tests/evals/benchmark/results \
     --os "${{ matrix.os }}" --model "${{ matrix.claude-model }}" \
     --parallel 1
   ```
6. Upload per-cell artifacts: `benchmark-${{ matrix.os }}-${{ matrix.claude-model }}-${{ github.run_id }}`.

**Aggregation job** (`needs: [benchmark-matrix]`, `runs-on: ubuntu-latest`):
1. Download all six cells' artifacts.
2. Append one merged line to `tests/evals/benchmark/trends.jsonl` (schema in §Data Model).
3. Run `python -m tests.evals.benchmark.render_scorecard` to rewrite `SCORECARD.md`.
4. Run the regression gate: compare current week's solve-rate-per-bucket against `baseline.json`. Fail exit-1 if any bucket drops >=10pp.
5. Conditional bot commit (see §Concurrency).

**Workflow cap:** `timeout-minutes: 180` (3h) per matrix cell — pessimistic bound for 20 L-bucket entries sequentially @ 90 min each. In practice most cells finish in 45–60 min.

### 4. Trend aggregation + ASCII scorecard

**Location:** `SCORECARD.md` at repo root (new file). Rewritten by `tests/evals/benchmark/render_scorecard.py`.

**Sections (exact order enforced by renderer):**

1. **Header** — generated-on timestamp, commit SHA, schema version.
2. **This week** — a table with columns: overall, by complexity (S/M/L), by language (top 5), by model tier (sonnet-4-6, opus-4-7).
3. **Last 12 weeks** — per-bucket sparklines rendered in the 8-char Unicode Block Elements range `▁▂▃▄▅▆▇█`. Example: `solve rate S: ▅▆▆▇▆▇█▇▇█▇█ (62% → 78%)`.
4. **Regressions** — table: entry slug | last-week status | this-week status | result JSON hyperlink. Only entries that flipped from `solved=true` to `solved=false` between consecutive weekly runs appear here.
5. **Cost-per-solve** — median USD across solved runs per model tier, rendered as sparkline over last 12 weeks. Reads from Phase 6's `state.cost.estimated_cost_usd` propagated through `BenchmarkResult.cost_usd`.
6. **vs peers** — a placeholder markdown table. First column has forge's current solve rate. Remaining columns hold rows for SWE-bench Verified, OpenHands, SWE-agent; cells are unfilled (`—`) with a link to each project's leaderboard. Renderer never fabricates peer numbers; manual update by the user is the defined path until Phase 8.5.
7. **Appendix** — per-entry raw solve booleans in a long table.

**ASCII/Unicode constraint:** all sections render in plain text. Unicode block elements `▁▂▃▄▅▆▇█` are the *only* non-ASCII characters. Tested to render in: iTerm2, macOS Terminal, Windows Terminal, Alacritty, the GitHub web UI markdown view. *(Open question flagged in §Open Questions re: screen readers.)*

**Sparkline encoding:** one block per weekly data point, 12 data points (oldest→newest). Gap weeks (no CI run) render as the zero-height block `▁`. Empty history renders as `▁▁▁▁▁▁▁▁▁▁▁▁`.

**Committing:** the aggregation job runs `git diff --quiet SCORECARD.md`. If no diff, skip commit. If diff, commit via `github-actions[bot]` with message `chore(bench): weekly scorecard <YYYY-MM-DD>`.

### 5. Baseline freeze + regression gate

**Location:** `tests/evals/benchmark/baseline.json`.

**Schema:** see §Data Model.

**Freeze:** First `benchmark.yml` run computes per-bucket solve rates, writes them to `baseline.json`, and commits. Subsequent runs compare current-week rates to the frozen baseline.

**Gate math:**
- For each complexity bucket `b ∈ {S, M, L}` and each model tier `m`:
  - `delta = current[b][m] - baseline[b][m]` (both in percentage points).
  - If `delta <= -10`, emit `BENCH-REGRESSION` CRITICAL finding and fail CI.
  - If `-10 < delta <= -5`, emit `BENCH-REGRESSION` WARNING (CI still passes).
  - If `delta > -5`, no finding.

**Why 10pp:** Weekly solve rates on ~15 corpus entries × 2 models have a natural variance of ~3–5pp even when nothing changed (model API drift, Anthropic-side routing, corpus entry flakiness). A 10pp floor separates noise from real regressions.

**Refresh:** `tests/evals/benchmark/refresh_baseline.py` rewrites `baseline.json` from the most recent `trends.jsonl` entry. Requires `--confirm` flag. Never runs automatically. A post-improvement workflow:

```bash
python -m tests.evals.benchmark.refresh_baseline --confirm
git add tests/evals/benchmark/baseline.json
git commit -m "bench: refresh baseline after <improvement>"
```

### 6. Cross-phase integration

- **Phase 1 (`hooks/_py/failure_log.py` + `.forge/.hook-failures.jsonl`):** the aggregation job reads the per-cell `.forge/.hook-failures.jsonl` artefacts and surfaces a `Hook failures this week: N` row in the scorecard header. Corpus entries where any hook failed during the run get a superscript marker in the appendix.
- **Phase 4 (learnings dispatch loop):** when a corpus entry goes `solved → failed` twice consecutively, emit a new learning type `benchmark.regression` with `domain = metadata.domains[0]` and `content = "Entry <slug> regressed on week <N>"`. Phase 4's selector service picks this up at PREFLIGHT; the relevant implementer / reviewer dispatch gets a surfaced warning. Stored in `learnings` table (schema: `shared/run-history/migrations/001-initial.sql:learnings`) with `type='benchmark.regression'`.

  **Cross-phase coordination note.** A new learning type `benchmark.regression` will be registered in Phase 4's learning-type enum. Phase 4's plan must accept this addition to its type-allowlist; this spec serves as the coordination point. The type is additive only — no existing Phase 4 learning types are renamed or removed, so no schema migration is needed. Phase 4 implementation should validate the type string against a registry that already includes `benchmark.regression` before Phase 8 ships.
- **Phase 6 (cost governance):** cost-per-solve reads `state.cost.estimated_cost_usd` directly. The aggregation job also enforces `benchmark.max_weekly_cost_usd` (default **$200**, configurable in `forge-config.md`). Spec uses `pct_consumed` (per Phase 6 field-name contract), not `pct_remaining`. When the week's accumulated estimated cost exceeds the ceiling mid-matrix, the aggregation job aborts remaining cells with a `BENCH-COST-CEILING` WARNING.

  **Ceiling derivation (empirical, not heuristic).** The original `$0.40`/run figure was an unsourced guess. The real per-run median is computed from `.forge/run-history.db` (schema: `shared/run-history/migrations/001-initial.sql`, column `runs.estimated_cost_usd REAL` exists at line 24) via:

  ```sql
  SELECT estimated_cost_usd
  FROM runs
  WHERE verdict IN ('PASS', 'CONCERNS')
    AND estimated_cost_usd IS NOT NULL
    AND started_at >= date('now', '-90 days')
  ORDER BY estimated_cost_usd
  LIMIT 1
  OFFSET (SELECT COUNT(*)/2
          FROM runs
          WHERE verdict IN ('PASS', 'CONCERNS')
            AND estimated_cost_usd IS NOT NULL
            AND started_at >= date('now', '-90 days'));
  ```

  Ceiling formula: `max_weekly_cost_usd = ceil(median × 15 × 6 × 1.5)` where 15 is the expected corpus size, 6 the matrix cell count, and 1.5 a buffer for Opus-tier L-bucket runs (Opus ≈ 3× standard cost, but most cells are Sonnet). Phase 6 uses $25/run as an example ceiling; if the user's real-world median is closer to that, the weekly ceiling lands in the $200–$400 range, not $36.

  **Commit-time protocol.** Spec author runs the query immediately before merging Phase 8 and pastes the computed median into this section. As of spec authoring, `.forge/run-history.db` on the user's machine does not yet contain 90 days of populated `estimated_cost_usd` data (the column was added in Phase 6 wiring and needs real runs to fill). The ceiling is therefore **conservatively set to $200** for initial release; it will be refreshed after 90 days of post-Phase-6 benchmark runs. A CHANGELOG entry and `forge-config.md` update records the refresh; no migration shim needed (personal tool, no backcompat).
- **Phase 7 (intent assurance, fg-540):** AC counting delegates to `fg-540-intent-verifier`. `corpus/<entry>/acceptance-criteria.yaml` format mirrors `.forge/specs/index.json` `ac_list` schema. When the run invokes forge, Phase 7's `build_intent_verifier_context` resolves the corpus AC list as the active spec (via an eval-mode injection path: the runner writes `.forge/specs/index.json` with the corpus ACs prior to `/forge-run`). Post-run, `partial_ac_pct` is computed from `state.intent_verification_results[]`.

  **Injection contract (canonical shape — cross-reference Phase 7 spec's §Data Model).** Before `/forge-run` is invoked in a corpus entry tempdir, `runner.py` writes `.forge/specs/index.json` with exactly:

  ```json
  {
    "version": 1,
    "active_spec_id": "<entry-id>",
    "specs": {
      "<entry-id>": {
        "requirement": "<requirement.md contents>",
        "acceptance_criteria": [
          {"id": "AC-B001", "text": "<AC text>", "verifier_hint": "http"},
          {"id": "AC-B002", "text": "<AC text>", "verifier_hint": "cli"}
        ],
        "source": "benchmark-injected"
      }
    }
  }
  ```

  **ID namespace to prevent collision.** Corpus-injected ACs use the `AC-B001..AC-B999` namespace (B prefix for benchmark-injected). Forge-generated ACs (produced by fg-540 or the shaper during a run) use the unprefixed `AC-001..` numeric namespace. The two namespaces never overlap, so a forge-run that adds its own ACs mid-pipeline does not overwrite the benchmark seed.

  **PREFLIGHT contract.** The orchestrator must preserve entries with `source: "benchmark-injected"` and not overwrite them on stale-spec refresh. This is a compatible extension to Phase 7's existing spec-refresh logic — any entry with a `source` field must be passed through untouched. A cross-phase note is dropped into Phase 7's spec (`2026-04-22-phase-7-intent-assurance-design.md`) as a prose coordination point; Phase 7 does not need re-review because the extension is additive (new field, documented default behavior).

## Data Model

### Corpus entry

**`requirement.md`** — original user request. Markdown. PII-scrubbed. Preamble header `# Requirement` required.

**`acceptance-criteria.yaml`**:
```yaml
# Schema version
version: 1
ac_list:
  - id: AC-001
    description: "Handler returns 200 with JSON body on valid POST /users"
    verifiable_via: http   # one of: http, cli, file, custom
    probe: "curl -fsS http://localhost:8080/users -d '{}' | jq -e '.id'"
  - id: AC-002
    description: "Duplicate email returns 409"
    verifiable_via: http
    probe: "..."
```

**`seed-project.tar.gz`** — gzipped tarball of the source commit. Must unpack to a directory that contains a `.git` folder (so forge can branch from it). Size cap: 50 MB.

**`expected-deliverables.yaml`**:
```yaml
version: 1
files_touched:
  expected_any_of:       # at least one must be modified
    - "src/routes/users.ts"
    - "src/handlers/user.ts"
  must_not_touch:        # glob patterns; modifying = hard fail
    - ".github/**"
    - "package-lock.json"
endpoints_expected:      # optional; verified via http probe
  - "POST /users"
  - "GET /users/:id"
tests_expected_min: 3    # minimum count of new/modified tests
```

**`metadata.yaml`**:
```yaml
version: 1
complexity: M              # S | M | L
domain: [api, persistence]
language: typescript
framework: express
source_run_id: "run-2025-11-14-a7f3"   # traceability only; not replayed
requires_docker: false                 # REQUIRED; no default
os_compat: [ubuntu-latest, macos-latest, windows-latest]  # subset of matrix OSes
notes: "Original PR: https://github.com/denissajnar/myapp/pull/412"
```

**`requires_docker` is mandatory.** The field has no default — every corpus entry must declare `true` or `false`. `curate.py` auto-detects the value by probing the seed-project tarball for `docker-compose.yml`, `Dockerfile`, `compose.yaml`, or a `docker:` top-level key in any `package.json`/`pyproject.toml` service manifest; it then asks the user to confirm (`"Detected Docker dependency: [Y/n]"`). Confirmation is mandatory before write.

`runner.py` fails fast with a clear error — `BENCH-METADATA-MISSING-DOCKER-FLAG` CRITICAL — if an entry's `metadata.yaml` has `requires_docker` unset or missing on a non-Docker OS (primarily Windows). On Linux/macOS runners (which always have Docker Engine / Docker Desktop available on GitHub-hosted runners), the missing flag still fails validation at schema-check time so no entry silently works on some OSes and fails on others.

**`os_compat`** is a list-valued field defaulting to `[ubuntu-latest, macos-latest, windows-latest]` (all three). Entries that need Docker on Windows, heavy native deps (`node-gyp` toolchains, `pyodbc`), or Linux-only filesystems narrow this list. `runner.py` filters the matrix by `os_compat ∩ matrix_os`; an entry with `os_compat: [ubuntu-latest, macos-latest]` simply does not run on Windows cells and is excluded from Windows denominators. This resolves AC-820's "Python-only subset" ambiguity: the subset is explicit per-entry, not implicit by language.

**PII scrub patterns** (applied to `requirement.md` + `expected-deliverables.yaml` + `metadata.yaml.notes`):

Reuses `shared/data-classification.md` §Detection Patterns where applicable. Additional benchmark-specific patterns:

| Pattern | Regex | Replacement |
|---|---|---|
| Absolute home path | `/Users/[^/\s]+` or `/home/[^/\s]+` or `C:\\Users\\[^\\]+` | `<redacted-home>` |
| Internal hostname | `\b[\w-]+\.(internal\|prod\|corp\|local)\b` | `<internal-host>` |
| Private IPv4 | `\b(10\.\d+\.\d+\.\d+\|172\.(1[6-9]\|2\d\|3[01])\.\d+\.\d+\|192\.168\.\d+\.\d+)\b` | `<private-ip>` |
| Email (non-public) | reused from `data-classification.md` SEC-PII | `<redacted-email>` (user confirms per match) |
| SSH fingerprint | `SHA256:[A-Za-z0-9+/]{43}=?` | `<ssh-fp>` |
| API key/token | reused from `data-classification.md` SEC-SECRET | `<redacted-secret>` (blocks commit unless user confirms per match) |

Curation script prompts user on every match that is not auto-replaceable (emails, secrets). Auto-replaceable patterns (paths, hostnames, private IPs) are scrubbed silently with a summary at the end.

### BenchmarkResult JSON (per-entry, per-cell)

**Location:** `tests/evals/benchmark/results/<YYYY-MM-DD>/<entry-id>.<os>.<model>.json`

```json
{
  "schema_version": 1,
  "entry_id": "2025-11-14-session-handoff-mcp",
  "run_date": "2026-04-27",
  "os": "ubuntu-latest",
  "model": "claude-sonnet-4-6",
  "started_at": "2026-04-27T06:03:14Z",
  "ended_at":   "2026-04-27T06:17:41Z",
  "duration_s": 867,
  "solved": true,
  "partial_ac_pct": 1.0,
  "ac_breakdown": {
    "AC-001": "PASS",
    "AC-002": "PASS",
    "AC-003": "UNVERIFIABLE"
  },
  "cost_usd": 0.42,
  "pipeline_verdict": "SHIP",
  "score": 92,
  "convergence_iterations": 2,
  "critical_findings": 0,
  "warning_findings": 3,
  "timeout": false,
  "must_not_touch_violations": [],
  "touched_files_actual": ["src/routes/users.ts", "tests/users.test.ts"],
  "hook_failures_count": 0,
  "error": null
}
```

### Trends JSONL (one line per weekly run)

**Location:** `tests/evals/benchmark/trends.jsonl` (append-only).

**Retention: append-only forever.** At ~1 KB per line × 52 weekly lines/year, a 10-year horizon yields roughly 500 KB. No rotation policy, no truncation, no archival tier. Git handles versioning; `git log -- tests/evals/benchmark/trends.jsonl` is the audit trail. If the file ever exceeds 10 MB (unlikely within 100 years at current rate), re-evaluate.

```json
{
  "schema_version": 1,
  "week_of": "2026-04-27",
  "commit_sha": "abc1234",
  "forge_version": "3.8.0",
  "cells": [
    {
      "os": "ubuntu-latest", "model": "claude-sonnet-4-6",
      "entries_total": 15, "entries_solved": 12, "entries_timeout": 1,
      "entries_docker_skipped": 0,
      "solve_rate_overall": 0.80,
      "solve_rate_by_complexity": {"S": 0.92, "M": 0.80, "L": 0.50},
      "median_cost_per_solve_usd": 0.38,
      "total_cost_usd": 5.47
    }
  ],
  "hook_failures_total": 0,
  "regressions": [
    {"entry_id": "2025-12-03-bun-build-to-python", "last_status": "solved", "this_status": "failed"}
  ]
}
```

### baseline.json

```json
{
  "schema_version": 1,
  "frozen_on": "2026-04-27",
  "frozen_commit_sha": "abc1234",
  "baselines": {
    "claude-sonnet-4-6": {
      "S": 0.90, "M": 0.75, "L": 0.45, "overall": 0.72
    },
    "claude-opus-4-7": {
      "S": 0.95, "M": 0.82, "L": 0.55, "overall": 0.78
    }
  },
  "regression_threshold_pp": 10
}
```

### SCORECARD.md section contract

Every section begins with an `<!-- section:<id> -->` HTML comment so the renderer can re-target sections idempotently. Unknown sections are preserved as-is (tolerates manual annotation).

## Data Flow

```
┌─────────────────────┐         ┌─────────────────────────────┐
│ .forge/run-history  │──(SQL)─▶│ curate.py (interactive Y/N) │
│ (user's real runs)  │         └──────────────┬──────────────┘
└─────────────────────┘                        │
                                               ▼
                                    ┌─────────────────────┐
                                    │ tests/evals/        │
                                    │   benchmark/corpus/ │
                                    └──────────┬──────────┘
                                               │
                    ┌──────────────────────────┴──────────────────────────┐
                    │                                                     │
         ┌──────────▼──────────┐                              ┌───────────▼──────────┐
         │ cron: Mon 06:00 UTC │                              │ workflow_dispatch    │
         └──────────┬──────────┘                              └───────────┬──────────┘
                    │                                                     │
                    └────────────────────┬────────────────────────────────┘
                                         ▼
                          ┌──────────────────────────────┐
                          │ 6-cell matrix (3 OS × 2 model)│
                          │   runner.py per cell         │
                          └──────────────┬───────────────┘
                                         ▼
                          ┌──────────────────────────────┐
                          │ results/<date>/*.json        │
                          │   (artifact-uploaded)        │
                          └──────────────┬───────────────┘
                                         ▼
                          ┌──────────────────────────────┐
                          │ aggregator job:              │
                          │  append trends.jsonl         │
                          │  render SCORECARD.md         │
                          │  compute gate vs baseline    │
                          │  bot-commit if diff          │
                          └──────────────────────────────┘
```

**Eligibility SQL** (curate.py):
```sql
SELECT id, requirement, language, framework, verdict, score,
       started_at, finished_at, branch_name, pr_url, config_snapshot
FROM runs
WHERE verdict IN ('PASS', 'CONCERNS')
  AND score >= 70
  AND started_at >= date('now', '-365 days')
ORDER BY score DESC, started_at DESC
LIMIT 100;
```

## Concurrency & Race

**Matrix parallelism.** 3 OS × 2 models = 6 parallel cells. Each cell runs on a separate GitHub-hosted runner with its own tempdir namespace — no file-system contention possible. The aggregation job `needs:` all 6 cells; it runs only after every cell finishes (or times out).

**Bot commit race.** The aggregator job runs on a scheduled trigger. If a human PR is being merged to `master` at the same time, two mutations converge:

Strategy: the aggregator fetches `origin/master` immediately before the `git push`, rebases any bot-only commits on top, and retries the push once. Second failure → upload `SCORECARD.md` as a workflow artifact and emit `BENCH-COMMIT-RACE` WARNING. The scorecard file is recomputed on the next weekly run anyway, so a skipped commit costs at most one week of freshness.

**Branch-protection stance.** Forge is a personal tool (per user memory); `master` has no branch protection configured for `github-actions[bot]`, so direct bot commits are the current default. If branch protection is ever added (e.g. required-review, required-status-checks) that blocks `github-actions[bot]`, the workflow must switch to a PR-based path:

```bash
gh pr create \
  --fill \
  --base master \
  --head benchmark-scorecard-$(date +%Y-%m-%d) \
  --label "automation,benchmark"
gh pr merge <num> --admin --squash   # or wait for manual review
```

The PR-based path is tracked as Open Question #9 (§Open Questions); it does not ship in v1.

**Concurrency group:**
```yaml
concurrency:
  group: benchmark-${{ github.ref }}
  cancel-in-progress: false  # weekly runs never cancel each other
```

**Parallel corpus execution within a cell.** Not used — `--parallel 1` per cell because the 6-cell matrix already parallelises. Running 4 corpus entries concurrently inside a single runner would contend on Anthropic API rate limits (all using the same token) and muddy cost attribution. Serial per cell.

## Error Handling

| Condition | Severity | Behaviour |
|---|---|---|
| `claude` CLI absent on runner | CRITICAL | Benchmark cell fails-fast; upload stub result with `error: "claude cli not installed"`. Aggregation continues with partial cells (N/6). Scorecard header shows "incomplete: <N>/6 cells ran." |
| Corpus entry tarball corrupt | CRITICAL | Cell aborts the entry only, logs `BENCH-CORPUS-CORRUPT`, continues with remaining entries. Week's results flagged as partial. |
| Docker-required entry on runner without Docker | WARNING | `BENCH-DOCKER-SKIPPED`. Entry excluded from denominator for that cell. |
| Windows runner + Docker-required entry | WARNING | Auto-skip (same finding); expected and silent beyond the first occurrence per run. |
| Anthropic API 429 / 500 | recoverable | Retry 3x with exponential backoff (1s, 4s, 16s). After exhaustion: treat entry as `timeout=true`, `error="api exhausted"`. |
| Per-entry timeout exceeded | non-recoverable | Record `timeout: true`, `solved: false`, continue with next entry. |
| Hook failure during run | recorded | Phase 1 hook-failure logs are uploaded as part of the cell artifact; aggregator counts them into scorecard header. No gate impact. |
| `.forge/state.json` missing post-run | CRITICAL | Record `error="state.json missing"`, `solved=false`, `pipeline_verdict="ERROR"`. Aggregation continues. |
| Cost ceiling tripped mid-matrix | WARNING | Remaining cells aborted; `BENCH-COST-CEILING` emitted; scorecard renders with partial data + explicit "cost-truncated" banner. |
| PII regex trip in curated entry post-commit | CRITICAL | Pre-commit hook (added to repo's `.git/hooks/pre-commit`? no — make it a pytest assertion on corpus validation) blocks the PR. Re-run curate.py. |
| Scorecard commit race lost twice | WARNING | Skip commit this week; artifact upload only. |
| Corpus has <10 entries | WARNING | Emit `BENCH-CORPUS-THIN`; run anyway. Emit every week until corpus is grown. |
| `trends.jsonl` corrupt | CRITICAL | Rename to `.corrupt-<epoch>` and start fresh. Prior sparklines reset to `▁▁▁▁...`. |

## Testing Strategy

**Unit tests** (run on every PR, fast):
- `tests/unit/test_benchmark_solve_predicate.py` — parametrised over `(pipeline_verdict, partial_ac_pct, critical_findings)` tuples. Covers the 0.9 threshold boundary, the verdict=FAIL short-circuit, and the unverifiable-AC counting rule.
- `tests/unit/test_render_scorecard.py` — synthetic `trends.jsonl` inputs → expected `SCORECARD.md`. Covers: empty history, all-solved, all-failed, regressions present, baseline drift >=10pp, cost-truncated banner, 12-week sparkline edge cases, ≤12-week history, >12-week history (only last 12 shown).
- `tests/unit/test_refresh_baseline.py` — requires `--confirm`; round-trips baseline JSON.
- `tests/unit/test_curate_pii_scrub.py` — each PII regex in isolation.
- `tests/unit/test_corpus_schema.py` — `jsonschema` validation of every file in every `corpus/<entry>/` against published schemas in `tests/evals/benchmark/schemas/*.json`.

**Contract tests:**
- `tests/contract/test_benchmark_result_schema.py` — every `BenchmarkResult` written conforms to `tests/evals/benchmark/schemas/result.schema.json`.
- `tests/contract/test_benchmark_trends_schema.py` — `trends.jsonl` lines validate.
- `tests/contract/test_corpus_no_absolute_paths.py` — greps every corpus file for absolute user paths (the curation script should prevent this, but the test locks the invariant).

**Integration test** (runs in CI, <5 min):
- `tests/integration/test_benchmark_synthetic_corpus.py` — a synthetic 1-entry corpus (`tests/evals/benchmark/fixtures/synthetic/2026-01-01-hello/`) with a trivial requirement ("add a GET /health endpoint"). Runs the benchmark runner in `--dry-run` mode (mirroring pipeline harness) to exercise discovery, result-writing, trends append, scorecard render, and gate math — without invoking the `claude` CLI. Exit code 0 and `SCORECARD.md` diff is deterministic.

**Self-referential check:** The benchmark harness itself is not benchmarked (avoid infinite regress). Its quality is governed by the unit+contract+integration tiers above.

**PR CI vs weekly CI:** PR CI runs `collect` + unit + contract + integration (no real benchmark; no `claude` CLI needed). Weekly cron is the only path that runs real benchmarks. Workflow-dispatch allows on-demand runs for debugging.

## Documentation Updates

- **`CLAUDE.md`** — §Validation: add link to `SCORECARD.md` and the weekly benchmark section. §Architecture: add SCORECARD.md to the repo-root file manifest. §Skills (implicit): benchmark is a tooling layer, not a skill; no new slash-command entry.
- **`README.md`** — add a "Measured" badge under the "Install" section linking to `SCORECARD.md`. Add a short paragraph naming the current solve rate (text updated manually or by a future automation). Include a one-sentence disambiguation: *"SCORECARD.md measures weekly real-feature solve rate on a curated corpus; `tests/evals/pipeline/leaderboard.md` measures per-PR pipeline smoke on synthetic scenarios. Different tiers, different cadences."*
- **`SCORECARD.md`** — new file at repo root. First commit contains the template (all sections empty, "awaiting first weekly run" banner).
- **`tests/evals/pipeline/README.md`** — new §See Also section referencing `tests/evals/benchmark/README.md` and clarifying the pipeline harness stays for per-PR smoke while benchmark is the weekly truth.
- **`tests/evals/benchmark/README.md`** — new file. Quickstart for curate/run/render/refresh. Table of corpus entries + complexity distribution.
- **`.github/workflows/benchmark.yml`** — new workflow.
- **`docs/adr/0013-weekly-benchmark-extension.md`** — new ADR. Documents the "extend pipeline harness in place" decision, the 0.9 solve threshold, the 10pp regression threshold, the 6-cell matrix choice, the personal-tool bot-commit pattern.
- **`CHANGELOG.md`** — entry under `## [3.8.0]` (or whatever version ships Phase 8) listing the new benchmark harness, SCORECARD.md, and the baseline freeze.
- **`shared/observability.md`** — add `forge.benchmark.run.*` OTel span attributes emitted by `runner.py` (`forge.benchmark.entry_id`, `forge.benchmark.os`, `forge.benchmark.model`, `forge.benchmark.solved`, `forge.benchmark.duration_s`, `forge.benchmark.cost_usd`).
- **`shared/learnings/README.md`** — add `benchmark.regression` to the learning-types table.
- **`forge-config.md` template** — add `benchmark:` section with `max_weekly_cost_usd`, `regression_threshold_pp`, `corpus_root`.

## Acceptance Criteria

1. **AC-801.** `tests/evals/benchmark/corpus/` exists with ≥10 entries on first Phase 8 release. Each entry validates against `tests/evals/benchmark/schemas/corpus_entry.schema.json` (unit test enforced).
2. **AC-802.** `python -m tests.evals.benchmark.runner --help` prints usage; exits 0. Same for `curate.py`, `render_scorecard.py`, `refresh_baseline.py`.
3. **AC-803.** `.github/workflows/benchmark.yml` exists with `cron: '0 6 * * 1'` trigger, `workflow_dispatch`, and a matrix of exactly `{os: [ubuntu-latest, macos-latest, windows-latest], claude-model: [claude-sonnet-4-6, claude-opus-4-7]}` (6 cells).
4. **AC-804.** Synthetic-corpus integration test passes in PR CI in <5 minutes without requiring `claude` CLI.
5. **AC-805.** `render_scorecard.py` unit tests cover: empty results, all-solved, all-failed, regressions present, baseline drift >=10pp, cost-truncated, 12-week edge cases.
6. **AC-806.** `SCORECARD.md` passes `markdown-lint` at repo-lint settings and renders correctly in the GitHub web UI (manual smoke check on first real run; automated via `grip` or `markdown-it` CLI in CI).
7. **AC-807.** `README.md` and `CLAUDE.md` link to `SCORECARD.md`. Unit test greps both files for the link.
8. **AC-808.** Weekly CI commits `SCORECARD.md` only when `git diff --quiet SCORECARD.md` reports a difference. Idempotency verified by running the aggregator twice in a row on identical `trends.jsonl` — second run produces no commit.
9. **AC-809.** Regression gate fails CI (`exit 1`) when solve-rate drops >=10pp in any `(bucket, model)` cell vs. baseline. Verified by a mutation test: manually mutate `baseline.json` by +15pp; re-run aggregator against the current trends line; confirm exit 1 and `BENCH-REGRESSION` finding.
10. **AC-810.** `baseline.json` validates against `baseline.schema.json`. `refresh_baseline.py` refuses to run without `--confirm`.
11. **AC-811.** `curate.py` scrubs PII per the patterns in §Data Model. Contract test feeds synthetic dirty input to the scrubber and asserts all redactions applied. User-interactive prompts reused from `AskUserQuestion` pattern (documented in `shared/ask-user-question-patterns.md`).
12. **AC-812.** Benchmark runner respects Phase 6 cost ceiling: reading `state.cost.pct_consumed` (not `pct_remaining`), aborting remaining cells when `cost_accumulated >= benchmark.max_weekly_cost_usd`. Default: `benchmark.max_weekly_cost_usd: 200` (derived per §Cross-phase §Phase 6; refreshed after 90 days of real data). Enforcement verified via a cost-simulator fixture (see AC-827), not real Anthropic calls.
13. **AC-813.** All new Python files pass `ruff check` and `mypy --strict` per `pyproject.toml:17-24`. `ruff format` applied. No files added to `extend-exclude`.
14. **AC-814.** `docs/adr/0013-weekly-benchmark-extension.md` committed; lists the decisions (extend-in-place, 0.9 threshold, 10pp gate, 6-cell matrix, bot-commit pattern) and links to this spec.
15. **AC-815.** No corpus entry contains absolute paths, internal hostnames, private IPs, emails, SSH fingerprints, or API keys. Contract test scans every file in `corpus/`.
16. **AC-816.** `shared/learnings/README.md` lists `benchmark.regression` as a new learning type. Phase 4 selector service test exercises injection of a `benchmark.regression` learning into a dispatch brief.
17. **AC-817.** Phase 7 integration: `fg-540-intent-verifier` reads `acceptance-criteria.yaml` ACs when benchmark runner is active, writes per-AC verdicts used by the `solved` predicate. Contract test asserts `state.intent_verification_results[]` populated for synthetic entry.
18. **AC-818.** Phase 1 integration: hook-failure counts from `.forge/.hook-failures.jsonl` roll up into the scorecard header. Renderer test covers both zero-failures and non-zero-failures cases.
19. **AC-819.** OTel spans emitted per §Documentation Updates. `shared/observability.md` lists all six attributes. Replay test in `tests/unit/test_otel_benchmark_spans.py` asserts the span stream for one synthetic run.
20. **AC-820.** Windows matrix cell completes in CI for every corpus entry where `metadata.yaml: os_compat` includes `windows-latest`. Entries narrower than the full OS set are skipped at the matrix-filter stage (not at runtime) and excluded from Windows denominators. Entries with `requires_docker: true` and `windows-latest` in `os_compat` emit `BENCH-DOCKER-SKIPPED` WARNING at runtime; cell still succeeds. `curate.py` enforces that `requires_docker: true` ∧ `windows-latest ∈ os_compat` requires explicit user confirmation at curation time.
21. **AC-821.** Solve predicate: unit test asserts all three conditions (verdict, AC pct, critical findings) must be true. Any single condition false → `solved=false`.
22. **AC-822.** Timeout per complexity: S=900s, M=2700s, L=5400s. Configurable via `benchmark.timeout_seconds.{S,M,L}` in `forge-config.md`; schema validates on PREFLIGHT (guard: `L > M > S`).
23. **AC-823.** Corpus curation never writes outside `tests/evals/benchmark/corpus/`. Contract test runs `curate.py` in a sandboxed CWD and asserts no writes to `/`, `$HOME`, `.forge/`, or any existing corpus entry (only new entry dirs).
24. **AC-824.** `trends.jsonl` append-only: a test runs the aggregator twice with disjoint results and asserts both lines present, in order, with matching `schema_version`.
25. **AC-825.** Concurrency lock: if a human PR is merged during the bot commit window, the aggregator retries once via rebase; on second conflict it uploads the artifact and logs WARNING. Integration-level smoke via a test that spoofs the git state.
26. **AC-826.** Model-ID plumbing end-to-end: for matrix cell `claude-model: claude-opus-4-7`, after runner.py executes an entry, the resulting `.forge/state.json` records `detected_model: "claude-opus-4-7"` (or the equivalent field forge writes for the active model). Verified by an integration test that runs a single synthetic-corpus entry under a stubbed `claude` CLI which echoes back the resolved model ID; asserts the ID matches the matrix cell. Confirms env-only propagation is insufficient and the `forge.local.md` override path works.
27. **AC-827.** Cost-ceiling enforcement verified via simulator fixture `tests/evals/benchmark/test_cost_ceiling.py`. A mock `forge-token-tracker.sh` emits synthetic spend events that cumulatively exceed `benchmark.max_weekly_cost_usd`; runner.py asserts the aggregation job aborts the remaining matrix cells with `BENCH-COST-CEILING` WARNING. No real Anthropic API calls in the test; the simulator writes directly to the tracker's JSONL output.

## Open Questions

1. **Haiku in the matrix.** Should `claude-haiku-4-5-20251001` be added as a third model column? Cost savings (~3× cheaper) would let the corpus grow to 30+. But tier-1 agents are the minority in forge's dispatch graph; solve rate on haiku would tell us less than solve rate on sonnet. Revisit after first 4 weeks of baseline data.
2. **Corpus growth cadence.** Should curate.py auto-prompt weekly from new `.forge/run-history.db` entries, or remain purely on-demand? Leaning on-demand to preserve "user-assisted, not auto-scraping."
3. **Baseline: per-model or unified?** Currently per-model (§5). Pros: detects tier-specific regressions (e.g. sonnet drops but opus holds). Cons: doubles the maintenance. A unified baseline hides model-tier regressions. Per-model wins for now.
4. **Linear/GitHub issue bodies as corpus requirements.** `metadata.yaml.notes` has a freeform field; should the `requirement.md` be allowed to reference external issue bodies, or must it be fully self-contained? Leaning self-contained — issue bodies may move/disappear; corpus entries must be reproducible in isolation.
5. **Phase 8.5 peer-comparison automation.** Should we script a `update_peers.py` that fetches current SWE-bench / OpenHands / SWE-agent leaderboard rows? Risk: the scrape breaks when leaderboard HTML changes. Keeping manual for now.
6. **Sparkline accessibility.** Screen readers read `▁▂▃▄▅▆▇█` as "lower one-eighth block" etc. — verbose but functional. If an a11y complaint materialises, add an adjacent `(N% → M%)` textual pair (already present in this spec) and declare sparkline decorative. For now, the textual range is already adjacent.
7. **macOS runner cost.** `macos-latest` minutes are 10× `ubuntu-latest`. Weekly run with 15 L-entries could hit $15+ of GitHub Actions minutes alone on mac-only. Track via `benchmark.max_weekly_cost_usd` — but that ceiling is for Anthropic API, not runner minutes. Separate line item in §Open Questions: should `benchmark.max_weekly_runner_minutes` be a second ceiling?
8. **Baseline refresh ergonomics.** Should `refresh_baseline.py` open a PR automatically (via `gh pr create`) rather than committing to a working branch? Cleaner audit trail but more ceremony for a personal-tool solo developer. Leaning current: manual `git commit` after `--confirm`.
9. **Bot-commit PR fallback.** If branch protection is ever added to `master` that blocks `github-actions[bot]`, the aggregator must switch from direct commit to a PR-based flow (`gh pr create --base master --head benchmark-scorecard-<date>`). Currently the workflow commits directly because master is unprotected (personal tool). Revisit if the user configures required-review or required-status-checks for bot commits.
