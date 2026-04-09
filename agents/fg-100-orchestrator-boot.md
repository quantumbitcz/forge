# Pipeline Orchestrator — Boot Phase (PREFLIGHT)

> This document is loaded by the orchestrator at pipeline start.
> Follow the core document (`fg-100-orchestrator-core.md`) for principles and forbidden actions.
> After PREFLIGHT completes, load `fg-100-orchestrator-execute.md` for stages 1-6.

---

**story_state:** `PREFLIGHT`

---

### §0.1 Requirement Mode Detection

Before reading config, detect the requirement mode from the user's input:

| Prefix | Mode | Effect |
|--------|------|--------|
| `bootstrap:` / `Bootstrap:` | Bootstrap | Dispatch `fg-050-project-bootstrapper` at Stage 2. Stage 3 uses bootstrap-scoped validation. Stage 4 is skipped (scaffolding done in Stage 2). Stage 6 uses reduced reviewer set. See `stage-contract.md` Bootstrap Mode. |
| `migrate:` / `migration:` | Migration | Dispatch `fg-160-migration-planner` at Stage 2 instead of `fg-200-planner`. Uses migration-specific states (MIGRATING, etc.). |
| `bugfix:` / `fix:` | bugfix | Dispatch `fg-020-bug-investigator` at Stages 1-2. Reduced validation (4 perspectives). Reduced review batch. |
| (anything else) | Standard | Normal pipeline flow with `fg-200-planner`. |

If the orchestrator is dispatched with `Mode: bugfix` in the prompt (from `/forge-fix`), set mode to `bugfix` directly without prefix detection.

Strip the mode prefix from the requirement before passing it to downstream agents. After state initialization (§0.17), update `state.json.mode` to the detected value (`"standard"`, `"migration"`, `"bootstrap"`, `"bugfix"`, `"testing"`, `"refactor"`, or `"performance"`).

**Specialized mode behaviors:**
- `testing`: Standard pipeline. Implementer focuses on test files only (no production code changes). Quality gate uses reduced reviewer set: `fg-410-code-reviewer`. Target score is `pass_threshold`, not 100.
- `refactor`: Standard pipeline. Planner uses refactor constraints: preserve existing behavior, no new features, maintain passing test suite. Review batch adds `fg-410-code-reviewer` as mandatory. Target score is `shipping.min_score`.
- `performance`: Standard pipeline. EXPLORE stage includes profiling/benchmarking context. Review batch includes `fg-416-backend-performance-reviewer` and/or `fg-414-frontend-quality-reviewer` as mandatory. Target score is `shipping.min_score`.

**Note:** `fg-010-shaper` is NOT dispatched by the orchestrator — it runs via the `/forge-shape` skill as a pre-pipeline phase.

After detecting mode, load mode overlay per core §10.

---

### §0.2 Read Project Config

Read `.claude/forge.local.md` and parse YAML frontmatter. Extract:
- `project_type`, `framework`, `module` -- project identity
- `explore_agents` -- agents for Stage 1
- `commands` -- build, lint, test, test_single, format (NEVER hardcode these)
- `scaffolder` -- enabled, patterns
- `quality_gate` -- batch definitions, inline_checks, max_review_cycles
- `test_gate` -- command, max_test_cycles, analysis_agents
- `validation` -- perspectives, max_validation_retries
- `implementation` -- parallel_threshold, max_fix_loops, tdd, scaffolder_before_impl
- `risk` -- auto_proceed threshold
- `conventions_file` -- path to module conventions
- `context7_libraries` -- documentation prefetch targets
- `preempt_file`, `config_file` -- paths to mutable state files

Store parsed config in memory. All subsequent stages reference these values -- never hardcode commands or agent names.

---

### §0.3 Read Mutable Runtime Params

Read `forge-config.md` (path from `config_file` or default `.claude/forge-config.md`). Extract:
- `max_fix_loops`, `max_review_loops`, `auto_proceed_risk`, `parallel_impl_threshold`
- Domain hotspots

**Parameter resolution order** (highest priority first):
1. `forge-config.md` -- auto-tuned values (if the parameter exists here, use it)
2. `forge.local.md` frontmatter -- fallback defaults
3. Plugin defaults -- hardcoded fallbacks: `max_fix_loops: 3`, `max_review_loops: 2`, `auto_proceed_risk: MEDIUM`, `parallel_impl_threshold: 3`

---

### §0.4 Config Validation

After reading config files, validate before proceeding:

1. **`forge.local.md`**: must exist and have valid YAML frontmatter
   - If missing: ERROR — "Run `/forge-init` to set up this project for the pipeline"
   - If YAML invalid: ERROR — show parse error with line number
2. **Required fields**: `project_type`, `framework`, `module`, `commands.build`, `commands.test`, `commands.lint`, `quality_gate` must be present. `commands.test_single` is recommended but not required (falls back to `commands.test` if missing).
   - If missing: ERROR — list all missing fields
3. **`conventions_file` path**: must resolve to a readable file
   - If missing: WARN — "Conventions file not found at {path}. Using universal defaults. Framework-specific checks will be skipped."
   - Continue with degraded mode, DO NOT abort
4. **`forge-config.md`**: optional
   - If missing: INFO — "No runtime config found. Using plugin defaults."
5. **Quality gate agents**: all agents referenced in `quality_gate.batch_N` must exist
   - Plugin agents (no `source: builtin`): verify file exists in `agents/` directory
   - Builtin agents (`source: builtin`): accept — Claude Code resolves these at runtime
   - If plugin agent missing: WARN — "Agent {name} not found in agents/. Will be skipped during REVIEW."

6. **Constraint validation** for configurable fields:
   - `total_retries_max`: must be >= 5 and <= 30, default 10. If out of range: WARN — use default (10).
   - `oscillation_tolerance`: must be >= 0 and <= 20, default 5. If out of range: WARN — use default (5).

If any ERROR-level validation fails, stop the pipeline and report all errors together. Do not fail on the first error — collect all validation failures and present them as a batch.

---

### §0.5 Convention Fingerprinting

After reading `conventions_file`, compute a fingerprint and store in state.json:

    conventions_hash: first 8 characters of SHA256 hash of conventions_file content

This enables mid-run drift detection. Compute with:
    sha256sum {conventions_file} | cut -c1-8

If conventions_file is unavailable (WARN already logged), set `conventions_hash` to empty string.

Additionally, parse the conventions file into sections (`##` headings). Compute SHA256 first 8 chars for each section's content. Store in `conventions_section_hashes`: `{ "architecture": "ab12cd34", "naming": "ef56gh78", ... }`. If conventions file unavailable, set to `{}`.

---

### §0.6 PREEMPT System + Version Detection

Read `forge-log.md` (path from `preempt_file` or default `.claude/forge-log.md`):

If `forge-log.md` does not exist (first-ever run on this project):
- INFO: "No pipeline log found. Starting with empty PREEMPT baseline."
- Set `preempt_items_applied` to `[]`
- Skip trend context (no previous runs)
- Continue — the retrospective agent will create `forge-log.md` at Stage 9

If it exists:
- Collect all `PREEMPT` and `PREEMPT_CRITICAL` items
- Filter items matching the inferred domain area of the current requirement (detection rules per `shared/domain-detection.md`)
- Note the last 3 run results for trend context

---

### §0.6a Detect Project Dependency Versions

Detect dependency versions from the project's manifest file (e.g., `build.gradle.kts`, `package.json`, `go.mod`, `Cargo.toml`, `Package.swift`, `.csproj`, `pyproject.toml`). Extract language version, framework version, and key dependency versions. Store in `state.json.detected_versions`:

```json
"detected_versions": {
  "language": "kotlin", "language_version": "2.0.0",
  "framework": "spring-boot", "framework_version": "3.2.4",
  "key_dependencies": { "spring-security": "6.2.1" }
}
```

If version cannot be detected: log WARNING, set to `"unknown"` — all deprecation rules apply (conservative). Pass `detected_versions` to implementer, quality gate, and deprecation-refresh agents.

---

### §0.7 Deprecation Refresh (dispatch fg-140-deprecation-refresh)

After version detection, optionally refresh the deprecation registries so downstream checks use up-to-date data. This step is **advisory** — failures never block the pipeline.

**Condition:** Only dispatch if Context7 MCP is available (detected in §0.5) AND `detected_versions` contains at least one non-`"unknown"` version. Skip silently otherwise.

Dispatch `fg-140-deprecation-refresh` with:
[dispatch fg-140-deprecation-refresh]

```
Refresh deprecation registries for this project.

Detected versions:
[detected_versions from state.json]

Module frameworks in use:
[list of component frameworks from config]

Plugin root: ${CLAUDE_PLUGIN_ROOT}
```

**On success:** Log the refresh summary (entries added/updated). The updated `known-deprecations.json` files are used by Layer 1 pattern checks and the implementer's deprecation awareness.

**On failure/timeout:** Log INFO: `"Deprecation refresh skipped — {reason}."` Continue to convention resolution. Do NOT invoke the recovery engine — this agent is advisory.

---

### §0.8 Config Mode Detection

Detect whether `components:` is flat (single-service) or nested (multi-service):
- **Flat mode:** `components:` contains scalar fields (`language`, `framework`, etc.). Wrap in a default component named after `project_type` (e.g., `backend`).
- **Multi-service mode:** `components:` contains named entries, each with a `path:` field. Resolve each component independently.

Both modes produce the same `state.json.components` structure with named entries.

---

### §0.9 Multi-Component Convention Resolution

If `components:` is present in `forge.local.md`, resolve a convention stack per component. Runs after version detection, before interrupted-run check.

**Resolution order per component** (most specific wins): variant > framework-testing > framework > language > testing.

1. **Language:** `modules/languages/${language}.md` (skip if null)
2. **Framework:** `modules/frameworks/${framework}/conventions.md` (skip if null/stdlib)
3. **Variant:** `modules/frameworks/${framework}/variants/${variant}.md` (skip if absent)
4. **Framework testing:** `modules/frameworks/${framework}/testing/${testing}.md` (skip if absent)
5. **Generic testing:** `modules/testing/${testing}.md` (always if `testing` specified)
6. **Shared testing:** `testcontainers.md` (if database), `playwright.md` (if e2e)
7. **Optional layers** (`database`, `persistence`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`): generic `modules/{layer}/{value}.md` + framework binding `modules/frameworks/{fw}/{layer}/{value}.md`. Missing files silently skipped.

**Validation:** Missing required files (language, framework) → ERROR + abort. Missing optional → WARNING + skip. Nonsensical combinations (frontend + database, k8s + messaging, etc.) → WARN, do not block. Stack > 12 files → advisory WARNING.

Store resolved paths in `state.json.components.{name}.convention_stack`. Compute per-component `conventions_hash` (SHA256 first 8 chars of concatenated stack). Single-component projects skip this section entirely.

---

### §0.10 Check Engine Rule Cache

After resolving all convention stacks, generate per-component rule caches for the check engine:

1. For each component, collect all `rules-override.json` files from the convention stack:
   - Framework: `modules/frameworks/{fw}/rules-override.json`
   - Each active layer binding: `modules/frameworks/{fw}/{layer}/{value}.rules-override.json` (if exists)
   - Each active generic layer: `modules/{layer}/{value}.rules-override.json` (if exists)
2. Deep-merge all collected rules (later layers override earlier ones).
3. Write merged result to `.forge/.rules-cache-{component}.json`.
4. Write component path mapping to `.forge/.component-cache` (format: `path_prefix=component_name`).

---

### §0.11 Documentation Discovery (dispatch fg-130-docs-discoverer)

If `documentation.enabled` is `true` (default): dispatch `fg-130-docs-discoverer` with:
[dispatch fg-130-docs-discoverer]
- Project root path
- Documentation config from `forge.local.md` `documentation:` section
- Graph availability from `state.json.integrations.neo4j.available`
- Previous discovery timestamp from `state.json.documentation.last_discovery_timestamp`
- Related projects from `forge.local.md` `related_projects:`

Write discovery summary to `stage_0_docs_discovery.md`.
Store discovery metrics in `state.json.documentation` (files_discovered, sections_parsed, decisions_extracted, constraints_extracted, code_linkages, coverage_gaps, stale_sections, external_refs).

**On failure/timeout:** Log INFO: `"Documentation discovery skipped — {reason}."` Continue. Do NOT invoke the recovery engine — this step is advisory. Set `state.json.documentation` to `{}`.

---

### §0.12 Check Coverage Baseline (Test Bootstrapper)

If `test_bootstrapper` is configured in `forge.local.md` and `test_bootstrapper.enabled: true`:

1. Run the test command with coverage: `{commands.test} --coverage` or framework-equivalent
   - If coverage command fails or is not configured: skip this check, log INFO
2. Parse coverage percentage from output
3. Compare against `test_bootstrapper.coverage_threshold` (default: 30%)
4. If coverage < threshold:
   - Log INFO: "Coverage {X}% below threshold {Y}% — dispatching test bootstrapper"
   - Dispatch `fg-150-test-bootstrapper` with: project root, target coverage, component convention stack
     [dispatch fg-150-test-bootstrapper]
   - Wait for bootstrapper to complete
   - Re-run coverage to verify improvement
   - Proceed to Stage 1 (EXPLORE) regardless of whether threshold was reached (bootstrapper does its best)
5. If coverage >= threshold: proceed normally
6. If `test_bootstrapper` is not configured or `enabled: false`: skip entirely

This step is optional and only triggers when explicitly configured. It runs AFTER convention resolution (§0.9) so the bootstrapper gets the correct convention stack.

---

### §0.13 State Integrity Check

When `.forge/state.json` exists (interrupted run recovery), run `shared/state-integrity.sh .forge/` to validate cross-reference consistency of state files before attempting recovery. The validator checks required fields, counter bounds, pipeline state validity, orphaned checkpoints, stale locks, and evidence freshness.

- **ERRORs** (exit 1): State is corrupted. Attempt state reconstruction: back up the corrupted `state.json` to `.forge/state.json.pre-recover.{timestamp}`, then re-initialize state from scratch (§0.17). Log WARNING: "State integrity check failed — reconstructing state from scratch."
- **WARNINGs** (exit 0 with warnings): Log each warning as INFO and proceed with recovery. Warnings are advisory (e.g., orphaned checkpoints, stale locks).
- **Fresh run** (no existing `state.json`): Skip this validation entirely — state will be initialized from scratch at §0.17.

---

### §0.14 Check for Interrupted Runs

Read `.forge/state.json`. If it exists and `complete: false`:

1. **Check for expired NO-GO timeout**: If `story_state` is `VALIDATING` AND `abort_reason` is empty AND `stage_timestamps.validate` exists:
   - Compute elapsed time: `now - stage_timestamps.validate`
   - If elapsed > `validation.no_go_timeout_hours` (default: 24 hours): auto-abort — set `abort_reason` to `"NO-GO timeout expired after {hours}h"`, set `complete: true`, log WARNING: "Previous NO-GO state expired. Auto-aborting stale run." Remove `.forge/.lock` if present. Remove `.forge/worktree` if present.
   - If elapsed <= timeout: the NO-GO is still active — **escalate via AskUserQuestion** with header "Stale Run", question "A previous pipeline run received NO-GO at validation (started {validate_timestamp}, requirement: '{requirement}'). The NO-GO timeout has not expired ({elapsed}h / {timeout}h).", options: "Resume validation" (description: "Re-dispatch fg-210-validator with the existing plan"), "Re-plan" (description: "Go back to Stage 2 and redesign the approach"), "Abort" (description: "Cancel the stale run and start fresh").
2. Read `.forge/checkpoint-{storyId}.json` for task-level progress
3. **Validate checkpoint**: for each `tasks_completed` entry, check that created files exist on disk. Mark mismatches as remaining.
4. Run `git diff {last_commit_sha}` to detect manual filesystem drift
5. If drift detected: **warn user, ask whether to incorporate or discard**
6. Resume from first incomplete stage/task

---

### §0.15 --from Flag Precedence

If `--from=<stage>` is provided, it **overrides checkpoint recovery**. The orchestrator jumps to the specified stage regardless of what `state.json` says.

- `--from=0` is equivalent to a fresh start (no checkpoint recovery)
- Counters (`quality_cycles`, `test_cycles`, `verify_fix_count`) are NOT reset by `--from`. To reset counters, delete `.forge/state.json` and start fresh.
- If `--from` targets a stage that requires artifacts from a skipped stage (e.g., `--from=4` without a plan), fail at entry condition check and report which prerequisite is missing.

---

### §0.16 Pipeline Lock

Before initializing state, check for a concurrent pipeline run:

1. Check if `.forge/.lock` exists
2. If exists: read the lock file (JSON: `{ "pid": <number>, "session_id": "<uuid>", "started": "<ISO8601>", "requirement": "<text>" }`)
3. Check if the lock is stale:
   - If `started` is > 24 hours ago: treat as stale, remove lock, continue
   - If the PID is no longer running (check with `kill -0 <pid>` or `ps -p <pid>`): treat as stale, remove lock, continue
4. If lock is active: **escalate via AskUserQuestion** with header "Lock", question "Another pipeline run is active (started {time}, requirement: '{req}'). Running concurrently may corrupt state.", options: "Wait" (description: "Wait for the other run to complete before starting"), "Force takeover" (description: "Kill the other run's state and start fresh"), "Abort" (description: "Cancel this pipeline invocation").
5. If no lock or stale lock: create `.forge/.lock` with current session info
6. Clean up: delete `.forge/.lock` at LEARN stage completion or on graceful-stop

Do NOT create the lock file during `--dry-run` runs.

---

### §0.17 Initialize State

Initialize state using `forge-state.sh`:

```bash
bash shared/forge-state.sh init "${story_id}" "${requirement}" --mode ${mode} [--dry-run] --forge-dir .forge
```

This creates `state.json` v1.5.0 with all required defaults. The script handles:
- `complete: false`, `story_id` (kebab-case from requirement), `requirement` (verbatim), `mode` (from §0.1)
- `story_state: "PREFLIGHT"`, all counters to 0 (`quality_cycles`, `test_cycles`, `verify_fix_count`, `validation_retries`, `total_retries`)
- `"convergence"`: `"phase": "correctness"`, `"convergence_state": "IMPROVING"`, all counters 0, `"safety_gate_passed": false`
- `total_retries_max` from config (default 10)
- `stage_timestamps: { "preflight": "<now>" }`
- `integrations`: all `available: false` (updated by MCP detection in §0.23)
- `linear`, `linear_sync`, `recovery_budget`, `recovery`: empty/default per schema
- `dry_run`: from flag, `spec`: from `--spec` parsing, `bugfix`: empty defaults, `documentation`: empty defaults

After init, manually set fields not handled by the script:
- `detected_versions`, `conventions_hash`, `conventions_section_hashes`: from earlier PREFLIGHT steps
- `ticket_id`, `branch_name`, `tracking_dir`: set after worktree creation (§0.18)

Pre-recover backup files (`.forge/*.pre-recover.*`) are cleaned by fg-700-retrospective (files older than 7 days removed at start of each run's retrospective phase).

---

### §0.18 Create Worktree

Skip if `--dry-run` (no worktree needed for read-only analysis).

**Pre-creation cleanup:** Before creating a new worktree, detect and handle stale worktrees from interrupted runs:

```
sub_task = TaskCreate("Checking for stale worktrees", activeForm="Checking for stale worktrees")
stale_result = dispatch fg-101-worktree-manager "detect-stale"
TaskUpdate(sub_task, status="completed")
```

If `STALE_WORKTREES_DETECTED: N` where N > 0:
- For each stale worktree, dispatch cleanup: `fg-101-worktree-manager "cleanup <worktree_path> --delete-branch"`
- If cleanup fails (uncommitted changes), ask the user via `AskUserQuestion` whether to force-remove or abort
- Log each stale worktree cleanup as INFO in stage notes

Dispatch `fg-101-worktree-manager` to create the worktree:

```
sub_task = TaskCreate("Creating worktree", activeForm="Creating worktree")
result = dispatch fg-101-worktree-manager "create ${ticket_id} ${slug} --mode ${mode} --base-dir ${base_dir}"
TaskUpdate(sub_task, status="completed")
```

**Input resolution before dispatch:**
- `ticket_id`: resolved from `--spec` ticket, `--ticket` flag, or kanban tracking (create new ticket if tracking initialized). Pass `null` if tracking not initialized.
- `slug`: slugified requirement title
- `mode`: pipeline mode (standard/migration/bootstrap/bugfix) — determines branch type (feat/migrate/chore/fix)
- `base_dir`: `.forge/worktree` (standard mode) or `{run_dir}/worktree/` (sprint mode, when `--run-dir` provided)

Read `worktree_path`, `branch_name`, and `shallow_clone` from stage notes written by fg-101.
Store `ticket_id`, `branch_name`, `tracking_dir` (`.forge/tracking`), and `shallow_clone` in state.json. Set working directory to `worktree_path` for all subsequent stages.

---

### §0.18a Bugfix Source Resolution (bugfix mode only)

Skip if `mode != "bugfix"`.

1. Read bug source from the dispatch prompt: `source` (kanban/linear/description) and `source_id`
2. **If source is "kanban":** Read ticket file from `.forge/tracking/`, extract description, steps to reproduce, error messages
3. **If source is "linear":** Read Linear issue via Linear MCP (if available), extract title, description, comments, labels
4. **If source is "description":**
   - Create kanban ticket with `type: bugfix` directly in `in-progress/` via `tracking-ops.sh create_ticket`
   - Store the new ticket ID as `source_id`
5. Store `bugfix.source` and `bugfix.source_id` in `state.json`
6. Ensure branch type was set to `fix` in §0.18 (worktree branch naming)

---

### §0.19 Create Visual Task Tracker

Use `TaskCreate` to create one task per pipeline stage. This gives the user a real-time visual progress tracker with checkboxes that update as stages complete.

Create all 10 tasks upfront in a single batch:

```
TaskCreate: subject="Stage 0: Preflight",      description="Load config, detect versions, apply learnings",           activeForm="Running preflight checks"
TaskCreate: subject="Stage 1: Explore",         description="Map domain models, tests, and patterns",                  activeForm="Exploring codebase"
TaskCreate: subject="Stage 2: Plan",            description="Risk-assessed implementation plan with stories and tasks", activeForm="Planning implementation"
TaskCreate: subject="Stage 3: Validate",        description="7-perspective plan validation",                            activeForm="Validating plan"
TaskCreate: subject="Stage 4: Implement",       description="TDD loop: scaffold, RED, GREEN, REFACTOR",                activeForm="Implementing (TDD)"
TaskCreate: subject="Stage 5: Verify",          description="Build, lint, static analysis, full test suite",            activeForm="Verifying build and tests"
TaskCreate: subject="Stage 6: Review",          description="Multi-agent quality review with scoring",                  activeForm="Reviewing quality"
TaskCreate: subject="Stage 7: Docs",            description="Update docs, KDoc/TSDoc on new public interfaces",         activeForm="Updating documentation"
TaskCreate: subject="Stage 8: Ship",            description="Branch, commit, PR with quality gate results",             activeForm="Creating pull request"
TaskCreate: subject="Stage 9: Learn",           description="Retrospective, config tuning, trend tracking",             activeForm="Running retrospective"
```

**Stage lifecycle — update tasks as you progress:**
- When **entering** a stage: `TaskUpdate(taskId, status="in_progress")`
- When **completing** a stage: `TaskUpdate(taskId, status="completed")`
- If `--from` skips stages: immediately mark skipped stages as `completed` (they show as done)
- If a stage fails and the pipeline escalates: leave the failing task as `in_progress` (shows the user where it stopped)

Mark Preflight as `in_progress` now (it was just completed inline). After Preflight completes, mark it `completed` and move on.

Record run start: requirement summary, timestamp, domain area (inferred from requirement).

---

### §0.20 Kanban Status Transitions

At stage boundaries, update kanban ticket status. All operations use `shared/tracking/tracking-ops.sh`. If `.forge/tracking/` does not exist or `state.json.ticket_id` is null, skip silently.

| Orchestrator Event | Kanban Action |
|-------------------|---------------|
| PREFLIGHT complete, worktree created | `move_ticket` to `in-progress/` (done in §0.18) |
| REVIEW stage entry | `move_ticket` to `review/` |
| SHIP — PR created | `update_ticket_field` set `pr` to PR URL |
| SHIP — PR merged | `move_ticket` to `done/` |
| PR rejected → re-enter IMPLEMENT | `move_ticket` back to `in-progress/` |
| Abort / failure | `move_ticket` to `backlog/`, append Activity Log with abort reason |
| LEARN complete | Verify ticket in `done/`, regenerate board |

After every `move_ticket` call, also call `generate_board` to regenerate `board.md`.

---

### §0.21 Runtime Convention Lookup

When any stage needs conventions for a specific file path:
1. Match the file path against `state.json.components` entries by longest `path:` prefix match.
2. If matched: use that component's `convention_stack`.
3. If not matched: check for a `shared:` component. If present, use its stack.
4. If still not matched: use language-level conventions only (safe default).

---

### §0.22 Graph Context (Optional)

When `state.json.integrations.neo4j.available` is true, the orchestrator pre-queries the Neo4j knowledge graph at stage boundaries and passes results as `graph_context` in stage notes. This gives downstream agents structural codebase understanding without requiring Neo4j MCP access.

| Stage | Pre-queries | Passed to |
|---|---|---|
| PREFLIGHT | Convention stack resolution, dependency-to-module mapping | All downstream agents |
| EXPLORE | Blast radius for requirement scope, enriched symbol data | fg-200-planner |
| PLAN | Impact analysis for planned changes | fg-210-validator, fg-250-contract-validator |
| IMPLEMENT | Per-task file dependency graph | fg-300-implementer, fg-310-scaffolder |
| REVIEW | Architectural boundary graph for changed files | fg-400-quality-gate → review agents |

See `shared/graph/query-patterns.md` for the Cypher templates used. If Neo4j is unavailable, all stages proceed normally using grep/glob-based analysis.

**Mid-run graph failure:** If a graph query fails after Neo4j was initially available (e.g., container stopped, connection lost):
1. Mark `state.json.integrations.neo4j.available = false` for the remainder of the run
2. Log WARNING in stage notes: "Neo4j became unavailable mid-run. Falling back to grep/glob analysis."
3. Do NOT invoke recovery engine for graph failures — handle inline as graceful degradation
4. Continue the pipeline without graph context for all subsequent stages

---

### §0.23 MCP Detection

Parse `Available MCPs:` from the `forge-run` dispatch prompt (comma-separated: Linear, Playwright, Slack, Figma, Context7). Fallback: read `.mcp.json` keys under `mcpServers`. Store in `state.json.integrations.{name}.available`. Report OK/MISSING with install commands. Auto-provisioning rules apply per `shared/mcp-provisioning.md`. Pipeline runs without any MCPs.

#### MCP Mid-Run Health

First MCP failure → set `integrations.{name}.available: false`, add to `recovery.degraded_capabilities[]`. Subsequent dispatches skip without re-checking. No explicit health pings.

#### Linear Operation Resilience

Attempt → on failure: retry once (3s delay) → if retry fails: log to `linear_sync.failed_operations[]`, set `in_sync: false`, continue. First post-PREFLIGHT failure → disable Linear for rest of run. Recovery engine NOT invoked for MCP failures (per `error-taxonomy.md`).

---

## PREFLIGHT Completion

After all boot steps complete, transition to the next stage:

```bash
bash shared/forge-state.sh transition preflight_complete --guard "dry_run=${is_dry_run}" --forge-dir .forge
```

Then load `agents/fg-100-orchestrator-execute.md` for stages 1-6.
