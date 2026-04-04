# Forge Bugfix Workflow (v1.2.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated bugfix workflow to forge — `/forge-fix` skill, `bugfix:` mode in the orchestrator, `fg-020-bug-investigator` agent with source-aware entry and flexible reproduction, and bug pattern tracking in the retrospective.

**Architecture:** One new agent (`fg-020-bug-investigator`) handles both INVESTIGATE (Stage 1) and REPRODUCE (Stage 2) in bugfix mode. All other stages reuse existing agents with bugfix-aware context. The orchestrator gains a fourth mode (`bugfix`) alongside `standard`, `migration`, and `bootstrap`. Entry via `/forge-fix` skill (thin launcher) or `/forge-run bugfix: <description>`. Tickets created automatically in kanban tracking when a plain description is provided.

**Tech Stack:** Markdown (agent/skill docs), bash (tests), bats (test framework)

**Spec:** `docs/superpowers/specs/2026-04-02-forge-redesign-design.md` — Section 8

---

## File Structure

### New files to create

```
agents/fg-020-bug-investigator.md          # New agent: investigate + reproduce bugs
skills/forge-fix/SKILL.md                  # New skill: /forge-fix entry point
tests/contract/bugfix-workflow.bats        # Contract tests for bugfix mode
tests/scenario/bugfix-mode.bats            # Scenario tests for bugfix entry + state
```

### Files to modify

```
agents/fg-100-orchestrator.md              # Add bugfix mode detection, stage dispatch, state schema
agents/fg-700-retrospective.md             # Add bug pattern tracking section
shared/stage-contract.md                   # Add Bugfix Mode section
shared/state-schema.md                     # Add bugfix object fields
skills/forge-run/SKILL.md                  # Accept bugfix: prefix
CLAUDE.md                                  # Document bugfix workflow
CONTRIBUTING.md                            # Document fg-020 agent
tests/validate-plugin.sh                   # Add structural checks for new files
```

---

## Task 1: Create fg-020-bug-investigator Agent

**Files:**
- Create: `agents/fg-020-bug-investigator.md`
- Test: `tests/contract/bugfix-workflow.bats`

The core new agent. Handles Stage 1 (INVESTIGATE) and Stage 2 (REPRODUCE) in bugfix mode.

- [ ] **Step 1: Create the agent file**

Create `agents/fg-020-bug-investigator.md`:

```markdown
---
name: fg-020-bug-investigator
description: |
  Bug investigation and reproduction agent — pulls context from ticket sources (kanban, Linear, description), explores fault area via graph and code search, attempts automated reproduction via failing test, falls back to user confirmation. Dispatched at Stage 1-2 in bugfix mode.

  <example>
  Context: User reports a 404 error on the group endpoint
  user: "/forge-fix Users get 404 on group endpoint"
  assistant: "I'll dispatch the bug investigator to trace the error, identify root cause, and write a failing test."
  </example>

  <example>
  Context: Bug ticket exists in kanban
  user: "/forge-fix FG-005"
  assistant: "I'll dispatch the bug investigator to pull context from ticket FG-005 and investigate."
  </example>
model: inherit
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'AskUserQuestion', 'neo4j-mcp']
---

# Bug Investigator (fg-020)

You investigate bugs and produce reproduction evidence. You operate in two phases: INVESTIGATE (Stage 1) and REPRODUCE (Stage 2).

**Philosophy:** Apply principles from `shared/agent-philosophy.md` — challenge assumptions, consider alternatives, seek disconfirming evidence. Don't jump to the first hypothesis.

Investigate the following bug: **$ARGUMENTS**

---

## 1. Identity & Purpose

You are the bug investigation agent. Your job is to:
1. **INVESTIGATE:** Trace a reported bug to its likely source in the codebase
2. **REPRODUCE:** Write a failing test (or obtain user confirmation) that proves the bug exists

You produce evidence, not fixes. The implementer (fg-300) fixes; you investigate.

---

## 2. Input Sources

You receive one of three input types (passed via orchestrator dispatch prompt):

### From Kanban Ticket
- Read the ticket file from `.forge/tracking/` (path provided by orchestrator)
- Extract: title, description, acceptance criteria, activity log
- Look for: error messages, stack traces, steps to reproduce, affected URLs/endpoints

### From Linear Issue
- Read the Linear issue via Linear MCP (issue ID provided by orchestrator)
- Extract: title, description, comments, labels, assignee context
- Look for: reproduction steps, screenshots, related issues

### From Plain Description
- Parse the raw text for: error symptoms, affected features, user actions that trigger the bug
- Ask clarifying questions if the description is too vague (max 3 questions)

---

## 3. Phase 1 — INVESTIGATE

### 3.1 Context Gathering

1. **Read project config:** Load `forge.local.md` for stack context (language, framework, testing)
2. **Query graph** (if available via neo4j-mcp):
   - Pattern 7 (Blast Radius): What files/modules relate to the reported symptom?
   - Pattern 14 (Bug Hotspots): Has this area had bugs before?
   - Pattern 15 (Test Coverage): What tests exist for the affected area?
3. **Search codebase** (if graph unavailable, use grep/glob):
   - Search for error messages, endpoint paths, class/function names mentioned in the report
   - Search for related test files
   - Check git log for recent changes in the affected area

### 3.2 Hypothesis Formation

Based on gathered context, form 1-3 hypotheses about the root cause. For each:
- **What:** The specific code defect (e.g., "missing null check on group lookup result")
- **Where:** File path and approximate line range
- **Why:** How this defect produces the reported symptom
- **Confidence:** HIGH / MEDIUM / LOW

Rank hypotheses by confidence. Investigate the highest-confidence hypothesis first.

### 3.3 Root Cause Isolation

For the top hypothesis:
1. Read the suspected file(s)
2. Trace the execution path from trigger to symptom
3. Identify the exact code that produces the incorrect behavior
4. Check if there's an existing test that should have caught this (and why it didn't)

### 3.4 Output (Stage 1 → Stage Notes)

Write to stage notes (max 2,000 tokens):
```
## Investigation Results

### Bug Summary
{One-sentence description of the confirmed or suspected bug}

### Root Cause Hypothesis
- **What:** {Specific defect}
- **Where:** {file:line}
- **Why:** {How it produces the symptom}
- **Confidence:** {HIGH|MEDIUM|LOW}

### Affected Files
- {file1} — {role in the bug}
- {file2} — {role}

### Existing Test Coverage
- {test_file} — covers {what}, misses {what}
- (or: No existing tests for this code path)

### Graph Context (if available)
- Bug hotspot score: {N previous bugs in this area}
- Dependency chain: {upstream/downstream impacts}
```

---

## 4. Phase 2 — REPRODUCE

### 4.1 Reproduction Strategy

Follow this decision tree:

1. **Extract reproduction steps** from ticket/issue (if available)
2. **Query graph:** What test framework does the project use? What test patterns exist nearby?
3. **Attempt to write a failing test:**
   - Unit test if isolated logic bug (e.g., wrong return value, null handling)
   - Integration test if data/API bug (e.g., wrong query, missing validation)
   - Playwright script if UI bug (requires Playwright MCP)
4. **Run the test:**
   - **FAILS** → reproduction confirmed. Record test file path and failure output.
   - **PASSES** → hypothesis wrong. Re-investigate (max 3 attempts total across all hypotheses).
5. **If cannot automate after 3 attempts:**
   - Ask user via `AskUserQuestion`:
     ```
     Header: "Bug Reproduction"
     Question: "I believe the bug occurs when {scenario}. Can you confirm this matches what you're seeing?"
     Options:
       A) Yes, that's exactly what happens
       B) No, it's different — let me describe what I see
       C) I'm not sure, let's try a different approach
     ```
   - User confirms (A) → proceed with manual reproduction evidence
   - User corrects (B) → re-investigate with new information
   - User unsure (C) → try next hypothesis or escalate
6. **If still unresolvable after all hypotheses exhausted:**
   - Ask user via `AskUserQuestion`:
     ```
     Header: "Unable to Reproduce"
     Question: "I've been unable to reproduce this bug after investigating {N} hypotheses. How would you like to proceed?"
     Options:
       A) Provide more context (I'll ask specific questions)
       B) Let's pair debug (I'll guide you through diagnostic steps)
       C) Close as unreproducible
     ```

### 4.2 Output (Stage 2 → Stage Notes)

Write to stage notes (max 2,000 tokens):
```
## Reproduction Results

### Method: {automated|manual|unresolvable}
### Reproduction Evidence
- Test file: {path} (if automated)
- Failure output: {summary}
- User confirmation: {yes/no/na} (if manual)

### Root Cause (confirmed)
- **Category:** {off-by-one|null_handling|race_condition|missing_validation|wrong_assumption|config_error}
- **Hypothesis:** {description}
- **Confidence:** {HIGH|MEDIUM|LOW}
- **Affected files:** {list}

### Suggested Fix Approach
- {Brief description of what needs to change — NOT implementation details}
- {Expected test to verify the fix}

### Attempts
- Attempt 1: {hypothesis} → {result}
- Attempt 2: {hypothesis} → {result} (if applicable)
```

---

## 5. Forbidden Actions

- **Do NOT fix the bug.** You investigate and reproduce only. The implementer (fg-300) fixes.
- **Do NOT modify source code** (except writing test files for reproduction).
- **Do NOT create more than 1 reproduction test** per hypothesis.
- **Do NOT ask more than 3 clarifying questions** in Phase 1.
- **Do NOT exceed 3 reproduction attempts** total.
- **Do NOT skip Phase 1.** Always investigate before attempting reproduction.
- **Do NOT invent bugs** — if you can't find evidence of the reported issue, say so honestly.
```

- [ ] **Step 2: Verify agent frontmatter matches filename**

```bash
grep "^name:" agents/fg-020-bug-investigator.md
```
Expected: `name: fg-020-bug-investigator`

- [ ] **Step 3: Commit**

```bash
git add agents/fg-020-bug-investigator.md
git commit -m "feat(agent): add fg-020-bug-investigator for bugfix workflow"
```

---

## Task 2: Create /forge-fix Skill

**Files:**
- Create: `skills/forge-fix/SKILL.md`

Thin launcher skill — parses input, resolves ticket source, dispatches orchestrator in bugfix mode.

- [ ] **Step 1: Create skill directory and file**

```bash
mkdir -p skills/forge-fix
```

Create `skills/forge-fix/SKILL.md`:

```markdown
---
name: forge-fix
description: |
  Start a bugfix workflow. Accepts a kanban ticket ID, Linear issue, or plain bug description.
  Dispatches the forge orchestrator in bugfix mode with investigation, reproduction, and fix stages.

  <example>
  Context: User has a kanban ticket for a bug
  user: "/forge-fix FG-005"
  assistant: "I'll start the bugfix workflow for ticket FG-005."
  </example>

  <example>
  Context: User describes a bug directly
  user: "/forge-fix Users get 404 when accessing their group"
  assistant: "I'll investigate the bug, write a failing test, and create a fix."
  </example>

  <example>
  Context: User has a Linear issue
  user: "/forge-fix --linear LIN-1234"
  assistant: "I'll pull context from Linear and start the bugfix workflow."
  </example>
---

# Forge Fix

Start a bugfix workflow. You are a thin launcher — parse input, resolve the bug source, and dispatch the orchestrator.

## 1. Input Parsing

Parse `$ARGUMENTS` to determine the bug source:

### Source Resolution

1. **Kanban ticket:** If input matches `{PREFIX}-{NNN}` pattern (e.g., `FG-005`, `WP-012`):
   - Source `shared/tracking/tracking-ops.sh`
   - Call `find_ticket ".forge/tracking" "{ticket_id}"` to locate the file
   - Read ticket's `title` and `## Description` as the bug description
   - Set `source = "kanban"`, `source_id = "{ticket_id}"`

2. **Linear issue:** If `--linear {ID}` flag present:
   - Set `source = "linear"`, `source_id = "{ID}"`
   - The orchestrator will read the Linear issue via MCP

3. **Plain description:** Anything else:
   - Set `source = "description"`, `source_id = null`
   - The bug description is the raw input text
   - A tracking ticket will be created automatically during PREFLIGHT

### MCP Detection

Detect available MCPs (same as `/forge-run`):
- Linear, Playwright, Slack, Figma, Context7
- First-call probe: attempt a lightweight operation, mark as available/unavailable

## 2. Dispatch Orchestrator

Dispatch `fg-100-orchestrator` via Agent tool with:

```
Execute the bugfix workflow for: {bug_description}

Mode: bugfix
Bug source: {source} ({source_id})
Available MCPs: {detected_mcps}
{If kanban ticket: Ticket path: {ticket_file_path}}
{If --linear: Linear issue ID: {source_id}}
```

## 3. Relay Output

Relay the orchestrator's final output unchanged. This will be one of:
- PR URL (fix shipped)
- Escalation (bug unresolvable, needs user input)
- Abort reason (if investigation failed)

## 4. Forbidden Actions

- Do NOT investigate, reproduce, or fix the bug yourself. Dispatch the orchestrator.
- Do NOT create tickets — the orchestrator handles that during PREFLIGHT.
- Do NOT modify any files.
```

- [ ] **Step 2: Verify skill frontmatter matches directory**

```bash
grep "^name:" skills/forge-fix/SKILL.md
```
Expected: `name: forge-fix`

- [ ] **Step 3: Commit**

```bash
git add skills/forge-fix/
git commit -m "feat(skill): add /forge-fix entry point for bugfix workflow"
```

---

## Task 3: Update Orchestrator — Bugfix Mode

**Files:**
- Modify: `agents/fg-100-orchestrator.md`

Add bugfix mode detection, stage dispatch changes, and bugfix state fields.

- [ ] **Step 1: Read orchestrator mode detection section**

Read `agents/fg-100-orchestrator.md` and find section 3.0 (Requirement Mode Detection, around line 197).

- [ ] **Step 2: Add bugfix mode to the mode detection table**

Find the mode detection table and add `bugfix:` / `fix:` as a new prefix:

```markdown
| Prefix | Mode | Effect |
|--------|------|--------|
| `bootstrap:` / `Bootstrap:` | bootstrap | Dispatch fg-050-project-bootstrapper at Stage 2 |
| `migrate:` / `migration:` | migration | Dispatch fg-160-migration-planner at Stage 2 |
| `bugfix:` / `fix:` | bugfix | Dispatch fg-020-bug-investigator at Stages 1-2 |
| (anything else) | standard | Normal pipeline flow with fg-200-planner |
```

Also add: "If the orchestrator is dispatched with `Mode: bugfix` in the prompt (from `/forge-fix`), set mode directly without prefix stripping."

- [ ] **Step 3: Add bugfix fields to state init JSON**

In section 3.8 (Initialize State), add the bugfix object to the state.json template:

```json
"bugfix": {
  "source": null,
  "source_id": null,
  "reproduction": {
    "method": null,
    "test_file": null,
    "attempts": 0
  },
  "root_cause": {
    "hypothesis": null,
    "category": null,
    "affected_files": [],
    "confidence": null
  }
}
```

Add after the `tracking_dir` field in the init JSON.

- [ ] **Step 4: Add bugfix source resolution to PREFLIGHT**

In the PREFLIGHT section, after ticket resolution (§3.9) but before worktree creation, add:

```markdown
### 3.9a Bugfix Source Resolution (bugfix mode only)

If `mode == "bugfix"`:
1. Read `bugfix.source` and `bugfix.source_id` from the dispatch prompt
2. **If source is "kanban":** Read ticket file, extract description, steps to reproduce
3. **If source is "linear":** Read Linear issue via MCP, extract description, comments
4. **If source is "description":** Create a kanban ticket with `type: bugfix` in `in-progress/`
5. Store `bugfix.source`, `bugfix.source_id` in state.json
6. Set branch type to `fix` (for worktree branch naming in §3.9)
```

- [ ] **Step 5: Update Stage 1 dispatch for bugfix mode**

Find the Stage 1 (EXPLORE) dispatch section. Add a conditional:

```markdown
### Stage 1 Dispatch

If `mode == "bugfix"`:
  // Wrap: TaskCreate("Investigating bug — fg-020-bug-investigator") → Agent → TaskUpdate
  Dispatch `fg-020-bug-investigator` with:
  - Bug description from state
  - Bug source and source_id
  - Ticket file path (if kanban)
  - Instruction: "Execute Phase 1 — INVESTIGATE"
  Read stage 1 notes from agent output.

Else (standard/migration/bootstrap):
  (existing explore dispatch logic unchanged)
```

- [ ] **Step 6: Update Stage 2 dispatch for bugfix mode**

Find the Stage 2 (PLAN) dispatch section. Add a conditional:

```markdown
### Stage 2 Dispatch

If `mode == "bugfix"`:
  // Wrap: TaskCreate("Reproducing bug — fg-020-bug-investigator") → Agent → TaskUpdate
  Dispatch `fg-020-bug-investigator` with:
  - Stage 1 investigation results (from stage notes)
  - Instruction: "Execute Phase 2 — REPRODUCE"
  Read stage 2 notes. Extract reproduction method, test file, root cause.
  Store in `state.json.bugfix.reproduction` and `state.json.bugfix.root_cause`.

Else if `mode == "migration"`:
  (existing migration dispatch)
Else if `mode == "bootstrap"`:
  (existing bootstrap dispatch)
Else:
  (existing standard planner dispatch)
```

- [ ] **Step 7: Update Stage 3 for bugfix validation**

Find the Stage 3 (VALIDATE) dispatch. Add bugfix context:

```markdown
If `mode == "bugfix"`:
  Dispatch `fg-210-validator` with bugfix-specific perspectives:
  - root_cause_validity: Is the identified root cause consistent with the symptoms?
  - fix_scope: Is the proposed fix minimal and targeted?
  - regression_risk: Could the fix break related functionality?
  - test_coverage: Does the reproduction test adequately verify the fix?
  (4 perspectives instead of the standard 7)
```

- [ ] **Step 8: Update Stage 6 for reduced review in bugfix mode**

Find the Stage 6 (REVIEW) dispatch. Add:

```markdown
If `mode == "bugfix"`:
  Reduced review batch — skip frontend reviewers for backend-only bugs:
  - Always: architecture-reviewer, security-reviewer
  - If frontend files changed: add frontend-reviewer
  - Skip: frontend-design-reviewer, frontend-a11y-reviewer, frontend-performance-reviewer (unless frontend files in diff)
```

- [ ] **Step 9: Update Stage 9 for bug pattern tracking**

Find the Stage 9 (LEARN) dispatch. Add:

```markdown
If `mode == "bugfix"`:
  Pass to `fg-700-retrospective`:
  - bugfix.root_cause.category
  - bugfix.reproduction.method
  - bugfix.root_cause.affected_files
  - Total reproduction attempts
  Retrospective will append bug pattern data to `.forge/forge-log.md`
```

- [ ] **Step 10: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat(orchestrator): add bugfix mode with stage dispatch and state fields"
```

---

## Task 4: Update Stage Contract

**Files:**
- Modify: `shared/stage-contract.md`

- [ ] **Step 1: Read current stage-contract.md**

Read the document to find the mode-specific sections (Migration Mode, Bootstrap Mode).

- [ ] **Step 2: Add Bugfix Mode section**

Add after the Bootstrap Mode section:

```markdown
## Bugfix Mode

Activated by `/forge-fix` or `/forge-run bugfix: <description>`. Sets `state.json.mode = "bugfix"`.

### Stage Mapping

| Stage | Name | Bugfix Behavior | Agent |
|-------|------|-----------------|-------|
| 0 | PREFLIGHT | Same as standard. Additionally resolves bug source (kanban/Linear/description). Creates ticket if needed. Branch type: `fix`. | fg-100 inline |
| 1 | INVESTIGATE | Replaces EXPLORE. Pulls bug context, searches codebase, queries graph, forms root cause hypotheses. | fg-020-bug-investigator |
| 2 | REPRODUCE | Replaces PLAN. Writes failing test or obtains user confirmation. Max 3 attempts. | fg-020-bug-investigator |
| 3 | ROOT CAUSE | Replaces VALIDATE. Confirms hypothesis with 4 bugfix perspectives (root cause validity, fix scope, regression risk, test coverage). | fg-210-validator (reused) |
| 4 | FIX | Same as IMPLEMENT. TDD: make failing test pass, refactor. | fg-300-implementer (reused) |
| 5 | VERIFY | Same as standard. | fg-500-test-gate (reused) |
| 6 | REVIEW | Reduced batch: architecture + security always; frontend reviewers only if frontend files changed. | fg-400-quality-gate (reused) |
| 7 | DOCS | Minimal: changelog entry + update affected docs only. | fg-350-docs-generator (reused) |
| 8 | SHIP | Same as standard. Branch: `fix/{ticket}-{slug}`. | fg-600-pr-builder (reused) |
| 9 | LEARN | Same + bug pattern tracking (root cause category, affected layer, reproduction method). | fg-700-retrospective (reused) |

### Entry Conditions (bugfix-specific)

- Stage 1: `mode == "bugfix"` and `bugfix.source` is set
- Stage 2: Stage 1 investigation notes available with at least one hypothesis
- Stage 3: Reproduction evidence available (test file path or user confirmation)

### Exit Conditions (bugfix-specific)

- Stage 1: Root cause hypothesis with confidence level in stage notes
- Stage 2: `bugfix.reproduction.method` set to `automated`, `manual`, or `unresolvable`
- Stage 3: Validator verdict (GO/REVISE/NO-GO) with bugfix perspectives

### Escalation

If reproduction fails after 3 attempts AND user cannot confirm:
- Mark `bugfix.reproduction.method = "unresolvable"`
- Ask user via orchestrator: Provide more context / Pair debug / Close as unreproducible
- If closed: set `state.json.abort_reason = "unreproducible"`, skip to LEARN
```

- [ ] **Step 3: Commit**

```bash
git add shared/stage-contract.md
git commit -m "docs(contract): add Bugfix Mode section to stage contract"
```

---

## Task 5: Update State Schema

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add bugfix fields to state schema**

Read `shared/state-schema.md` and find the field reference section. Add a new subsection:

```markdown
### Bugfix Fields

Present when `mode == "bugfix"`. Null/empty for other modes.

| Field | Type | Description |
|-------|------|-------------|
| `bugfix.source` | enum | `"kanban"`, `"linear"`, or `"description"`. How the bug was reported. |
| `bugfix.source_id` | string or null | Ticket ID (e.g., `FG-005`) or Linear issue ID. Null for plain descriptions. |
| `bugfix.reproduction.method` | enum or null | `"automated"`, `"manual"`, or `"unresolvable"`. Set at Stage 2. |
| `bugfix.reproduction.test_file` | string or null | Path to reproduction test file (if automated). |
| `bugfix.reproduction.attempts` | integer | Number of reproduction attempts (max 3). |
| `bugfix.root_cause.hypothesis` | string or null | Description of identified root cause. |
| `bugfix.root_cause.category` | enum or null | `"off_by_one"`, `"null_handling"`, `"race_condition"`, `"missing_validation"`, `"wrong_assumption"`, `"config_error"`. |
| `bugfix.root_cause.affected_files` | array | List of file paths affected by the bug. |
| `bugfix.root_cause.confidence` | enum or null | `"high"`, `"medium"`, `"low"`. |
```

Also add `"bugfix"` to the list of valid `mode` values: `"standard"`, `"migration"`, `"bootstrap"`, `"bugfix"`.

Update the JSON example to include the bugfix object.

- [ ] **Step 2: Commit**

```bash
git add shared/state-schema.md
git commit -m "feat(schema): add bugfix fields to state schema"
```

---

## Task 6: Update Retrospective — Bug Pattern Tracking

**Files:**
- Modify: `agents/fg-700-retrospective.md`

- [ ] **Step 1: Read retrospective agent**

Read `agents/fg-700-retrospective.md` to find the learnings/log writing section.

- [ ] **Step 2: Add bug pattern tracking section**

Add a new section for bugfix-mode-specific learning:

```markdown
## Bug Pattern Tracking (bugfix mode only)

When `state.json.mode == "bugfix"`, append a structured bug pattern entry to `.forge/forge-log.md` under a `## Bug Patterns` section:

```markdown
### BUG-{ticket_id} — {root_cause_hypothesis}
- **Date:** {ISO timestamp}
- **Root cause category:** {bugfix.root_cause.category}
- **Affected layer:** {inferred from affected_files: domain|persistence|API|frontend|infra}
- **Affected files:** {bugfix.root_cause.affected_files}
- **Detection method:** {how the bug was found: user_report|test|monitoring|code_review}
- **Reproduction:** {bugfix.reproduction.method} ({bugfix.reproduction.attempts} attempts)
- **Fix commit:** {last commit on the worktree branch}
```

Over time, this data reveals:
- **Hotspot areas:** Files/modules that accumulate bugs → candidates for refactoring or extra test coverage
- **Common root cause patterns:** Recurring categories → candidates for automated detection rules or PREEMPT items
- **Reproduction difficulty trends:** Areas where automated reproduction is hard → may need better test infrastructure
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-700-retrospective.md
git commit -m "feat(retrospective): add bug pattern tracking for bugfix mode"
```

---

## Task 7: Update forge-run to Accept bugfix: Prefix

**Files:**
- Modify: `skills/forge-run/SKILL.md`

- [ ] **Step 1: Add bugfix prefix detection**

In the Input Parsing section of `skills/forge-run/SKILL.md`, add `bugfix:` and `fix:` as recognized prefixes:

```markdown
### Mode Prefixes

If the requirement starts with a recognized prefix, pass the mode to the orchestrator:
- `bugfix: <description>` or `fix: <description>` → `Mode: bugfix`
- `migrate: <description>` → `Mode: migration`
- `bootstrap: <description>` → `Mode: bootstrap`
- (no prefix) → `Mode: standard`

The prefix is stripped before passing the requirement to the orchestrator.

Note: For bugfix mode, prefer `/forge-fix` which provides richer source resolution (kanban tickets, Linear issues). The `bugfix:` prefix in `/forge-run` is a convenience shortcut.
```

- [ ] **Step 2: Commit**

```bash
git add skills/forge-run/SKILL.md
git commit -m "feat(forge-run): accept bugfix: prefix for bugfix mode"
```

---

## Task 8: Contract Tests

**Files:**
- Create: `tests/contract/bugfix-workflow.bats`

- [ ] **Step 1: Write contract tests**

Create `tests/contract/bugfix-workflow.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
  STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
  STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
  BUG_INVESTIGATOR="$PLUGIN_ROOT/agents/fg-020-bug-investigator.md"
  FORGE_FIX="$PLUGIN_ROOT/skills/forge-fix/SKILL.md"
  FORGE_RUN="$PLUGIN_ROOT/skills/forge-run/SKILL.md"
  RETROSPECTIVE="$PLUGIN_ROOT/agents/fg-700-retrospective.md"
}

# --- Agent ---

@test "bugfix: fg-020-bug-investigator agent exists" {
  [ -f "$BUG_INVESTIGATOR" ]
}

@test "bugfix: fg-020-bug-investigator has valid frontmatter" {
  grep -q "^name: fg-020-bug-investigator$" "$BUG_INVESTIGATOR"
  grep -q "^tools:" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator has neo4j-mcp in tools" {
  grep -q "neo4j-mcp" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator has AskUserQuestion in tools" {
  grep -q "AskUserQuestion" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator documents Phase 1 INVESTIGATE" {
  grep -q "INVESTIGATE\|Phase 1" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator documents Phase 2 REPRODUCE" {
  grep -q "REPRODUCE\|Phase 2" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator has Forbidden Actions" {
  grep -q "Forbidden Actions" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator documents max 3 reproduction attempts" {
  grep -q "3 attempt\|max 3\|3 reproduction" "$BUG_INVESTIGATOR"
}

# --- Skill ---

@test "bugfix: forge-fix skill exists" {
  [ -f "$FORGE_FIX" ]
}

@test "bugfix: forge-fix has valid frontmatter" {
  grep -q "^name: forge-fix$" "$FORGE_FIX"
}

@test "bugfix: forge-fix documents kanban ticket input" {
  grep -q "kanban\|FG-005\|ticket" "$FORGE_FIX"
}

@test "bugfix: forge-fix documents Linear input" {
  grep -q "linear\|--linear\|LIN-" "$FORGE_FIX"
}

@test "bugfix: forge-fix documents plain description input" {
  grep -q "description\|plain" "$FORGE_FIX"
}

@test "bugfix: forge-fix dispatches fg-100-orchestrator with bugfix mode" {
  grep -q "bugfix\|Mode: bugfix" "$FORGE_FIX"
}

# --- Orchestrator ---

@test "bugfix: orchestrator detects bugfix mode prefix" {
  grep -q "bugfix:\|fix:" "$ORCHESTRATOR"
}

@test "bugfix: orchestrator has bugfix fields in state init" {
  grep -q '"bugfix"' "$ORCHESTRATOR"
}

@test "bugfix: orchestrator dispatches fg-020-bug-investigator at Stage 1" {
  grep -q "fg-020-bug-investigator" "$ORCHESTRATOR"
}

@test "bugfix: orchestrator has bugfix-specific Stage 3 validation perspectives" {
  grep -q "root_cause_validity\|fix_scope\|regression_risk" "$ORCHESTRATOR"
}

# --- Stage Contract ---

@test "bugfix: stage contract has Bugfix Mode section" {
  grep -q "Bugfix Mode" "$STAGE_CONTRACT"
}

@test "bugfix: stage contract documents INVESTIGATE stage" {
  grep -q "INVESTIGATE" "$STAGE_CONTRACT"
}

@test "bugfix: stage contract documents REPRODUCE stage" {
  grep -q "REPRODUCE" "$STAGE_CONTRACT"
}

@test "bugfix: stage contract documents unreproducible escalation" {
  grep -q "unreproducible\|unresolvable" "$STAGE_CONTRACT"
}

# --- State Schema ---

@test "bugfix: state schema documents bugfix.source field" {
  grep -q "bugfix.source\|bugfix\.source" "$STATE_SCHEMA"
}

@test "bugfix: state schema documents bugfix.reproduction field" {
  grep -q "bugfix.reproduction\|bugfix\.reproduction" "$STATE_SCHEMA"
}

@test "bugfix: state schema documents bugfix.root_cause field" {
  grep -q "bugfix.root_cause\|bugfix\.root_cause" "$STATE_SCHEMA"
}

@test "bugfix: state schema lists bugfix as valid mode" {
  grep -q '"bugfix"\|bugfix' "$STATE_SCHEMA"
}

# --- Retrospective ---

@test "bugfix: retrospective documents bug pattern tracking" {
  grep -q "Bug Pattern\|bug pattern" "$RETROSPECTIVE"
}

@test "bugfix: retrospective tracks root cause category" {
  grep -q "root.cause.category\|Root cause category\|root_cause" "$RETROSPECTIVE"
}

# --- forge-run ---

@test "bugfix: forge-run accepts bugfix: prefix" {
  grep -q "bugfix:" "$FORGE_RUN"
}
```

- [ ] **Step 2: Run tests**

```bash
tests/lib/bats-core/bin/bats tests/contract/bugfix-workflow.bats
```
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add tests/contract/bugfix-workflow.bats
git commit -m "test: add contract tests for bugfix workflow"
```

---

## Task 9: Update Documentation + Structural Validation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `CONTRIBUTING.md`
- Modify: `tests/validate-plugin.sh`

- [ ] **Step 1: Update CLAUDE.md**

Add to the relevant sections:

1. In "Key conventions" → "Pipeline modes" gotchas, add:
```markdown
- **Bugfix mode:** `/forge-fix` or `/forge-run bugfix: <description>`. Stage 1 dispatches `fg-020-bug-investigator` (INVESTIGATE), Stage 2 continues with reproduction. Stage 3 validates with 4 bugfix perspectives (root cause validity, fix scope, regression risk, test coverage). Stage 6 uses reduced reviewer batch. Stage 9 tracks bug patterns. See `stage-contract.md` Bugfix Mode section.
```

2. In the agents listing, add `fg-020-bug-investigator` to the Pre-pipeline agents:
```markdown
- Pre-pipeline: `fg-010-shaper`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`
```

3. In the Skills listing, add `forge-fix`:
```markdown
`forge-fix` (bugfix entry — accepts ticket ID, Linear issue, or description),
```

4. In state schema description, mention bugfix fields.

5. Update plugin version from v1.1.0 to v1.2.0.

- [ ] **Step 2: Update CONTRIBUTING.md**

Add a note about the bugfix agent and workflow.

- [ ] **Step 3: Update plugin.json and marketplace.json version**

```bash
sed -i '' 's/"1.1.0"/"1.2.0"/' .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

- [ ] **Step 4: Add structural checks to validate-plugin.sh**

Add:
```bash
echo ""
echo "--- BUGFIX WORKFLOW ---"

# fg-020-bug-investigator exists
check "fg-020-bug-investigator agent exists" "[ -f '$ROOT/agents/fg-020-bug-investigator.md' ]"

# forge-fix skill exists
check "forge-fix skill exists" "[ -f '$ROOT/skills/forge-fix/SKILL.md' ]"

# forge-fix frontmatter name matches
check "forge-fix name matches directory" "grep -q '^name: forge-fix$' '$ROOT/skills/forge-fix/SKILL.md'"
```

- [ ] **Step 5: Run structural validation**

```bash
./tests/validate-plugin.sh
```

- [ ] **Step 6: Run full test suite**

```bash
./tests/run-all.sh
```

- [ ] **Step 7: Regenerate seed.cypher**

```bash
./shared/graph/generate-seed.sh
```

- [ ] **Step 8: Commit all doc + validation changes**

```bash
git add CLAUDE.md CONTRIBUTING.md .claude-plugin/ tests/validate-plugin.sh shared/graph/seed.cypher
git commit -m "docs: document bugfix workflow, bump version to 1.2.0"
```
