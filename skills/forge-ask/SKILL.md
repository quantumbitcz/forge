---
name: forge-ask
description: "[read-only] Query forge state, codebase knowledge, run history, or analytics. Never mutates project state. Use to check pipeline status, search wiki/graph for code answers, view past runs, see analytics, or get an onboarding tour."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep', 'Agent']
---

# /forge-ask — Read-Only Query Surface

Five subcommands plus a default codebase Q&A path. Read-only — no mutations to project state. Always-safe to invoke.

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output (status, history, insights, profile)
- **--fresh**: bypass cache (codebase Q&A only)
- **--deep**: exhaustive grep/glob (codebase Q&A only)

## Exit codes

See `shared/skill-contract.md` for the standard table.

## Subcommand dispatch

**Positional, no NL fallback. Bare args (no recognized verb) default to codebase Q&A.**

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. If `$ARGUMENTS` is empty: prompt "What would you like to know about this codebase?" and re-read.
3. If `$ARGUMENTS == --help`: print usage and exit 0.
4. Split: `SUB="$1"; shift; REST="$*"`.
5. If `$SUB` is in `{status, history, insights, profile, tour}`: dispatch to `### Subcommand: <SUB>` with `$REST`.
6. Otherwise: treat the entire `$ARGUMENTS` string as a freeform question and dispatch to `### Subcommand: ask` (default).

## Usage

```
/forge-ask <subcommand> [args]
/forge-ask "<freeform question>"

Subcommands:
  status                    Current pipeline state
  history [--limit=N]       Past runs from .forge/run-history.db
  insights [--scope=...]    Quality, cost, convergence trends
  profile [<run-id>]        Per-stage timing and cost breakdown
  tour                      5-stop guided introduction

Default action (no recognized subcommand): codebase Q&A via wiki + graph + explore cache + docs.

Flags:
  --help                    Show this message
  --json                    Structured output (status-like)
  --fresh                   Bypass cache (Q&A only)
  --deep                    Exhaustive search (Q&A only)
```

## Shared prerequisites

1. **Git repository:** `git rev-parse --show-toplevel`. If fails: STOP.
2. **Forge initialized:** `.claude/forge.local.md` exists. If absent: report "Forge not initialized. Run /forge first." and STOP. (This skill does NOT auto-bootstrap.)

## Read-only contract (AC-S012)

This skill MUST NOT modify any file under the project root, `.forge/`, or `.claude/`. Verified by a contract test that runs every subcommand and asserts `git status` is unchanged after.

`allowed-tools` excludes `Write` and `Edit` — the harness enforces this.

The Q&A subcommand may write to `.forge/ask-cache/` (an opaque cache); this is the only permitted write and is excluded from the AC-S012 contract test by an explicit cache-path check.

---

### Subcommand: ask (default)

Codebase Q&A. Answer questions about the codebase by aggregating knowledge from all available data sources. Provide authoritative, evidence-based answers with file path references (clickable in IDE).

#### Configuration

Read from `forge-config.md` or use defaults:

| Key | Default | Description |
|-----|---------|-------------|
| `forge_ask.enabled` | `true` | Enable/disable subcommand |
| `forge_ask.deep_mode` | `false` | Also run grep/glob for exhaustive answers |
| `forge_ask.max_source_files` | `20` | Max file references to include in answer |
| `forge_ask.cache_answers` | `true` | Cache answers in `.forge/ask-cache/` |

#### Steps

##### 1. Parse Question

Read `$REST` (or full `$ARGUMENTS` when no subcommand) as the user's question. If empty, ask: "What would you like to know about this codebase?"

##### 2. Check Cache

If `forge_ask.cache_answers` is enabled:

1. Compute a cache key from the normalized question (lowercase, stripped punctuation, first 80 chars).
2. Check `.forge/ask-cache/{cache_key}.md` exists.
3. If exists, check staleness: if `.forge/state.json` has a newer `_seq` than the cached `_seq`, invalidate (new run has occurred).
4. If valid cache hit, return cached answer with note: "(Cached answer. Run `/forge-ask --fresh {question}` to bypass cache.)"

If `$ARGUMENTS` starts with `--fresh`, strip the flag and skip cache lookup.

##### 3. Query Data Sources

Query sources in priority order. For each source: check availability, query, collect relevant fragments. Stop early if confidence is high (3+ corroborating sources).

**Source 1 — Wiki (`.forge/wiki/`)**

1. Check if `.forge/wiki/` directory exists with `.md` files.
2. If available: search wiki files for content matching the question keywords.
3. Extract matching sections with their source file paths.
4. Wiki entries are curated summaries — treat as highest-confidence source.

**Source 2 — Knowledge Graph (Neo4j)**

1. Check if Neo4j MCP is available (probe `neo4j-mcp` tool).
2. If available: construct a Cypher query targeting the question's domain:
   - For "how does X work?" — query relationships and dependencies of X.
   - For "what tests cover X?" — query `TESTED_BY` relationships.
   - For "what changed in X?" — query nodes with recent `updated_at`.
   - For entity lookups — `MATCH (n) WHERE n.name CONTAINS '{entity}'`.
3. Extract node names, relationships, and file paths from results.

**Source 3 — Explore Cache (`.forge/explore-cache.json`)**

1. Check if `.forge/explore-cache.json` file exists.
2. If available: read cached exploration results (architecture maps, component inventories, dependency graphs).
3. Match question keywords against cached exploration summaries.
4. Explore cache provides structural context — file organization, module boundaries, entry points.

**Source 4 — Docs Index (`.forge/docs-index.json` or project docs)**

1. Check if `.forge/docs-index.json` exists (generated by docs-generate skill).
2. If not, check for common doc locations: `docs/`, `doc/`, `README.md`, `ARCHITECTURE.md`, `ADR/`.
3. Search documentation files for relevant content.
4. Docs provide authoritative intent descriptions — what things are supposed to do.

**Source 5 — Direct Search (deep mode only)**

If `forge_ask.deep_mode` is `true` or `$ARGUMENTS` contains `--deep`:

1. Run targeted grep across the codebase for question-relevant identifiers.
2. Run glob patterns for files matching question entities (e.g., question mentions "payment" -> glob for `**/payment*`, `**/pay*`).
3. Read up to `max_source_files` most relevant files to extract implementation details.
4. This is the most expensive source — only used when other sources are insufficient or deep mode is explicitly requested.

##### 4. Aggregate and Synthesize

1. Combine fragments from all available sources.
2. Resolve conflicts: wiki > graph > explore-cache > docs > direct search.
3. Identify gaps: note if no source covers a particular aspect of the question.
4. Compose a coherent answer structured as:

```markdown
## Answer

{Direct answer to the question in 2-5 sentences.}

### Details

{Expanded explanation with architecture context, code flow, or implementation details as relevant.}

### Key Files

| File | Role |
|------|------|
| `{absolute_path}` | {brief description of file's relevance} |

### Sources

- {Source name}: {what it contributed}
```

5. Limit file references to `max_source_files` (default 20). Prefer files that directly answer the question over tangentially related files.

##### 5. Cache Answer

If `forge_ask.cache_answers` is enabled and this was not a `--fresh` query:

1. Write the answer to `.forge/ask-cache/{cache_key}.md` with a header containing the `_seq` from current `state.json` (or `0` if no state).
2. Keep cache directory size reasonable: if more than 50 cached answers exist, delete the oldest 10.

##### 6. Example Queries

These are illustrative — the subcommand handles any freeform question:

- "How does authentication work?" — traces auth flow through modules, middleware, and config.
- "What tests cover the payment flow?" — identifies test files, test frameworks, and coverage gaps.
- "What changed in the last 3 runs?" — reads forge-log.md and state history for recent changes.
- "Where is the database schema defined?" — finds migration files, ORM models, and schema definitions.
- "Which modules depend on the user service?" — queries dependency graph or greps for imports.

#### Notes

- This is READ-ONLY (cache writes excluded per AC-S012). Never modify project files.
- Always include absolute file paths so they are clickable in IDE.
- If no data sources are available (no wiki, no graph, no cache), fall back to direct search regardless of deep_mode setting.
- If the question is about forge plugin internals (not the project), answer from plugin knowledge directly without querying data sources.
- If the answer is uncertain, say so explicitly. Do not fabricate information.

---

### Subcommand: status

Show the current state of the development pipeline for this project.

#### Prerequisites (in addition to shared)

- **State exists:** Check `.forge/state.json` exists. If not: report "No pipeline run in progress. Run `/forge-run` to start." and STOP.

#### Steps

1. Read `.forge/state.json` and display:
   - **Current stage:** `story_state` value (e.g., IMPLEMENTING, REVIEWING)
   - **Story ID:** `story_id`
   - **Mode:** `mode` (standard/migration/bootstrap). Note if `dry_run: true`.
   - **Quality score:** last recorded score (if REVIEW stage reached)
   - **Convergence:** `convergence.phase` (correctness/perfection/safety_gate), `convergence.convergence_state` (IMPROVING/PLATEAUED/REGRESSING), `convergence.total_iterations`, `convergence.safety_gate_failures`. If `convergence.unfixable_findings` is non-empty, show count.
   - **Fix cycles:** `verify_fix_count`, `quality_cycles`, `test_cycles`
   - **Stage timestamps:** which stages have completed and when
   - **Linear tracking:** Epic ID and status (if `linear.epic_id` is set)
   - **Linear sync:** `linear_sync.in_sync` (true/false, note failed operations if not in sync)
   - **Integrations:** which MCPs were detected as available
   - **Total retries:** `total_retries` / `total_retries_max` (global retry budget usage)
   - **Score history:** `score_history` (quality oscillation trend, e.g., `[85, 78, 92]`)
   - **Recovery budget:** `recovery_budget.total_weight` / `recovery_budget.max_weight` (recovery budget usage)
   - **Documentation:** `documentation.files_discovered` files, `documentation.decisions_extracted` decisions, `documentation.stale_sections` stale sections (if documentation subsystem active)

2. Check for recent stage notes:
   - Read the latest `.forge/stage_*_notes_*.md` file
   - Show a 2-3 line summary of the last stage's output

3. **Background run detection** -- check if `.forge/progress/status.json` exists (indicates `--background` mode, see `shared/background-execution.md`):

   a. Read `.forge/progress/status.json` and display:
      - **Run ID:** `run_id`
      - **Current stage:** `stage` (e.g., IMPLEMENTING, REVIEWING) with `stage_number`/9
      - **Progress:** `progress_pct`% -- render a visual progress bar (e.g. `[████████░░░░░░░░] 52%`)
      - **Quality score:** `score` (or "Not yet scored" if `null`)
      - **Convergence:** `convergence_phase` (`correctness`/`perfection`/`null`) -- iteration `convergence_iteration`
      - **ETA:** `eta_minutes` minutes remaining (or "Calculating..." if `null`)
      - **Elapsed:** computed from `started_at` to `last_update`
      - **Model usage:** for each key in `model_usage`, show model name, dispatch count, tokens in/out (formatted as `45K in / 12K out`)

   b. **Alerts** -- if `alerts` array is non-empty:
      - Display each alert with type, severity, message, and timestamp
      - If alert has `options`, show available resolution choices
      - If pipeline is paused (`state.json.background_paused: true`), show "PAUSED -- awaiting resolution for alert `{background_alert_id}`" with the paused duration (from `background_paused_at` to now)
      - Explain how to resolve: edit `.forge/progress/alerts.json`, set `resolved: true` and `resolution` to the chosen option ID

   c. **Stage summaries** -- read `.forge/progress/stage-summary/*.json` for completed stages and show:
      - Stage name, duration, agents dispatched count
      - Score delta (`score_before` -> `score_after`) if available
      - Finding counts (CRITICAL/WARNING/INFO)

   d. **Timeline tail** -- read the last 5 entries from `.forge/progress/timeline.jsonl` and display a compact event log

4. **`--watch` flag** -- when invoked as `/forge-ask status --watch`:
   - Poll `.forge/progress/status.json` every 5 seconds (default, matches `background.progress_update_interval_seconds`)
   - Refresh the display with updated stage, progress, score, alerts, and model usage
   - Exit automatically when the pipeline completes (`stage` = `LEARNING` and `progress_pct` = 100) or aborts
   - If an alert appears during watch, highlight it immediately and show resolution instructions

5. If `complete: true` in state.json:
   - If `abort_reason` is present and non-empty: report "Last run aborted: {abort_reason}"
   - Otherwise: report "Last run completed successfully"
   - Show final quality score and verdict
   - Show PR URL if available
   - If `recovery_failed: true`: report "Recovery engine failed at stage {last_known_stage}"

#### Hook Health

If `.forge/.hook-failures.jsonl` exists and is non-empty:
1. Count total failure entries: `wc -l < .forge/.hook-failures.jsonl`
2. Count unique hook names: `jq -r '.hook_name' .forge/.hook-failures.jsonl | sort -u | wc -l`
3. Show last 3 failures with timestamps: `tail -3 .forge/.hook-failures.jsonl | jq -r '"\(.ts)  \(.hook_name) exit=\(.exit_code)"'`
4. If count > 10: show warning "High hook failure rate. Run /forge-recover diagnose for details."

If `.forge/.hook-failures.jsonl` does not exist or is empty: show "Hooks: healthy (no failures logged)"

<!-- absorbed from Phase 1 Task 24 (skills/forge-status/SKILL.md §Live progress) -->
#### Live progress

After the primary status output, print a `--- live ---` separator and
render data from `.forge/progress/status.json` and
`.forge/run-history-trends.json` (both optional):

If `.forge/progress/status.json` exists:
1. Parse via `python3 -c "import json; print(json.load(open('.forge/progress/status.json')))"`.
2. Print: `Stage: {stage}  Agent: {agent_active or 'idle'}`.
3. Print elapsed vs timeout: `{elapsed_ms_in_stage}ms / {timeout_ms}ms`.
4. If `(now - updated_at) > 60s` and `(now - state_entered_at) > stage_timeout_ms`: print "Run appears hung — consider /forge-recover diagnose."

If `.forge/run-history-trends.json` exists:
1. Print last 5 runs as a table: run_id, verdict, score, duration_s.
2. Print count of `recent_hook_failures`.

If neither file exists: print "No live data (run has not completed a
subagent dispatch yet)."

#### Config validation summary

After the primary status report, emit a compact config-validation block. This
absorbs what `/forge-verify --config` used to do (that subcommand is deleted
as of Phase 2). Scope:

1. Load `.claude/forge.local.md` (if present) and `.claude/forge-config.md`.
2. Validate against PREFLIGHT constraints (`shared/preflight-constraints.md`).
3. Report each constraint as PASS/FAIL/UNCHECKED with a one-line rationale.
4. Under `--json`, emit this block as a `config_validation` top-level object:
   ```json
   {
     "config_validation": {
       "local_md_exists": true,
       "config_md_exists": true,
       "constraints": [
         { "id": "pass_threshold", "verdict": "PASS" },
         { "id": "total_retries_max", "verdict": "PASS" }
       ]
     }
   }
   ```
If `.claude/forge.local.md` is missing entirely, emit the config block with
`local_md_exists: false` and skip constraint checks (nothing to validate).

#### Recent hook failures

Read the last 5 entries from `.forge/events.jsonl` where `type == "hook_failure"`.
For each, show timestamp, hook name, exit code, and a one-line stderr snippet.
If the file is missing or contains no hook_failure entries, emit "No recent
hook failures." Under `--json`, emit as a `recent_hook_failures` array.

#### Status error handling

| Condition | Action |
|-----------|--------|
| state.json unparseable | Report "state.json is corrupted. Run `/forge-recover repair` to fix or `/forge-recover reset` to start fresh." and STOP |
| state.json missing fields | Show what is available, note missing fields as "unknown" |
| progress/status.json malformed | Report "Background progress data is corrupt." and fall back to state.json only |
| Stage notes file missing | Skip stage notes section, continue with other data |

---

### Subcommand: history

View trends across multiple pipeline runs — score oscillations, agent effectiveness, common findings, and PREEMPT health.

#### Prerequisites (in addition to shared)

- **History data exists:** Check at least one of these sources:
  - `.claude/forge-log.md` with run entries
  - `.forge/reports/` with report files
  If neither exists: report "No pipeline history found. Run `/forge-run` to start building history." and STOP.

#### Steps

##### 1. Gather History Data

Read all available history sources:

1. **Forge log** (`.claude/forge-log.md`): Primary source -- contains per-run entries with dates, requirements, scores, verdicts, and retrospective notes.
2. **Run reports** (`.forge/reports/`): Detailed per-run reports with findings, agent dispatches, and timing data.
3. **Learnings** (`shared/learnings/` and `.forge/learnings/`): PREEMPT items and agent effectiveness records.

If forge-log.md is very large (>500 lines), summarize the last 10 runs instead of all runs.

##### 2. Present Quality Score Trend

Extract from forge-log.md each run's date, requirement summary, final quality score, verdict, total fix cycles (verify + review), and wall time:

```
## Pipeline Run History

### Quality Score Trend
| Date | Requirement | Score | Verdict | Fix Cycles | Duration |
|------|-------------|-------|---------|------------|----------|
```

Compute trend direction: improving (last 3 scores ascending), declining (descending), or stable (within oscillation tolerance).

##### 3. Present Most Common Findings

Aggregate finding categories across all runs. Show top 5 by frequency:

```
### Most Common Findings
1. {CATEGORY} ({N} runs) -- {typical description}
2. ...
```

Identify findings that appear in 3+ runs as convention candidates -- patterns the team consistently triggers that should be codified as project rules.

##### 4. Present Agent Effectiveness

If agent effectiveness data exists in forge-log.md (added by retrospective):

```
### Agent Effectiveness
| Agent | Runs | Avg Time | Avg Findings | FP Rate |
|---|---|---|---|---|
```

If no effectiveness data: report "Agent effectiveness tracking not yet available. Will populate after future runs."

##### 5. Present PREEMPT Health

Read learnings files for PREEMPT items:

```
### PREEMPT Health
- Active items: {count} (HIGH: {n}, MEDIUM: {n}, LOW: {n})
- Archived items: {count}
- Last promotion: {date} -- {item description}
- Decay candidates: {count} items with 10+ unused runs
```

If no PREEMPT data: report "No PREEMPT items found."

##### 6. Cross-Run Trend Summary

Synthesize the data into actionable observations:
- Score trajectory over the last 5 runs
- Whether convergence is getting faster or slower
- Top recurring finding that should become a convention

#### History error handling

| Condition | Action |
|-----------|--------|
| forge-log.md missing | Fall back to reports directory. If also missing, STOP with guidance |
| forge-log.md unparseable | Report "forge-log.md has unexpected format. Showing raw content summary." and display what can be extracted |
| Reports directory empty | Work from forge-log.md alone, note limited data |
| State corruption | This subcommand is read-only and does not depend on state.json |

#### History notes

- This is read-only -- do not modify any files
- If forge-log.md is very large (>500 lines), summarize the last 10 runs instead of all runs
- If reports directory does not exist, work from forge-log.md alone

---

### Subcommand: insights

Analyze trends across pipeline runs to surface actionable insights about quality, cost, agent behavior, and pipeline health.

#### Prerequisites (in addition to shared)

- **Run history exists:** Check at least one of these sources exists:
  - `.forge/reports/` with report files
  - `.forge/state.json` with `telemetry` data
  - `.claude/forge-log.md` with run entries
  If none exist: report "No pipeline run data found. Run `/forge-run` to generate data, then try again." and STOP.

#### Steps

##### 1. Gather Data

Read all available data sources:

1. **Run reports** (`.forge/reports/*.json` or `.forge/reports/*.md`): per-run summaries including scores, findings, timings, agent dispatches.
2. **Telemetry** (`.forge/state.json` → `telemetry`): current/last run metrics — token usage, wall time, stage durations, agent dispatch counts.
3. **Forge log** (`.claude/forge-log.md`): human-readable run history with dates, requirements, scores, verdicts, and retrospective notes.
4. **Learnings** (`shared/learnings/` and `.forge/learnings/`): accumulated patterns, PREEMPT items, agent effectiveness records.
5. **Score history** (`.forge/state.json` → `score_history`): per-iteration score progression within the current/last run.

If a source is unavailable, skip it and note which categories will have incomplete data.

##### 2. Analyze — Six Insight Categories

###### Category 1: Quality Trajectory

Analyze score trends across runs:

- **Score trend:** Plot scores from all available runs. Indicate direction (improving, declining, stable).
- **Recurring findings:** Identify finding categories that appear in 3+ runs. These are convention candidates.
- **Severity distribution shift:** Compare CRITICAL/WARNING/INFO ratios between early and recent runs.
- **Convention candidates:** Findings that recur but never get permanently fixed suggest missing conventions or team patterns that should be codified.

```markdown
### Quality Trajectory

| Run | Date | Score | Verdict | CRITICALs | WARNINGs |
|-----|------|-------|---------|-----------|----------|
| {n} | {date} | {score} | {verdict} | {count} | {count} |

**Trend:** {improving/declining/stable} ({delta} over {n} runs)

**Recurring Findings (3+ runs):**
| Category | Occurrences | Last Seen | Suggestion |
|----------|-------------|-----------|------------|
| {cat}    | {n}         | {date}    | {codify as convention / investigate root cause} |
```

###### Category 2: Agent Effectiveness

Analyze which agents contribute most to quality improvement:

- **Most impactful reviewer:** Agent whose findings lead to the largest score improvements after fixing.
- **Least triggered agent:** Reviewer that rarely produces findings — may indicate over-scoping or irrelevance to this project.
- **Mutation kill rate:** If mutation testing data exists (from test gate), report the kill rate trend.
- **False positive rate:** Agents with high FP rates (findings marked as dismissed or not-applicable).

```markdown
### Agent Effectiveness

| Agent | Dispatches | Avg Findings | Score Impact | FP Rate |
|-------|-----------|-------------|-------------|---------|
| {agent} | {n} | {avg} | {delta} | {pct}% |

**Most impactful:** {agent} — avg {delta} point improvement per dispatch
**Least triggered:** {agent} — {n} findings across {m} runs
**Mutation kill rate:** {pct}% (trend: {direction})
```

###### Category 3: Cost Analysis

Analyze resource consumption and cost efficiency:

- **Per-run cost trend:** Token counts and USD estimates across recent runs with anomaly detection (>2x average flagged).
- **Per-stage cost breakdown:** Average tokens, average cost, percentage of total, and trend direction per stage.
- **Cost-per-quality-point:** Efficiency metric per (stage, model tier) from `.forge/trust.json` `model_efficiency`. Stages without score impact are reported separately as overhead.
- **Model tier distribution:** Dispatches, tokens, and percentage per tier (premium/standard/fast).
- **Budget utilization:** Ceiling vs used per run, alert trigger counts.
- **Top-3 cost recommendations:** Evidence-based suggestions sorted by confidence and expected savings.

Sources: `state.json.cost`, `state.json.tokens`, `.forge/trust.json` `model_efficiency`, `state.json.cost_alerting`.

Recommendation generation:
1. Model downgrade opportunities (from trust.model_efficiency, requires 5+ data points)
2. Convergence cost reduction (when avg iterations > 5)
3. Stage budget overruns (consistently exceeding per-stage limits)
4. Output compression opportunities (>30% verbose dispatches)
5. Context guard trigger frequency (avg > 3 triggers/run)

```markdown
### Cost Analysis

#### Per-Run Cost Trend

| Run | Date | Tokens | Est. Cost | Score | Cost/Point | Budget Used |
|-----|------|--------|-----------|-------|------------|-------------|

#### Per-Stage Cost Breakdown

| Stage | Avg Tokens | Avg Cost | % of Total | Trend |
|-------|-----------|----------|-----------|-------|

#### Cost-Per-Quality-Point (Efficiency)

| Stage | Tier | Tokens/Point | Runs | Suggestion |
|-------|------|-------------|------|------------|

#### Model Tier Distribution

| Tier | Dispatches | Tokens | % of Total | Avg Cost |
|------|-----------|--------|-----------|----------|

#### Budget Utilization

| Run | Ceiling | Used | % | Alerts Triggered |
|-----|---------|------|---|-----------------|

#### Top-3 Cost Recommendations

| # | Recommendation | Expected Savings | Confidence |
|---|---------------|-----------------|------------|
```

###### Category 4: Convergence Patterns

Analyze how efficiently the pipeline converges to shipping quality:

- **Average iterations to ship:** Mean total iterations across runs.
- **Plateau causes:** Most common reasons for score plateaus (conflicting findings, over-strict rules, flaky tests).
- **Safety gate failure rate:** How often the safety gate rejects and forces a phase restart.
- **First-pass success rate:** Percentage of runs that pass quality on the first verify+review cycle.

```markdown
### Convergence Patterns

| Metric | Value |
|--------|-------|
| Avg iterations to ship | {n} |
| First-pass success rate | {pct}% |
| Safety gate failure rate | {pct}% |
| Most common plateau cause | {cause} |

**Iteration Distribution:**
| Iterations | Runs | % |
|-----------|------|---|
| 1-2       | {n}  | {pct}% |
| 3-5       | {n}  | {pct}% |
| 6+        | {n}  | {pct}% |
```

###### Category 5: Memory Health

Analyze the accumulated knowledge base:

- **Active PREEMPT items:** Count by priority (HIGH/MEDIUM/LOW), identify items nearing decay.
- **Auto-discovered patterns:** Patterns added by retrospective that have been applied in subsequent runs.
- **Decay candidates:** PREEMPT items with 10+ unused runs approaching demotion or archival.
- **Learning growth:** Rate of new learnings per run.

```markdown
### Memory Health

**PREEMPT Items:**
| Priority | Active | Applied (last 5 runs) | Decay Candidates |
|----------|--------|-----------------------|------------------|
| HIGH     | {n}    | {n}                   | {n}              |
| MEDIUM   | {n}    | {n}                   | {n}              |
| LOW      | {n}    | {n}                   | {n}              |
| ARCHIVED | {n}    | —                     | —                |

**Pattern Discovery:**
- Total auto-discovered patterns: {n}
- Applied in subsequent runs: {n} ({pct}%)
- Never applied: {n} (review for removal)

**Learnings Growth:**
- Total learnings files: {n}
- New entries (last 5 runs): {n}
- Most active category: {category}
```

###### Category 6: Compression Effectiveness

Analyze token savings and compression compliance:

- **Output compression savings:** Compare actual output tokens per agent from `state.json.tokens.output_tokens_per_agent` against the expected range for their stage's compression level. Estimate tokens saved relative to verbose baseline using the stage-level token ranges from `shared/output-compression.md`: verbose 800-2000, standard 800-2000, terse 400-1200, minimal 100-600.
- **Compression level distribution:** Show dispatch counts per level from `state.json.tokens.compression_level_distribution`. Highlight if distribution is skewed (e.g., 90% verbose suggests misconfiguration or `output_compression.enabled: false`).
- **Drift detection:** Identify agents consistently exceeding their stage's expected token range by >50%. An agent dispatched at `terse` (expected 400-1200 tokens) producing 1800 tokens is drifting.
- **Input compression savings:** If `/forge-compress` has been run (detect via `*.original.md` backup files in `agents/`), compute before/after line counts and estimated token savings using `wc -l`.
- **Caveman mode usage:** Report whether caveman mode was active (read `.forge/caveman-mode`), which level, and how many sessions used it (from `.forge/events.jsonl` if available).

```markdown
### Compression Effectiveness

**Output Compression:**
| Metric | Value |
|--------|-------|
| Dispatches at verbose | {n} |
| Dispatches at standard | {n} |
| Dispatches at terse | {n} |
| Dispatches at minimal | {n} |
| Estimated output tokens saved | {n} ({pct}% vs all-verbose baseline) |

**Drift Alerts:**
| Agent | Stage Level | Expected Range | Actual Tokens | Status |
|-------|------------|----------------|---------------|--------|
| {agent} | terse | 400-1200 | {n} | DRIFT / OK |

**Input Compression:**
| Scope | Files | Before (lines) | After (lines) | Reduction |
|-------|-------|-----------------|---------------|-----------|
| agents/ | {n} | {n} | {n} | {pct}% |

**Caveman Mode:** {off/lite/full/ultra}
```

##### 3. Generate Summary and Recommendations

Synthesize the six categories into actionable recommendations:

```markdown
## Pipeline Insights Report

**Project:** {project name}
**Runs analyzed:** {count}
**Date range:** {earliest} to {latest}

{Category 1-6 sections as above}

### Recommendations

| Priority | Action | Category | Expected Impact |
|----------|--------|----------|-----------------|
| {1-N}    | {specific action} | {category} | {what improves} |
```

Prioritize recommendations by expected impact:

1. **Recurring CRITICALs** — codify as project conventions or fix root cause.
2. **High convergence cost** — tune thresholds or add PREEMPT items for common patterns.
3. **Low-value agents** — consider disabling agents with zero findings across 5+ runs.
4. **Stale PREEMPT items** — archive items that never match to reduce overhead.
5. **Score regression** — investigate if a recent config change degraded quality.
6. **High compression drift** — suggest tuning per-stage levels or upgrading drifting agents' model tier.

##### 4. Save Report

Write the full report to `.forge/reports/insights-{date}.md` where `{date}` is today in `YYYY-MM-DD` format. If the reports directory does not exist, create it.

#### Insights notes

- This is READ-ONLY with respect to project code. Only writes to `.forge/reports/` (an opaque report cache, not project code).
- If only one data source is available, generate a partial report and note which categories have insufficient data.
- Do not fabricate data. If a metric cannot be computed, report "Insufficient data" rather than estimating.
- For projects with fewer than 3 runs, note that trend analysis requires more data points and focus on single-run metrics instead.
- Token-to-USD conversion is approximate. Use $3/MTok input, $15/MTok output as defaults unless project config specifies otherwise.

#### Insights error handling

| Condition | Action |
|-----------|--------|
| No run data available | Report "No pipeline run data found. Run `/forge-run` to generate data, then try again." and STOP |
| Only one data source available | Generate partial report and note which categories have insufficient data |
| Fewer than 3 runs | Note that trend analysis requires more data points. Focus on single-run metrics |
| Report directory does not exist | Create `.forge/reports/` before writing the report |
| Data source unparseable | Skip the malformed source, log WARNING, continue with remaining sources |
| State corruption | This subcommand reads state.json for telemetry but does not depend on valid pipeline state |

---

### Subcommand: profile

Per-stage timing and cost breakdown. Optional `<run-id>` (default: most recent run).

#### Prerequisites (in addition to shared)

- **Performance data exists:** Check `.forge/state.json` exists with `cost.wall_time_seconds > 0`. If no timing data: report "No performance data available. Run a pipeline first with `/forge-run`." and STOP.
- **Events log (optional):** Check `.forge/events.jsonl` exists. If not: note that per-stage/per-agent timing analysis will be limited -- report token and convergence data from state.json only, and note that detailed timing requires events.jsonl.

#### Steps

##### 1. Gather Performance Data

Read all available performance data sources:

1. **Events log** (`.forge/events.jsonl`): Parse all `state_transition` events to extract timing:
   - Per-stage duration: time between entering and leaving each stage
   - Per-agent duration: time between agent dispatch and completion events

2. **State file** (`.forge/state.json`): Extract:
   - `cost.wall_time_seconds` -- total run time
   - `tokens.by_stage` -- token consumption per stage
   - `tokens.by_agent` -- token consumption per agent
   - `convergence.phase_history` -- iteration details
   - `score_history` -- quality score progression

3. **Run reports** (`.forge/reports/*.json`): If available, extract per-run timing for trend analysis across multiple runs.

##### 2. Compute Metrics

Calculate the following metrics from the gathered data:

- **Stage time share**: For each pipeline stage, compute duration as percentage of total wall time
- **Agent dispatch frequency**: Count how many times each agent was dispatched
- **Token efficiency**: Tokens consumed per score point improvement
- **Convergence cost**: Extra tokens spent in fix/review cycles beyond the first pass
- **Bottleneck identification**: Flag any stage consuming >40% of total time, or any agent dispatched >5 times

##### 3. Generate Report

Present the analysis in this format:

```markdown
# Pipeline Performance Profile

## Time Breakdown by Stage
| Stage | Duration | % of Total | Iterations |
|-------|----------|-----------|------------|

## Time Breakdown by Agent
| Agent | Total Time | Dispatches | Avg per Dispatch |
|-------|-----------|-----------|-----------------|

## Token Consumption
| Component | Input Tokens | Output Tokens | Total |
|-----------|-------------|--------------|-------|

## Convergence Efficiency
- Total iterations: {N}
- Phase 1 iterations: {N}
- Phase 2 iterations: {N}
- Safety gate attempts: {N}
- Score trajectory: {start} -> {end}

## Bottleneck Analysis
- Slowest stage: {stage} ({duration}s, {pct}% of total)
- Most dispatched agent: {agent} ({count} times)
- Highest token consumer: {agent/stage}

## Recommendations
{If any stage > 40% of total time, suggest optimization}
{If any agent dispatched > 5 times, suggest scope reduction}
{If convergence took > 5 iterations, suggest PREEMPT items or threshold tuning}
```

##### 4. Compare with Previous Runs

If multiple run reports exist in `.forge/reports/`, compare performance across runs:
- Show wall time trend (improving or degrading)
- Identify stages that are consistently slow
- Note if convergence efficiency is improving over time (fewer iterations per run)

#### Profile error handling

| Condition | Action |
|-----------|--------|
| state.json missing or unparseable | Report "Pipeline state not found or corrupt. Run `/forge-run` first." and STOP |
| events.jsonl missing | Generate partial report from state.json only, note limited data |
| events.jsonl has malformed lines | Skip malformed lines, log WARNING, continue with valid entries |
| No token data available | Report "No token usage data recorded." and skip token analysis sections |
| State corruption | Suggest `/forge-recover repair` to fix state, then re-run profiler |

---

### Subcommand: tour

Welcome to Forge, a 10-stage autonomous development pipeline. This tour walks you through the 5 skills you'll use most, in the order you'll need them.

Present each stop sequentially. Pause between stops to let the user ask questions or try the skill.

#### Stop 1: /forge-init (Setup)

**What it does:** Configures Forge for your project by detecting your tech stack (language, framework, testing) and generating local config files.

**When to use:** First time setting up Forge in a project.

**What happens:**
- Detects your language, framework, and testing setup
- Generates `.claude/forge.local.md` (project config)
- Generates `.claude/forge-config.md` (pipeline settings)
- Detects available MCP integrations (Linear, Playwright, etc.)

**Try it:** Run `/forge-init` in any project.

---

#### Stop 2: /forge-verify (Quick Health Check)

**What it does:** Runs build + lint + test and reports pass/fail. No pipeline, no agents — just a quick sanity check.

**When to use:** Before any pipeline run, after manual changes, before committing.

**What happens:**
- Runs your build command (if configured)
- Runs your lint command (if configured)
- Runs your test command (if configured)
- Reports PASS / FAIL / SKIPPED per step

**Try it:** Run `/forge-verify` to check your project's baseline health.

---

#### Stop 3: /forge-run (Build Features)

**What it does:** The main entry point. Give it a requirement, and it runs the full 10-stage pipeline: explore → plan → implement (TDD) → verify → review → ship.

**When to use:** When you have a clear feature to build.

**Example:**
```
/forge-run Add email validation to user registration with error messages
```

**What happens:**
1. Explores your codebase for context (~1 min)
2. Creates an implementation plan (may ask for approval)
3. Implements via TDD — writes tests first, then code
4. Verifies: runs tests, lint, and code review
5. Fixes any issues found in review (may loop 2-5 times)
6. Generates documentation and creates a PR

---

#### Stop 4: /forge-fix (Fix Bugs)

**What it does:** Specialized bugfix workflow — investigates root cause, writes a failing test that reproduces the bug, implements the fix.

**When to use:** When you have a bug to fix.

**Example:**
```
/forge-fix Users get 404 when accessing /api/groups endpoint
```

**What happens:**
1. Investigates the bug (max 3 reproduction attempts)
2. Writes a failing test demonstrating the bug
3. Implements the minimal fix
4. Verifies no regressions

---

#### Stop 5: /forge-review (Review Changes)

**What it does:** Reviews your recent code changes using 3-8 specialized review agents (security, architecture, performance, accessibility, etc.).

**When to use:** After making changes, before committing or creating a PR.

**Example:**
```
/forge-review          # Quick mode: 3 agents
/forge-review --full   # Full mode: up to 8 agents
```

**What happens:**
- Detects changed files (staged + unstaged)
- Dispatches review agents in parallel
- Reports findings by severity (CRITICAL / WARNING / INFO)
- Calculates quality score (0-100)
- Offers to fix findings automatically

---

#### Tour Summary

| Skill | When | Time |
|-------|------|------|
| `/forge-init` | First time setup | ~1 min |
| `/forge-verify` | Quick health check | ~30s |
| `/forge-run` | Build a feature | 5-30 min |
| `/forge-fix` | Fix a bug | 3-15 min |
| `/forge-review` | Review code quality | 1-5 min |

#### What's Next?

- **All skills:** See the skill table in `CLAUDE.md` §Skill selection guide.
- **Reduce token usage:** `/forge-compress output`
- **Pipeline analytics:** `/forge-ask insights`
- **Multiple features:** `/forge-sprint`

#### Platform Notes

##### Windows (WSL2) — Recommended

WSL2 is the recommended way to run Forge on Windows. All scripts require bash 4.0+ which WSL2 provides natively.

```bash
# Install WSL2 (PowerShell as Administrator)
wsl --install -d Ubuntu

# Inside WSL2
sudo apt update && sudo apt install -y bash python3 git docker.io
```

**Important:** Run all Forge commands from within WSL2, not PowerShell or CMD.

##### Windows (Git Bash) — Limited Support

Git Bash provides a minimal bash environment but has known limitations:

- MSYS path translation causes issues with hook path resolution (see commit `0ac4874`)
- Docker commands require Docker Desktop with WSL2 backend enabled
- Some scripts may hit Windows long path limits (260 chars)

```bash
# Requires Git for Windows with Git Bash
# Enable long paths in git
git config --global core.longpaths true
```

##### macOS — Full Support

macOS ships with bash 3.x. Forge requires bash 4.0+.

```bash
brew install bash python3
# Verify version
bash --version  # Must show 4.0+
```

##### Linux — Full Support

All major distributions are supported. Install bash 4+ and python3:

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y bash python3 git

# Fedora / RHEL
sudo dnf install -y bash python3 git

# Arch Linux
sudo pacman -S bash python git
```

---

## Error Handling

| Condition | Action |
|---|---|
| Prerequisites fail | Report and STOP |
| Empty question (default subcommand, no args) | Prompt "What would you like to know?" |
| `--help` | Print usage and exit 0 |
| Unknown subcommand | Treat as freeform question; dispatch to default Q&A |
| No data sources (wiki, graph, cache, docs all absent) | Fall back to direct grep/glob regardless of `deep_mode` |
| Neo4j unavailable | Skip graph; log INFO; continue |
| All sources empty | Report "Could not find relevant information. Try rephrasing or use `--deep`." |

## See Also

- `/forge` — Write-surface entry (run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit)
- `/forge-admin` — State and config management (recover, abort, config, handoff, automation, playbooks, compress, graph, refine)
