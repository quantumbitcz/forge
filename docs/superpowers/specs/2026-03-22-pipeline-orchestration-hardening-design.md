# Pipeline Orchestration Hardening — Design Spec

**Date:** 2026-03-22
**Scope:** All pipeline agents, shared contracts, skills, plugin manifests, MCP integrations
**Status:** Approved for implementation

---

## Context

A thorough audit of every pipeline agent (`pl-*`), cross-cutting reviewer, shared contract, recovery system, health check, skill, and plugin manifest revealed structural gaps that affect reliability at scale. This spec addresses all findings in 16 areas.

The driving principles behind every change:

- **Autonomy first.** The pipeline should complete runs with zero user interaction in the common case. The user is asked only when a decision is genuinely 50/50 or when a critical failure requires human judgment. Everything else — architectural choices, naming, patterns, trade-offs with a clear winner — the agent decides and documents why.
- **Score 100 or explain why not.** Every finding gets fixed or gets a written explanation. Nothing is silently accepted.
- **Safety before speed.** Before deleting, disabling, or removing anything, verify it wasn't intentional. A disabled plugin, a skipped test, a commented-out config line — these may exist for a reason. Check git blame, check comments, check conventions before touching them.
- **Transparency.** Every run produces a human-readable recap of what was done, why, and what was left. Stakeholders who never touch the CLI should be able to read the recap and understand the full picture.

---

## 1. Large Codebase & Multi-Module Support

### Why this matters

The orchestrator assumes a single `module` value in config. If a requirement spans a Kotlin backend and a React frontend (common in full-stack features), the pipeline uses one module's conventions for everything. Explorers have no file limits — a naive exploration of a 100K-file monorepo would exhaust context or timeout.

### What changes

**Orchestrator (`pl-100`)** gets a new section: `## Large Codebase Handling`

```
When dispatching any agent, enforce these limits:
- Exploration: max 50 files per pass, grouped by domain area
- Implementation: max 20 files per task. If a task lists more, split it
- Review: max 100 files per batch agent dispatch
- If the project has multiple modules (e.g., both `build.gradle.kts` and
  `package.json` at different paths), treat each as a separate sub-pipeline
  with its own conventions file

For multi-module requirements:
1. EXPLORE dispatches per-module explorers in parallel
2. PLAN creates stories grouped by module, with integration points explicit
3. IMPLEMENT runs per-module, sequentially (backend first, then frontend)
4. REVIEW dispatches module-appropriate reviewers for each module's files
```

**Why per-module sequential, not parallel:** Backend changes often define the API contract that frontend consumes. Running them in parallel would mean the frontend implements against a non-existent API. Backend-first ensures contracts exist before frontend work starts.

**Multi-module state tracking:** For multi-module runs, `state.json` gets a `modules` array tracking per-module progress:

```json
{
  "modules": [
    { "module": "kotlin-spring", "story_state": "IMPLEMENTING", "story_id": "story-1" },
    { "module": "react-vite", "story_state": "PLANNING", "story_id": "story-2" }
  ]
}
```

The orchestrator manages module transitions: backend module completes through VERIFY before frontend module enters IMPLEMENT.

---

## 2. Git Worktree Enforcement

### Why this matters

The implementer currently works directly in the user's working tree. If the user is editing files while the pipeline runs, conflicts are guaranteed. Even worse, a failed pipeline run could leave the working tree in a half-modified state.

### What changes

**Orchestrator** gets a new section: `## Worktree Policy`

```
At IMPLEMENT stage entry:
1. Create a worktree: `git worktree add .pipeline/worktree -b pipeline/{story-id}`
2. All implementation, scaffolding, and testing happens inside the worktree
3. Dispatched agents receive the worktree path, not the main working directory
4. On SHIP success: merge worktree branch back to the base branch, clean up
5. On SHIP failure or abort: preserve worktree for manual inspection

Ordering with checkpoint:
1. First: git checkpoint commit in main tree (`git add -A && git commit`)
2. Then: create worktree branching from that checkpoint commit
3. All subsequent work happens in the worktree
This ensures the worktree starts from a clean, committed state.

Health check before worktree creation:
- Verify no existing worktree at .pipeline/worktree (clean up stale ones)
- Verify working tree is clean (no uncommitted changes that would block branch creation)
- If working tree is dirty: warn user, offer to stash, never force-clean

Check engine compatibility:
- The check engine hook (`engine.sh --hook`) uses `git rev-parse --show-toplevel`
  to find the project root. Inside a worktree, this resolves correctly to the
  worktree root. No changes needed to engine.sh.
- Agents dispatched inside the worktree receive the worktree path as their
  working directory. All relative paths resolve within the worktree.

NEVER run `git worktree remove --force` or `git clean -f` without user confirmation.
```

**Why worktrees instead of branches:** Worktrees give physical isolation — the user's IDE stays on their branch, the pipeline works in its own directory. Branches alone would still modify the same files on disk.

---

## 3. Config Validation in PREFLIGHT

### Why this matters

If `dev-pipeline.local.md` doesn't exist, has malformed YAML, or references a non-existent conventions file, the pipeline fails at a random later stage with a confusing error. Fail-fast in PREFLIGHT is better.

### What changes

**Orchestrator PREFLIGHT section** gets explicit validation steps:

```
After reading config files, validate:

1. dev-pipeline.local.md exists and has valid YAML frontmatter
   - If missing: ERROR — "Run /pipeline-init to set up this project"
   - If YAML invalid: ERROR — show parse error, line number

2. Required fields present: project_type, framework, module, commands.build,
   commands.test, quality_gate
   - If missing: ERROR — list missing fields

3. conventions_file path resolves to a readable file
   - If missing: WARN — "Conventions file not found at {path}.
     Using universal defaults. Framework-specific checks will be skipped."
   - Continue with degraded mode, do NOT abort

4. pipeline-config.md exists (optional)
   - If missing: INFO — "No runtime config found. Using defaults."

5. All agents referenced in quality_gate batches exist
   - Plugin agents: verify the agent name matches a file in agents/
   - Builtin agents: accept any name (Claude Code resolves these)
   - If plugin agent missing: WARN — "Agent {name} not found.
     Will be skipped during REVIEW."
```

**Why warn-and-continue instead of hard-fail for conventions:** A missing conventions file shouldn't block the entire pipeline. Universal checks still work. The user gets told, and module-specific checks are skipped. This respects the autonomy principle — fix what you can, report what you can't.

**Convention file verification timing:** The PREFLIGHT check is a one-time validation that the path resolves. However, each agent that reads the conventions file should also handle the case where it's become unreadable between stages (deleted, permissions changed). The rule: PREFLIGHT does the initial check and warns. Each agent does a defensive `Read` and if it fails, proceeds with universal defaults and logs INFO. No agent should crash because the conventions file disappeared mid-run.

---

## 4. Forbidden Actions

### Why this matters

The orchestrator has principles but no hard prohibitions. Without explicit "DO NOT" rules, agents can drift into destructive behavior — modifying shared contracts, reading entire codebases, asking the user unnecessary questions, or deleting things that were intentionally disabled.

### What changes

**Every agent** gets a `## Forbidden Actions` section:

```
## Forbidden Actions

These are hard rules. Violating them is always wrong, regardless of context.

### Universal (ALL agents including orchestrator):
- DO NOT modify shared contracts (scoring.md, stage-contract.md, state-schema.md)
- DO NOT modify conventions files during a pipeline run
- DO NOT modify CLAUDE.md directly (propose changes only)
- DO NOT continue after a CRITICAL finding without user approval
- DO NOT create files outside .pipeline/ and the project source tree
- DO NOT force-push, force-clean, or destructively modify git state
- DO NOT delete or disable anything without first checking if it was intentional
  (check git blame, comments, config flags before removing)
- DO NOT hardcode commands, agent names, or file paths — always read from config

### Orchestrator-only (pl-100):
- DO NOT read source files — dispatched agents do this
- DO NOT ask the user outside the 3 defined touchpoints (start, approval, escalation)
- DO NOT dispatch agents without explicit scope and file limits

### Implementation agents (pl-300, pl-310):
- DO NOT modify files outside the task's listed file paths
- DO NOT add features beyond what acceptance criteria specify
- DO NOT refactor across module boundaries during Boy Scout improvements
```

**The "check before deleting" rule explained:** When an agent encounters something that looks unused — a disabled hook, a commented-out config line, a skipped test — it must NOT assume it's dead code. The pattern:

```
Before removing/disabling/deleting anything:
1. Check git blame — who added it and when?
2. Check surrounding comments — is there a "disabled because..." note?
3. Check config flags — is there a `disabled: true` or `skip: true`?
4. If intentionally disabled: leave it alone, note in stage notes
5. If genuinely dead: remove it, document in recap why it was removed
6. If unclear: leave it alone. Log as INFO finding for human review.

Default: preserve. The cost of keeping dead code is low. The cost of
removing something intentionally disabled is high.
```

---

## 5. Autonomy Model

### Why this matters

The pipeline's value is autonomous execution. Every unnecessary user question costs time and breaks flow. But some decisions genuinely need human input — shipping those without asking creates worse problems.

### What changes

**Orchestrator** gets a new section: `## Autonomy & Decision Framework`

```
## Autonomy & Decision Framework

The pipeline operates with MAXIMUM autonomy. The user is interrupted only when:
1. Pipeline starts (present the requirement interpretation)
2. Genuine 50/50 architectural decisions (see below)
3. CRITICAL findings that can't be auto-resolved
4. PR approval

For ALL other decisions, the agent decides and documents the reasoning.

### Decision Hierarchy

When you encounter a design, architecture, or implementation choice:

**Clear winner (70/30 or better)** — Choose it silently.
Document: "Decision: {chosen} because {reason}" in stage notes.
Example: "Using sealed interface hierarchy — matches existing pattern in
UserPersisted/UserNotPersisted/UserId."

**Slight lean (60/40)** — Choose the simpler option.
Document both options and why the simpler one won.
Prefer: fewer files, less coupling, easier to reverse, matches existing patterns.
Example: "Chose plain text over Markdown for notes — YAGNI, can upgrade later
without schema change."

**Genuine 50/50** — Ask the user.
Present: both options, concrete trade-offs, your slight lean if any.
Example: "Should expired subscriptions be soft-deleted or hard-deleted?
Soft-delete preserves audit trail but grows the table. Hard-delete is simpler
but loses history. Your data retention policy determines this — I can't infer it."

**Requires domain knowledge** — Ask the user.
Example: "The coaching session model has a 'status' field. What are the valid
transitions? (e.g., can a cancelled session be reopened?)"

### What is NEVER worth asking about
- Implementation details (data structure, algorithm choice)
- Code style (conventions file decides)
- Test strategy (TDD rules decide)
- Naming (follow existing patterns)
- Whether to fix a WARNING (always fix if possible)
- Whether to apply Boy Scout improvements (always apply within budget)
```

**Why this level of detail:** Without explicit guidance, AI agents tend toward two extremes — either asking about everything (annoying, slow) or deciding everything silently (risky). The hierarchy gives a clear decision tree that minimizes interruptions while protecting against bad autonomous calls.

---

## 6. Error Handling & Recovery Enhancements

### Why this matters

Current agents have sparse error handling. Missing config files, malformed YAML, git conflicts, flaky tests, timeout scenarios — all undefined. The pipeline either crashes or enters fix loops that never terminate.

### What changes

**6.1 Command timeouts (all agents that run shell commands)**

```
Every shell command gets a timeout (all configurable via dev-pipeline.local.md):
- commands.build: 120 seconds (configurable via commands.build_timeout)
- commands.test: 300 seconds (configurable via commands.test_timeout)
- commands.lint: 60 seconds (configurable via commands.lint_timeout)
- Inline check scripts: 5 seconds (existing hooks.json timeout: 5000ms)

On timeout:
- Classify as TOOL_FAILURE
- Log: "Command '{cmd}' timed out after {N}s"
- Report to orchestrator for retry or escalation
```

**6.2 Flaky test detection (`pl-500-test-gate`)**

```
On first test failure:
1. Re-run ONLY the failing tests (not full suite)
2. If they PASS on re-run: mark as FLAKY
   - Log WARNING: "Flaky test: {test_name} — passed on re-run"
   - Proceed (don't enter fix loop for flaky tests)
   - Post to Linear ticket: "Flaky test detected: {test_name}"
3. If they FAIL again: genuine failure, enter normal fix loop
```

**Why re-run only failing tests:** Re-running the entire suite for one flaky test wastes minutes. Targeted re-run confirms flakiness in seconds.

**6.3 Standardized escalation format (all agents)**

```
When escalating to user, always use this format:

## Pipeline Paused: {STAGE_NAME}

**What happened:** {specific failure — not "something went wrong"}
**What was tried:** {N} attempts — {strategy 1}, {strategy 2}, ...
**Root cause (best guess):** {analysis based on error output}
**Options:**
1. {Concrete action} — `/pipeline-run --from={stage}`
2. {Alternative} — what changes to make first
3. Abort — no action needed, state preserved

Never escalate with just "Pipeline blocked." Always include diagnosis.
```

**6.4 Recovery budget**

```
The existing recovery engine defines 7 strategies (transient-retry,
state-reconstruction, agent-reset, tool-diagnosis, dependency-health,
resource-cleanup, graceful-stop). Each strategy has its own internal
retry limit.

New constraint: Max 5 total strategy *applications* per pipeline run.
The recovery engine tries strategies in priority order. After 5 total
applications (across any combination of strategies), stop trying and
escalate. This means in the worst case, the engine tries 5 different
strategies (or the same one 5 times, or any mix).

If recovery itself fails: write minimal state.json with
{ "recovery_failed": true, "last_known_stage": N } and escalate
with playbook. Never enter infinite recovery loops.

This cap is a new constraint added to shared/recovery/recovery-engine.md.
```

**6.5 Oscillation detection (`pl-400-quality-gate`)**

```
Track score across fix cycles. If score DECREASES between cycles
(e.g., 85 → 78), flag as "quality regression during fix cycle."
- Post to Linear: "Fix cycle {N} made things worse: {score_before} → {score_after}"
- Escalate: don't keep fixing if fixes are introducing new problems
```

---

## 7. Score 100 Philosophy

### Why this matters

The current pipeline accepts CONCERNS (score 60-79) as "good enough" after max cycles. This means warnings accumulate across runs. The new philosophy: every finding gets fixed or gets a written explanation.

### What changes

**7.1 Escalation ladder**

| Score | Action |
|---|---|
| 95-99 | Proceed. Remaining INFOs documented in Linear. Likely style nits or intentional trade-offs. |
| 80-94 | Proceed with CONCERNS. Each unfixed WARNING documented in Linear with: what, why, options. Create follow-up tickets for architectural WARNINGs. |
| 60-79 | Pause. Full findings posted to Linear. Ask user: "Score {N}/100 after {max} cycles. {M} findings remain. Options: 1) I fix specific items you choose, 2) Proceed as-is, 3) Abort." |
| < 60 | Pause. Recommend abort or major replan. Present architectural analysis of root cause. |
| Any CRITICAL remaining | Hard stop. NEVER proceed. Post to Linear. Present specific CRITICAL with full context and options. |

**7.2 Unfixable finding documentation**

When a finding survives all fix cycles, the quality gate posts a structured comment on the Linear Epic:

```markdown
## Unfixed Finding: {CATEGORY-CODE}

**What:** {description of the issue}
**Why it wasn't fixed:** {specific reason — not "couldn't fix it"}
**Options:**
1. {Option A} — {trade-offs, estimated effort}
2. {Option B} — {trade-offs, estimated effort}
3. {Accept for now} — {risk assessment at current scale}

**Recommendation:** {which option and why}
```

**Why document everything:** A finding that's "unfixable in this sprint" is still a finding. The documentation creates a paper trail. The follow-up ticket ensures it doesn't get forgotten. The Linear comment means anyone reviewing the epic can see the full quality picture.

---

## 8. Boy Scout Rule — Formalized

### Why this matters

The implementer already mentions "leave code better than you found it" but it's vague and untracked. Agents don't know what's allowed, how much, or how to report it.

### What changes

**8.1 New finding category: `SCOUT-*`**

Boy Scout improvements are logged as positive findings (no point deduction):

```
file:line | SCOUT-CLEANUP | INFO | Extracted 45-line method into helper | Was violating 40-line limit
file:line | SCOUT-NAMING  | INFO | Renamed `data` to `coachingSession` | Improved readability
file:line | SCOUT-IMPORT  | INFO | Removed 3 unused imports | Dead code cleanup
```

**8.2 Hard boundaries**

```
## Boy Scout Rules (all implementation agents)

You MUST improve code you touch. You MUST NOT go looking for things to fix.

Allowed (within files you're already modifying):
- Remove unused imports
- Rename unclear variables (same file only)
- Extract overlong functions (>40 lines)
- Add missing KDoc/TSDoc on functions you modified
- Replace deprecated API calls you encounter
- Fix obvious typos in comments

Forbidden:
- Modifying files not in your task's file list
- Refactoring across module boundaries
- Changing public API signatures
- Adding features "while you're here"
- Restructuring test files you didn't change
- Removing disabled code/config without checking intent (see Section 4)

Budget: Max 10 Boy Scout changes per task. If you find more,
log them as INFO findings for the next run's PREEMPT.
```

**Why a budget:** Without limits, an eager agent could "Boy Scout" an entire file, turning a 2-line change into a 200-line diff. The budget keeps improvements proportional to the actual task.

---

## 9. Recap Agent — `pl-720-recap`

### Why this matters

The retrospective (`pl-700`) updates config and learnings for the pipeline's future runs. But humans — PR reviewers, project stakeholders, future developers — need a different view: what was done, why decisions were made, what improved, and what was left. Currently, this information is scattered across stage notes, state.json, and Linear comments.

### What changes

**New agent: `agents/pl-720-recap.md`**

```yaml
name: pl-720-recap
description: Creates a human-readable markdown recap of the entire pipeline run.
  Reads all stage notes, state, quality reports, and Boy Scout logs to produce a
  single document explaining what was built, why decisions were made, what was
  improved, what remains unfixed, and key metrics. Suitable for PR descriptions,
  team updates, and project history.
tools: [Read, Glob, Grep, Bash]
```

Note: The recap agent does not list Linear MCP tools in its frontmatter. It uses
whatever tools are available at runtime (Linear tools are visible in the agent's
prompt context if the MCP is active). If Linear is unavailable, the recap is
written to file only — no error.

**Execution order within Stage 9 (LEARN):**
1. `pl-700-retrospective` runs first — updates config, captures learnings
2. `pl-720-recap` runs second — reads all outputs including retrospective results
3. Orchestrator closes the Linear Epic AFTER both agents complete
This ensures the recap can reference learnings from the retrospective.

**Input (from orchestrator):**
- All stage notes paths (`.pipeline/stage_*_notes_*.md`)
- State.json (counters, timestamps, integrations)
- Quality gate report (findings, scores, verdicts)
- Boy Scout log (SCOUT-* findings)
- PR URL (if created)
- Linear Epic ID (if tracked)

**Output: `.pipeline/reports/recap-{date}-{story-id}.md`**

```markdown
# Pipeline Recap: {requirement summary}

**Date:** {ISO date}
**Duration:** {minutes}
**PR:** #{number} ({url})
**Linear:** {epic-id}
**Quality Score:** {final-score}/100 ({verdict})

---

## What Was Built

{Per-story summary: what files were created/modified, what functionality
was added, how it integrates with existing code}

## Key Decisions Made

{Table: decision | chosen option | rejected option | reasoning}

Explanation: For each non-obvious decision, explain the trade-off analysis.
Why was this the right call for this project, at this time?

## Quality Improvements (Boy Scout)

{Table: file | change | impact}

These are improvements made to existing code while implementing the feature.
They weren't requested — they were found along the way and fixed.

## Unfixed Findings

{Table: finding | severity | why unfixed | follow-up ticket}

For each: what would it take to fix, and why wasn't it done in this run?

## Metrics

{Table: files created, files modified, tests written, coverage, fix cycles,
score progression, PREEMPT items applied, Boy Scout improvements}

## Learnings Captured

{List of PREEMPT items added or updated, with context on what triggered them}
```

**Where the recap goes:**
1. Written to `.pipeline/reports/recap-{date}-{story-id}.md`
2. If Linear available: summarized (max 2000 chars) as comment on Epic
3. If PR exists: "What Was Built" and "Key Decisions" sections appended to PR description
4. Referenced in orchestrator's final report

**Why a separate agent instead of extending pl-700:** Single responsibility. The retrospective optimizes the pipeline. The recap explains to humans. Mixing them would make both worse — the retrospective would get bloated with prose, and the recap would get polluted with config tuning details.

---

## 10. Linear MCP Integration

### Why this matters

The pipeline creates stories, epics, and tasks during planning — but they only exist in stage notes. Linear tracking gives the team visibility into pipeline progress, creates a permanent record of decisions, and enables filtering/searching across runs.

### What changes

**10.1 Config (added to all 12 module templates)**

```yaml
linear:
  enabled: true
  team: "DEV"
  project: ""
  labels: ["pipeline-managed"]
```

If `linear.enabled: false` or missing, skip all Linear calls. No agent should fail if Linear is unavailable.

**10.2 Lifecycle**

| Stage | Linear Action | Target |
|---|---|---|
| PLAN | Create Epic + Stories + Tasks | Epic from requirement, Stories from plan, Tasks under Stories |
| VALIDATE | Comment on Epic: validation verdict | Epic |
| IMPLEMENT | Move Task: Backlog → In Progress → Done | Each Task as it completes |
| VERIFY | Comment on Epic: build/test results | Epic |
| REVIEW | Comment on Epic: quality score + findings | Epic (per cycle) |
| SHIP | Link PR to Epic, move Stories to In Review | Epic + Stories |
| LEARN | Comment with retrospective summary, close Epic | Epic |

**10.3 State tracking**

Add to `state-schema.md`:
```json
{
  "linear": {
    "epic_id": "DEV-123",
    "story_ids": ["DEV-124", "DEV-125"],
    "task_ids": { "task-1": "DEV-126", "task-2": "DEV-127" }
  }
}
```

**10.4 Agent instruction (added to every pipeline agent)**

```
## Linear Tracking

If `integrations.linear.available` is true in state.json:
- Update the corresponding Linear issue after completing your work
- Set status to the appropriate value for this stage
- Add a comment summarizing your output (max 500 chars)
- If blocked or failed: add comment explaining why

If Linear is unavailable: skip silently. Never fail because Linear is down.
```

**Why Linear is optional:** Not every project uses Linear. Not every user has the MCP installed. The pipeline must work perfectly without it. Linear is an enhancement, not a dependency.

---

## 11. Adaptive MCP Integration

### Why this matters

The pipeline can benefit from many MCPs beyond Linear — Playwright for preview validation, Slack for notifications, Context7 for documentation, GitHub for PR creation. But requiring them would make the plugin unusable for anyone who doesn't have them all installed.

### What changes

**11.1 PREFLIGHT MCP detection**

The orchestrator checks its available tools for known MCP patterns:

```
MCP detection (PREFLIGHT):
Check for tool name patterns in your available tools:
- mcp__plugin_linear_linear__*     → Linear available
- mcp__plugin_playwright_playwright__* → Playwright available
- mcp__plugin_slack_slack__*       → Slack available
- mcp__plugin_figma_figma__*       → Figma available
- mcp__plugin_context7_context7__* → Context7 available

Store results in state.json under "integrations".
```

**11.2 Suggest missing MCPs (informational, never blocking)**

```
## Optional Integrations

Detected:
 Linear — task tracking enabled
 Context7 — documentation lookup enabled

Not detected (install for enhanced features):
 Playwright — preview validation. Install: claude mcp add playwright -- npx -y @anthropic/mcp-playwright
 Slack — notifications. Install: claude mcp add slack -- npx -y @anthropic/mcp-slack

Pipeline will run fine without these. They add capabilities, not requirements.
```

**11.3 Per-agent MCP usage**

| Agent | Linear | Playwright | Slack | Context7 | GitHub |
|---|---|---|---|---|---|
| pl-100-orchestrator | Create Epic/Stories | — | Notify start/finish | — | — |
| pl-200-planner | Create Tasks | — | — | Lookup docs | — |
| pl-300-implementer | Update Task status | — | — | Lookup docs | — |
| pl-400-quality-gate | Comment findings | — | — | — | — |
| pl-500-test-gate | Comment test results | — | — | — | — |
| pl-600-pr-builder | Link PR to Epic | — | Notify PR ready | — | Create PR |
| pl-650-preview-validator | — | Smoke + E2E + Visual | — | — | — |
| pl-700-retrospective | Close Epic + summary | — | Post summary | — | — |
| pl-720-recap | Post recap comment | — | — | — | — |

**11.4 Graceful degradation (in every agent)**

```
If an MCP call fails unexpectedly (was available but errored):
- Log WARNING in stage notes
- Continue without it
- NEVER fail the pipeline because an optional integration is down
- NEVER retry MCP calls more than once
```

**Why we do NOT bundle MCPs in `.mcp.json`:** Linear, Slack, Playwright all require user credentials. Auto-starting them without setup would produce auth errors on every plugin load. The plugin discovers and adapts to whatever the user has.

---

## 12. Plugin Manifest & Public Repo

### Why this matters

The plugin is distributed as a public GitHub repo via the `quantumbitcz` marketplace. The manifests need to be correct for marketplace install to work.

### What changes

**`plugin.json` updates:**

```json
{
  "name": "dev-pipeline",
  "version": "1.1.0",
  "description": "Autonomous 10-stage development pipeline with multi-language support, self-healing recovery, and generalized code quality checks",
  "author": {
    "name": "QuantumBit s.r.o.",
    "url": "https://github.com/quantumbitcz"
  },
  "repository": "https://github.com/quantumbitcz/dev-pipeline",
  "homepage": "https://github.com/quantumbitcz/dev-pipeline",
  "license": "Proprietary",
  "keywords": [
    "pipeline", "tdd", "code-review", "quality-gate", "linear",
    "kotlin", "typescript", "python", "go", "rust", "swift", "java", "c"
  ],
  "category": "development",
  "hooks": "hooks/hooks.json"
}
```

Changes: version bump to 1.1.0, added `homepage`, explicit `hooks` path, added `linear` keyword.

**`marketplace.json`** — no changes needed. `source: "./"` is correct for a public repo where the plugin IS the repo.

**Installation flow (for users):**
```
/plugin marketplace add quantumbitcz
/plugin install dev-pipeline@quantumbitcz
```

**Why version bump matters:** Claude Code caches plugins by version. If you change plugin code but don't bump the version, users won't see updates. Every release needs a version bump.

---

## 13. Shared Contract Updates

### 13.1 `state-schema.md` — new fields

```json
{
  "version": "1.1",
  "integrations": {
    "linear": { "available": true, "team": "DEV" },
    "playwright": { "available": true },
    "slack": { "available": false },
    "context7": { "available": true }
  },
  "linear": {
    "epic_id": "DEV-123",
    "story_ids": ["DEV-124"],
    "task_ids": { "task-1": "DEV-126" }
  },
  "cost": {
    "wall_time_seconds": 0,
    "stages_completed": 0
  },
  "recovery_applied": [],
  "scout_improvements": 0
}
```

**Why `version` field:** Schema evolution is inevitable. Without a version field, old state files from previous runs can't be auto-migrated. The recovery engine needs to know which schema it's reading.

### 13.2 `scoring.md` — additions

- Add `SCOUT-*` as a tracked (non-penalty) category
- Add time limit guidance: "Each review cycle should complete within 10 minutes"
- Add findings cap: "If >100 raw findings before dedup, agents should return top 100 by severity with note"
- Add score sub-bands for Linear documentation granularity (these are operational guidance, not new verdicts — the PASS/CONCERNS/FAIL verdicts remain unchanged):
  - 95-99 (PASS): remaining INFOs documented in Linear, no follow-up tickets
  - 80-94 (PASS): each unfixed WARNING documented in Linear with options, architectural WARNINGs get follow-up tickets
  - 60-79 (CONCERNS): full findings posted to Linear, user asked for guidance
  - <60 (FAIL): recommend abort or replan

### 13.3 Health checks — new checks

Add to `pre-stage-health.sh`:
- `.claude/` directory writability (PREFLIGHT)
- Disk space check: min 100MB free (IMPLEMENT, VERIFY)
- Git state: no merge conflicts, no rebase in progress (IMPLEMENT)
- Module-specific tool: Java version for JVM, Node version for JS, Python version for Python

Add to `dependency-check.sh`:
- Context7 API probe (IMPLEMENT — needed for doc prefetch)
- Git remote reachability (SHIP — needed before PR creation)

---

## 14. Agent-Specific Enhancements

### 14.1 `pl-200-planner`

- Add token budget per section: risk matrix max 300 tokens, stories max 500 each
- Add: "If requirement spans multiple modules, create one story per module with explicit integration points"
- Add: "If conventions file is unreadable, log WARNING and proceed with universal defaults"
- Add: "Max 2 minutes brainstorming alternatives. If none clearly better, proceed as-is"
- Add: "If task affects >20 files, it's too large — split into sub-tasks"

### 14.2 `pl-210-validator`

- Add per-perspective budget: ~20% of output tokens each
- Add: "Read conventions file ONCE, cache across all 5 perspectives"
- Add: "If >20 findings, return top 20 by severity with truncation note"
- Add: "If conventions file missing, skip convention checks, proceed with universal checks"

### 14.3 `pl-300-implementer`

- Add: "Max 5 minutes per fix attempt. If stuck, try a different approach or report failure"
- Add: "On flaky test: re-run once. If passes, proceed. If fails again, fix loop"
- Add: "DO NOT modify files outside the task's listed file paths"
- Change: function size from "~30-40 lines" to "max 40 lines (hard limit)"
- Change: nesting from "~3 levels" to "max 3 levels (hard limit)"
- Add: "Before removing or disabling any existing code, check git blame and comments to verify it wasn't intentionally placed"

### 14.4 `pl-310-scaffolder`

- Add: "Verify pattern file exists (`ls`) before reading. If missing, report ERROR"
- Add: "Max 3 compilation fix attempts. After 3, report partial scaffold"
- Add: "If generated file >400 lines, split into sub-components per module conventions"

### 14.5 `pl-400-quality-gate`

- Add: "If >50 deduplicated findings, return top 50 by severity. Note total count"
- Add: oscillation detection (Section 6.5)
- Add: "If all batches skipped (no conditions met), return PASS with WARNING: coverage gap"

### 14.6 `pl-500-test-gate`

- Add: command timeout (Section 6.1)
- Add: flaky test detection (Section 6.2)
- Add: "Coverage exception list read from module conventions, not hardcoded"
- Add: "If >500 tests in suite, run targeted tests first (matching changed files)"

### 14.7 `pl-600-pr-builder`

- Add: "If `gh pr create` fails, retry once. If still fails, output manual git commands"
- Add: "If branch has existing open PR, update existing instead of creating new"
- Add: "Append recap's 'What Was Built' and 'Key Decisions' to PR description"

### 14.8 `pl-050-project-bootstrapper`

- Add: "If context7 unavailable, use latest stable from conventions file — DO NOT guess versions"
- Add: "After scaffold: run build + test. If fails after 3 attempts, report partial scaffold"
- Add: "If bootstrap description is ambiguous, ask ONE question to clarify language/framework"
- Add: "Validate every generated file compiles/parses before reporting success"

### 14.9 `pl-150-test-bootstrapper`

- Add: "If test framework is not installed, report ERROR with install command — do not attempt to install it"
- Add: "If coverage tool is unavailable, skip coverage report, log INFO, continue with test generation"
- Add: "Before generating tests for a file, check if tests already exist (grep for imports of the source file in test directories)"
- Reviewed and confirmed: existing constraints (never mock everything, realistic data, 3 fix attempts max, idempotent) are adequate

### 14.10 `pl-160-migration-planner`

- Add: "If context7 is unavailable for API mapping, use the library's CHANGELOG or migration guide from the repo — do not guess API equivalents"
- Add: "If circular dependency discovered mid-migration, pause the current phase and report with dependency graph"
- Reviewed and confirmed: existing constraints (never mix old/new API in same file, each batch own commit, pause on 3+ rollbacks) are the most rigorous of any agent — no further hardening needed

### 14.11 `pl-250-contract-validator`

- Add: "If contract file has no git baseline (new contract, not yet committed), treat all fields as 'added' — no breaking changes possible"
- Add: "If `git show` fails for baseline, log WARNING and run current-state-only analysis (structure validation without diff)"
- Reviewed and confirmed: existing 15 constraints are the most disciplined in the pipeline — no further hardening needed

### 14.12 `pl-710-feedback-capture`

- Add: "If conventions file is missing or unreadable, classify feedback without convention cross-reference and note the limitation"
- Add: "If extracted rule contradicts existing conventions, flag as 'CONFLICT' severity and include both the user's feedback and the convention text"
- Reviewed and confirmed: existing constraints (never modify CLAUDE.md, never modify code, always write feedback file) are adequate

### 14.13 `pl-650-preview-validator`

- Add: "If Playwright MCP becomes unreachable mid-check, stop the current check, score with available results, log which checks were skipped"
- Add: "If preview URL returns non-200 after 3 retries (30s apart), mark as CRITICAL and skip remaining checks — do not wait indefinitely"
- Reviewed and confirmed: existing constraints (10 min timeout, graceful degradation, max 1 fix cycle) are good but the Playwright dependency needs explicit fallback guidance since it's the only agent whose core function depends on an optional MCP

### 14.14 `pipeline-init` skill

- Add: "DETECT phase: validate git repo, `.claude/` writable, no existing config (or ask to overwrite)"
- Add: "VALIDATE phase: run build AND test — report which command failed"
- Add: "If module detection ambiguous (multiple project files), ask user which is primary"
- Add: "After init, run `engine.sh --dry-run` to verify check engine works"

---

## 15. New Skills

### 15.1 `/pipeline-status` (universal)

Reads `.pipeline/state.json` and latest stage notes. Shows: current stage, last run result, quality score, pending findings, Linear epic (if tracked).

### 15.2 `/pipeline-reset` (universal)

Safely removes `.pipeline/` directory after confirming with user. Preserves `pipeline-log.md` (learnings) — only clears run state.

### 15.3 `/verify` (universal)

Runs build + lint + test for the current module without a full pipeline. Reads commands from `dev-pipeline.local.md`. Quick smoke test.

### 15.4 `/security-audit` (universal)

Runs module-appropriate security scanner: `npm audit`, `cargo audit`, `pip-audit`, `./gradlew dependencyCheckAnalyze`, `govulncheck`. Aggregates results.

### 15.5 `/codebase-health` (universal)

Runs the check engine in full `--review` mode outside the pipeline context. Reports all findings across all layers.

### 15.6 `/migration` (universal)

Thin launcher for `pl-160-migration-planner`. Accepts migration description as input.

**Why only 6 skills:** YAGNI. The audit identified 30+ possible skills, but most are speculative. These 6 cover the gaps users actually hit: "what's the pipeline doing?" (status), "start fresh" (reset), "quick check" (verify), "is it secure?" (audit), "how's the codebase?" (health), "upgrade a dependency" (migration). More can be added per-module as demand emerges.

---

## 16. Deprecated File Cleanup (Already Done)

The previous session already completed:
- Removed 5 deprecated react-vite hooks (wrappers to engine.sh)
- Removed 3 deprecated kotlin-spring scripts (wrappers to engine.sh)
- Fixed 4 ghost agent references in module templates
- Created `backend-performance-reviewer` and `frontend-performance-reviewer`
- Cleaned `frontend-reviewer` (removed security/performance leaks)
- Added performance reviewers + missing cross-cutting agents to all 12 module templates

---

## Implementation Priority

### Phase 1: Foundation (highest impact, enables everything else)

1. Orchestrator hardening (Sections 1-5): forbidden actions, config validation, autonomy model, worktree, large codebase
2. Error handling (Section 6): timeouts, flaky tests, escalation format, recovery budget
3. State schema updates (Section 13.1): version field, integrations, Linear IDs
4. Plugin manifest (Section 12): version bump, homepage

### Phase 2: Quality & Tracking

5. Score 100 philosophy (Section 7): escalation ladder, unfixable finding docs
6. Boy Scout formalization (Section 8): SCOUT-* category, boundaries, budget
7. Linear integration (Section 10): lifecycle, per-agent instructions
8. MCP detection (Section 11): PREFLIGHT probe, suggestions

### Phase 3: Agents & Skills

9. Agent-specific enhancements (Section 14): all 14 agents (9 core + 5 reviewed-and-confirmed)
10. Recap agent (Section 9): new `pl-720-recap`
11. New skills (Section 15): 6 skills
12. Health check additions (Section 13.3)

### Phase 4: Module Templates

13. Update all 12 module `local-template.md` files with Linear config section

---

## File Change Summary

| Category | Modify | Create |
|---|---|---|
| Orchestrator (`pl-100-orchestrator.md`) | 1 | 0 |
| Pipeline agents (pl-200, pl-210, pl-300, pl-310, pl-400, pl-500, pl-600, pl-700, pl-710, pl-150, pl-160, pl-250, pl-650) | 13 | 1 (`pl-720-recap`) |
| Review agents (6 cross-cutting: architecture, security, frontend, frontend-performance, backend-performance, infra-deploy) | 6 | 0 |
| Skills | 0 | 6 |
| Shared contracts (state-schema, scoring, stage-contract) | 3 | 0 |
| Recovery engine (recovery-engine.md — add budget cap) | 1 | 0 |
| Health checks (2 scripts) | 2 | 0 |
| Plugin manifests (plugin.json) | 1 | 0 |
| Module templates (12 modules) | 12 | 0 |
| Bootstrapper + init (pl-050, pipeline-init skill) | 2 | 0 |
| **Total** | **41** | **7** |

---

## Phase 2 Enhancements (2026-03-22)

The following enhancements were designed and implemented in the same session:

1. **`--dry-run` flag** — Pipeline preview: runs PREFLIGHT→EXPLORE→PLAN→VALIDATE then stops. No worktree, no Linear, no file changes.
2. **Parallel conflict detection** — Tasks sharing files in the same parallel group are automatically serialized. Planner also warned to avoid conflicts by design.
3. **Timeout enforcement** — Command timeouts (configurable per-project), agent dispatch timeouts (30 min stage cap), and stage/pipeline timeouts with checkpoint-before-stop guarantee.
4. **Pipeline observability** — Progress reporting at each stage transition (`[STAGE N/10]`), error reporting with diagnostic context, cost tracking (wall time, stages completed).
5. **Error taxonomy** — 15 classified error types with recovery strategies in `shared/error-taxonomy.md`. Pre-classified errors skip heuristic matching in the recovery engine.
6. **Scoring customization** — Per-project overrides for formula weights and verdict thresholds in `pipeline-config.md`. Constraints enforced at PREFLIGHT.
7. **Agent effectiveness tracking** — Retrospective tracks per-agent metrics (time, findings, false positive rate, coverage). Auto-tuning triggers at 30% FP rate, zero findings, or >120s average.
8. **PREEMPT lifecycle** — Confidence decay (10 unused runs: HIGH→MEDIUM→LOW→ARCHIVED), archival to bottom of pipeline-log.md, promotion trigger at 3+ applications.
9. **Cross-project learning promotion** — Patterns appearing in 3+ runs with HIGH confidence are proposed for module-level learnings. 3+ projects triggers conventions upgrade proposal.
10. **Convention drift detection** — SHA256 first 8 chars of conventions file stored at PREFLIGHT. Agents compare mid-run and warn if file changed.
11. **Agent communication protocol** — Formal documentation of data flow (stage notes, shared findings context, state.json ownership, agent restrictions) in `shared/agent-communication.md`.
12. **`/pipeline-history` skill** — View quality score trends, common findings, agent effectiveness, and PREEMPT health across runs.
13. **`/pipeline-rollback` skill** — Safe undo with 4 modes: worktree, post-merge revert, Linear cleanup, state-only reset.

### Phase 2 File Summary

| Category | Files |
|---|---|
| Orchestrator (dry-run, conflicts, timeouts, observability, drift) | 1 modified |
| Planner (conflict prevention) | 1 modified |
| Quality gate (inter-batch dedup reference) | 1 modified |
| Retrospective (effectiveness, PREEMPT lifecycle, cross-project) | 1 modified |
| Shared contracts (error taxonomy, agent communication, scoring, state schema, recovery engine) | 5 modified/created |
| Learnings (effectiveness template, README) | 2 modified/created |
| Skills (pipeline-history, pipeline-rollback) | 2 created |
| Module templates (scoring config) | 2 modified |
| Documentation (CLAUDE.md, spec) | 2 modified |
| **Total** | **17 files** |
