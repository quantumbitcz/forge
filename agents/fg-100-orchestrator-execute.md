# Pipeline Orchestrator — Execute Phase (Stages 1-6)

> This document is loaded after PREFLIGHT completes.
> Follow the core document (`fg-100-orchestrator-core.md`) for principles and forbidden actions.
> After REVIEW passes, load `fg-100-orchestrator-ship.md` for stages 7-9.
> On re-entry (PR rejection, evidence BLOCK), re-read this document.

---

## Stage 1: EXPLORE

**story_state:** `EXPLORING` | **TaskUpdate:** Mark "Stage 0: Preflight" -> `completed`, Mark "Stage 1: Explore" -> `in_progress`

### SS1.1 Mode-Aware Exploration

Check `state.json.mode_config.stages.explore` for overrides (set at PREFLIGHT via mode overlay).
If `override.agent` exists: dispatch that agent instead of the default.
If `override.skip`: skip this stage entirely.

**If `mode_config.stages.explore.agent == "fg-020-bug-investigator"`:**

[dispatch fg-020-bug-investigator]
Dispatch `fg-020-bug-investigator` with:
- Bug description (from ticket or raw input)
- Bug source and source_id
- Ticket file path (if kanban)
- Project stack context from forge.local.md
- Graph availability flag
- Instruction: "Execute Phase 1 -- INVESTIGATE"

Read stage 1 notes. Extract: root cause hypothesis, affected files, confidence.
Store affected files in `state.json.bugfix.root_cause.affected_files`.

Write `.forge/stage_1_notes_{storyId}.md` with investigation results.
Update state: `story_state` -> `"EXPLORING"`, add `explore` timestamp.
Mark Explore as completed. Skip to Stage 2.

**Standard / Migration / Bootstrap Mode:**

Dispatch exploration agents configured in `forge.local.md` under `explore_agents`. Default: `feature-dev:code-explorer` (primary) + `Explore` (secondary, subagent_type=Explore).
[dispatch per protocol]

### SS1.2 Exploration Agents

**Agent 1: Primary Explorer**

```
Analyze the codebase to understand what exists for: [requirement].
Map relevant: domain models, interfaces, implementations, adapters, controllers, migrations, API specs.
Identify: files needing changes, pattern files to follow, existing tests, KDoc/TSDoc patterns.
Return a structured report with exact file paths.
```

**Agent 2: Test Explorer**

```
Find all existing tests related to [domain area].
Identify test patterns, fixture usage, helper utilities.
List test classes with scenarios. Check for coverage gaps.
```

Dispatch both in parallel. Collect and **summarize** results -- file paths, pattern files, test classes, identified gaps. Do NOT keep raw agent output.

**Documentation context:** If documentation was discovered at PREFLIGHT (check `state.json.documentation.files_discovered > 0`):
- Include doc discovery summary (`stage_0_docs_discovery.md`) in exploration context
- If architecture docs exist, explorers should validate code structure against documented architecture rather than re-inferring it from scratch

Write `.forge/stage_1_notes_{storyId}.md` with the exploration summary.

Update state: `story_state` -> `"EXPLORING"`, add `explore` timestamp.

Mark Explore as completed.

**Post-EXPLORE Scope Check (Auto-Decomposition):**

After exploration completes (standard mode only -- skip for bugfix, migration, bootstrap modes), check if the requirement spans too many architectural domains:

1. **Read config**: Check `scope.auto_decompose` from `forge-config.md` (default: `true`). If `false`, skip this check.

2. **Analyze exploration results**: From stage 1 notes, count distinct architectural domains touched by the requirement:
   - Different bounded contexts (separate domain model packages/directories)
   - Different API groups (separate controller/route namespaces)
   - Independent data models (separate database tables/collections with no FK relationships)
   - Different infrastructure concerns (auth vs. payments vs. notifications)

3. **Threshold check**: If domain count >= `scope.decomposition_threshold` (default: 3 from `forge-config.md`):

   a. Log in stage notes: `"Deep scope check triggered: {domain_count} domains detected (threshold: {threshold}). Domains: {domain_list}"`

   b. Dispatch `fg-015-scope-decomposer`:
      [dispatch fg-015-scope-decomposer]
      ```
      Decompose this multi-feature requirement into independent features:

      Requirement: {original_requirement}

      Source: deep_scan
      Exploration notes: {summarized stage 1 notes -- file paths, domains, patterns}
      Available MCPs: {detected_mcps}
      ```

   c. The scope decomposer handles user approval and dispatches `fg-090-sprint-orchestrator`. This orchestrator instance should then **stop execution** -- the sprint orchestrator takes over.

   d. Update state: `decomposition.source = "deep_scan"`, store extracted features and routing in `state.json.decomposition`.

   e. Set `story_state` to `"DECOMPOSED"` and return. Do NOT proceed to Stage 2.

4. **If domain count < threshold**: Proceed to Stage 2 (PLAN) as normal.

---

## Stage 2: PLAN

**story_state:** `PLANNING` | **TaskUpdate:** Mark "Stage 1: Explore" -> `completed`, Mark "Stage 2: Plan" -> `in_progress`

### SS2.1 Mode-Aware Planning

Check `state.json.mode_config.stages.plan` for overrides (set at PREFLIGHT via mode overlay).
If `override.agent` exists: dispatch that agent instead of the default.
If `override.skip`: skip this stage entirely.
If `override.perspectives`: use those validation perspectives downstream.

**If `mode_config.stages.plan.agent == "fg-020-bug-investigator"`:**

1. Dispatch `fg-020-bug-investigator` with:
   [dispatch fg-020-bug-investigator]
   - Stage 1 investigation results (from stage notes)
   - Instruction: "Execute Phase 2 -- REPRODUCE"
2. Read stage 2 notes. Extract:
   - reproduction method -> store in `state.json.bugfix.reproduction.method`
   - test file -> store in `state.json.bugfix.reproduction.test_file`
   - attempts -> store in `state.json.bugfix.reproduction.attempts`
   - root cause category -> store in `state.json.bugfix.root_cause.category`
   - root cause hypothesis -> store in `state.json.bugfix.root_cause.hypothesis`
   - confidence -> store in `state.json.bugfix.root_cause.confidence`
3. If `reproduction.method == "unresolvable"`:
   Increment `state.json.bugfix.context_retries` (initialized to 0 at PREFLIGHT).
   Ask user via AskUserQuestion with header "Bug Reproduction", question "The bug could not be reproduced. How would you like to proceed?", options:
   - "Provide more context" (description: "Supply additional information -- Stage 1 investigation will re-run") -- **only if `bugfix.context_retries < 2`**; omit after 2 retries to prevent infinite loops
   - "Pair debug" (description: "Get diagnostic guidance for manual debugging")
   - "Close as unreproducible" (description: "Mark the bug as unreproducible and skip to Stage 9")
   On "Provide more context": re-run Stage 1 with user's additional context.
   On "Pair debug": provide diagnostic guidance, then pause for user.
   On "Close as unreproducible": set `abort_reason` to "Bug unreproducible", skip to Stage 9 (LEARN).
4. The requirement has already been stripped of the `bugfix:` / `fix:` prefix at PREFLIGHT.
5. After reproduction completes, the planner output is replaced by the bug investigator's fix plan (root cause + targeted fix). Proceed to VALIDATE.

Write `.forge/stage_2_notes_{storyId}.md` with reproduction and root cause details.
Update state: `story_state` -> `"PLANNING"`, set `domain_area`, `risk_level` (bugfix default: LOW unless root cause spans 3+ files -> MEDIUM), add `plan` timestamp.
Mark Plan as completed.

**If `mode_config.stages.plan.agent == "fg-160-migration-planner"`:**

1. Dispatch `fg-160-migration-planner` instead of `fg-200-planner`
   [dispatch fg-160-migration-planner]
2. The migration planner uses its own state machine (MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY) -- see `fg-160-migration-planner.md` for details
3. The requirement has already been stripped of the `migrate:` / `migration:` prefix at PREFLIGHT

**If `mode_config.stages.plan.agent == "fg-050-project-bootstrapper"`:**

1. Dispatch `fg-050-project-bootstrapper` instead of `fg-200-planner`
2. The bootstrapper infers project structure, build system, and architecture from the requirement description -- see `fg-050-project-bootstrapper.md` for details
3. The requirement has already been stripped of the `bootstrap:` prefix at PREFLIGHT
4. After bootstrapping completes, downstream stages honor `mode_config` overrides:
   - **Stage 3 (VALIDATE):** `mode_config.stages.validate.perspectives` provides bootstrap-scoped perspectives. `challenge_brief_required: false`.
   - **Stage 4 (IMPLEMENT):** `mode_config.stages.implement.skip: true` -- skip entirely. Transition directly from VALIDATE (GO) to VERIFY.
   - **Stage 5 (VERIFY):** Runs normally -- build + lint + tests must pass.
   - **Stage 6 (REVIEW):** `mode_config.stages.review.batch_override` provides reduced reviewer set. `target_score` is `pass_threshold`.

### SS2.2 Standard Planning (no mode_config.stages.plan.agent override)

Dispatch `fg-200-planner` with a **<2,000 token** prompt:
[dispatch fg-200-planner]

```
Create an implementation plan for: [requirement]

Exploration results (summarized):
[list relevant file paths, pattern files, existing tests, gaps -- NOT raw agent output]

PREEMPT learnings to apply:
[list matched PREEMPT items from forge-log.md]

Domain hotspots:
[list hotspot entries for this domain from forge-config.md]

Conventions file: [path from config]
Scaffolder patterns: [from config]

Spec stories (from --spec):
[## Stories block from spec file if --spec was used, else omit this section entirely]
```

**Documentation decision traceability:** If graph is available and documentation was discovered:
- Run "Decision Traceability" query for packages in the plan scope
- Include `DocDecision` and `DocConstraint` summaries in planner input
- Planner should note when tasks conflict with existing decisions -> create "Generate ADR" sub-task
- ADR sub-tasks are created when a decision meets 2+ significance criteria: alternatives evaluated (Challenge Brief has 2+ alternatives), cross-cutting impact (3+ packages or 2+ layers), irreversibility, security/compliance implications, precedent-setting

Extract from the planner's response:
- **Risk level** (LOW / MEDIUM / HIGH)
- **Stories** (1-3) with Given/When/Then acceptance criteria
- **Tasks** (2-8) with parallel groups (max 3 groups)
- **Test strategy**

Update state: `story_state` -> `"PLANNING"`, set `domain_area`, `risk_level`, add `plan` timestamp.

**Domain validation:** After planner completes, verify `domain_area` is set in state.json. If missing or empty, default to `"general"` and log WARNING: "domain_area not set by planner -- defaulting to general". See `shared/domain-detection.md` for the full detection algorithm and known domain list.

### SS2.3 Cross-Repo and Multi-Service Tasks

**Cross-Repo Task Detection:**

When `related_projects` is configured in `forge.local.md`, the planner should additionally:

1. Check if any planned tasks affect API contracts (OpenAPI specs, shared types, proto files, GraphQL schemas)
2. For each affected contract, identify related projects that consume or produce the contract
3. Create cross-repo tasks for each affected related project (e.g., "Update frontend types for new API field")
4. Tag cross-repo tasks with `cross_repo: true` and `target_project: {project_name}` in the plan
5. Group cross-repo tasks into a final parallel group that runs AFTER the main repo implementation completes

**Multi-Service Task Decomposition:**

In multi-service mode (components with `path:` entries), the planner must:
1. Identify which services are affected by the requirement.
2. Create per-service tasks -- each task targets exactly one service.
3. Tag each task with its `component` name (e.g., `component: user-service`).
4. Note cross-service dependencies in the task ordering (e.g., "payment-service event schema" must be defined before "notification-service consumer").
5. Shared libraries (`shared:` component) get their own tasks if the requirement affects them.

**Linear tracking:**

```
forge-linear-sync.sh emit plan_complete '<plan_json>'
```

(The sync script handles availability checking internally.)

Write `.forge/stage_2_notes_{storyId}.md` with planning decisions.

Mark Plan as completed.

---

## Stage 3: VALIDATE

**story_state:** `VALIDATING` | **TaskUpdate:** Mark "Stage 2: Plan" -> `completed`, Mark "Stage 3: Validate" -> `in_progress`

### SS3.1 Mode-Aware Validation

Check `state.json.mode_config.stages.validate` for overrides (set at PREFLIGHT via mode overlay).
If `override.skip`: skip this stage entirely.
If `override.perspectives`: use those validation perspectives instead of the defaults.

**Bugfix Validation (mode_config.stages.validate.perspectives overrides defaults):**

Dispatch `fg-210-validator` with 4 bugfix-specific perspectives (instead of the standard 7):
[dispatch fg-210-validator (bugfix)]

```
Validate this bugfix plan:

Bug: [description from ticket or raw input]
Root cause: [hypothesis from stage 2 notes]
Confidence: [from state.json.bugfix.root_cause.confidence]
Affected files: [from state.json.bugfix.root_cause.affected_files]
Reproduction test: [from state.json.bugfix.reproduction.test_file]

Validation perspectives:
- root_cause_validity: Is the identified root cause consistent with the reported symptoms?
- fix_scope: Is the proposed fix minimal and targeted? No scope creep.
- regression_risk: Could the fix break related functionality?
- test_coverage: Does the reproduction test adequately verify the fix will work?

Conventions file: [path from config]
```

Process verdict normally (GO/REVISE/NO-GO). On REVISE, re-dispatch `fg-020-bug-investigator` Phase 2 (not `fg-200-planner`).

### SS3.2 Standard Validation (all other modes)

Dispatch `fg-210-validator` with a **<2,000 token** prompt:
[dispatch fg-210-validator]

```
Validate this implementation plan:

Plan (summarized):
[requirement, risk, steps with file paths, parallel groups, test strategy]

Validation perspectives: [from config -- default 7: Architecture, Security, Edge Cases, Test Strategy, Conventions, Approach Quality, Documentation Consistency]
Conventions file: [path from config]
Domain area: [area]
Risk level: [from plan]
```

### SS3.3 Process Verdict and Contract Validation

**Process Verdict:**

| Verdict | Action |
|---------|--------|
| **GO** | Proceed to contract validation (if applicable), then decision gate |
| **REVISE** | Amend the plan based on findings, re-dispatch `fg-200-planner` with rejection reasons, then re-validate. Max: `validation.max_validation_retries` (default: 2). After max, escalate as NO-GO. |
| **NO-GO** | Show findings to user and ask for guidance. Pipeline pauses. |
| **NO-GO (spec-level)** | If validator findings indicate the spec itself is problematic (contradictory ACs, infeasible scope, missing domain context), suggest reshaping instead of replanning. Present via AskUserQuestion: "Reshape spec" (re-run `/forge-shape` with validator findings as context), "Try replanning" (re-dispatch planner), "Abort". |

Increment `validation_retries` on each REVISE verdict.

**Spec-level issue detection:** If any validator finding contains keywords "contradictory", "mutually exclusive", "infeasible", "spec-level", or if 3+ findings reference acceptance criteria wording (not implementation), treat as spec-level NO-GO. The distinction matters: implementation issues can be re-planned, but spec issues require reshaping with the user.

**Contract Validation (conditional, dispatch fg-250-contract-validator):**

After plan validation passes (GO), check if cross-repo contract validation is needed.

**Condition:** Dispatch only when ALL of the following are true:
1. `related_projects` is configured in `forge.local.md` (at least one entry)
2. The plan includes tasks that affect API contracts (OpenAPI specs, shared types, proto files, GraphQL schemas) -- check file paths in the plan for patterns like `*.proto`, `*api*spec*`, `*openapi*`, `*graphql*`, `*schema*`, or files in shared contract directories
3. `fg-210-validator` returned GO (do not run contract validation on REVISE or NO-GO)

Dispatch `fg-250-contract-validator` with:

```
Validate API contract changes in this plan:

Affected contract files:
[list of contract-related file paths from the plan]

Related projects:
[related_projects entries from config -- name, path, framework]

Plan summary:
[requirement + tasks affecting contracts]
```

**Process verdict:**

| Verdict | Action |
|---------|--------|
| **SAFE** | Proceed to decision gate -- no breaking contract changes detected |
| **BREAKING** | Add contract findings to stage notes. If all breaking changes have corresponding cross-repo tasks in the plan, proceed with WARNING. If breaking changes lack consumer-side tasks, return to `fg-200-planner` for plan amendment (counts toward `validation_retries`). |

**If not dispatched** (conditions not met): skip silently, proceed to decision gate.

### SS3.4 Decision Gate

After validation passes (GO), compare plan `risk_level` against `auto_proceed_risk` from config:

| Plan Risk | Config Threshold | Action |
|-----------|-----------------|--------|
| LOW | any | Proceed automatically |
| MEDIUM | MEDIUM or higher | Proceed automatically |
| MEDIUM | LOW | Show plan, ask user |
| HIGH | HIGH or ALL | Proceed automatically |
| HIGH | MEDIUM or lower | Show plan, ask user |

When proceeding automatically, announce briefly:
> "Pipeline proceeding with [RISK] risk plan ([N] stories, [M] tasks). Validation: GO. Reply 'stop' to pause."

When asking the user for plan approval, show the full plan and validation verdict, then **use AskUserQuestion** with header "Plan", question "The plan has been validated. How would you like to proceed?", options: "Approve" (description: "Proceed with this plan -- start implementation"), "Revise" (description: "I have feedback -- please adjust the plan"), "Abort" (description: "Cancel the pipeline run").

**Linear tracking:**

```
forge-linear-sync.sh emit validate_complete '<verdict_json>'
```

(The sync script handles availability checking internally.)

Write `.forge/stage_3_notes_{storyId}.md` with validation analysis.

Update state: add `validate` timestamp.

Mark Validate as completed.

---

## Stage 4: IMPLEMENT

**story_state:** `IMPLEMENTING` | **TaskUpdate:** Mark "Stage 3: Validate" -> `completed`, Mark "Stage 4: Implement" -> `in_progress`

If `dry_run` is true in state.json, skip this stage and all subsequent stages. The pipeline already output the dry-run report after VALIDATE.

### SS4.1 Pre-Implementation Setup

**Git Checkpoint:**

Before dispatching any implementer, create a checkpoint for rollback safety:

```bash
git add -A && git commit -m "wip: pipeline checkpoint pre-implement" --allow-empty
```

Record the SHA in `state.json.last_commit_sha`.

**Verify Worktree:**

Verify worktree exists at `.forge/worktree`. If not (should not happen after PREFLIGHT), abort with error `WORKTREE_MISSING`.

All subsequent implementation, scaffolding, and testing happens inside the worktree. Dispatched agents receive the worktree path as their working directory.

**Documentation Prefetch:**

If `context7_libraries` is configured, resolve and query context7 MCP for current API docs. If context7 is unavailable, fall back to conventions file + codebase grep, and log a warning.

### SS4.2 Mode-Aware Implementation

Check `state.json.mode_config.stages.implement` for overrides (set at PREFLIGHT via mode overlay).
If `override.skip`: skip this stage entirely (e.g., bootstrap mode skips IMPLEMENT).
If `override.agent` exists: dispatch that agent instead of the default.

### SS4.3 Execute Tasks

For each parallel group (sequential order, groups 1 -> 2 -> 3):

  **Note:** When the group has 2+ tasks, scaffolders and implementers run in separate phases -- scaffolders first (serial), then conflict detection, then implementers (parallel). See SS4.5 for the complete execution sequence.

  For each task in the group (concurrent up to `implementation.parallel_threshold`):

  a. If `scaffolder_before_impl: true` in config: dispatch `fg-310-scaffolder` with task details, scaffolder patterns, conventions file path. Scaffolder generates boilerplate, types, TODO markers.
     [dispatch fg-310-scaffolder]

  b. Write tests (RED phase -- tests defining expected behavior, expected to fail).

  c. Dispatch `fg-300-implementer` with a **<2,000 token** prompt containing ONLY that task's details:
     [dispatch fg-300-implementer]

  ```
  Implement this task:
  [task description, files to create/modify, acceptance criteria]

  Commands: build=[from config], test_single=[from config]
  Conventions file: [path from config]
  PREEMPT checklist: [matched items]

  Implementation rules:
  1. Follow TDD: write test first, then implement, then verify
  2. Do NOT duplicate tests -- grep existing tests first
  3. Test business behavior, not implementation details
  4. Do NOT test framework behavior
  5. KDoc/TSDoc on all public interfaces
  6. Functions under ~40 lines
  7. No deep nesting (>3 levels)
  8. Follow pattern files exactly
  9. Boy Scout Rule: improve code you touch (safe, small, local improvements only)
  ```

  d. Verify with `commands.build` or `commands.test_single` from config.

### SS4.4 Checkpoints and Failure Isolation

**Checkpoints:**

After each task completes, write `.forge/checkpoint-{storyId}.json` (see `shared/state-schema.md` for format):
- Record task status (pass/fail/skipped), files created/modified, fix attempts
- Update `tasks_remaining`

**Failure Isolation:**

If a task fails after `max_fix_loops` attempts: record as failed, continue with remaining tasks in the group. Other tasks are not blocked by one failure.

After all groups complete, write `.forge/stage_4_notes_{storyId}.md` with implementation decisions.

Extract from results: steps completed vs failed, files created/modified, fix loop count, unresolved failures, test coverage notes.

### SS4.5 Parallel Conflict Detection

**Timing:** Conflict detection runs AFTER all scaffolders in the group have completed but BEFORE any implementer in the group is dispatched. This ensures file lists from scaffolder output are final. Sequence for each parallel group:

1. Run all scaffolders in the group (serially -- scaffolders are fast and their output is needed for conflict detection)
2. Dispatch `fg-102-conflict-resolver` to analyze task dependencies
3. Dispatch implementers for the conflict-free groups (parallel up to `parallel_threshold`)
4. After implementers complete, process any serialized sub-groups from the conflict resolver's output

Dispatch `fg-102-conflict-resolver`:

```
sub_task = TaskCreate("Analyzing task conflicts", activeForm="Analyzing task conflicts")
result = dispatch fg-102-conflict-resolver "analyze --items ${task_list_json}"
TaskUpdate(sub_task, status="completed")
```

Read `parallel_groups`, `serial_chains`, `conflicts` from stage notes written by fg-102. Use these to determine dispatch order -- conflict-free tasks run in parallel, conflicting tasks are serialized into sub-groups.

This check runs at IMPLEMENT time, not PLAN time, because task file lists are finalized during scaffolding.

### SS4.6 Component-Scoped Dispatch and Frontend Polish

**Component-Scoped Dispatch (multi-component projects):**

Each dispatch scoped to one component: set active component state to `"IMPLEMENTING"`, include ONLY that component's convention stack, commands, and working directory path. Cross-component tasks: process primary component first (typically backend), then dependents in order -- always serialized, never parallel when one depends on the other's output.

**Frontend Creative Polish (conditional, dispatch fg-320-frontend-polisher):**

After `fg-300-implementer` completes a task for a frontend component, optionally dispatch the creative polisher for visual refinement.

**Condition:** Only dispatch when ALL of the following are true:
1. The completed task created or modified `.tsx`, `.jsx`, `.svelte`, or `.vue` component files
2. The component's framework is `react`, `nextjs`, or `sveltekit`
3. `frontend_polish.enabled` is true in the component's config (default: true for frontend components)

Dispatch `fg-320-frontend-polisher` with:
[dispatch fg-320-frontend-polisher]

```
Polish this frontend implementation:

Changed component files: [list of .tsx/.jsx/.svelte files from the completed task]
Conventions file: [component's convention stack path]
Design direction: [from frontend_polish.aesthetic_direction if configured, else "professional and distinctive"]
Viewport targets: [from frontend_polish.viewport_targets, default: 375, 768, 1280]
Design theory: ${CLAUDE_PLUGIN_ROOT}/shared/frontend-design-theory.md

Constraints:
- DO NOT change business logic or break tests
- Run test command after changes: [component's commands.test]
```

**On success:** Tests still pass + visual polish applied. Proceed to next task or VERIFY.

**On failure/timeout:** Log WARNING: `"Frontend polish skipped -- {reason}."` Proceed without polish. The implementation is already correct and tested -- polish is enhancement, not correctness. Do NOT invoke the recovery engine.

**Linear tracking:**

```
forge-linear-sync.sh emit implement_complete '<result_json>'
```

(The sync script handles availability checking internally.)

Update state: add `implement` timestamp.

Mark Implement as completed.

**Post-IMPLEMENT Graph Update:**

If `graph.enabled` and files changed: run `update-project-graph.sh` with changed files. Update `state.json.graph` (last_update_stage=4, stale=false). On failure: WARNING, set stale=true, continue.

**Graph Transaction Failure Handling:**

All graph Cypher generators (`build-project-graph.sh`, `incremental-update.sh`, `update-project-graph.sh`, `enrich-symbols.sh`) emit `:begin`/`:commit` transaction boundaries. When feeding this output to Neo4j (via `cypher-shell` or MCP):
- If any statement within the transaction fails: execute `:rollback` to discard partial changes
- Log the failure as INFO (not recovery-engine material): `"Graph update failed: {error}. Rolled back. Pipeline continues with stale graph."`
- Set `state.json.integrations.neo4j.available = false` to prevent further graph operations in this run
- The pipeline continues -- graph is optional, never blocking

---

## Stage 5: VERIFY

**story_state:** `VERIFYING` | **TaskUpdate:** Mark "Stage 4: Implement" -> `completed`, Mark "Stage 5: Verify" -> `in_progress`

**Entry guard:** Before entering Stage 5, verify that at least one implementation task completed successfully. If all tasks failed after max retries, escalate to user per `stage-contract.md` Stage 5 entry guard. Do NOT proceed to VERIFY with zero successful tasks.

### SS5.1 VERIFY Phase A -- Build & Lint

Read `.forge/.hook-failures.log` if it exists. If non-empty, count entries and log in stage notes, then delete the file.

Read `.forge/.check-engine-skipped`. If present and count > 0, store in `state.json.check_engine_skipped` and log in stage notes: `'{N} file edits had inline checks skipped (hook timeout/error). Running full verification now.'`

Dispatch `fg-505-build-verifier`:
[dispatch fg-505-build-verifier]

```
Verify build and lint pass.

Commands: build={commands.build}, lint={commands.lint}
Inline checks: {quality_gate.inline_checks from config}
Max fix loops: {implementation.max_fix_loops from config}
Check engine skipped: {count from .forge/.check-engine-skipped}
Conventions file: {conventions_file path}
```

Parse the VERDICT line from the agent's output.

If verdict == "PASS": proceed to Phase B (SS5.2).
If verdict == "FAIL": call `forge-state.sh transition phase_a_failure --guard "verify_fix_count=N" --guard "max_fix_loops=M" --guard "total_iterations=I" --guard "max_iterations=J"` and follow returned action.

### SS5.2 VERIFY Phase B -- Test Gate (dispatch fg-500-test-gate)

Dispatch `fg-500-test-gate` with config:
[dispatch fg-500-test-gate]

```
Run test suite and analyze results.
Test command: [test_gate.command from config]
Analysis agents: [test_gate.analysis_agents from config]
```

1. If tests pass: dispatch `test_gate.analysis_agents` for coverage/quality analysis
2. If tests fail: dispatch `fg-300-implementer` with failing test details, then re-run tests. Increment `test_cycles`.
3. **Max:** `test_gate.max_test_cycles` from config (separate counter from build fix loops)

If max test cycles exhausted, escalate to user.

Quality is NOT re-run after a test fix unless the fix introduces substantial new code.

**Per-Component Verification (multi-component projects only):**

For multi-component projects: identify changed components, run Phase A + Phase B per component using that component's `commands`. Independent components verify in parallel; a passed component is not re-verified unless another fix touches its files. All changed components must pass. State: `"VERIFYING"` -> `"VERIFIED"` / `"FAILED"`. Single-component projects skip this.

**Linear tracking:**

```
forge-linear-sync.sh emit verify_complete '<result_json>'
```

(The sync script handles availability checking internally.)

Write `.forge/stage_5_notes_{storyId}.md` with verification details, fix loop history.

Update state: `verify_fix_count`, `test_cycles`, add `verify` timestamp.

Mark Verify as completed.

### SS5.3 Convergence Engine Integration

After IMPLEMENT completes, the orchestrator enters the convergence loop.
All convergence decisions are made by `forge-state.sh transition` -- do NOT reimplement the algorithm.

**Phase 1 (Correctness): VERIFY (this stage)**

- On verify_pass: `forge-state.sh transition verify_pass --guard "convergence.phase=correctness"` -> transitions to REVIEWING
- On phase_a_failure: `forge-state.sh transition phase_a_failure --guard "verify_fix_count=N" --guard "max_fix_loops=M" --guard "total_iterations=I" --guard "max_iterations=J"` -> may return to IMPLEMENTING or ESCALATED
- On tests_fail: `forge-state.sh transition tests_fail --guard "phase_iterations=N" --guard "max_test_cycles=M" --guard "total_iterations=I" --guard "max_iterations=J"` -> may return to IMPLEMENTING or ESCALATED

Each Phase 1 iteration increments both `convergence.total_iterations` and `total_retries`. If `total_retries >= total_retries_max`, escalate regardless of convergence state.

**Phase transition:** On VERIFY pass, set `convergence.phase = "perfection"`, reset `convergence.phase_iterations = 0`, append to `convergence.phase_history`.

**Post-VERIFY / Pre-REVIEW Graph Updates:**

Post-VERIFY: if fix iterations changed additional files (delta from last_update_files), update graph with delta only. Pre-REVIEW: if `graph.stale == true`, run full update. If stale == false, no-op. Failures: WARNING + stale=true, continue.

---

## Stage 6: REVIEW

**story_state:** `REVIEWING` | **TaskUpdate:** Mark "Stage 5: Verify" -> `completed`, Mark "Stage 6: Review" -> `in_progress`

**Kanban:** `move_ticket` to `review/` + `generate_board` (per boot SS0.21).

### SS6.1 Pre-Review Context

Before dispatching `fg-400-quality-gate`:
- If graph available: run "Documentation Impact" and "Stale Docs Detection" queries
- Include results in quality gate context alongside changed files

Check `state.json.mode_config.stages.review` for overrides (set at PREFLIGHT via mode overlay).
If `override.skip`: skip this stage entirely.
If `override.reviewers`: use that reviewer set instead of the config-driven batches.

**Reduced Review Batch (mode_config.stages.review.batch_override):**

Reduced review batch (overrides config-driven batches):
- Always dispatch: `fg-410-code-reviewer`, `fg-411-security-reviewer`
- If frontend files in diff (`*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.css`): add `fg-413-frontend-reviewer`
- Skip by default: `fg-416-backend-performance-reviewer`

Dispatch the reduced batch as a single batch (no multi-batch sequencing needed). After completion, proceed to scoring (SS6.2) normally.

### SS6.2 Batch Dispatch (standard / migration / bootstrap modes)

Read `quality_gate` config. For each `batch_N` defined in config:
[dispatch per protocol]
1. Dispatch all agents in the batch **in parallel**
2. Wait for batch completion before starting next batch
3. Partial failure: proceed with available results, note coverage gap (see `shared/scoring.md`)

After all batches: run `quality_gate.inline_checks` (scripts or skills from config).

**Version Compatibility Check (dispatch fg-417-version-compat-reviewer):**

After all quality gate batches and inline checks complete, dispatch `fg-417-version-compat-reviewer` as a cross-cutting review agent. This runs independently of the config-driven batch system because version compatibility is a universal concern across all frameworks.

**Condition:** Only dispatch when `detected_versions` in state.json contains at least one non-`"unknown"` version. Skip silently otherwise.

Dispatch `fg-417-version-compat-reviewer` with:

```
Analyze version compatibility for this project:

Changed files: [list from quality gate]
Detected versions: [detected_versions from state.json]
Conventions file: [path from config]
```

Merge the returned findings into the quality gate's finding pool before scoring. Findings use the `QUAL-COMPAT` category and follow the standard unified format.

**On failure/timeout:** Log INFO-level coverage gap: `"fg-417-version-compat-reviewer timed out -- version compatibility not reviewed."` Proceed to scoring without version-compat findings. If the agent covers a critical domain (it does -- dependency conflicts can cause runtime failures), use WARNING severity (-5) for the coverage gap finding per `shared/scoring.md` critical agent gap rule.

### SS6.3 Score and Verdict

1. Collect all findings from all batches + inline checks
2. Deduplicate by `(file, line, category)` -- keep highest severity (see `shared/scoring.md`)
3. Score: `max(0, 100 - critical_weight*CRITICAL - warning_weight*WARNING - info_weight*INFO)` (weights from `forge-config.md` scoring section; defaults: 20/5/2)
4. Append score to `state.json.score_history` (e.g., `[85, 78, 92]` across cycles)

After scoring, call the appropriate forge-state.sh transition:
- score >= target_score: `forge-state.sh transition score_target_reached`
- delta > plateau_threshold: `forge-state.sh transition score_improving --guard "total_iterations=N" --guard "max_iterations=M"`
- score plateau: `forge-state.sh transition score_plateau --guard "plateau_count=N" --guard "plateau_patience=P" --guard "total_iterations=I" --guard "max_iterations=J" --guard "score=S" --guard "pass_threshold=T" --guard "concerns_threshold=C"`
- score regressing: `forge-state.sh transition score_regressing --guard "delta=D" --guard "oscillation_tolerance=T"`
- diminishing returns: `forge-state.sh transition score_diminishing --guard "diminishing_count=N" --guard "score=S" --guard "pass_threshold=T"`

Follow the returned action (dispatch implementer, transition to safety_gate, or escalate).

**Component-Aware Quality Gate (multi-component projects):**

Multi-component: annotate each file with its owning component's convention stack. Backend-scoped reviewers get backend files only; frontend-scoped get frontend files only; cross-cutting reviewers (security, etc.) get all files. Unified scoring -- one score/verdict per cycle, not per component. Each finding annotated with `component: {name}`. Cross-service consistency: verify event schemas, API contracts, shared types match. Single-component projects skip this.

**State Machine Reference:**

All state transitions in this section follow the formal transition table in `shared/state-transitions.md`. The orchestrator MUST look up (current_state, event, guard) in that table for every control flow decision. Do not interpret prose descriptions as state transition logic -- use the table. If a (state, event) pair is not in the table, log ERROR and escalate.

**Decision Logging:**

On every state transition, convergence evaluation, recovery attempt, and escalation, emit a decision log entry to `.forge/decisions.jsonl` per `shared/decision-log.md`. Fire-and-forget -- logging failure does not block the pipeline.

### SS6.4 Convergence-Driven Fix Cycle

Fix cycles are driven by the convergence engine (`shared/convergence-engine.md`). After scoring, read the action returned by forge-state.sh (SS6.3) and execute:

- **IMPROVING:** Send ALL findings to `fg-300-implementer`, increment `convergence.phase_iterations` and `convergence.total_iterations` and `quality_cycles` and `total_retries`, re-dispatch REVIEW.
- **Score target reached:** Transition to `"safety_gate"`. Dispatch VERIFY (Stage 5) one final time.
- **PLATEAUED:** Apply score escalation ladder (SS6.5), document unfixable findings in `convergence.unfixable_findings`, transition to `"safety_gate"`.
- **REGRESSING:** Escalate immediately.
- **Safety gate:** Dispatch VERIFY (Stage 5 -- full build + lint + tests). If VERIFY passes, set `convergence.safety_gate_passed = true`, proceed to DOCS. If VERIFY fails, transition back to `"correctness"` (Phase 1) -- Phase 2 fixes broke something.

**Code Review Feedback Rigor:**

Before dispatching `fg-300-implementer` with review findings (from quality gate, PR reviewer, or convergence fix cycle), the orchestrator MUST follow this verification pattern:

1. **READ** the feedback completely -- every finding, not just the summary.
2. **VERIFY** each finding against the actual code. Is it a real issue or a false positive? Read the referenced file and line.
3. **EVALUATE** severity honestly -- do not inflate (to force a fix) or deflate (to skip inconvenient work).
4. **PUSH BACK** where warranted: if a finding is technically incorrect, document the reasoning and exclude it from the implementer dispatch. Record excluded findings with justification in stage notes.
5. **YAGNI check:** If a reviewer suggests adding features not in the spec (logging, metrics, validation beyond requirements, defensive patterns not justified by the threat model), mark as `SCOUT-*` and defer -- do not include in the implementer dispatch.

Only after this verification pass, dispatch the implementer with the verified findings.

**Do NOT implement review feedback blindly. Verify each finding before acting.**

**Pre-dispatch budget check:** Before dispatching implementer, check `total_retries` against `total_retries_max`. If within 1 of max, log WARNING in stage notes.

If convergence exhausted (`total_iterations >= max_iterations`) and score still < target:
> "Pipeline converged at score {score}/{target_score} after {total_iterations} iterations. {unfixable_count} unfixable findings documented. Proceeding per score escalation ladder."

### SS6.5 Score Escalation Ladder and Oscillation Detection

**Score Escalation Ladder:**

After convergence exhaustion (plateau or max_iterations reached), apply this ladder to determine next action:

| Score | Action |
|---|---|
| 95-99 | Proceed. Document remaining INFOs in Linear. |
| 80-94 | Proceed with CONCERNS. Each unfixed WARNING documented in Linear with: what, why, options. Create follow-up tickets for architectural WARNINGs. |
| 60-79 | Pause. Full findings posted to Linear. Ask user with escalation format. |
| < 60 | Pause. Recommend abort or replan. Present architectural root cause analysis. |
| Any CRITICAL | Hard stop. NEVER proceed. Post to Linear. Present the CRITICAL with full context and options. |

**Oscillation Detection (via Convergence Engine):**

Oscillation detection is part of the convergence engine's REGRESSING state (see `shared/convergence-engine.md`). The orchestrator:

1. After each REVIEW scoring, computes `delta = score_current - score_previous` using `score_history[]`
2. If `delta < 0` and `abs(delta) > oscillation_tolerance`: set `convergence.convergence_state = "REGRESSING"`, escalate to user
3. If `delta < 0` and `abs(delta) <= oscillation_tolerance`: allow one more cycle (plateau_count increments). Second consecutive dip escalates.

**Interaction with max_iterations:** Oscillation tolerance does NOT extend beyond `convergence.max_iterations`. If `total_iterations >= max_iterations`, the run ends regardless of oscillation state.

Track convergence state in stage notes: `"Convergence: {state} (iteration {N}/{max}, delta {delta}, plateau {plateau_count}/{patience})"`.

Write `.forge/stage_6_notes_{storyId}.md` with review report, score history.

Update state: `quality_cycles`, add `review` timestamp.

Mark Review as completed.
