# Stage Contract

This document defines the 10 pipeline stages as a contract between the orchestrator (`pl-100-orchestrator`) and all agents. It is the authoritative reference for stage numbering, naming, transitions, data flow, and entry/exit conditions.

Any agent or module that needs to understand where it fits in the pipeline should read this document.

## Stage Overview

| Stage | Name | Agent(s) | story_state | Entry Condition | Exit Condition |
|-------|------|----------|-------------|-----------------|----------------|
| 0 | PREFLIGHT | inline + `pl-130-docs-discoverer` + conditional: `pl-140-deprecation-refresh`, `pl-150-test-bootstrapper` | `PREFLIGHT` | User invokes `/pipeline-run` with a requirement; concurrent run lock acquired | Config loaded, convention stacks resolved per component, rule caches generated, state initialized, documentation discovered, deprecation rules refreshed, test baseline established |
| 1 | EXPLORE | `explore_agents` from config | `EXPLORING` | Config loaded successfully | Exploration results summarized in stage notes |
| 2 | PLAN | `pl-200-planner` | `PLANNING` | Exploration complete | Plan with risk level, stories, tasks, and parallel groups |
| 3 | VALIDATE | `pl-210-validator` + conditional: `pl-250-contract-validator` | `VALIDATING` | Plan exists | GO verdict (or NO-GO escalated to user); cross-repo contracts validated if applicable |
| 4 | IMPLEMENT | `pl-310-scaffolder` + `pl-300-implementer` + conditional: `pl-320-frontend-polisher` | `IMPLEMENTING` | Plan validated with GO verdict; worktree created on a unique branch; working tree clean | All tasks completed inside worktree (or failed after max retries) |
| 5 | VERIFY | inline (Phase A) + `pl-500-test-gate` (Phase B) | `VERIFYING` | Implementation complete | Build + lint + tests all pass |
| 6 | REVIEW | `pl-400-quality-gate` | `REVIEWING` | Verification passed | Quality verdict PASS or CONCERNS |
| 7 | DOCS | `pl-350-docs-generator` | `DOCUMENTING` | Review passed | Documentation updated; no new public interfaces lack documentation; coverage gaps reduced or explained |
| 8 | SHIP | `pl-600-pr-builder` + conditional: `pl-650-preview-validator`, `infra-deploy-verifier`, `pl-710-feedback-capture` (on PR rejection) | `SHIPPING` | Documentation done | PR created; preview validated (if enabled); infra verified (if applicable); presented to user; worktree merged and cleaned up |
| 9 | LEARN | `pl-700-retrospective` + `pl-720-recap` | `LEARNING` | PR approved by user (or rejected with feedback captured) | Run logged, config updated, report written |

**Convention file defensive read:** Each agent that reads the conventions file handles the case where it becomes unreadable between stages. PREFLIGHT validates the path; each agent does a defensive Read and proceeds with universal defaults if it fails.

---

## Stage Details

### Stage 0: PREFLIGHT

**Agent:** Inline + `pl-130-docs-discoverer` (documentation discovery dispatched after config resolution)
**story_state:** `PREFLIGHT`

**Entry condition:** User invokes `/pipeline-run` with a requirement string.

**Inputs:**
- User's requirement string (from `/pipeline-run` argument)
- `dev-pipeline.local.md` (static project config)
- `pipeline-config.md` (mutable runtime params)
- `pipeline-log.md` (PREEMPT items, run history)
- `.pipeline/state.json` (if exists -- interrupted run detection)

**Actions:**
1. Read and parse `dev-pipeline.local.md` config (agents, commands, conventions, module).
2. Read `pipeline-config.md` (max_fix_loops, auto_proceed_risk, hotspots). Apply parameter resolution order: `pipeline-config.md` > `dev-pipeline.local.md` > plugin defaults.
3. Read `pipeline-log.md` (PREEMPT items for the domain area, last 3 runs).
4. Check `.pipeline/state.json` for interrupted runs:
   - If `complete: false`: validate checkpoint artifacts, detect git drift via `git diff` against `last_commit_sha`.
   - If drift detected: warn user, ask whether to incorporate or discard.
   - Resume from first incomplete stage.
5. Apply `--from` flag if provided (overrides checkpoint recovery).
6. Initialize `.pipeline/state.json` with all counters at 0.
7. Create task list (10 stages).
8. Detect config mode (flat vs. multi-service components:)
9. Resolve convention stacks per component (language, framework, variant, testing + optional crosscutting layers: database, persistence, migrations, api_protocol, messaging, caching, search, storage, auth, observability)
10. Run layer combination validation, log warnings for nonsensical configurations
11. Detect versions for all layers from manifest files, store in detected_versions.key_dependencies
12. Generate per-component rule cache (.pipeline/.rules-cache-{component}.json)
13. Write component path mapping (.pipeline/.component-cache)
14. If `documentation.enabled` is `true` (default): dispatch `pl-130-docs-discoverer` with project root, documentation config, graph availability, previous discovery timestamp, and related projects. Write discovery summary to `stage_0_docs_discovery.md`. Store metrics in `state.json.documentation`.

**Outputs:**
- Initialized `.pipeline/state.json`
- Parsed config (passed as context to subsequent stages)
- Matched PREEMPT items (recorded in `preempt_items_applied`)

**Exit condition:** Config loaded, convention stacks resolved per component, rule caches generated, state initialized, documentation discovered (or skipped if `documentation.enabled` is `false`).

**Documentation discovery failure:** If `documentation.enabled` is `true` but `pl-130-docs-discoverer` times out or returns an error: log WARNING in stage notes, set `state.json.documentation.discovery_error = true`, and proceed. Downstream agents (pl-350-docs-generator, docs-consistency-reviewer) check this flag and operate with degraded documentation context — they skip cross-referencing and coverage gap analysis but still generate docs for changed files.

---

### Stage 1: EXPLORE

**Agent(s):** Configured in `dev-pipeline.local.md` under `explore_agents` (default: `feature-dev:code-explorer` + `Explore`)
**story_state:** `EXPLORING`

**Entry condition:** Config loaded successfully at PREFLIGHT.

**Inputs:**
- User's requirement
- PREEMPT items for the domain area
- `conventions_file` path from config

**Actions:**
1. Dispatch exploration agents in parallel:
   - **Primary agent:** Maps domain models, architecture, and patterns relevant to the requirement.
   - **Secondary agent:** Maps existing tests, fixtures, and coverage gaps.
2. Summarize results: file paths, pattern files, test classes, identified gaps.

**Outputs:**
- `stage_1_notes_{storyId}.md` -- exploration summary
- Structured list of: relevant source files, test files, pattern files, domain model files, identified gaps

**Exit condition:** Exploration results summarized and available for the planner.

**On failure/timeout:** Exploration is advisory, not blocking. If all exploration agents time out or fail:
1. Log WARNING in stage notes: `"Exploration failed: {reason}. Proceeding with degraded context."`
2. Set `state.json.exploration_degraded: true`
3. Proceed to Stage 2 (PLAN). The planner operates with reduced context — it may produce a less optimal plan.

---

### Stage 2: PLAN

**Agent:** `pl-200-planner`
**story_state:** `PLANNING`

**Entry condition:** Exploration complete (Stage 1 outputs available).

**Inputs:**
- Exploration results (summarized, not raw file contents)
- PREEMPT learnings for the domain area
- Domain hotspots from `pipeline-config.md`
- `conventions_file` content
- `scaffolder.patterns` from config

**Actions:**
1. Assess risk: LOW / MEDIUM / HIGH based on what is touched (security, billing, migration, API contract, internal-only).
2. Decompose into 1-3 stories with Given/When/Then acceptance criteria.
3. Break stories into 2-8 tasks with parallel groups (max 3 groups).
4. Design test strategy.
5. Reference `scaffolder.patterns` from config for file paths.
6. Challenge the requirement: evaluate whether the requested approach is optimal, propose alternatives if better options exist.

**Outputs:**
- Structured plan: risk level, stories (with acceptance criteria), tasks (with parallel groups), test strategy
- `stage_2_notes_{storyId}.md` -- planning decisions and rationale
- Updated `state.json`: `risk_level`, `domain_area`

**Exit condition:** Complete plan with risk assessment, stories, tasks, parallel groups, and test strategy.

---

### Stage 3: VALIDATE

**Agent:** `pl-210-validator`
**story_state:** `VALIDATING`

**Entry condition:** Plan exists (Stage 2 output available).

**Inputs:**
- Plan from Stage 2
- `validation.perspectives` from config (7 perspectives)
- `conventions_file` content (module-specific conventions)
- Source files referenced in the plan

**Actions:**
1. Run 7 validation perspectives (Architecture, Security, Edge Cases, Test Strategy, Conventions, Approach Quality, Documentation Consistency). Perspective content comes from the module's `conventions.md`. Approach Quality evaluates whether the proposed solution is the simplest adequate approach and whether the Challenge Brief justifies complexity.
2. Return verdict: GO / REVISE / NO-GO. Plans with missing Challenge Briefs get REVISE.
3. On REVISE: return specific issues for the planner to address.

**Outputs:**
- Verdict: GO, REVISE, or NO-GO
- Validation findings (per perspective)
- `stage_3_notes_{storyId}.md` -- validation analysis

**Exit condition (GO):** Proceed to Stage 4.

**On REVISE:** Loop back to Stage 2 (PLANNING). Increment `validation_retries`. Max retries: `validation.max_validation_retries` (default: 2). After max retries with continued REVISE, escalate as NO-GO.

**On NO-GO:** Escalate to user. Pipeline pauses. If the user does not respond within 24 hours (configurable via `validation.no_go_timeout_hours`, default: 24), the orchestrator auto-aborts: clean up the worktree if created, set `state.json.complete = true` with `abort_reason: "NO-GO timeout"`, and log a WARNING in stage notes. The stale timeout is checked by PREFLIGHT of any subsequent `/pipeline-run` invocation (not by a background process).

**Decision gate:** Compare plan `risk_level` against `risk.auto_proceed` from config:
- Risk <= threshold: proceed automatically on GO.
- Risk > threshold: show plan to user, ask for approval before proceeding.

---

### Stage 4: IMPLEMENT

**Agent(s):** `pl-310-scaffolder` + `pl-300-implementer`
**story_state:** `IMPLEMENTING`

**Entry condition:** Plan validated with GO verdict (Stage 3). Worktree created at `.pipeline/worktree` on a unique branch; working tree clean.

**Pre-entry checks:**
1. Check `git branch --list pipeline/{story-id}` — if the branch already exists, append epoch suffix (e.g., `pipeline/{story-id}-1711100000`).
2. Check for stale worktree at `.pipeline/worktree` — if found, remove it and log WARNING.
3. Verify working tree is clean (`git status --porcelain` returns empty).

**Inputs:**
- Validated plan with tasks and parallel groups
- `scaffolder.patterns` from config
- `conventions_file` content
- `commands.build` and `commands.test_single` from config
- `context7_libraries` from config (for documentation prefetch)

**Actions:**
1. Git checkpoint: `git add -A && git commit -m "wip: pipeline checkpoint pre-implement"`. Record SHA in `state.json.last_commit_sha`.
2. Documentation prefetch: resolve and query context7 libraries for current API docs.
3. **Parallel Conflict Detection** — before dispatching each parallel group:
   ```
   BEFORE dispatching parallel group G:
     1. For each task T in G:
        - If scaffolder ran: read files_created + files_modified from scaffolder output
        - Else: read task.files from plan (flat list of file paths)
     2. Build conflict map: { "path/file.kt": ["T001", "T003"] }
     3. For each file with >1 task:
        - Keep first task (by plan order) in group G
        - Move all other tasks claiming that file to new sub-group G'
        - Log: "Conflict: {file} claimed by {tasks}. Serialized {moved_tasks}."
     4. Dispatch G (now conflict-free)
     5. After G completes, run conflict check on G' (recursive)
     6. Report total serializations in stage notes
   ```
4. For each parallel group (sequential order, after conflict detection):
   - For each task in group (concurrent up to `implementation.parallel_threshold`):
     a. `pl-310-scaffolder` generates boilerplate (if `scaffolder_before_impl: true`).
     b. Write tests (RED phase -- tests that define expected behavior, expected to fail).
     c. `pl-300-implementer` writes implementation to pass tests (GREEN) + refactors.
     d. Verify with `commands.build` or `commands.test_single`.
5. Write checkpoint (`checkpoint-{storyId}.json`) after each task.
6. If a task fails after `max_fix_loops`: record as failed, continue with remaining tasks.

**Outputs:**
- Source files (created and modified)
- Test files (created and modified)
- `checkpoint-{storyId}.json` -- task-level progress
- `stage_4_notes_{storyId}.md` -- implementation decisions
- Updated `state.json.last_commit_sha`

**Exit condition:** All tasks completed (pass or fail after max retries). At least one task must pass for the pipeline to proceed. All implementation completed inside worktree.

---

### Stage 5: VERIFY

**Agent(s):** Inline (Phase A) + `pl-500-test-gate` (Phase B)
**story_state:** `VERIFYING`

**Entry condition:** Implementation complete (Stage 4 -- all tasks attempted).

**Entry guard:** At least one implementation task must have completed successfully. If all tasks failed after max retries, the orchestrator escalates to the user instead of entering VERIFY:

The orchestrator **escalates via AskUserQuestion** with header "Blocked", question "All implementation tasks failed. No code to verify. Breakdown: {failed_tasks}.", options: "Re-plan" (review errors and redesign approach from Stage 2), "Retry" (re-run from Stage 4 with adjusted approach), "Abort" (stop the pipeline run).

**Inputs:**
- `commands.build`, `commands.lint`, `commands.format` from config
- `inline_checks` from config (scripts or skills)
- `test_gate.command` from config
- `test_gate.analysis_agents` from config

**Phase A -- Build & Lint (inline, fail-fast):**
1. Before running build/lint, read `.pipeline/.check-engine-skipped`. If present and count > 0: report in stage notes. Delete marker after reading. Informational only — VERIFY runs full checks regardless.
2. Run `commands.build` (compile check).
3. Run `commands.lint` (lint + static analysis).
4. Run `inline_checks` from config (module scripts or skills).
5. On failure: analyze error, fix, re-run from failed step. Increment `verify_fix_count`. Max: `implementation.max_fix_loops`.

**Phase B -- Test Gate (`pl-500-test-gate`):**
1. Run `test_gate.command` (full test suite).
2. If tests pass: dispatch `test_gate.analysis_agents` for coverage and quality analysis.
3. If tests fail: dispatch `pl-300-implementer` with failing test details, then re-run tests. Increment `test_cycles`. Max: `test_gate.max_test_cycles`.

**Outputs:**
- Build/lint pass confirmation
- Test results (pass/fail, coverage report)
- `stage_5_notes_{storyId}.md` -- verification details, fix loop history
- Updated counters: `verify_fix_count`, `test_cycles`

**Exit condition:** Build passes, lint passes, all tests pass.

**Convergence role:** Stage 5 serves as Phase 1 (Correctness) of the convergence engine. The orchestrator enters Phase 1 after IMPLEMENT completes. Phase 1 exits when `verify_result.tests_pass AND verify_result.analysis_pass` — where `analysis_pass` is `true` when all Phase B analysis agents return without CRITICAL findings and the overall verdict is not FAIL (see `convergence-engine.md` for the full definition). If Phase A fails (build/lint error), Phase B does not run and `analysis_pass` is not evaluated — this is classified as `PHASE_A_FAILURE` and the convergence engine routes back to IMPLEMENT with build/lint errors. When VERIFY passes fully, the convergence engine transitions to Phase 2 (Perfection → Stage 6). Stage 5 is also the safety gate — re-invoked after Phase 2 converges to catch regressions. See `shared/convergence-engine.md`.

**Verify result classification:** The verify stage produces one of three outcomes consumed by the convergence engine:
- **PHASE_A_FAILURE**: Build or lint failed before tests ran. Phase B (test gate) is not executed. `analysis_pass` is not evaluated. Routes to IMPLEMENT with build/lint errors.
- **Tests fail** (`tests_pass: false`): Build/lint passed but tests failed. Routes to IMPLEMENT with failing test details.
- **Full pass** (`tests_pass: true AND analysis_pass: true`): All verification passed. Transitions to Phase 2 (Perfection) or confirms safety gate.

**Phase A failure escalation:** If `verify_fix_count >= max_fix_loops`, the pipeline escalates to the user. Each Phase A retry increments `total_retries`. Escalation format:

The orchestrator **escalates via AskUserQuestion** with header "Blocked", question "Build/lint fix loop exhausted ({verify_fix_count}/{max_fix_loops}). Last error: {error_summary}.", options: "Fix manually" (fix the issue and resume from Stage 5), "Re-plan" (go back to Stage 2 and redesign the approach), "Abort" (stop the pipeline run).

**Phase B failure escalation:** If `test_cycles >= max_test_cycles`, the orchestrator **escalates via AskUserQuestion** with header "Blocked", question "Test fix loop exhausted ({test_cycles}/{max_test_cycles}). Failing tests: {test_summary}.", options: "Fix manually" (fix the failing tests and resume from Stage 5), "Re-plan" (go back to Stage 2 and redesign the approach), "Abort" (stop the pipeline run).

---

### Stage 6: REVIEW

**Agent:** `pl-400-quality-gate`
**story_state:** `REVIEWING`

**Entry condition:** Verification passed (Stage 5 -- build + lint + tests all green).

**Inputs:**
- `quality_gate` config (batch definitions, inline_checks, max_review_cycles)
- Changed files from implementation
- `conventions_file` content

**Actions:**
1. For each `quality_gate.batch_N` in config: dispatch all agents in the batch in parallel. Wait for batch completion before starting next batch.
2. Run `quality_gate.inline_checks` (scripts or skills).
3. Deduplicate findings by `(file, line, category)` -- keep highest severity (see `scoring.md`).
4. Score using formula: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`.
5. Return score and findings to the orchestrator. The **convergence engine** decides whether to iterate (see `shared/convergence-engine.md`):
   - Score = `target_score` → transition to safety gate (VERIFY one more time)
   - Score improving → dispatch IMPLEMENT with findings, then REVIEW again
   - Score plateaued → declare convergence, proceed to safety gate with documented unfixables
   - Score regressing beyond `oscillation_tolerance` → escalate to user
6. **Score Oscillation Handling** — integrated into convergence engine's REGRESSING state detection. See `convergence-engine.md` algorithm.

**Outputs:**
- Quality verdict: PASS, CONCERNS, or FAIL
- Deduplicated finding list with scores
- Score history (score per cycle)
- `stage_6_notes_{storyId}.md` -- review report

**Exit condition (converged at target):** Score = `target_score` (default 100) and safety gate passed. Proceed to Stage 7.

**Exit condition (converged below target):** Score plateaued below target. The convergence engine applies the score escalation ladder (see `convergence-engine.md`):

| Plateau Score | Verdict | Action |
|---|---|---|
| >= `pass_threshold` (default 80) | PASS | Proceed directly to safety gate. Sub-band 95-99: no follow-up tickets. Sub-band 80-94: architectural WARNINGs get follow-up tickets. |
| >= `concerns_threshold` AND < `pass_threshold` (default 60-79) | CONCERNS | Escalate to user for guidance before proceeding to safety gate. User may accept, guide further fixes, or abort. |
| < `concerns_threshold` (default < 60) | FAIL | Escalate to user. Recommend abort or replan. Do NOT proceed to safety gate. |

Safety gate must still pass after plateau acceptance. Unfixable findings are documented in `convergence.unfixable_findings`.

**Exit condition (FAIL):** Any CRITICAL remaining after convergence exhaustion → escalate to user.

**On fix cycle:** Convergence engine dispatches IMPLEMENT with findings, then REVIEW again. Increment `quality_cycles` (inner cap) and `convergence.total_iterations` (outer cap). See `shared/convergence-engine.md`.

---

### Stage 7: DOCS

**Agent:** `pl-350-docs-generator`
**story_state:** `DOCUMENTING`

**Entry condition:** Review passed with PASS or CONCERNS verdict (Stage 6).

**Inputs:**
- Changed files from implementation
- Quality verdict and score from Stage 6
- Plan stage notes (Challenge Brief content for ADR generation)
- Doc discovery summary (`stage_0_docs_discovery.md`)
- Documentation config from `dev-pipeline.local.md` `documentation:` section
- Framework conventions

**Actions:**
1. Dispatch `pl-350-docs-generator` with changed files, quality verdict, plan notes, discovery summary, documentation config, and framework conventions.
2. Generator updates docs affected by changed files (graph-guided if available).
3. Generator creates ADRs for significant decisions from the plan.
4. Generator updates changelog with this run's changes.
5. Generator updates OpenAPI spec if API endpoints changed.
6. Generator verifies KDoc/TSDoc on all new public interfaces.
7. Generator creates missing docs for new modules if `auto_generate` is enabled.
8. All output written to `.pipeline/worktree`.

**Outputs:**
- Generated/updated documentation files in worktree
- `stage_7_notes_{storyId}.md` -- documentation generation summary
- Updated knowledge graph documentation nodes (if graph available)
- Updated docs index (`.pipeline/docs-index.json`)

**Exit condition:** Documentation updated; no new public interfaces lack documentation; coverage gaps reduced or explained.

**On failure/timeout:** Documentation generation is best-effort. If `pl-350-docs-generator` times out or fails:
1. Log WARNING in stage notes: `"DOC generation failed: {reason}. Proceeding to SHIP without generated docs."`
2. Set `state.json.documentation.generation_error: true`
3. Proceed to Stage 8 (SHIP). Missing documentation is not blocking — it can be addressed in a follow-up.
4. The retrospective (Stage 9) will flag the documentation failure for the user.

---

### Stage 8: SHIP

**Agent:** `pl-600-pr-builder`
**story_state:** `SHIPPING`

**Entry condition:** Documentation done (Stage 7).

**Inputs:**
- All changed files
- Quality gate verdict and score
- Test results
- Story metadata (requirement, risk level)

**Actions:**
1. Create branch: `feat/*`, `fix/*`, or `refactor/*` based on requirement type.
2. Stage relevant files (exclude `.claude/`, `build/`, `.env`, `.pipeline/`, `node_modules/`).
3. Create conventional commit (no AI attribution, no Co-Authored-By).
4. Push branch and create PR via `gh pr create`.
5. PR body includes: Summary, Quality Gate verdict + score, Test Plan, Pipeline Run metrics.
6. Present PR to user for approval.

**Outputs:**
- Git branch
- Commit(s)
- Pull request (URL)
- `stage_8_notes_{storyId}.md` -- PR details

**Exit condition:** PR created; worktree merged if no conflicts, or PR created with conflict flag if base branch diverged. Worktree cleaned up on successful merge (or preserved on failure/conflict).

**On user approval:** Proceed to Stage 9 (LEARN).

**On user rejection/feedback:**

`pl-710-feedback-capture` classifies feedback into one of two paths using these heuristics. Default to `implementation` when ambiguous.

**Design feedback signals** (route to Stage 2 — PLAN):
- References: architecture, approach, decomposition, scope, strategy, wrong decision, missing story
- Structural: "should have split into N tasks", "this needs a different approach", "wrong abstraction"
- Scope: "missing feature X", "should also handle Y", "need to add Z endpoint"

**Implementation feedback signals** (route to Stage 4 — IMPLEMENT):
- References: specific files, line numbers, test cases, class names, function names
- Behavioral: "this function should return X", "test doesn't cover Y", "logic is wrong at Z"
- Quality: "error handling missing for X", "needs null check", "performance issue in loop"

When feedback contains signals from both categories, count the signals:
- Design signals outnumber implementation signals by 2:1 or more → classify as `design`
- Implementation signals outnumber design signals, or ratio is roughly equal → classify as `implementation` (safer — less disruption)
- If the feedback contains a clear scope change (e.g., "split into 2 features", "add a new endpoint") regardless of signal count → classify as `design`
- If ambiguous and the user's feedback is short (< 3 sentences), prefer `implementation` — short feedback typically targets specific code issues

**Path A — `implementation` feedback** (references specific files, code behavior, test cases):
1. Dispatch `pl-710-feedback-capture` to record the correction structurally.
2. Reset `quality_cycles` and `test_cycles` to 0.
3. Increment `total_retries` by 1.
4. Re-enter Stage 4 (IMPLEMENT) with feedback context.

**Path B — `design` feedback** (references wrong approach, wrong decomposition, missing stories, architectural direction):
1. Dispatch `pl-710-feedback-capture` to record the correction structurally.
2. Reset stage-specific counters (`quality_cycles`, `test_cycles`, `verify_fix_count`, `validation_retries`) to 0. Do NOT reset `total_retries`.
3. Increment `total_retries` by 1.
4. Re-enter Stage 2 (PLAN) with feedback as planner input.

**Cross-stage re-entry validation:**

Before re-entering Stage 2 or Stage 4 from Stage 8, the orchestrator validates:

1. **Worktree availability:** If re-entering Stage 4 (implementation path), verify `.pipeline/worktree` still exists and is a valid git worktree. If the worktree was cleaned up (e.g., by a previous ship attempt), recreate it from the pipeline branch before dispatching the implementer.
2. **Feedback loop detection:** Track `state.json.feedback_loop_count` — incremented on each PR rejection re-entry. "Same classification" means the string value of `feedback_classification` matches the previous rejection (e.g., both `"design"` or both `"implementation"`) — it does NOT require the same specific issue, only the same category. If the same `feedback_classification` is received 2 consecutive times (i.e., user rejected → re-plan → re-implement → re-ship → rejected again with same classification), escalate:

   The orchestrator **escalates via AskUserQuestion** with header "Loop", question "Feedback loop detected: {classification} feedback received {count} consecutive times. The pipeline re-planned/re-implemented but the same type of feedback recurred.", options: "Guide" (provide specific guidance — the user's text will be prepended to the next stage's input as high-priority context), "Start fresh" (abort current run and begin a new `/pipeline-run`), "Override" (proceed with current state despite recurring feedback — reset `feedback_loop_count` to 0 and continue).

   Reset `feedback_loop_count` to 0 when `feedback_classification` changes between rejections.
3. **Scaffold outputs:** If re-entering Stage 4, verify that scaffolder outputs from the initial implementation are still present in the worktree. If missing (e.g., worktree was recreated), re-run the scaffolder before dispatching the implementer.

---

### Stage 9: LEARN

**Agent(s):** `pl-700-retrospective` + `pl-720-recap`
**story_state:** `LEARNING`

**Entry condition:** PR approved by user. Also entered (with partial data) if PR is rejected and feedback is captured, after the re-run completes.

**Inputs:**
- Full run summary (all stage notes, counters, timestamps)
- `pipeline-log.md` (existing PREEMPT items and run history)
- `pipeline-config.md` (current tunable parameters)
- `.pipeline/reports/` (previous run reports for trend comparison)
- `.pipeline/feedback/` (user corrections from this run)

**Actions:**
1. Analyze run: failures, fixes, review findings, implementation notes.
2. Extract learnings: PREEMPT (preventable checks), PATTERN (observed approach), TUNING (config adjustment).
3. Append run entry to `pipeline-log.md`.
4. Update `pipeline-config.md` (metrics, domain hotspots).
5. Apply auto-tuning rules:
   - `avg_fix_loops > max_fix_loops - 0.5` for 3+ runs -> increment `max_fix_loops`
   - `avg_fix_loops < 1.0` for 5+ runs -> decrement `max_fix_loops` (min: 2)
   - Domain with 3+ issues -> add domain-specific PREEMPT
   - `success_rate < 60%` over 5 runs -> set `auto_proceed` to LOW
   - `success_rate = 100%` over 5 runs -> set `auto_proceed` to HIGH
6. Track trends against previous runs in `.pipeline/reports/`.
7. Propose CLAUDE.md updates if a pattern repeated 3+ times.
8. Consolidate feedback directory if >20 entries.
9. Detect PREEMPT_CRITICAL escalations (3+ occurrences -> suggest hook/rule).
10. Write pipeline report to `.pipeline/reports/pipeline-{date}.md`.
11. Set `state.json.complete` to `true`.

**Outputs:**
- Updated `pipeline-log.md`
- Updated `pipeline-config.md`
- `.pipeline/reports/pipeline-{date}.md`
- `stage_final_notes_{storyId}.md`
- `state.json.complete = true`

**Exit condition:** Run logged, config updated, report written. Pipeline complete.

**pipeline-log.md format:** Each run entry is appended as a markdown block (append-only — never modify old entries). Format: `### Run: [DATE] -- [requirement summary]` header followed by bold-labeled fields: `Result` (SUCCESS/SUCCESS_WITH_FIXES/FAILED), `Risk level`, `Domain area`, `Fix loops` (with verify/review breakdown), `Stages` (per-stage ok/fail), `Failures` (what failed, how fixed, preventable?), `Review findings` (per-agent), `Learnings` (PREEMPT/PATTERN/TUNING entries), `Implementation notes`, `Pipeline health` (trend assessment). See `pl-700-retrospective.md` section 2a for the full template. PREEMPT items track confidence decay: 10 domain-matched unused runs → HIGH → MEDIUM → LOW → ARCHIVED; 1 false positive = 3 unused runs.

---

## Transitions

### Normal Flow (Linear)

```
0 PREFLIGHT -> 1 EXPLORE -> 2 PLAN -> 3 VALIDATE -> 4 IMPLEMENT -> 5 VERIFY -> 6 REVIEW -> 7 DOCS -> 8 SHIP -> 9 LEARN
```

### Retry Loops

| Loop | From | To | Trigger | Counter | Max |
|------|------|----|---------|---------|-----|
| Plan revision | 3 VALIDATE | 2 PLAN | REVISE verdict | `validation_retries` | `validation.max_validation_retries` (default: 2) |
| Build/lint fix | 5 VERIFY (Phase A) | 5 VERIFY (Phase A) | Build or lint failure | `verify_fix_count` | `implementation.max_fix_loops` (default: 3) |
| Test fix | 5 VERIFY (Phase B) | 4 IMPLEMENT (targeted) | Test failure | `test_cycles` | `test_gate.max_test_cycles` (default: 2) |
| Quality fix | 6 REVIEW | 4 IMPLEMENT (targeted) | Score < 100 | `quality_cycles` | `quality_gate.max_review_cycles` (default: 2; set to 1 when convergence is active — the convergence engine manages the outer loop) |
| PR rejection (implementation) | 8 SHIP | 4 IMPLEMENT | User rejects PR with implementation feedback | increments `total_retries` | `total_retries_max` (default: 10) |
| PR rejection (design) | 8 SHIP | 2 PLAN | User rejects PR with design feedback | increments `total_retries` | `total_retries_max` (default: 10) |

> **Convergence engine note:** The quality fix loop above describes the inner cycle (per convergence iteration). The outer loop is managed by the convergence engine with `convergence.max_iterations` (default: 8) as the hard cap and plateau detection as the normal exit. See `shared/convergence-engine.md`.

### Migration Mode

The orchestrator detects the pipeline mode from the requirement prefix at PREFLIGHT (section 3.0 in `pl-100-orchestrator.md`). Mode is stored in `state.json.mode`.

**Migration mode** (`migrate:` / `migration:` prefix):

1. Stage 0 (PREFLIGHT): Runs normally. Detects current dependency versions for migration version targeting.
2. Stage 1 (EXPLORE): Runs normally — explores current usage of the library/framework being migrated.
3. Stage 2 (PLAN): `pl-160-migration-planner` is dispatched instead of `pl-200-planner`. Produces a phased migration plan with rollback checkpoints. Uses Context7 to fetch migration guides for the target version.
4. Stage 3 (VALIDATE): Runs normally with all 7 perspectives. The validator checks migration feasibility: breaking changes identified, rollback plan exists, data migration strategy defined.
5. Stage 4 (IMPLEMENT): Uses the migration planner's execution strategy (phased migration with rollback checkpoints). The `story_state` cycles through migration-specific states:
   - `MIGRATING` — actively applying migration changes
   - `MIGRATION_PAUSED` — paused at a checkpoint, awaiting verification
   - `MIGRATION_CLEANUP` — removing deprecated code paths after successful migration
   - `MIGRATION_VERIFY` — running verification against the migrated codebase
   These states replace `IMPLEMENTING` in `story_state` during migration execution.
6. Stage 5 (VERIFY): Runs normally — build + lint + tests must pass after migration.
7. Stage 6 (REVIEW): Runs normally with full reviewer set. `version-compat-reviewer` is especially important — verifies no deprecated APIs remain.
8. Stages 7-9 (DOCS, SHIP, LEARN): Run normally. Documentation updates include migration notes and upgraded version references.

The `/migration` skill dispatches `pl-160-migration-planner` directly for standalone use outside the pipeline.

See `agents/pl-160-migration-planner.md` for the full migration state machine, rollback strategy, and phased execution model.

**Bootstrap mode** (`bootstrap:` prefix):

1. Stage 0 (PREFLIGHT): Runs normally. If no `dev-pipeline.local.md` exists yet, PREFLIGHT uses plugin defaults and defers config generation to the bootstrapper.
2. Stage 1 (EXPLORE): Runs with reduced scope — confirms empty/minimal state. If no source files exist, exploration completes immediately with `"greenfield: true"` in stage notes.
3. Stage 2 (PLAN): `pl-050-project-bootstrapper` is dispatched instead of `pl-200-planner`. The bootstrapper performs requirements gathering, architecture decisions, and scaffolding. It auto-runs `/pipeline-init` at the end.
4. Stage 3 (VALIDATE): Runs with **bootstrap-scoped perspectives**. The validator checks: (a) project compiles (build command passes), (b) at least one test passes, (c) Docker config is valid (`docker compose config`), (d) architecture matches the declared pattern. Skips: conventions check (no pre-existing conventions to violate), approach quality (single approach was chosen interactively), documentation consistency (new project has no docs baseline). Challenge Brief is NOT required for bootstrap plans.
5. Stage 4 (IMPLEMENT): **Skipped** — the bootstrapper already created all files in Stage 2. The orchestrator transitions directly from VALIDATE (GO) to VERIFY.
6. Stage 5 (VERIFY): Runs normally — build + lint + tests must pass. The bootstrapper should have left the project in a green state; VERIFY confirms this.
7. Stage 6 (REVIEW): Runs with **reduced reviewer set**. Only dispatches: `architecture-reviewer` (verify scaffold structure), `security-reviewer` (check for hardcoded secrets, insecure defaults). Skips: `frontend-*-reviewer` (no design baseline), `backend-performance-reviewer` (no business logic yet), `docs-consistency-reviewer` (no docs baseline), `version-compat-reviewer` (versions just resolved from context7). Quality target for bootstrap is `pass_threshold` (not 100) — new projects start clean.
8. Stages 7-9 (DOCS, SHIP, LEARN): Run normally. The docs generator creates initial documentation. The PR builder creates an "initial scaffold" PR. The retrospective records the bootstrap as the first run.

The `/bootstrap-project` skill dispatches `pl-050-project-bootstrapper` directly for standalone use outside the pipeline.

See `agents/pl-050-project-bootstrapper.md` for supported project types and scaffolding capabilities.

### Targeted Re-Implementation

When a fix cycle re-enters Stage 4 (IMPLEMENT) from Stage 5 or Stage 6, the implementation is **targeted** — scoped to only the files and issues identified by the preceding stage.

**Test fix (Stage 5 Phase B → Stage 4):**
- Implementer receives the list of failing tests and their error details.
- Scope: only files whose tests failed. Do not re-scaffold.
- Implementer must not modify test files (focus on fixing implementation to pass existing tests).

**Quality fix (Stage 6 → Stage 4):**
- Implementer receives the deduplicated finding list organized by file.
- Scope: only files mentioned in quality findings. Do not re-scaffold.
- Implementer addresses findings in severity order (CRITICAL first, then WARNING, then INFO).

**Constraints for both paths:**
- The scaffolder is NOT re-run (scaffolding completed in the initial Stage 4 pass). **Exception:** If scaffolder outputs are missing from the worktree (e.g., worktree was recreated after a failure), re-run the scaffolder before dispatching the implementer. See Stage 8 cross-stage re-entry validation point 3.
- Changes are made in the existing worktree (no new branch).
- After targeted fixes, the pipeline returns to the originating stage (5 or 6) for re-verification.
- Conflict detection is skipped (single-task targeted fixes don't need it).

### Global Retry Budget

All retry loops share a cumulative budget tracked in `state.json.total_retries`. Every retry increment (`validation_retries++`, `verify_fix_count++`, `test_cycles++`, `quality_cycles++`) also increments `total_retries`. PR rejection paths also directly increment `total_retries` by 1.

| Field | Default | Configurable In |
|-------|---------|-----------------|
| `total_retries_max` | 10 | `pipeline-config.md` |

When `total_retries >= total_retries_max`, the orchestrator escalates to the user regardless of which individual loop has budget remaining. Escalation format:

The orchestrator **escalates via AskUserQuestion** with header "Budget", question "Pipeline exhausted global retry budget ({total_retries}/{total_retries_max}). Breakdown: validation={N}, build_fix={N}, test_fix={N}, quality_fix={N}.", options: "Continue" (increase budget and keep iterating), "Ship as-is" (create PR with current state), "Abort" (stop the pipeline run).

Constraint: `total_retries_max` must be >= 5 and <= 30. If violated, use default (10).

### Escalation Paths

| Condition | Action |
|-----------|--------|
| VALIDATE returns NO-GO | Pipeline pauses, user must decide |
| VERIFY Phase A exceeds max fix loops | Pipeline reports failure, user must intervene |
| VERIFY Phase B exceeds max test cycles | Pipeline escalates to user |
| REVIEW returns FAIL after max cycles | Pipeline escalates to user |
| REVIEW score regression > `oscillation_tolerance` | Pipeline escalates to user immediately |
| REVIEW two consecutive score dips (even within tolerance) | Pipeline escalates to user immediately |
| `total_retries >= total_retries_max` | Pipeline escalates to user with retry breakdown |
| Risk > `auto_proceed` threshold at Stage 3 | Pipeline pauses for user plan approval |

### Transition Diagram

```
                    +---REVISE---+
                    |            |
                    v            |
 0 -> 1 -> 2 -> [3] -> 4 -> [5] -> [6] -> 7 -> [8] -> 9
               GO |         ^  |         ^       |  |
                  |   fail  |  |   fix   |       |  |
                  +-------->+  +-------->+       |  |
                  ^            test fix          |  |
                  |                              |  |
                  +--- design feedback ----------+  |
                                                    |
                          +--- impl feedback -------+
                          |
                          v
                          4 (with feedback context)
```

---

## --from Flag Behavior

The `--from` flag allows users to manually resume a pipeline from a specific stage, overriding checkpoint-based recovery.

### Syntax

```
/pipeline-run "requirement" --from=<stage_name_or_number>
```

Valid values: stage number (0-9) or lowercase stage name (`preflight`, `explore`, `plan`, `validate`, `implement`, `verify`, `review`, `docs`, `ship`, `learn`).

### Behavior

1. `--from` takes precedence over checkpoint recovery. If `state.json` indicates the pipeline should resume at Stage 4 but `--from=6` is specified, the pipeline starts at Stage 6.
2. When `--from` skips stages, the orchestrator assumes prior stages completed successfully. It reads whatever stage notes and artifacts exist from previous runs.
3. If `--from` points to a stage that requires artifacts from a skipped stage (e.g., `--from=4` without a plan from Stage 2), the pipeline fails at entry condition check and reports which prerequisite is missing.
4. `--from=0` is equivalent to a fresh start (no checkpoint recovery).
5. Counters (`quality_cycles`, `test_cycles`, `verify_fix_count`) are NOT reset by `--from`. To reset counters, delete `.pipeline/state.json` and start fresh.

### Common Use Cases

| Command | Use Case |
|---------|----------|
| `--from=4` | Plan is good, want to re-implement from scratch |
| `--from=5` | Made manual code changes, want to re-verify |
| `--from=6` | Tests pass, want to re-run quality review |
| `--from=8` | Review passed, want to re-create PR (e.g., after branch issues) |

---

## --dry-run Flag Behavior

The `--dry-run` flag allows users to preview what the pipeline would do without making any changes.

### Syntax

```
/pipeline-run "requirement" --dry-run
/pipeline-run "requirement" --dry-run --from=plan
```

### Behavior

1. `--dry-run` runs Stages 0-3 (PREFLIGHT, EXPLORE, PLAN, VALIDATE) normally
2. After VALIDATE completes, the pipeline **stops** and outputs a dry-run report
3. Stages 4-9 (IMPLEMENT through LEARN) are skipped entirely
4. `--dry-run` is compatible with `--from` (e.g., `--dry-run --from=plan` skips EXPLORE)

### What dry-run does NOT do

- Does NOT create a git worktree
- Does NOT create Linear tickets
- Does NOT modify any source files
- Does NOT create a PR
- Stage notes ARE written to `.pipeline/` (for debugging)
- State.json IS written with `"dry_run": true`

### Common Use Cases

| Command | Use Case |
|---------|----------|
| `--dry-run` | Preview the full plan before committing to implementation |
| `--dry-run --from=plan` | Re-plan after exploration, preview without re-exploring |

---

## Data Flow Summary

```
Stage 0 (PREFLIGHT)
  OUT: config, state.json, preempt items
    |
    v
Stage 1 (EXPLORE)
  IN:  requirement, preempt items, conventions
  OUT: exploration summary (files, patterns, gaps)
    |
    v
Stage 2 (PLAN)
  IN:  exploration results, preempt items, hotspots, conventions, scaffolder patterns
  OUT: plan (risk, stories, tasks, groups, test strategy)
    |
    v
Stage 3 (VALIDATE)
  IN:  plan, perspectives, conventions, source files
  OUT: verdict (GO/REVISE/NO-GO), validation findings
    |
    v
Stage 4 (IMPLEMENT)
  IN:  validated plan, scaffolder patterns, conventions, build/test commands, context7 docs
  OUT: source files, test files, checkpoint, last_commit_sha
    |
    v
Stage 5 (VERIFY)
  IN:  build/lint/test commands, inline checks, test gate config
  OUT: build pass, test pass, coverage report, fix loop counts
    |
    v
Stage 6 (REVIEW)
  IN:  quality gate config, changed files, conventions
  OUT: verdict (PASS/CONCERNS/FAIL), findings, score history
    |
    v
Stage 7 (DOCS)
  IN:  changed files, review findings, CLAUDE.md, conventions
  OUT: updated docs
    |
    v
Stage 8 (SHIP)
  IN:  changed files, quality verdict, test results, story metadata
  OUT: branch, commit, PR
    |
    v
Stage 9 (LEARN)
  IN:  all stage notes, counters, timestamps, log, config, reports, feedback
  OUT: updated log, updated config, report, state.json.complete=true
```
