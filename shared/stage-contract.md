# Stage Contract

This document defines the 10 pipeline stages as a contract between the orchestrator (`pl-100-orchestrator`) and all agents. It is the authoritative reference for stage numbering, naming, transitions, data flow, and entry/exit conditions.

Any agent or module that needs to understand where it fits in the pipeline should read this document.

## Stage Overview

| Stage | Name | Agent(s) | story_state | Entry Condition | Exit Condition |
|-------|------|----------|-------------|-----------------|----------------|
| 0 | PREFLIGHT | inline | `PREFLIGHT` | User invokes `/pipeline-run` with a requirement | Config loaded, state.json initialized, task list created |
| 1 | EXPLORE | `explore_agents` from config | `EXPLORING` | Config loaded successfully | Exploration results summarized in stage notes |
| 2 | PLAN | `pl-200-planner` | `PLANNING` | Exploration complete | Plan with risk level, stories, tasks, and parallel groups |
| 3 | VALIDATE | `pl-210-validator` | `VALIDATING` | Plan exists | GO verdict (or NO-GO escalated to user) |
| 4 | IMPLEMENT | `pl-310-scaffolder` + `pl-300-implementer` | `IMPLEMENTING` | Plan validated with GO verdict; worktree created | All tasks completed inside worktree (or failed after max retries) |
| 5 | VERIFY | inline (Phase A) + `pl-500-test-gate` (Phase B) | `VERIFYING` | Implementation complete | Build + lint + tests all pass |
| 6 | REVIEW | `pl-400-quality-gate` | `REVIEWING` | Verification passed | Quality verdict PASS or CONCERNS |
| 7 | DOCS | inline | `DOCUMENTING` | Review passed | Documentation updated if needed |
| 8 | SHIP | `pl-600-pr-builder` | `SHIPPING` | Documentation done | PR created and presented to user; worktree merged and cleaned up |
| 9 | LEARN | `pl-700-retrospective` + `pl-720-recap` | `LEARNING` | PR approved by user (or rejected with feedback captured) | Run logged, config updated, report written |

**Convention file defensive read:** Each agent that reads the conventions file handles the case where it becomes unreadable between stages. PREFLIGHT validates the path; each agent does a defensive Read and proceeds with universal defaults if it fails.

---

## Stage Details

### Stage 0: PREFLIGHT

**Agent:** Inline (orchestrator logic, no sub-agent dispatch)
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

**Outputs:**
- Initialized `.pipeline/state.json`
- Parsed config (passed as context to subsequent stages)
- Matched PREEMPT items (recorded in `preempt_items_applied`)

**Exit condition:** Config loaded, state initialized, no unresolved interrupted-run conflicts.

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
- `validation.perspectives` from config (5 perspectives)
- `conventions_file` content (module-specific conventions)
- Source files referenced in the plan

**Actions:**
1. Run 5 validation perspectives (Architecture, Security, Edge Cases, Test Strategy, Conventions). Perspective content comes from the module's `conventions.md`.
2. Return verdict: GO / REVISE / NO-GO.
3. On REVISE: return specific issues for the planner to address.

**Outputs:**
- Verdict: GO, REVISE, or NO-GO
- Validation findings (per perspective)
- `stage_3_notes_{storyId}.md` -- validation analysis

**Exit condition (GO):** Proceed to Stage 4.

**On REVISE:** Loop back to Stage 2 (PLANNING). Increment `validation_retries`. Max retries: `validation.max_validation_retries` (default: 2). After max retries with continued REVISE, escalate as NO-GO.

**On NO-GO:** Escalate to user. Pipeline pauses.

**Decision gate:** Compare plan `risk_level` against `risk.auto_proceed` from config:
- Risk <= threshold: proceed automatically on GO.
- Risk > threshold: show plan to user, ask for approval before proceeding.

---

### Stage 4: IMPLEMENT

**Agent(s):** `pl-310-scaffolder` + `pl-300-implementer`
**story_state:** `IMPLEMENTING`

**Entry condition:** Plan validated with GO verdict (Stage 3). Worktree created at `.pipeline/worktree` branching from pre-implement checkpoint commit.

**Inputs:**
- Validated plan with tasks and parallel groups
- `scaffolder.patterns` from config
- `conventions_file` content
- `commands.build` and `commands.test_single` from config
- `context7_libraries` from config (for documentation prefetch)

**Actions:**
1. Git checkpoint: `git add -A && git commit -m "wip: pipeline checkpoint pre-implement"`. Record SHA in `state.json.last_commit_sha`.
2. Documentation prefetch: resolve and query context7 libraries for current API docs.
3. For each parallel group (sequential order):
   - For each task in group (concurrent up to `implementation.parallel_threshold`):
     a. `pl-310-scaffolder` generates boilerplate (if `scaffolder_before_impl: true`).
     b. Write tests (RED phase -- tests that define expected behavior, expected to fail).
     c. `pl-300-implementer` writes implementation to pass tests (GREEN) + refactors.
     d. Verify with `commands.build` or `commands.test_single`.
4. Write checkpoint (`checkpoint-{storyId}.json`) after each task.
5. If a task fails after `max_fix_loops`: record as failed, continue with remaining tasks.

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

**Inputs:**
- `commands.build`, `commands.lint`, `commands.format` from config
- `inline_checks` from config (scripts or skills)
- `test_gate.command` from config
- `test_gate.analysis_agents` from config

**Phase A -- Build & Lint (inline, fail-fast):**
1. Run `commands.build` (compile check).
2. Run `commands.lint` (lint + static analysis).
3. Run `inline_checks` from config (module scripts or skills).
4. On failure: analyze error, fix, re-run from failed step. Increment `verify_fix_count`. Max: `implementation.max_fix_loops`.

**Phase B -- Test Gate (`pl-500-test-gate`):**
1. Run `test_gate.command` (full test suite).
2. If tests pass: dispatch `test_gate.analysis_agents` for coverage and quality analysis.
3. If tests fail: dispatch `pl-300-implementer` with failing test details, then re-run tests. Increment `test_cycles`. Max: `test_gate.max_test_cycles`.

**Outputs:**
- Build/lint pass confirmation
- Test results (pass/fail, coverage report)
- `stage_5_notes_{storyId}.md` -- verification details, fix loop history
- Updated counters: `verify_fix_count`, `test_cycles`

**Exit condition:** Build passes, lint passes, all tests pass. If Phase A exceeds max fix loops, pipeline reports failure. If Phase B exceeds max test cycles, pipeline escalates to user.

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
5. If score < 100 and cycles remaining: send ALL findings to implementer, fix cycle, rescore. Increment `quality_cycles`.
6. Determine verdict from final score.

**Outputs:**
- Quality verdict: PASS, CONCERNS, or FAIL
- Deduplicated finding list with scores
- Score history (score per cycle)
- `stage_6_notes_{storyId}.md` -- review report

**Exit condition (PASS):** Score >= 80, no CRITICALs. Proceed to Stage 7.

**Exit condition (CONCERNS):** Score 60-79, no CRITICALs. Proceed to Stage 7 with findings preserved in notes.

**On FAIL:** If cycles remain, loop: dispatch implementer with findings, return to review. If max cycles reached: escalate to user.

**On fix cycle:** Loop back to Stage 4 context (implementer fixes), then re-verify (Stage 5), then re-review (Stage 6). Increment `quality_cycles`.

---

### Stage 7: DOCS

**Agent:** Inline (orchestrator logic)
**story_state:** `DOCUMENTING`

**Entry condition:** Review passed with PASS or CONCERNS verdict (Stage 6).

**Inputs:**
- Changed files from implementation
- Review findings (especially DOC-* category)
- Current CLAUDE.md content
- Module conventions

**Actions:**
1. Update CLAUDE.md if new patterns or gotchas were introduced.
2. Verify API documentation (OpenAPI descriptions for BE, TSDoc for FE).
3. Add KDoc/TSDoc on all new public interfaces.
4. No new documentation files unless explicitly requested by the user.

**Outputs:**
- Updated documentation files (if applicable)
- `stage_7_notes_{storyId}.md` -- documentation changes made

**Exit condition:** Documentation is current. No new public interfaces lack documentation.

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

**Exit condition:** PR created and presented to user. Worktree branch merged back to base branch and cleaned up (or preserved on failure).

**On user approval:** Proceed to Stage 9 (LEARN).

**On user rejection/feedback:**
1. Dispatch `pl-710-feedback-capture` to record the correction structurally.
2. Reset `quality_cycles` and `test_cycles` to 0.
3. Re-enter Stage 4 (IMPLEMENT) with feedback context.

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
| Quality fix | 6 REVIEW | 4 IMPLEMENT (targeted) | Score < 100 | `quality_cycles` | `quality_gate.max_review_cycles` (default: 2) |
| PR rejection | 8 SHIP | 4 IMPLEMENT | User rejects PR | resets `quality_cycles`, `test_cycles` | No max (user-driven) |

### Escalation Paths

| Condition | Action |
|-----------|--------|
| VALIDATE returns NO-GO | Pipeline pauses, user must decide |
| VERIFY Phase A exceeds max fix loops | Pipeline reports failure, user must intervene |
| VERIFY Phase B exceeds max test cycles | Pipeline escalates to user |
| REVIEW returns FAIL after max cycles | Pipeline escalates to user |
| Risk > `auto_proceed` threshold at Stage 3 | Pipeline pauses for user plan approval |

### Transition Diagram

```
                    +---REVISE---+
                    |            |
                    v            |
 0 -> 1 -> 2 -> [3] -> 4 -> [5] -> [6] -> 7 -> [8] -> 9
               GO |         ^  |         ^       |
                  |   fail  |  |   fix   |       |
                  +-------->+  +-------->+       |
                               test fix          |
                                                 |
                          +--- user rejects -----+
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
