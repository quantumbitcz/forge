# Pipeline Orchestration Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden every pipeline agent with guardrails, error handling, large-codebase support, worktree enforcement, Linear MCP integration, adaptive MCP detection, Boy Scout tracking, and a recap agent — making the pipeline production-ready for autonomous execution.

**Architecture:** All changes are to markdown agent files (`.md`), JSON schemas, bash health check scripts, and skill definitions. No application code. The pipeline is a documentation-only Claude Code plugin. Each agent gets new sections appended or existing sections tightened. Shared contracts get new fields. New skills are thin markdown files.

**Tech Stack:** Markdown (agent definitions), YAML frontmatter, JSON (state schema, plugin manifest), Bash (health check scripts)

**Spec:** `docs/superpowers/specs/2026-03-22-pipeline-orchestration-hardening-design.md`

---

## Phase 1: Foundation

These tasks establish the patterns that all other phases depend on.

---

### Task 1: Harden pl-100-orchestrator — New Sections

This is the largest single change. The orchestrator gets 5 new sections that define the behavior all other agents follow.

**Files:**
- Modify: `agents/pl-100-orchestrator.md`

**Reference:** Spec Sections 1-5 (Large Codebase, Worktree, Config Validation, Forbidden Actions, Autonomy)

- [ ] **Step 1: Read the current orchestrator**

Read the full `agents/pl-100-orchestrator.md` to understand existing structure and section numbering. Identify where new sections should be inserted (after the existing Pipeline Principles section, before Reference Documents).

- [ ] **Step 2: Add `## Large Codebase & Multi-Module Handling` section**

Insert after Section 17 (Pipeline Principles). Content per spec Section 1:
- File limits per dispatch: exploration max 50 files, implementation max 20 files per task, review max 100 files per batch
- Multi-module detection: if project has multiple framework markers at different paths, treat each as sub-pipeline
- Multi-module ordering: backend modules complete through VERIFY before frontend enters IMPLEMENT
- Multi-module state: `modules` array in state.json tracks per-module progress

- [ ] **Step 3: Add `## Worktree Policy` section**

Content per spec Section 2:
- At IMPLEMENT entry: checkpoint commit first, then `git worktree add .pipeline/worktree -b pipeline/{story-id}`
- All implementation in worktree, agents receive worktree path
- On SHIP success: merge back, clean up. On failure: preserve for inspection
- Health checks: no stale worktree, clean working tree, check engine compatibility note
- NEVER `git worktree remove --force` or `git clean -f` without user confirmation

- [ ] **Step 4: Add config validation to PREFLIGHT section (Stage 0)**

Insert validation steps into the existing PREFLIGHT section (Section 3), after config reading. Content per spec Section 3:
- Validate `dev-pipeline.local.md` exists + valid YAML + required fields
- Validate `conventions_file` path resolves (WARN if missing, continue with degraded mode)
- Validate `pipeline-config.md` (INFO if missing, use defaults)
- Validate all agents in `quality_gate` batches exist (WARN if plugin agent missing)

- [ ] **Step 5: Add `## Forbidden Actions` section**

Content per spec Section 4, split into three subsections:
- Universal (all agents): don't modify contracts, conventions, CLAUDE.md, don't force-push, don't delete without checking intent
- Orchestrator-only: don't read source, don't ask user outside touchpoints, don't dispatch without scope/limits
- Implementation agents: don't modify files outside task list, don't add features beyond AC, don't refactor across boundaries

- [ ] **Step 6: Add `## Autonomy & Decision Framework` section**

Content per spec Section 5:
- Decision hierarchy: clear winner (70/30) → slight lean (60/40) → genuine 50/50 → domain knowledge needed
- What is NEVER worth asking about: implementation details, code style, test strategy, naming, whether to fix WARNINGs
- Maximum autonomy principle

- [ ] **Step 7: Add MCP detection to PREFLIGHT**

Insert into PREFLIGHT section. Content per spec Section 11.1-11.2:
- Check available tools for known MCP patterns (linear, playwright, slack, figma, context7)
- Store results in state.json `integrations` field
- Report available/missing MCPs with install suggestions (informational only, never blocking)

- [ ] **Step 8: Add `## Escalation Format` section**

Content per spec Section 6.3:
- Standard template: What happened, What was tried, Root cause, Options with commands
- "Never escalate with just 'Pipeline blocked.' Always include diagnosis."

- [ ] **Step 9: Update Stage 6 (REVIEW) with Score 100 escalation ladder**

Modify the existing Stage 6 section. Content per spec Section 7.1:
- 95-99: proceed, document INFOs in Linear
- 80-94: proceed with CONCERNS, document WARNINGs in Linear with options, create follow-up tickets
- 60-79: pause, post to Linear, ask user
- <60: pause, recommend abort or replan
- Any CRITICAL: hard stop, never proceed
- Add oscillation detection: if score decreases between cycles, flag and escalate

- [ ] **Step 10: Update Stage 9 (LEARN) dispatch order**

Add `pl-720-recap` dispatch after `pl-700-retrospective`. Close Linear Epic after both complete.

- [ ] **Step 11: Add Linear lifecycle to relevant stages**

Insert Linear create/update instructions per spec Section 10.2:
- Stage 2 (PLAN): create Epic + Stories + Tasks
- Stage 3 (VALIDATE): comment on Epic
- Stage 4 (IMPLEMENT): move Tasks Backlog → In Progress → Done
- Stage 5 (VERIFY): comment on Epic with results
- Stage 8 (SHIP): link PR to Epic
- All conditional on `integrations.linear.available` in state.json

- [ ] **Step 12: Validate changes**

```bash
# Check frontmatter is valid
head -6 agents/pl-100-orchestrator.md

# Verify name matches filename
grep "^name:" agents/pl-100-orchestrator.md

# Check all section headers are well-formed
grep "^## " agents/pl-100-orchestrator.md
```

- [ ] **Step 13: Commit**

```bash
git add agents/pl-100-orchestrator.md
git commit -m "feat: harden orchestrator with worktree, multi-module, forbidden actions, autonomy, MCP detection, Linear lifecycle, escalation"
```

---

### Task 2: Update Shared Contracts

**Files:**
- Modify: `shared/state-schema.md`
- Modify: `shared/scoring.md`
- Modify: `shared/stage-contract.md`
- Modify: `shared/recovery/recovery-engine.md`

- [ ] **Step 1: Read all 4 files**

Read each file to understand current structure.

- [ ] **Step 2: Update `state-schema.md`**

Add new fields per spec Section 13.1:
- `version: "1.1"` — schema version for migration
- `integrations` object — MCP detection results
- `linear` object — epic_id, story_ids, task_ids
- `modules` array — per-module state for multi-module runs
- `cost` object — wall_time_seconds, stages_completed
- `recovery_applied` array — which strategies were used
- `scout_improvements` counter — Boy Scout changes count

- [ ] **Step 3: Update `scoring.md`**

Add per spec Section 13.2:
- `SCOUT-*` as tracked non-penalty category (add to Category Codes table)
- `FE-PERF-*` already added in previous session — verify it's there
- Time limit guidance: "Each review cycle should complete within 10 minutes"
- Findings cap: "If >100 raw findings before dedup, agents should return top 100 by severity"
- Score sub-bands for Linear documentation: 95-99 (INFOs only), 80-94 (WARNINGs documented), 60-79 (user asked), <60 (replan)

- [ ] **Step 4: Update `stage-contract.md`**

Add:
- Worktree creation at Stage 4 entry (after checkpoint commit)
- Worktree merge at Stage 8 (SHIP)
- `pl-720-recap` dispatch in Stage 9 (after `pl-700-retrospective`, before Epic close)
- Convention file defensive read note: each agent handles missing conventions independently

- [ ] **Step 5: Update `recovery-engine.md`**

Add recovery budget per spec Section 6.4:
- Max 5 total strategy applications per pipeline run
- If recovery itself fails: write minimal state.json with `recovery_failed: true`
- Escalate with playbook
- Never enter infinite recovery loops

- [ ] **Step 6: Validate**

```bash
# Check all files parse (no broken markdown)
for f in shared/state-schema.md shared/scoring.md shared/stage-contract.md shared/recovery/recovery-engine.md; do
  echo "=== $f ===" && head -3 "$f"
done
```

- [ ] **Step 7: Commit**

```bash
git add shared/state-schema.md shared/scoring.md shared/stage-contract.md shared/recovery/recovery-engine.md
git commit -m "feat: update shared contracts with schema v1.1, SCOUT category, recovery budget, worktree lifecycle"
```

---

### Task 3: Enhance Health Checks

**Files:**
- Modify: `shared/recovery/health-checks/pre-stage-health.sh`
- Modify: `shared/recovery/health-checks/dependency-check.sh`

- [ ] **Step 1: Read both scripts**

Read to understand current check patterns and how to add new ones consistently.

- [ ] **Step 2: Add checks to `pre-stage-health.sh`**

Per spec Section 13.3:
- PREFLIGHT: `.claude/` directory writability check
- IMPLEMENT: disk space check (min 100MB free), git state (no merge conflicts, no rebase in progress)
- VERIFY: module-specific tool version check (java for JVM, node for JS, python for Python — detect from module config)
- SHIP: git remote reachability check

- [ ] **Step 3: Add checks to `dependency-check.sh`**

Per spec Section 13.3:
- Context7 API probe (attempt resolve-library-id with a known library, timeout 5s)
- Git remote reachability (git ls-remote, timeout 5s)

- [ ] **Step 4: Verify scripts are executable**

```bash
chmod +x shared/recovery/health-checks/pre-stage-health.sh shared/recovery/health-checks/dependency-check.sh
bash -n shared/recovery/health-checks/pre-stage-health.sh
bash -n shared/recovery/health-checks/dependency-check.sh
```

- [ ] **Step 5: Commit**

```bash
git add shared/recovery/health-checks/
git commit -m "feat: add health checks for disk space, git state, module tools, context7, remote reachability"
```

---

### Task 4: Update Plugin Manifest

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Read current plugin.json**

- [ ] **Step 2: Update fields**

Per spec Section 12:
- Version: `"1.0.0"` → `"1.1.0"`
- Add `"homepage": "https://github.com/quantumbitcz/dev-pipeline"`
- Add `"hooks": "hooks/hooks.json"` (explicit path)
- Add `"linear"` to keywords array

- [ ] **Step 3: Validate JSON**

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('Valid JSON')"
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump plugin to v1.1.0, add homepage, explicit hooks path"
```

---

## Phase 2: Quality & Tracking

These tasks add the quality philosophy, Boy Scout tracking, and the recap agent.

---

### Task 5: Harden pl-400-quality-gate — Score 100, Oscillation, Linear

**Files:**
- Modify: `agents/pl-400-quality-gate.md`

- [ ] **Step 1: Read current quality gate**

- [ ] **Step 2: Add unfixable finding documentation format**

Add after existing Section 8 (Aim for 100). Content per spec Section 7.2:
- Structured comment template for Linear: What, Why not fixed, Options, Recommendation
- Post on Epic when a finding survives all fix cycles

- [ ] **Step 3: Add oscillation detection**

Add to Section 9 (Fix Cycles). Content per spec Section 6.5:
- Track score across cycles. If score DECREASES, flag "quality regression during fix cycle"
- Post to Linear, escalate — don't keep fixing if fixes introduce new problems

- [ ] **Step 4: Add findings cap**

Add to Section 14 (Output Format):
- "If >50 deduplicated findings, return top 50 by severity. Note: '{N} additional findings truncated'"

- [ ] **Step 5: Add empty-batch handling**

Add to Section 4 (Batch Dispatch):
- "If all batches skipped (no conditions met), return PASS with WARNING: 'No review agents qualified — full coverage gap'"

- [ ] **Step 6: Add Linear tracking instruction**

Add a `## Linear Tracking` section per spec Section 10.4:
- Check `integrations.linear.available` in state.json
- Comment on Epic: quality score, findings summary, unfixed finding details
- If Linear unavailable: skip silently

- [ ] **Step 7: Add Forbidden Actions section**

Add universal forbidden actions from spec Section 4.

- [ ] **Step 8: Validate and commit**

```bash
head -6 agents/pl-400-quality-gate.md
grep "^name:" agents/pl-400-quality-gate.md
git add agents/pl-400-quality-gate.md
git commit -m "feat: harden quality gate with oscillation detection, findings cap, Linear tracking, forbidden actions"
```

---

### Task 6: Harden pl-300-implementer — Boy Scout, Guardrails, Linear

**Files:**
- Modify: `agents/pl-300-implementer.md`

- [ ] **Step 1: Read current implementer**

- [ ] **Step 2: Formalize Boy Scout rule**

Replace or expand the existing Boy Scout section. Content per spec Section 8:
- New `SCOUT-*` finding category (non-penalty)
- Allowed improvements: unused imports, unclear variables, overlong functions, missing docs, deprecated APIs, typos
- Forbidden: files outside task list, cross-module refactoring, public API changes, adding features
- Budget: max 10 changes per task. Log as INFO findings

- [ ] **Step 3: Tighten function/nesting limits**

Change existing guidance per spec Section 14.3:
- Function size: `"~30-40 lines"` → `"max 40 lines (hard limit)"`
- Nesting: `"~3 levels"` → `"max 3 levels (hard limit)"`

- [ ] **Step 4: Add safety-before-deletion rule**

Per spec Section 4:
- "Before removing or disabling any existing code, check git blame and surrounding comments"
- "If intentionally disabled: leave it alone. If genuinely dead: remove and document in recap. If unclear: leave it alone, log as INFO"

- [ ] **Step 5: Add timeout and flaky test guidance**

Per spec Section 6.1 and 6.2:
- "Max 5 minutes per fix attempt. If stuck, try different approach or report failure"
- "On flaky test: re-run ONLY failing test once. If passes on re-run, mark FLAKY and proceed"

- [ ] **Step 6: Add file scope constraint**

Per spec Section 14.3:
- "DO NOT modify files outside the task's listed file paths without explicit justification logged in stage notes"

- [ ] **Step 7: Add Linear tracking, Forbidden Actions, Autonomy sections**

Per spec Sections 4, 5, 10.4:
- Linear: update Task status (In Progress → Done), comment summary
- Forbidden actions: universal subset
- Autonomy: decision framework for implementation choices

- [ ] **Step 8: Validate and commit**

```bash
head -6 agents/pl-300-implementer.md
git add agents/pl-300-implementer.md
git commit -m "feat: harden implementer with Boy Scout formalization, hard limits, safety-before-deletion, flaky test handling, Linear tracking"
```

---

### Task 7: Create pl-720-recap Agent

**Files:**
- Create: `agents/pl-720-recap.md`

- [ ] **Step 1: Write the recap agent**

Full content per spec Section 9. Include:
- YAML frontmatter: name `pl-720-recap`, description, tools `[Read, Glob, Grep, Bash]`
- Identity: human-readable recap writer, reads stage notes + state + quality reports
- Input: all stage note paths, state.json, quality report, Boy Scout log, PR URL, Linear Epic ID
- Output format: the full recap template (What Was Built, Key Decisions, Boy Scout Improvements, Unfixed Findings, Metrics, Learnings)
- Where output goes: `.pipeline/reports/recap-{date}-{story-id}.md`, Linear comment, PR description enrichment
- Context management: read-only (never modify source), output under 3000 tokens for the file (Linear comment summarized to 2000 chars)
- Linear tracking note: uses runtime-available tools, no frontmatter listing
- Forbidden actions: universal subset

- [ ] **Step 2: Validate frontmatter**

```bash
head -6 agents/pl-720-recap.md
grep "^name:" agents/pl-720-recap.md
# Verify name matches filename (without .md)
```

- [ ] **Step 3: Commit**

```bash
git add agents/pl-720-recap.md
git commit -m "feat: add pl-720-recap agent for human-readable pipeline run summaries"
```

---

## Phase 3: Agent Hardening

Each task hardens 1-3 related agents. These are independent and can be parallelized.

---

### Task 8: Harden pl-200-planner and pl-210-validator

**Files:**
- Modify: `agents/pl-200-planner.md`
- Modify: `agents/pl-210-validator.md`

- [ ] **Step 1: Read both agents**

- [ ] **Step 2: Enhance pl-200-planner**

Per spec Section 14.1:
- Add token budget per section: risk matrix max 300 tokens, stories max 500 each
- Add: "If requirement spans multiple modules, create one story per module with explicit integration points"
- Add: "If conventions file is unreadable, log WARNING and proceed with universal defaults — DO NOT guess"
- Add: "Max 2 minutes brainstorming alternatives. If none clearly better, proceed as-is"
- Add: "If task affects >20 files, it's too large — split into sub-tasks"
- Add Linear tracking: create Tasks under Stories
- Add Forbidden Actions: universal subset
- Add Autonomy section

- [ ] **Step 3: Enhance pl-210-validator**

Per spec Section 14.2:
- Add per-perspective budget: ~20% of output tokens each
- Add: "Read conventions file ONCE, cache result across all 5 perspectives"
- Add: "If >20 findings, return top 20 by severity with truncation note"
- Add: "If conventions file missing, skip convention checks, proceed with universal checks only"
- Add Forbidden Actions: universal subset

- [ ] **Step 4: Validate and commit**

```bash
for f in agents/pl-200-planner.md agents/pl-210-validator.md; do
  head -6 "$f" && grep "^name:" "$f"
done
git add agents/pl-200-planner.md agents/pl-210-validator.md
git commit -m "feat: harden planner and validator with token budgets, multi-module support, convention fallbacks"
```

---

### Task 9: Harden pl-310-scaffolder and pl-500-test-gate

**Files:**
- Modify: `agents/pl-310-scaffolder.md`
- Modify: `agents/pl-500-test-gate.md`

- [ ] **Step 1: Read both agents**

- [ ] **Step 2: Enhance pl-310-scaffolder**

Per spec Section 14.4:
- Add: "Verify pattern file exists (`ls`) before reading. If missing, report ERROR, do not guess"
- Add: "Max 3 compilation fix attempts. After 3, report partial scaffold and stop"
- Add: "If generated file exceeds 400 lines, split into sub-components per module conventions"
- Add Forbidden Actions: universal + implementation subset
- Add Linear tracking: update Task status

- [ ] **Step 3: Enhance pl-500-test-gate**

Per spec Section 14.6:
- Add command timeout: `timeout ${test_gate.timeout:-300} ${test_gate.command}`
- Add flaky test detection: re-run only failing tests, mark FLAKY if passes on re-run
- Change: coverage exception list read from module conventions, not hardcoded
- Add: "If >500 tests in suite, run targeted tests first (only tests matching changed files), then full suite"
- Add Linear tracking: comment test results on Epic
- Add Forbidden Actions: universal subset

- [ ] **Step 4: Validate and commit**

```bash
for f in agents/pl-310-scaffolder.md agents/pl-500-test-gate.md; do
  head -6 "$f" && grep "^name:" "$f"
done
git add agents/pl-310-scaffolder.md agents/pl-500-test-gate.md
git commit -m "feat: harden scaffolder and test gate with pattern validation, timeouts, flaky test detection"
```

---

### Task 10: Harden pl-600-pr-builder and pl-050-project-bootstrapper

**Files:**
- Modify: `agents/pl-600-pr-builder.md`
- Modify: `agents/pl-050-project-bootstrapper.md`

- [ ] **Step 1: Read both agents**

- [ ] **Step 2: Enhance pl-600-pr-builder**

Per spec Section 14.7:
- Add: "If `gh pr create` fails, retry once. If still fails, output manual git commands for the user"
- Add: "If branch already has an existing open PR, update the existing PR instead of creating new"
- Add: "Append recap's 'What Was Built' and 'Key Decisions' sections to PR description body"
- Add Linear tracking: link PR to Epic, move Stories to In Review
- Add Forbidden Actions: universal subset

- [ ] **Step 3: Enhance pl-050-project-bootstrapper**

Per spec Section 14.8:
- Add: "If context7 unavailable, use latest stable version from conventions file — DO NOT guess from training data"
- Add: "After scaffold: run build + test commands. If fails after 3 attempts, report partial scaffold with clear error"
- Add: "If bootstrap description is ambiguous (e.g., 'REST API' without language), ask ONE question to clarify"
- Add: "Validate every generated file compiles/parses before reporting success"
- Add Forbidden Actions: universal subset

- [ ] **Step 4: Validate and commit**

```bash
for f in agents/pl-600-pr-builder.md agents/pl-050-project-bootstrapper.md; do
  head -6 "$f" && grep "^name:" "$f"
done
git add agents/pl-600-pr-builder.md agents/pl-050-project-bootstrapper.md
git commit -m "feat: harden PR builder and bootstrapper with retry logic, context7 fallback, validation"
```

---

### Task 11: Harden pl-700-retrospective, pl-710-feedback-capture, and remaining agents

**Files:**
- Modify: `agents/pl-700-retrospective.md`
- Modify: `agents/pl-710-feedback-capture.md`
- Modify: `agents/pl-150-test-bootstrapper.md`
- Modify: `agents/pl-160-migration-planner.md`
- Modify: `agents/pl-250-contract-validator.md`
- Modify: `agents/pl-650-preview-validator.md`

- [ ] **Step 1: Read all 6 agents**

- [ ] **Step 2: Enhance pl-700-retrospective**

- Add Linear tracking: close Epic with summary comment
- Add Forbidden Actions: universal subset
- Add: "Execution order: retrospective runs BEFORE pl-720-recap. Epic close happens AFTER both complete."

- [ ] **Step 3: Enhance pl-710-feedback-capture**

Per spec Section 14.12:
- Add: "If conventions file missing, classify without cross-reference, note the limitation"
- Add: "If extracted rule contradicts conventions, flag as CONFLICT severity with both texts"
- Add Forbidden Actions: universal subset

- [ ] **Step 4: Enhance pl-150-test-bootstrapper**

Per spec Section 14.9:
- Add: "If test framework not installed, report ERROR with install command"
- Add: "If coverage tool unavailable, skip coverage, log INFO, continue"
- Add: "Before generating, check if tests already exist (grep for imports)"

- [ ] **Step 5: Enhance pl-160-migration-planner**

Per spec Section 14.10:
- Add: "If context7 unavailable for API mapping, use CHANGELOG or migration guide — do not guess"
- Add: "If circular dependency discovered, pause current phase and report with graph"

- [ ] **Step 6: Enhance pl-250-contract-validator**

Per spec Section 14.11:
- Add: "If contract has no git baseline (new, uncommitted), treat all fields as 'added'"
- Add: "If `git show` fails, log WARNING, run current-state-only analysis"

- [ ] **Step 7: Enhance pl-650-preview-validator**

Per spec Section 14.13:
- Add: "If Playwright MCP becomes unreachable mid-check, stop, score with available results, log skipped checks"
- Add: "If preview URL returns non-200 after 3 retries (30s apart), mark CRITICAL, skip remaining checks"

- [ ] **Step 8: Add Forbidden Actions to all 6 agents**

Add the universal forbidden actions section to each.

- [ ] **Step 9: Validate all agents**

```bash
for f in agents/pl-700-retrospective.md agents/pl-710-feedback-capture.md agents/pl-150-test-bootstrapper.md agents/pl-160-migration-planner.md agents/pl-250-contract-validator.md agents/pl-650-preview-validator.md; do
  echo "=== $f ===" && head -6 "$f" && grep "^name:" "$f"
done
```

- [ ] **Step 10: Commit**

```bash
git add agents/pl-700-retrospective.md agents/pl-710-feedback-capture.md agents/pl-150-test-bootstrapper.md agents/pl-160-migration-planner.md agents/pl-250-contract-validator.md agents/pl-650-preview-validator.md
git commit -m "feat: harden retrospective, feedback capture, test bootstrapper, migration planner, contract validator, preview validator"
```

---

### Task 12: Add Forbidden Actions + Linear + MCP to Review Agents

**Files:**
- Modify: `agents/architecture-reviewer.md`
- Modify: `agents/security-reviewer.md`
- Modify: `agents/frontend-reviewer.md`
- Modify: `agents/frontend-performance-reviewer.md`
- Modify: `agents/backend-performance-reviewer.md`
- Modify: `agents/infra-deploy-reviewer.md`

- [ ] **Step 1: Read all 6 review agents**

- [ ] **Step 2: Add to each reviewer**

Append three sections to each of the 6 reviewers:

**Forbidden Actions** (universal subset from spec Section 4):
```
## Forbidden Actions

- DO NOT modify source files — you are read-only
- DO NOT modify shared contracts, conventions files, or CLAUDE.md
- DO NOT invent findings — only report confirmed issues
- DO NOT delete or disable anything without checking if it was intentional
```

**Linear Tracking** (per spec Section 10.4):
```
## Linear Tracking

If `integrations.linear.available` is true in state.json:
- Findings are posted to the Linear Epic by pl-400-quality-gate (not by you)
- You return findings in the standard format; the quality gate handles Linear

You do NOT interact with Linear directly.
```

**Graceful MCP Degradation** (per spec Section 11.4):
```
## Optional Integrations

If Context7 MCP is available, use it to verify current API patterns.
If unavailable, rely on conventions file and codebase grep.
Never fail because an optional MCP is down.
```

- [ ] **Step 3: Validate all**

```bash
for f in agents/architecture-reviewer.md agents/security-reviewer.md agents/frontend-reviewer.md agents/frontend-performance-reviewer.md agents/backend-performance-reviewer.md agents/infra-deploy-reviewer.md; do
  echo "=== $f ===" && grep "^name:" "$f"
done
```

- [ ] **Step 4: Commit**

```bash
git add agents/architecture-reviewer.md agents/security-reviewer.md agents/frontend-reviewer.md agents/frontend-performance-reviewer.md agents/backend-performance-reviewer.md agents/infra-deploy-reviewer.md
git commit -m "feat: add forbidden actions, Linear tracking, MCP degradation to all 6 review agents"
```

---

### Task 13: Enhance pipeline-init Skill

**Files:**
- Modify: `skills/pipeline-init/SKILL.md`

- [ ] **Step 1: Read current skill**

- [ ] **Step 2: Add validation enhancements**

Per spec Section 14.14:
- DETECT phase: validate git repo exists, `.claude/` directory writable, check for existing `dev-pipeline.local.md` (ask to overwrite if exists)
- VALIDATE phase: run BOTH build AND test commands — report which specific command failed and suggest fix
- Ambiguous detection: if multiple framework markers (e.g., both `package.json` and `build.gradle.kts`), ask user which is primary module
- Post-init: run `shared/checks/engine.sh --dry-run` to verify check engine works with detected module

- [ ] **Step 3: Commit**

```bash
git add skills/pipeline-init/SKILL.md
git commit -m "feat: harden pipeline-init with git validation, overwrite detection, dual build+test check, engine dry-run"
```

---

## Phase 4: Skills & Templates

---

### Task 14: Create New Universal Skills

**Files:**
- Create: `skills/pipeline-status/SKILL.md`
- Create: `skills/pipeline-reset/SKILL.md`
- Create: `skills/verify/SKILL.md`
- Create: `skills/security-audit/SKILL.md`
- Create: `skills/codebase-health/SKILL.md`
- Create: `skills/migration/SKILL.md`

- [ ] **Step 1: Create `/pipeline-status` skill**

```yaml
---
name: pipeline-status
description: Show current pipeline state, last run results, quality score, and Linear tracking
disable-model-invocation: false
---
```

Body: Read `.pipeline/state.json`. Display: current stage, story_state, quality score, fix cycle counts, Linear epic (if tracked), last stage timestamps, any pending findings. If no state file, report "No pipeline run in progress."

- [ ] **Step 2: Create `/pipeline-reset` skill**

```yaml
---
name: pipeline-reset
description: Clear pipeline run state and start fresh (preserves learnings)
disable-model-invocation: false
---
```

Body: Confirm with user ("This will remove .pipeline/ directory. Learnings in pipeline-log.md are preserved. Proceed?"). If yes, remove `.pipeline/` directory. Report what was cleaned.

- [ ] **Step 3: Create `/verify` skill**

```yaml
---
name: verify
description: Quick build + lint + test check for the current module without running the full pipeline
disable-model-invocation: false
---
```

Body: Read `dev-pipeline.local.md` for commands. Run `commands.build`, then `commands.lint`, then `commands.test` sequentially. Report pass/fail for each. On failure, show error output. Do not enter fix loops.

- [ ] **Step 4: Create `/security-audit` skill**

```yaml
---
name: security-audit
description: Run module-appropriate security scanners and aggregate results
disable-model-invocation: false
---
```

Body: Detect module from config. Run appropriate scanner: `npm audit` (JS/TS), `cargo audit` (Rust), `pip-audit` (Python), `./gradlew dependencyCheckAnalyze` (JVM), `govulncheck ./...` (Go). Aggregate results. Report: total vulnerabilities by severity, top 10 most critical, suggested fixes.

- [ ] **Step 5: Create `/codebase-health` skill**

```yaml
---
name: codebase-health
description: Run the check engine in full review mode and report all findings across all layers
disable-model-invocation: false
---
```

Body: Run `shared/checks/engine.sh --review`. Parse output. Report findings by category and severity. Summary: total findings, score using shared formula, top issues.

- [ ] **Step 6: Create `/migration` skill**

```yaml
---
name: migration
description: Plan and execute a library or framework migration using the migration planner agent
disable-model-invocation: false
---
```

Body: Thin launcher that dispatches `pl-160-migration-planner` with the user's input. Similar pattern to `/bootstrap-project` launching `pl-050-project-bootstrapper`.

- [ ] **Step 7: Fix `/fe-react-doctor` hardcoded path**

Read `skills/fe-react-doctor/SKILL.md`. Replace the hardcoded path `/Users/denissajnar/WebstormProjects/wellplanned-fe` with dynamic detection: use current working directory or read from `dev-pipeline.local.md` config.

- [ ] **Step 8: Validate all skills**

```bash
for d in skills/*/; do
  echo "=== $d ===" && head -5 "${d}SKILL.md"
done
```

- [ ] **Step 9: Commit**

```bash
git add skills/
git commit -m "feat: add 6 universal skills (pipeline-status, pipeline-reset, verify, security-audit, codebase-health, migration), fix fe-react-doctor path"
```

---

### Task 15: Update All Module Templates with Linear Config

**Files:**
- Modify: `modules/kotlin-spring/local-template.md`
- Modify: `modules/java-spring/local-template.md`
- Modify: `modules/python-fastapi/local-template.md`
- Modify: `modules/go-stdlib/local-template.md`
- Modify: `modules/rust-axum/local-template.md`
- Modify: `modules/typescript-node/local-template.md`
- Modify: `modules/typescript-svelte/local-template.md`
- Modify: `modules/react-vite/local-template.md`
- Modify: `modules/swift-ios/local-template.md`
- Modify: `modules/swift-vapor/local-template.md`
- Modify: `modules/c-embedded/local-template.md`
- Modify: `modules/infra-k8s/local-template.md`

- [ ] **Step 1: Add Linear config to each template**

Add to the YAML frontmatter of each `local-template.md`, after the `risk:` section:

```yaml
linear:
  enabled: false
  team: ""
  project: ""
  labels: ["pipeline-managed"]
```

Default is `enabled: false` so Linear doesn't activate unless user configures it via `/pipeline-init`.

- [ ] **Step 2: Add command timeouts to each template**

Add to the `commands:` section of each template:

```yaml
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60
```

- [ ] **Step 3: Validate all templates**

```bash
for m in modules/*/local-template.md; do
  echo "=== $m ===" && grep -c "linear:" "$m" && grep -c "build_timeout:" "$m"
done
```

- [ ] **Step 4: Commit**

```bash
git add modules/*/local-template.md
git commit -m "feat: add Linear config and command timeouts to all 12 module templates"
```

---

### Task 16: Update CLAUDE.md Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md**

- [ ] **Step 2: Update documentation**

- Add `pl-720-recap` to the agent list
- Add the 6 new skills to the Skills section
- Add Linear integration mention to Key Conventions
- Update agent count references
- Add Boy Scout `SCOUT-*` category to scoring description
- Add worktree policy mention
- Remove references to deleted deprecated hooks/scripts (already partially done)

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with new agents, skills, Linear integration, worktree policy"
```

---

## Verification Checklist (run after all tasks)

```bash
# 1. All agent names match filenames
for f in agents/*.md; do
  name=$(grep "^name:" "$f" | head -1 | sed 's/name: *//')
  file=$(basename "$f" .md)
  if [ "$name" != "$file" ]; then echo "MISMATCH: $f (name=$name, file=$file)"; fi
done

# 2. All scripts executable
find modules/ hooks/ shared/ -name "*.sh" ! -perm -111

# 3. All skills have valid frontmatter
for d in skills/*/; do
  head -3 "${d}SKILL.md"
done

# 4. Plugin manifest valid JSON
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('plugin.json OK')"
python3 -c "import json; json.load(open('.claude-plugin/marketplace.json')); print('marketplace.json OK')"

# 5. Check engine dry-run
shared/checks/engine.sh --dry-run

# 6. No ghost agent references in templates
grep -r 'fe-design-reviewer\|rs-arch-reviewer\|py-arch-reviewer\|go-arch-reviewer' modules/*/local-template.md || echo "No ghost references"

# 7. All module templates have Linear config
for m in modules/*/local-template.md; do
  grep -q "linear:" "$m" || echo "MISSING linear: $m"
done
```
