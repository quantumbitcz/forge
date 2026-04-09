# Pipeline Orchestrator — Ship Phase (Stages 7-9)

> This document is loaded after REVIEW passes (score accepted).
> Follow the core document (`fg-100-orchestrator-core.md`) for principles and forbidden actions.

---

## 7.1 Stage 7: DOCS (dispatch fg-350-docs-generator)

**State transition:** Call `forge-state.sh transition docs_complete` after fg-350 returns (or `docs_failure` on error).
**TaskUpdate:** Mark "Stage 6: Review" -> `completed`, Mark "Stage 7: Docs" -> `in_progress`

### Mode-Aware Documentation

Check `state.json.mode_config.stages.docs` for overrides (set at PREFLIGHT via mode overlay).
If `override.skip`: skip this stage entirely (write INFO note, proceed to pre-ship).
If `override.reduced`: dispatch fg-350 with `mode: reduced` (updates only, no new generation).

### Dispatch

[dispatch fg-350-docs-generator]

```
Changed files: [list from implementation checkpoints]
Quality verdict: [PASS/CONCERNS] with score [N]
Plan stage notes: [Challenge Brief content for ADR generation]
Doc discovery summary: [from stage_0_docs_discovery.md]
Documentation config: [from forge.local.md documentation: section]
Framework conventions: [path to documentation conventions]
Mode: pipeline
```

Rules:
- Update docs affected by changed files (graph-guided)
- Generate ADRs for significant decisions from the plan
- Update changelog with this run's changes
- Update OpenAPI spec if API endpoints changed
- Verify KDoc/TSDoc on all new public interfaces
- Generate missing docs for new modules if auto_generate is enabled
- Respect user-maintained fences
- Export to configured targets if export.enabled
- Write all output to .forge/worktree

**On success:** Call `forge-state.sh transition docs_complete`. Write `.forge/stage_7_notes_{storyId}.md` with documentation generation summary.

**On failure:** Call `forge-state.sh transition docs_failure`. The transition logs WARNING and sets `documentation.generation_error = true` but proceeds to pre-ship -- documentation failure does not block shipping.

**Linear tracking:**

```
forge-linear-sync.sh emit docs_complete '<result_json>'
```

(The sync script handles availability checking internally.)

Update state: add `docs` timestamp.

Mark Docs as completed.

---

## 7.2 Pre-Ship Verification (dispatch fg-590-pre-ship-verifier)

**TaskUpdate:** Mark "Stage 7: Docs" -> `completed`

Dispatch `fg-590-pre-ship-verifier` with:
[dispatch fg-590-pre-ship-verifier]

```
Verify shipping readiness. Run fresh build, lint, tests, and code review.

Commands: build={commands.build}, test={commands.test}, lint={commands.lint}
Current score: [last score from convergence state]
shipping.min_score: [from config, default 100]
BASE_SHA: [worktree branch point]
HEAD_SHA: [current HEAD]
shipping.evidence_review: [from config, default true]
```

Read `.forge/evidence.json` after fg-590 returns.

Update `state.json.evidence`: increment `attempts`, set `last_run` and `verdict`. If BLOCK, append to `block_history`.

---

## 7.3 Evidence Verdict Routing

All evidence routing decisions use `forge-state.sh transition` -- do NOT reimplement the routing logic.

**IF `evidence.verdict == "SHIP"`:**

Call `forge-state.sh transition evidence_SHIP --guard "evidence_fresh=true"`. The returned action is `SHIPPING (PR creation)`. Proceed to SS8.1.

If evidence is stale (timestamp older than `shipping.evidence_max_age_minutes`): call `forge-state.sh transition evidence_SHIP --guard "evidence_fresh=false"`. The returned action re-dispatches fg-590 (re-verify). Loop back to SS7.2.

**IF `evidence.verdict == "BLOCK"`:**

Call `forge-state.sh transition evidence_BLOCK --guard "block_reason={category}"` where `{category}` is derived from `block_reasons`:

| Block Reason | Guard Value | Returned State | Action |
|---|---|---|---|
| `build.exit_code != 0` | `block_reason=build` | `IMPLEMENTING` | Convergence Phase 1 (correctness). Re-enter Stage 4 -> Stage 5. |
| `lint.exit_code != 0` | `block_reason=lint` | `IMPLEMENTING` | Convergence Phase 1 (correctness). Re-enter Stage 4 -> Stage 5. |
| `tests.failed > 0` | `block_reason=tests` | `IMPLEMENTING` | Convergence Phase 1 (correctness). Re-enter Stage 4 -> Stage 5. |
| `review.critical_issues > 0` | `block_reason=review` | `IMPLEMENTING` | Convergence Phase 2 (perfection). Re-enter Stage 4 -> Stage 6. |
| `review.important_issues > 0` | `block_reason=review` | `IMPLEMENTING` | Convergence Phase 2 (perfection). Re-enter Stage 4 -> Stage 6. |
| `score.current < shipping.min_score` | `block_reason=score` | `IMPLEMENTING` | Convergence Phase 2 (perfection). Re-enter Stage 4 -> Stage 6. |

After the fix loop completes, re-run Stage 7 (DOCS, incremental) then re-dispatch fg-590. Repeat until SHIP or convergence plateaus.

**IF convergence PLATEAUED during evidence fix loop:**

Escalate via AskUserQuestion with header "Evidence Gate Blocked", question "Pre-ship verification cannot reach shipping target. Current score: {score}. Block reasons: {reasons}.", options:
1. **"Keep trying"** -- reset `plateau_count` to 0, `convergence_state` to `"IMPROVING"`, continue iterating (global `max_iterations` cap still applies)
2. **"Fix manually"** -- pause pipeline, user fixes outside forge, resume from Stage 5 (VERIFY)
3. **"Abort"** -- stop pipeline, no PR, write abort report

**Autonomous mode:** Auto-select "Keep trying". On `max_iterations` exhausted: hard abort, write `.forge/abort-report.md`, no PR.

---

## 8.1 Stage 8: SHIP (dispatch fg-600-pr-builder)

**State transition:** Call `forge-state.sh transition pr_created` after fg-600 returns successfully.
**TaskUpdate:** Mark "Stage 8: Ship" -> `in_progress`

**Pre-condition:** `.forge/evidence.json` must exist with `verdict: "SHIP"` and `timestamp` within `shipping.evidence_max_age_minutes`. If missing or stale, re-dispatch fg-590 (SS7.2). If BLOCK, follow evidence verdict routing (SS7.3).

### Dispatch

[dispatch fg-600-pr-builder]

```
Create branch, commit, and PR for this pipeline run.

Changed files: [list from implementation]
Quality verdict: [PASS/CONCERNS] with score [N]
Evidence verdict: SHIP (evidence.json timestamp: [timestamp])
Test results: [pass/fail summary]
Story metadata: requirement=[req], risk=[level]
Stage 7 notes: [path to stage_7_notes_{storyId}.md]

Rules:
- Branch: feat/* | fix/* | refactor/* based on requirement type
- Exclude: .claude/, build/, .env, .forge/, node_modules/
- Conventional commit (no AI attribution, no Co-Authored-By)
- PR body: Summary, Quality Gate (verdict + score), Test Plan, Pipeline Run metrics
- PR body section "## Verification Evidence": build status + duration, test count + duration, lint status, review issue counts, quality score (from .forge/evidence.json)
- PR body section "## Documentation": coverage percentage and delta, files created/updated, ADRs generated (from stage_7_notes)
```

Present PR to user with summary of work, quality score, test results.

**Kanban:** After PR creation, `update_ticket_field` set `pr` to PR URL + `generate_board` (per core doc SS3.12).

**Linear tracking:**

```
forge-linear-sync.sh emit pr_created '<pr_json>'
```

(The sync script handles availability checking internally.)

---

## 8.2 Merge Conflict Handling

Before merging the worktree branch, the PR builder should detect potential conflicts:

1. Determine the base branch (the branch active at worktree creation -- typically the branch checked out at PREFLIGHT). Run `git merge-tree $(git merge-base HEAD {base_branch}) HEAD {base_branch}` to detect conflicts before attempting the actual merge
2. If conflicts detected:
   - Do NOT merge
   - Create the PR as-is (branch exists, conflicts visible in PR)
   - Escalate to user with conflict details:
     > "Pipeline created PR but merge conflicts detected with base branch. Conflicting files: {list}. Options: (1) Resolve conflicts manually and merge, (2) Rebase worktree branch with `/forge-run --from=ship`, (3) Abort -- worktree preserved at `.forge/worktree`."
3. If no conflicts: proceed with merge normally
4. If merge itself fails unexpectedly (after dry-merge passed): preserve worktree, escalate with error details

---

## 8.3 Preview Validation (conditional)

If `preview.enabled` is `true` in `forge.local.md` and the PR was created successfully:

1. Wait for preview URL to become available (from CI/CD webhook or `preview.url_pattern` config)
2. Dispatch `fg-650-preview-validator` with: PR number, preview URL, smoke test routes, Lighthouse thresholds, Playwright test paths
   [dispatch fg-650-preview-validator]
3. fg-650 posts results as a PR comment (smoke tests, Lighthouse audit, visual regression, E2E)
4. **Gating behavior** based on `preview.block_merge` config (default: `false`):
   - If `block_merge: false` (default): verdict is advisory only. FAIL -> add `preview-failed` label, include findings in user presentation, but proceed to user response.
   - If `block_merge: true`: FAIL verdict **blocks stage progression**. The orchestrator loops: dispatch `fg-300-implementer` with preview findings, re-run VERIFY (safety check), re-dispatch preview validator. Max `preview.max_fix_loops` (default: 1) attempts. Each loop iteration increments `total_iterations` and `total_retries` -- the global budget still applies. After exhaustion of `max_fix_loops` OR `total_retries >= total_retries_max`, escalate via AskUserQuestion:
     ```
     header: Preview Validation Failed
     question: Preview environment validation failed after {attempts} fix attempts. How would you like to proceed?
     options:
       - "Fix manually" (description: "Pause pipeline for manual intervention, resume from VERIFY when ready")
       - "Merge anyway" (description: "Override preview gating for this PR only -- findings preserved in PR comment")
       - "Abort" (description: "Close PR and abort the pipeline")
     ```
5. If verdict is PASS or CONCERNS: proceed to user response.

If `preview.enabled` is not configured or `false`: skip preview validation.

---

## 8.4 Infrastructure Deployment Verification (conditional)

If any component has `framework: k8s` or `container_orchestration:` config in `forge.local.md`:

1. Dispatch `fg-610-infra-deploy-verifier` with: changed manifests, deployment target, container images, Helm charts
   [dispatch fg-610-infra-deploy-verifier]
2. `fg-610-infra-deploy-verifier` performs tiered verification: static analysis (lint, template) -> container build -> cluster validation (if available)
3. If verdict is FAIL: include findings in user presentation, recommend manifest fixes
4. If verdict is PASS or CONCERNS: proceed

If no infrastructure components are configured: skip infrastructure verification.

---

## 8.5 User Response + Feedback Loop Detection

After PR presentation (and optional preview/infra verification), await user response.

All feedback routing decisions use `forge-state.sh transition` -- do NOT reimplement counter logic.

### Approval

On user approval: call `forge-state.sh transition user_approve_pr`. The returned state is `LEARNING`.

**Kanban:** `move_ticket` to `done/` + `generate_board` (per core doc SS3.12). Proceed to Stage 9 (SS9.1).

**Linear tracking:**

```
forge-linear-sync.sh emit pr_approved '<approval_json>'
```

(The sync script handles availability checking internally.)

### Feedback / Rejection

On user rejection: first dispatch `fg-710-post-run` (Part A: Feedback Capture) to record the correction structurally.

**Kanban:** `move_ticket` back to `in-progress/` + `generate_board` (per core doc SS3.12).

Read `feedback_classification` from `state.json` (set by `fg-710-post-run`).

**Feedback loop detection** (before re-entering any stage):

1. Read the new `feedback_classification` from `state.json`.
2. Compare to `state.json.previous_feedback_classification`:
   - If same classification: call `forge-state.sh transition feedback_loop_detected --guard "feedback_loop_count={N}"` (where N = current count + 1).
   - If different classification: reset `feedback_loop_count` to 0, update `previous_feedback_classification`.
3. If `feedback_loop_count >= 2`: the transition returns `ESCALATED`. AskUserQuestion with header "Loop", question "Feedback loop detected: {classification} feedback received {feedback_loop_count} consecutive times.", options: "Guide" (provide specific guidance -- the user's text will be prepended to the next stage's input as high-priority context), "Start fresh" (abort current run and begin new `/forge-run`), "Override" (proceed with current state despite recurring feedback -- reset `feedback_loop_count` to 0 and continue).
4. If not escalating, proceed with re-entry below.

**Re-entry routing** (via forge-state.sh):

| Classification | Transition Call | Returned State | Counter Resets (automatic) |
|---|---|---|---|
| **Implementation** | `forge-state.sh transition pr_rejected --guard "feedback_classification=implementation"` | `IMPLEMENTING` | `quality_cycles = 0`, `test_cycles = 0`, `total_retries += 1` |
| **Design** | `forge-state.sh transition pr_rejected --guard "feedback_classification=design"` | `PLANNING` | `quality_cycles = 0`, `test_cycles = 0`, `verify_fix_count = 0`, `validation_retries = 0`, `total_retries += 1` |

The script handles all counter resets automatically. After transition, check `total_retries` against `total_retries_max` (returned in the action metadata). If budget exhausted, escalate.

On re-entry to IMPLEMENTING or PLANNING, re-read `fg-100-orchestrator-execute.md` and resume from the corresponding stage with the user's feedback as high-priority context.

Write `.forge/stage_8_notes_{storyId}.md` with PR details.

Update state: add `ship` timestamp.

Mark Ship as completed.

---

## 9.1 Stage 9: LEARN (dispatch fg-700-retrospective)

**State transition:** Call `forge-state.sh transition retrospective_complete` after all learn sub-stages complete.
**TaskUpdate:** Mark "Stage 8: Ship" -> `completed`, Mark "Stage 9: Learn" -> `in_progress`

### Mode-Aware Retrospective

Check `state.json.mode_config.stages.learn` for overrides (set at PREFLIGHT via mode overlay).
If `override.skip`: skip retrospective entirely (write INFO note, proceed to cleanup).
If `override.reduced`: dispatch fg-700 with reduced summary (skip auto-tuning).

If `state.json.mode == "bugfix"`, include additional bugfix context in the dispatch prompt:
```
Bugfix context:
- Root cause category: [state.json.bugfix.root_cause.category]
- Reproduction method: [state.json.bugfix.reproduction.method]
- Affected files: [state.json.bugfix.root_cause.affected_files]
- Reproduction attempts: [state.json.bugfix.reproduction.attempts]

Write a bug pattern entry to `.forge/forge-log.md` under a `## Bug Patterns` section.
```

### Dispatch

[dispatch fg-700-retrospective]

Dispatch `fg-700-retrospective` with a **<2,000 token** summary:

```
Analyze this pipeline run and update forge-log.md and forge-config.md.

Run summary:
- Requirement: [summary]
- Domain area: [area]
- Risk level: [level]
- Stages completed: [list with pass/fail]
- Plan validation: [GO/REVISE/NO-GO] (iterations: [N])
- Verify fix loops: [count]
- Quality cycles: [count]
- Test cycles: [count]
- Review findings summary: [key findings and resolutions]
- Unresolved issues: [any remaining problems]
- Result: [SUCCESS / SUCCESS_WITH_FIXES / FAILED]

Preempt file: [path from config]
Config file: [path from config]
Reports dir: .forge/reports/
Stage notes dir: .forge/

Apply auto-tuning rules from forge-config.md.
Update metrics, domain hotspots, PREEMPT learnings.
Check for PREEMPT_CRITICAL escalations (3+ occurrences -> suggest hook/rule).
Propose CLAUDE.md updates if a pattern repeated 3+ times.
Write report to .forge/reports/forge-{date}.md.
```

After retrospective completes, update `state.json`: `complete` -> `true`.

**Linear tracking:**

```
forge-linear-sync.sh emit retrospective_complete '<result_json>'
```

(The sync script handles availability checking internally.)

---

## 9.2 Worktree Cleanup

After retrospective and before post-run, dispatch worktree cleanup:

```
dispatch fg-101-worktree-manager "cleanup ${worktree_path}"
```

If cross-repo worktrees exist, also dispatch:

```
dispatch fg-103-cross-repo-coordinator "cleanup --feature ${feature_id}"
```

Delete `.forge/.lock` (or `{run_dir}/.lock` in sprint mode).

---

## 9.3 Post-Run (dispatch fg-710-post-run)

After `fg-700-retrospective` completes:

1. Dispatch `fg-710-post-run` with:
   [dispatch fg-710-post-run]
   - All stage note paths
   - `state.json` path
   - Quality gate report path
   - PR URL (if created)

2. Post-run agent runs Part A (feedback capture) then Part B (recap)
3. Recap writes `.forge/reports/recap-{date}-{storyId}.md`

**Linear tracking:**

```
forge-linear-sync.sh emit run_complete '<recap_json>'
```

(The sync script handles availability checking internally. Posts summarized recap as comment on Epic and closes Epic after both retrospective and post-run complete.)

5. If PR exists: append "What Was Built" and "Key Decisions" to PR description

Write `.forge/stage_final_notes_{storyId}.md`.

Call `forge-state.sh transition retrospective_complete`. The returned state is `COMPLETE`.

**TaskUpdate:** Mark "Stage 9: Learn" -> `completed`. All 10 task checkboxes should now show as done.

---

## 9.4 Final Report

After all stages complete, output a concise summary:

```
Pipeline complete: [SUCCESS / SUCCESS_WITH_FIXES / FAILED]
PR: [URL or "not created"]
Validation: [GO] after [N] iterations
Quality gate: [PASS / CONCERNS / FAIL] (score: [N])
Fix loops: [N] (verify: [N], review: [N], test: [N])
Stories: [N] | Tasks: [M] | Tests: [T]
Learnings: [N] new PREEMPT items added
Health: [improving / stable / degrading]
```

**State Machine Reference:**

All state transitions in this document follow the formal transition table in `shared/state-transitions.md`. The orchestrator MUST look up (current_state, event, guard) in that table for every control flow decision. Do not interpret prose descriptions as state transition logic -- use the table. If a (state, event) pair is not in the table, log ERROR and escalate.

**Decision Logging:**

On every state transition, convergence evaluation, recovery attempt, and escalation, emit a decision log entry to `.forge/decisions.jsonl` per `shared/decision-log.md`. Fire-and-forget -- logging failure does not block the pipeline.
