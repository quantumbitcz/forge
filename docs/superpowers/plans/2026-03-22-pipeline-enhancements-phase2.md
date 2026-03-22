# Pipeline Enhancements Phase 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dry-run mode, parallel conflict detection, scoring customization, PREEMPT lifecycle, error taxonomy, agent effectiveness tracking, pipeline history, timeout enforcement, convention drift detection, cross-project learnings, observability, rollback skill, and agent communication protocol to the pipeline.

**Architecture:** All changes are markdown agent definitions, YAML templates, bash scripts, and skill files. The orchestrator gets new sections for dry-run, conflict detection, timeouts, and observability. Shared contracts get new schemas for error taxonomy and agent effectiveness. New skills provide history view and rollback. Module templates get scoring customization.

**Tech Stack:** Markdown (agent definitions), YAML frontmatter, JSON (schemas), Bash (scripts)

**Prerequisite:** Phase 1 hardening branch (`feat/orchestration-hardening`) must be the working base. All work in `.pipeline/worktree/`.

---

## Phase A: Orchestrator Capabilities

---

### Task 1: Add `--dry-run` Flag to Orchestrator

The most requested capability — preview what the pipeline would do without making changes.

**Files:**
- Modify: `agents/pl-100-orchestrator.md`

- [ ] **Step 1: Read Section 2 (Argument Parsing) of the orchestrator**

Understand the existing `--from` flag handling to follow the same pattern.

- [ ] **Step 2: Add `--dry-run` to argument parsing section**

After the existing `--from` documentation, add:

```markdown
### --dry-run Mode

If `--dry-run` is passed:

1. Run PREFLIGHT normally (config validation, MCP detection, state init)
2. Run EXPLORE normally (codebase analysis)
3. Run PLAN normally (create stories, tasks, parallel groups)
4. Run VALIDATE normally (check plan quality)
5. **STOP after VALIDATE.** Do not enter IMPLEMENT.

Output a dry-run report:

```
## Dry Run Report

**Requirement:** {requirement}
**Module:** {module} ({framework})
**Risk Level:** {risk_level}
**Validation:** {GO/REVISE/NO-GO}

### Plan Summary
- Stories: {count}
- Tasks: {count} across {group_count} parallel groups
- Estimated files: {count} creates, {count} modifies

### Quality Gate Configuration
- Batch 1: {agent_list}
- Batch 2: {agent_list}
- Inline checks: {list}

### Integrations Available
{MCP detection results}

### PREEMPT Items Matched
{list of PREEMPT items that would apply}

To execute: `/pipeline-run {same arguments without --dry-run}`
```

Key rules:
- `--dry-run` creates NO files outside `.pipeline/` (stage notes are still written for debugging)
- `--dry-run` creates NO Linear tickets
- `--dry-run` creates NO git branches or worktrees
- `--dry-run` is compatible with `--from` (e.g., `--dry-run --from=plan` skips EXPLORE)
- State.json is written but with `"dry_run": true` flag
```

- [ ] **Step 3: Add `dry_run` field to state initialization template (Section 3.7)**

In the state.json template, add: `"dry_run": false` (set to `true` when `--dry-run` is active).

- [ ] **Step 4: Validate section numbering**

```bash
grep "^## [0-9]" agents/pl-100-orchestrator.md
```

- [ ] **Step 5: Commit**

```bash
git add agents/pl-100-orchestrator.md
git commit -m "feat: add --dry-run flag for pipeline preview without execution"
```

---

### Task 2: Add Parallel Task Conflict Detection

Prevent two tasks in the same parallel group from modifying the same file.

**Files:**
- Modify: `agents/pl-100-orchestrator.md`
- Modify: `agents/pl-200-planner.md`

- [ ] **Step 1: Read orchestrator Section 7 (IMPLEMENT) for parallel group dispatch**

- [ ] **Step 2: Add conflict detection to orchestrator IMPLEMENT section**

Insert after the existing parallel group dispatch logic:

```markdown
### 7.x Parallel Conflict Detection

Before dispatching a parallel group, validate no file conflicts exist:

1. For each task in the group, collect the `files` list (creates + modifies)
2. Find any files that appear in 2+ tasks within the same group
3. If conflicts found:
   - Log WARNING: "Conflict detected: {file} is in both Task {A} and Task {B}"
   - Serialize the conflicting tasks: move Task {B} to a new sequential group after the current group
   - Report to user in stage notes: "Serialized {N} tasks due to file conflicts"
4. If no conflicts: proceed with parallel dispatch as normal

This check runs at IMPLEMENT time, not PLAN time, because task file lists are finalized during scaffolding.
```

- [ ] **Step 3: Add conflict awareness to planner**

In `agents/pl-200-planner.md`, add to the parallel groups section:

```markdown
### Conflict Prevention

When assigning tasks to parallel groups:
- Tasks that modify the same file MUST NOT be in the same group
- If unsure whether two tasks share files, place them in sequential groups (safer)
- The orchestrator performs runtime conflict detection as a safety net, but the planner should minimize conflicts by design
```

- [ ] **Step 4: Commit**

```bash
git add agents/pl-100-orchestrator.md agents/pl-200-planner.md
git commit -m "feat: add parallel task conflict detection with automatic serialization"
```

---

### Task 3: Add Timeout Enforcement Mechanism

Document how timeouts are actually enforced, not just declared.

**Files:**
- Modify: `agents/pl-100-orchestrator.md`

- [ ] **Step 1: Read orchestrator Section 16 (Timeouts)**

- [ ] **Step 2: Replace the existing timeout section with enforcement details**

Expand the section:

```markdown
## 16. Timeout Enforcement

### Agent Dispatch Timeouts

When dispatching an agent via the Agent tool:

1. Record the dispatch timestamp in stage notes
2. The Agent tool has a built-in timeout mechanism — agents complete when they return a result
3. If an agent has not returned after the stage timeout (30 min), the orchestrator:
   - Stops waiting for the agent
   - Proceeds with available results from other agents in the batch
   - Logs: "Agent {name} timed out after {duration}. Proceeding without its results."
   - Adds INFO finding: `{agent}:0 | REVIEW-GAP | INFO | Agent timed out, {focus} not reviewed`
4. If a late result arrives after the orchestrator moved on: discard it

### Command Timeouts

When running shell commands (build, test, lint):

1. Use the configurable timeout from `commands.{cmd}_timeout` in `dev-pipeline.local.md`
2. Default timeouts: build=120s, test=300s, lint=60s
3. Wrap execution: run the command, track wall time, if it exceeds timeout:
   - Kill the process
   - Report: "Command '{cmd}' timed out after {N}s"
   - Classify as TOOL_FAILURE for recovery engine

### Stage Timeouts

| Level | Timeout | Action |
|---|---|---|
| Single agent | Per-agent (no fixed limit, Agent tool manages) | Proceed with available results |
| Single command | `commands.*_timeout` (default 120-300s) | Kill, report TOOL_FAILURE |
| Stage total | 30 minutes | Checkpoint, warn user, suggest resume |
| Full pipeline | 2 hours | Checkpoint, pause, notify user |
| Full pipeline (dry-run) | 30 minutes | Stop, report what was completed |

### Enforcement Rule

Timeouts are defensive — they prevent runaway execution, not thoroughness. When a timeout fires:
- NEVER discard work already completed
- ALWAYS checkpoint before stopping
- ALWAYS tell the user what was completed and what was skipped
- NEVER retry after a stage timeout (the user decides to resume or abort)
```

- [ ] **Step 3: Commit**

```bash
git add agents/pl-100-orchestrator.md
git commit -m "feat: add timeout enforcement mechanism with command, agent, and stage-level handling"
```

---

### Task 4: Add Pipeline Observability

Give the orchestrator a progress reporting mechanism.

**Files:**
- Modify: `agents/pl-100-orchestrator.md`

- [ ] **Step 1: Add observability section to orchestrator**

Add as a new section before Reference Documents:

```markdown
## N. Pipeline Observability

### Progress Reporting

At each stage transition, output a concise progress line:

```
[STAGE N/10] {STAGE_NAME} — {status} ({elapsed}s)
```

Examples:
```
[STAGE 0/10] PREFLIGHT — complete (2s) — module: kotlin-spring, risk: MEDIUM
[STAGE 1/10] EXPLORE — complete (15s) — 12 files analyzed, 3 patterns found
[STAGE 2/10] PLAN — complete (8s) — 2 stories, 5 tasks, 2 parallel groups
[STAGE 3/10] VALIDATE — complete (6s) — verdict: GO
[STAGE 4/10] IMPLEMENT — in progress — task 3/5 (group 2)
[STAGE 5/10] VERIFY — complete (12s) — build OK, lint OK, tests 42/42
[STAGE 6/10] REVIEW — complete (25s) — score: 94/100 (CONCERNS), cycle 2/2
[STAGE 7/10] DOCS — complete (3s) — no updates needed
[STAGE 8/10] SHIP — complete (5s) — PR #42 created
[STAGE 9/10] LEARN — complete (4s) — 1 learning, recap written
```

### Error Reporting

When a stage fails or pauses, include diagnostic context:

```
[STAGE 5/10] VERIFY — FAILED (45s) — test failures: 3 (AuthServiceTest, PlanTest, NoteTest)
```

### Cost Tracking

Update `cost` in state.json at each stage transition:
- `wall_time_seconds`: total elapsed from PREFLIGHT start
- `stages_completed`: increment by 1

Report in final output:
```
Pipeline complete in {wall_time}s — {stages_completed} stages, {quality_score}/100
```
```

- [ ] **Step 2: Commit**

```bash
git add agents/pl-100-orchestrator.md
git commit -m "feat: add pipeline observability with progress reporting and cost tracking"
```

---

## Phase B: Shared Contracts & Schemas

---

### Task 5: Add Error Taxonomy

Standardize error classification across all agents.

**Files:**
- Create: `shared/error-taxonomy.md`

- [ ] **Step 1: Create the error taxonomy document**

```markdown
# Error Taxonomy

Standard error classification for all pipeline agents. Every error reported to the orchestrator or recovery engine must use this format.

## Error Format

```
ERROR_TYPE: {type}
ERROR_DETAIL: {specific message}
RECOVERABLE: true | false
SUGGESTED_STRATEGY: {recovery strategy name or "none"}
CONTEXT: {file:line or command that failed}
```

## Error Types

| Type | Meaning | Recoverable? | Default Strategy |
|---|---|---|---|
| `TOOL_FAILURE` | Shell command failed (build, test, lint) | Yes | `transient-retry` |
| `BUILD_FAILURE` | Compilation error | Yes | `tool-diagnosis` |
| `TEST_FAILURE` | Test assertion failed | Yes | `tool-diagnosis` |
| `LINT_FAILURE` | Linter reported errors | Yes | `tool-diagnosis` |
| `AGENT_TIMEOUT` | Dispatched agent didn't return in time | Yes | `agent-reset` |
| `AGENT_ERROR` | Dispatched agent returned an error | Maybe | `agent-reset` |
| `STATE_CORRUPTION` | state.json or checkpoint unreadable | Yes | `state-reconstruction` |
| `DEPENDENCY_MISSING` | Required tool/binary not found | No | `dependency-health` |
| `CONFIG_INVALID` | dev-pipeline.local.md malformed or missing required fields | No | none (user must fix) |
| `GIT_CONFLICT` | Merge conflict or dirty state | No | `resource-cleanup` |
| `DISK_FULL` | Insufficient disk space | No | `resource-cleanup` |
| `NETWORK_UNAVAILABLE` | External service unreachable (GitHub, context7, Linear) | Maybe | `transient-retry` |
| `PERMISSION_DENIED` | File or directory not writable | No | none (user must fix) |
| `MCP_UNAVAILABLE` | Optional MCP server not responding | Yes | graceful degradation |
| `PATTERN_MISSING` | Referenced pattern file doesn't exist | No | none (planner must fix) |

## Usage by Agents

When an agent encounters an error:

1. Classify it using the table above
2. If `RECOVERABLE: true`: attempt the `SUGGESTED_STRATEGY` (up to recovery budget)
3. If `RECOVERABLE: false`: report to orchestrator immediately with the error format
4. The orchestrator decides: retry, skip, or escalate to user

## Usage by Recovery Engine

The recovery engine reads the `ERROR_TYPE` field to select the appropriate strategy without heuristic classification. This replaces the free-text error parsing that was previously required.

## Error Aggregation

If multiple errors occur in the same stage:
- Report all of them (don't stop at the first)
- Group by ERROR_TYPE
- The most severe (non-recoverable) determines the stage outcome
```

- [ ] **Step 2: Reference from recovery-engine.md**

In `shared/recovery/recovery-engine.md`, add a note:

```markdown
### Error Classification

Errors should be classified per `shared/error-taxonomy.md` before invoking recovery strategies. If an error arrives with a pre-classified `ERROR_TYPE` and `SUGGESTED_STRATEGY`, use those directly instead of heuristic classification.
```

- [ ] **Step 3: Reference from orchestrator**

In the orchestrator's Reference Documents section, add `shared/error-taxonomy.md`.

- [ ] **Step 4: Commit**

```bash
git add shared/error-taxonomy.md shared/recovery/recovery-engine.md agents/pl-100-orchestrator.md
git commit -m "feat: add error taxonomy with 15 classified error types and recovery strategies"
```

---

### Task 6: Add Scoring Formula Customization

Allow projects to tune quality thresholds.

**Files:**
- Modify: `shared/scoring.md`
- Modify: all 12 `modules/*/local-template.md` files (add `scoring:` section)

- [ ] **Step 1: Add customization section to scoring.md**

After the existing formula section:

```markdown
## Scoring Customization

The default formula (`100 - 20*CRITICAL - 5*WARNING - 2*INFO`) and thresholds (PASS >= 80, CONCERNS 60-79, FAIL < 60) can be overridden per-project in `pipeline-config.md`:

```yaml
scoring:
  critical_weight: 20
  warning_weight: 5
  info_weight: 2
  pass_threshold: 80
  concerns_threshold: 60
```

### Resolution Order

1. `pipeline-config.md` scoring values (if present)
2. Plugin defaults (the values in this document)

### Constraints

- `critical_weight` must be >= 10 (CRITICALs are always serious)
- `pass_threshold` must be >= 60 (below 60 is always FAIL)
- `concerns_threshold` must be < `pass_threshold`
- If any constraint is violated, log WARNING and use plugin defaults

### When to Customize

- **Stricter** (raise weights/thresholds): regulated industries, production-critical systems, shared libraries
- **Looser** (lower weights/thresholds): prototypes, internal tools, early-stage startups
- **Default works for most projects.** Only customize if the default scoring is causing false gates (blocking good code) or false passes (allowing bad code).
```

- [ ] **Step 2: Add scoring config to module pipeline-config-templates**

For each module's `pipeline-config-template.md`, add:

```yaml
# scoring:
#   critical_weight: 20
#   warning_weight: 5
#   info_weight: 2
#   pass_threshold: 80
#   concerns_threshold: 60
```

Commented out by default — users uncomment to customize.

- [ ] **Step 3: Commit**

```bash
git add shared/scoring.md modules/*/pipeline-config-template.md
git commit -m "feat: add scoring formula customization with per-project overrides"
```

---

### Task 7: Add Agent Effectiveness Tracking

Close the feedback loop on which agents are performing well.

**Files:**
- Modify: `shared/learnings/README.md`
- Create: `shared/learnings/agent-effectiveness-template.md`
- Modify: `agents/pl-700-retrospective.md`

- [ ] **Step 1: Create agent effectiveness template**

```markdown
# Agent Effectiveness Tracking

Template for tracking review agent performance across pipeline runs. Updated by `pl-700-retrospective`.

## Metrics Per Agent

For each review agent dispatched during REVIEW:

| Metric | Description | Source |
|---|---|---|
| `runs` | Total times dispatched | stage notes |
| `avg_time_seconds` | Average wall time per dispatch | stage timestamps |
| `avg_findings` | Average findings returned per dispatch | quality gate report |
| `false_positive_rate` | Findings marked incorrect by implementer / total findings | fix cycle deltas |
| `coverage_pct` | Files reviewed / files changed | agent output vs changed files list |

## False Positive Detection

A finding is classified as "false positive" when:
1. The implementer marks it as `ACCEPTED` (intentional trade-off) AND
2. The quality gate re-scores and the finding is gone (not because it was fixed, but because the re-review no longer flags it)

A finding is NOT a false positive when:
- The implementer fixes it (it was real)
- The implementer documents it as unfixable (it's real but out of scope)

## Auto-Tuning Triggers

If an agent's `false_positive_rate` exceeds 30% over 5+ runs:
- Retrospective suggests: "Agent {name} has {rate}% false positive rate. Consider tightening its rules or reviewing its conventions file."

If an agent's `avg_findings` drops to 0 over 5+ runs:
- Retrospective suggests: "Agent {name} hasn't found issues in 5 runs. It may be redundant for this project, or the codebase has matured past its checks."

If an agent's `avg_time_seconds` exceeds 120s consistently:
- Retrospective suggests: "Agent {name} averages {time}s. Consider limiting its file scope or splitting into focused sub-agents."
```

- [ ] **Step 2: Add effectiveness tracking to retrospective**

In `agents/pl-700-retrospective.md`, add a section:

```markdown
## Agent Effectiveness Analysis

During retrospective, analyze agent performance:

1. Read quality gate reports from all cycles
2. For each review agent that was dispatched:
   - Count findings, time taken, files reviewed
   - Estimate false positive rate from fix cycle deltas
3. Update agent effectiveness data in pipeline-log.md:
   ```
   ### Agent Effectiveness ({date})
   | Agent | Runs | Avg Time | Avg Findings | FP Rate |
   |---|---|---|---|---|
   | architecture-reviewer | 12 | 8s | 1.2 | 5% |
   | security-reviewer | 12 | 12s | 0.8 | 10% |
   ```
4. Check auto-tuning triggers (see `shared/learnings/agent-effectiveness-template.md`)
5. If any trigger fires, add improvement proposal
```

- [ ] **Step 3: Update learnings README**

In `shared/learnings/README.md`, add reference to the agent effectiveness template.

- [ ] **Step 4: Commit**

```bash
git add shared/learnings/agent-effectiveness-template.md shared/learnings/README.md agents/pl-700-retrospective.md
git commit -m "feat: add agent effectiveness tracking with false positive detection and auto-tuning triggers"
```

---

## Phase C: PREEMPT Lifecycle & Cross-Project Learnings

---

### Task 8: Add PREEMPT Lifecycle (Confidence Decay & Archival)

Prevent pipeline-log.md from growing unbounded.

**Files:**
- Modify: `agents/pl-700-retrospective.md`
- Modify: `shared/learnings/README.md`

- [ ] **Step 1: Add PREEMPT lifecycle rules to retrospective**

```markdown
## PREEMPT Lifecycle

### Confidence Decay

After each run, evaluate PREEMPT items:

- Items that were matched AND applied: increment `hit_count`, reset decay
- Items that were matched but NOT triggered (domain matched, but no violation found): no change
- Items that were NOT matched (domain didn't match this run): no change
- Items that have not been hit in 10 consecutive runs where the domain was active:
  - HIGH → MEDIUM
  - MEDIUM → LOW
  - LOW → ARCHIVED

### Archival

When a PREEMPT item reaches ARCHIVED status:
1. Move it from the active section to an `## Archived PREEMPT Items` section at the bottom of `pipeline-log.md`
2. Keep the full item (don't delete) — it may be needed for historical context
3. Archived items are NOT loaded during PREFLIGHT (saves context budget)

### Promotion

When the same PREEMPT pattern appears in 3+ runs with HIGH confidence:
- Suggest promoting it to the module's conventions file or rules-override.json
- Log: "PREEMPT {ID} has fired {N} times with HIGH confidence. Consider making it a permanent rule."

### Format

Each PREEMPT item must include:
```
### {MODULE}-PREEMPT-{NNN}: {title}
- **Domain:** {area}
- **Pattern:** {what to do or avoid}
- **Confidence:** HIGH | MEDIUM | LOW
- **Hit count:** {N}
- **Last hit:** {ISO date}
- **Runs since last hit:** {N}
```
```

- [ ] **Step 2: Update learnings README with lifecycle documentation**

- [ ] **Step 3: Commit**

```bash
git add agents/pl-700-retrospective.md shared/learnings/README.md
git commit -m "feat: add PREEMPT lifecycle with confidence decay, archival, and promotion triggers"
```

---

### Task 9: Add Cross-Project Learnings Promotion

Promote project-level patterns to module-level when they recur.

**Files:**
- Modify: `agents/pl-700-retrospective.md`
- Modify: `shared/learnings/README.md`

- [ ] **Step 1: Add cross-project promotion to retrospective**

```markdown
## Cross-Project Learning Promotion

When a PREEMPT item is promoted (3+ runs, HIGH confidence), the retrospective checks:

1. Is this pattern already in the module's learnings file (`shared/learnings/{module}.md`)?
   - If yes: increment the module-level hit count
   - If no: propose adding it

2. Propose format:
   ```
   New module-level learning proposed:
   - Source: project PREEMPT {ID} from {project}
   - Pattern: {description}
   - Confidence: HIGH (triggered {N} times)
   - Action: Add to shared/learnings/{module}.md
   ```

3. The retrospective does NOT modify `shared/learnings/{module}.md` directly (that's a shared contract). It proposes the addition in the pipeline report.

4. If the same pattern is proposed from 3+ different projects:
   - Escalate: "Module-wide pattern detected across {N} projects. Consider adding to {module}/conventions.md."
```

- [ ] **Step 2: Commit**

```bash
git add agents/pl-700-retrospective.md shared/learnings/README.md
git commit -m "feat: add cross-project learning promotion to module-level patterns"
```

---

## Phase D: Convention Drift & Communication

---

### Task 10: Add Convention Drift Detection

Detect when conventions change mid-run.

**Files:**
- Modify: `agents/pl-100-orchestrator.md`
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add conventions hash to state initialization**

In the orchestrator PREFLIGHT section, after reading conventions_file:

```markdown
### Convention Fingerprinting

After reading conventions_file, compute a hash of its content and store in state.json:

```json
{
  "conventions_hash": "{md5 or first 8 chars of sha256}"
}
```

This enables mid-run drift detection: if an agent reads the conventions file and gets a different hash, it knows the file changed.
```

- [ ] **Step 2: Add `conventions_hash` to state-schema.md**

Add to the field reference table:

```
| `conventions_hash` | string | Yes | MD5/SHA256 hash of conventions_file content at PREFLIGHT time. Agents compare against current hash to detect mid-run convention changes. |
```

- [ ] **Step 3: Add drift check instruction for agents**

Add to the orchestrator's Dispatched Agents subsection (Context Management):

```markdown
### Convention Drift Check

Agents that read the conventions file should:
1. After reading, compute hash of the content
2. Compare with `conventions_hash` in state.json
3. If different: log WARNING "Conventions file changed mid-run (PREFLIGHT hash: {old}, current: {new}). Using current version."
4. Continue with the current (newer) version — don't use stale conventions
```

- [ ] **Step 4: Commit**

```bash
git add agents/pl-100-orchestrator.md shared/state-schema.md
git commit -m "feat: add convention drift detection via content hash comparison"
```

---

### Task 11: Add Agent Communication Protocol

Define how agents share context beyond stage notes.

**Files:**
- Create: `shared/agent-communication.md`
- Modify: `agents/pl-100-orchestrator.md`

- [ ] **Step 1: Create agent communication document**

```markdown
# Agent Communication Protocol

Agents in the pipeline do not communicate directly. All inter-agent data flows through the orchestrator via two mechanisms:

## 1. Stage Notes (async, persistent)

Each stage writes `.pipeline/stage_N_notes_{storyId}.md`. Downstream stages can read upstream notes.

- Written by: the agent completing a stage
- Read by: the orchestrator (always), downstream agents (when orchestrator includes relevant context in dispatch)
- Format: markdown with structured sections (findings, decisions, metrics)
- Lifetime: per-run (cleared on `/pipeline-reset`)

## 2. Shared Findings Context (within REVIEW stage)

During REVIEW, multiple agents run in parallel batches. Their findings are collected by `pl-400-quality-gate` for deduplication. To reduce duplicate work:

### Finding Deduplication Hints

When the quality gate dispatches batch 2+ agents, it includes a summary of findings from previous batches:

```
Previous batch findings (for deduplication — do not re-report these):
- ARCH-HEX-001: file.kt:42 — Core imports adapter type
- SEC-AUTH-003: controller.kt:15 — Missing ownership check
```

This prevents batch 2 agents from flagging the same issues batch 1 already found.

### Cross-Agent References

If a review agent finds an issue that relates to another agent's domain:

```
file:line | ARCH-BOUNDARY | WARNING | Core imports adapter — also a security concern (ownership verification depends on this) | Fix: move mapping to adapter
```

The `also a security concern` note helps the quality gate understand the finding's cross-cutting nature without requiring the security reviewer to independently discover it.

## 3. What Agents CANNOT Do

- Agents cannot dispatch other agents (only the orchestrator dispatches)
- Agents cannot modify state.json (only the orchestrator writes state)
- Agents cannot read other agents' in-progress work (isolation is enforced)
- Agents cannot send messages to the user (only the orchestrator presents to user)

## 4. Data Flow Diagram

```
EXPLORE agent → stage_1_notes → orchestrator → PLAN agent dispatch prompt
PLAN agent → stage_2_notes → orchestrator → VALIDATE agent dispatch prompt
VALIDATE agent → stage_3_notes → orchestrator → IMPLEMENT agent dispatch prompt
...
REVIEW batch 1 agents → findings → quality gate → batch 2 dispatch prompt (includes batch 1 findings summary)
```

All data flows through the orchestrator. Agents are isolated. The orchestrator curates what context each agent receives.
```

- [ ] **Step 2: Reference from orchestrator**

Add to the Reference Documents section: `shared/agent-communication.md`.

- [ ] **Step 3: Commit**

```bash
git add shared/agent-communication.md agents/pl-100-orchestrator.md
git commit -m "feat: add agent communication protocol defining data flow and isolation rules"
```

---

## Phase E: New Skills

---

### Task 12: Create `/pipeline-history` Skill

View trends across pipeline runs.

**Files:**
- Create: `skills/pipeline-history/SKILL.md`

- [ ] **Step 1: Create the skill**

```markdown
---
name: pipeline-history
description: View quality score trends, agent effectiveness, and run metrics across pipeline runs
disable-model-invocation: false
---

# Pipeline History

View trends across pipeline runs for this project.

## What to do

1. Read `.claude/pipeline-log.md` for run history
2. Read `.pipeline/reports/` for detailed run reports (if available)
3. Present a summary:

```
## Pipeline Run History

### Quality Score Trend
| Date | Requirement | Score | Verdict | Fix Cycles | Duration |
|------|-------------|-------|---------|------------|----------|
| 2026-03-20 | Add product catalog | 94/100 | PASS | 2 | 45s |
| 2026-03-18 | Fix billing bug | 100/100 | PASS | 0 | 22s |
| 2026-03-15 | Add notifications | 88/100 | CONCERNS | 3 | 78s |

### Most Common Findings
1. PERF-N+1 (3 runs) — N+1 queries in persistence adapters
2. CONV-DOC (2 runs) — Missing KDoc on new exports
3. ARCH-BOUNDARY (1 run) — Core importing adapter type

### Agent Effectiveness
{If agent effectiveness data exists in pipeline-log.md, show the table}

### PREEMPT Health
- Active items: {count} (HIGH: {n}, MEDIUM: {n}, LOW: {n})
- Archived items: {count}
- Last promotion: {date} — {item description}
```

## If no history exists

Report: "No pipeline runs found. Run `/pipeline-run` to start building history."
```

- [ ] **Step 2: Commit**

```bash
git add skills/pipeline-history/SKILL.md
git commit -m "feat: add /pipeline-history skill for cross-run trend analysis"
```

---

### Task 13: Create `/pipeline-rollback` Skill

Documented rollback procedure when things go wrong.

**Files:**
- Create: `skills/pipeline-rollback/SKILL.md`

- [ ] **Step 1: Create the skill**

```markdown
---
name: pipeline-rollback
description: Safely rollback pipeline changes — revert worktree, restore state, or undo specific commits
disable-model-invocation: false
---

# Pipeline Rollback

Safely undo pipeline changes when something goes wrong.

## Modes

### 1. Rollback worktree (most common)

If the pipeline's worktree has changes you don't want:

```bash
# Option A: Delete the worktree entirely (preserves main tree)
git worktree remove .pipeline/worktree --force

# Option B: Reset worktree to pre-implement state
cd .pipeline/worktree && git reset --hard HEAD~{N}
```

The main working tree is NEVER affected by worktree rollback.

### 2. Rollback after merge

If the worktree was already merged to your branch:

```bash
# Find the merge commit
git log --oneline -10

# Revert the merge
git revert {merge-commit-sha}
```

### 3. Rollback Linear tickets

If Linear tickets were created but the pipeline failed:

- The pipeline does NOT auto-delete Linear tickets on failure
- Manually archive or delete the Epic in Linear
- Or leave them — they document the attempted work

### 4. Rollback state only

If you want to keep the code but reset the pipeline state:

```bash
/pipeline-reset
```

This removes `.pipeline/` (state, checkpoints, notes) but preserves the code changes.

## What to do

1. Ask the user what they want to rollback (worktree, merge, Linear, state)
2. Show the appropriate commands
3. Confirm before executing any destructive operation
4. NEVER force-delete without confirmation
```

- [ ] **Step 2: Commit**

```bash
git add skills/pipeline-rollback/SKILL.md
git commit -m "feat: add /pipeline-rollback skill for safe undo of pipeline changes"
```

---

## Phase F: Documentation Updates

---

### Task 14: Update CLAUDE.md and Spec

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-03-22-pipeline-orchestration-hardening-design.md`

- [ ] **Step 1: Update CLAUDE.md**

Add to the Skills section:
```
- `pipeline-history` — view quality score trends and agent effectiveness across runs.
- `pipeline-rollback` — safely undo pipeline changes (worktree, merge, Linear, state).
```

Add to the Key conventions section:
```
### Error taxonomy (`shared/error-taxonomy.md`)
- 15 standard error types with recovery strategies. Agents classify errors before reporting to the orchestrator.

### Agent communication (`shared/agent-communication.md`)
- All inter-agent data flows through the orchestrator. Agents are isolated and cannot communicate directly.
```

Add to Gotchas:
```
- The scoring formula is customizable per-project via `pipeline-config.md`. See `shared/scoring.md` for constraints.
- PREEMPT items decay in confidence if unused for 10+ runs. HIGH → MEDIUM → LOW → ARCHIVED.
- The orchestrator enforces parallel task conflict detection at IMPLEMENT time — tasks sharing files are automatically serialized.
```

- [ ] **Step 2: Update the design spec**

Append to the spec document:

```markdown
## Phase 2 Enhancements (added 2026-03-22)

The following enhancements were designed and implemented in the same session as Phase 1:

1. `--dry-run` flag for pipeline preview
2. Parallel task conflict detection with automatic serialization
3. Timeout enforcement mechanism (command, agent, stage levels)
4. Pipeline observability (progress reporting, cost tracking)
5. Error taxonomy (15 classified error types)
6. Scoring formula customization
7. Agent effectiveness tracking
8. PREEMPT lifecycle (confidence decay, archival, promotion)
9. Cross-project learning promotion
10. Convention drift detection
11. Agent communication protocol
12. `/pipeline-history` skill
13. `/pipeline-rollback` skill
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-03-22-pipeline-orchestration-hardening-design.md
git commit -m "docs: update CLAUDE.md and spec with Phase 2 enhancements"
```

---

## Verification Checklist

Run after all tasks:

```bash
# New files exist
ls shared/error-taxonomy.md shared/agent-communication.md shared/learnings/agent-effectiveness-template.md
ls skills/pipeline-history/SKILL.md skills/pipeline-rollback/SKILL.md

# Section numbering in orchestrator
grep "^## [0-9]" agents/pl-100-orchestrator.md

# All skills have valid frontmatter
for d in skills/*/; do head -3 "${d}SKILL.md"; echo; done

# Scoring customization in templates
grep -c "scoring:" modules/*/pipeline-config-template.md

# dry_run field in state init
grep "dry_run" agents/pl-100-orchestrator.md

# conventions_hash in state schema
grep "conventions_hash" shared/state-schema.md

# Error taxonomy types count
grep -c "ERROR_TYPE\|TOOL_FAILURE\|BUILD_FAILURE" shared/error-taxonomy.md
```
