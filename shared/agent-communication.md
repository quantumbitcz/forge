# Agent Communication Protocol

Agents in the pipeline do not communicate directly. All inter-agent data flows through the orchestrator via defined mechanisms.

## 1. Stage Notes (async, persistent)

Each stage writes `.forge/stage_N_notes_{storyId}.md`. Downstream stages can read upstream notes via the orchestrator's dispatch prompt.

- Written by: the agent completing a stage
- Read by: the orchestrator (always), downstream agents (when orchestrator includes relevant context in dispatch)
- Format: markdown with structured sections (findings, decisions, metrics)
- Lifetime: per-run (cleared on `/forge-reset`)

### What goes in stage notes
- Decisions made and reasoning (for downstream agents and recap)
- Findings with file:line references (for quality gate and implementer)
- Metrics (time, files, test counts — for retrospective)
- Errors encountered and recovery actions taken

### What does NOT go in stage notes
- Full file contents (reference by path instead)
- Raw tool output (extract structured data)
- Conversation history or reasoning traces

### Stage Notes Size Budget

Stage notes should stay under **2,000 tokens** to prevent context cascading in downstream dispatch prompts. If a stage produces more content:

1. **Findings:** Deduplicate to top 20 by severity before writing. Include total count: "20 of {N} findings shown."
2. **File listings:** Reference by directory pattern (e.g., `src/domain/**`) instead of listing every file.
3. **Metrics:** Use a compact table format, not prose.

The **retrospective** (Stage 9) reads all stage notes (0-8). With the 2K cap, 9 stage notes total ~18K tokens — well within dispatch limits. Feedback files and reports are read separately by the retrospective agent (not included in the orchestrator dispatch prompt). If a project has accumulated many feedback entries (>20), the retrospective reads only `feedback/summary.md` (the consolidated file).

## 2. Task Hierarchy

Task visibility follows the agent dispatch hierarchy:

- **Level 1 (Orchestrator):** fg-100-orchestrator creates 10 stage-level tasks. These are the top-level progress indicators.
- **Level 2 (Coordinators):** Agents dispatched by the orchestrator (fg-400, fg-500, fg-600, fg-200, fg-310, etc.) create sub-tasks within their stage for batches, phases, or file groups.
- **Level 3 (Leaf agents):** Agents dispatched by coordinators (fg-300 TDD cycles, fg-610-infra-deploy-verifier tiers) create sub-sub-tasks for their internal steps.

Maximum nesting depth: 3 levels. Leaf agent sub-tasks are the finest granularity.

Tasks are session-scoped (not persisted to state.json). They provide real-time visual progress in the Claude Code UI but do not survive conversation restarts.

## 3. Shared Findings Context (within REVIEW stage)

During REVIEW, multiple agent batches run sequentially. To reduce duplicate work, the quality gate includes previous batch findings in subsequent dispatch prompts.

### Finding Deduplication Hints

When the quality gate dispatches batch 2+ agents, it includes a summary of findings from previous batches:

    Previous batch findings (for deduplication — do not re-report these):
    - ARCH-HEX-001: file.kt:42 — Core imports adapter type
    - SEC-AUTH-003: controller.kt:15 — Missing ownership check

This prevents batch 2 agents from flagging the same issues batch 1 already found.

### Deduplication Hint Size Cap

Cap dedup hints at **top 20 findings by severity** (all CRITICALs first, then WARNINGs, then INFOs by line number). If previous batches produced > 20 findings, include note:

    Previous batch findings ({N} total, showing top 20 for dedup):
    ...
    ({N-20} additional findings omitted — focus on your domain, post-hoc dedup will catch overlaps)

### Cross-Agent References

If a review agent finds an issue that relates to another agent's domain, note it:

    file:line | ARCH-BOUNDARY | WARNING | Core imports adapter — also a security concern (ownership check depends on this boundary) | Fix: move mapping to adapter

The quality gate uses these cross-references to understand finding relationships.

### Conflict Reporting Protocol

When a review agent produces a finding that contradicts another agent's known output (via dedup hints or cross-agent references), it MUST report the conflict explicitly:

```
CONFLICT: {category} at {file}:{line}
  Agent A: {finding_A_description} (severity: {sev_A})
  Agent B: {finding_B_description} (severity: {sev_B})
```

Conflict resolution priority is defined in `shared/checks/category-registry.json` (`priority` field). Lower number = higher priority. Categories without explicit priority default to 5 (CONV-level). Current priority bands:

1. **Security** (SEC-*) — priority 1
2. **Architecture** (ARCH-*, STRUCT-*) — priority 2
3. **Code Quality** (QUAL-*, TEST-*, CONTRACT-*) — priority 3
4. **Performance** (PERF-*, FE-PERF-*, INFRA-*) — priority 4
5. **Convention** (CONV-*, DOC-*, A11Y-*, DESIGN-*) — priority 5
6. **Style** (APPROACH-*, SCOUT-*) — priority 6

When two findings conflict at the same priority level, the finding with the higher severity wins. If severity is also equal, both findings are escalated to the user via the quality gate report with a CONFLICT annotation.

Agents should NOT attempt to resolve conflicts themselves. Report the conflict and let the quality gate arbitrate.

## 4. State.json (orchestrator-managed)

The orchestrator is the sole writer of state.json. Agents read it (for integrations, conventions_hash, etc.) but never write to it.

## 5. What Agents CANNOT Do

- Agents cannot dispatch agents in other stages (all inter-stage data flows through the orchestrator via stage notes). However, coordinator agents (quality gate, test gate, PR builder, planner, scaffolder) may dispatch sub-agents within their own stage for specialized analysis or feedback capture.
- Agents cannot write to state.json (only the orchestrator writes state)
- Agents cannot read other agents' in-progress work (isolation enforced by separate dispatch)
- Agents cannot send messages to the user (only the orchestrator presents to user)
- Agents cannot modify shared contracts (scoring.md, state-schema.md, etc.)
- Agents cannot undo, revert, or overwrite work produced by another agent — if an agent detects a conflict with another agent's output, it MUST report the conflict in stage notes and let the orchestrator decide the resolution strategy.

## 6. Data Flow Summary

    EXPLORE agent → stage_1_notes → orchestrator → PLAN dispatch prompt
    PLAN agent → stage_2_notes → orchestrator → VALIDATE dispatch prompt
                                              ↘ Linear: create Epic/Stories/Tasks
    VALIDATE agent → stage_3_notes → orchestrator → IMPLEMENT dispatch prompt
                                                  ↘ Linear: validation verdict comment
    IMPLEMENT agent → stage_4_notes → orchestrator → state.json (preempt_items_status)
                                                   → checkpoint.json (preempt_items_used)
    VERIFY (test gate) → stage_5_notes → orchestrator → REVIEW dispatch prompt
    REVIEW batch 1 → findings → quality gate → batch 2 (top 20 dedup hints)
    REVIEW final → stage_6_notes → orchestrator → state.json (score_history)
    DOCS agent → stage_7_notes → orchestrator → state.json (documentation)
                                              ← changed files, quality verdict, plan notes,
                                                discovery summary (stage_0_docs_discovery.md)
    SHIP agent → stage_8_notes → orchestrator → LEARN dispatch prompt
                                              ↘ Linear: PR link, status
    FEEDBACK agent → classification → orchestrator → route to PLAN or IMPLEMENT
    LEARN (retro) → stage_final_notes → forge-log.md (PREEMPT hit counts)
                                  → forge-config.md (auto-tuning)
    LEARN (post-run) → recap report ↘ Linear: summary comment

All data flows through the orchestrator. Agents are isolated. The orchestrator curates what each agent receives.

**Checkpoint persistence:** The orchestrator writes `checkpoint-{storyId}.json` after each Stage 4 task completion for resume capability. Checkpoints are orchestrator-internal state — agents do not read or write checkpoints directly.

## 7. Sprint ↔ Feature Communication

The sprint orchestrator (fg-090) communicates with feature orchestrators (fg-100) through:

1. **Sprint state file:** `.forge/sprint-state.json` — read by all, written only by fg-090
2. **Per-run state files:** `.forge/runs/{feature-id}/state.json` — written by each fg-100 instance
3. **Agent dispatch:** fg-090 dispatches fg-100 instances as sub-agents

Feature orchestrators do NOT write to `sprint-state.json`. The sprint orchestrator polls per-run state files and updates sprint state.

### Wait Mechanism

When `--wait-for <project_id>` is set, the feature orchestrator:
1. Reads `sprint-state.json` for the dependency project's status
2. Blocks at PREFLIGHT until dependency status >= `verifying`
3. Poll interval: 30 seconds
4. Timeout: `cross_repo.timeout_minutes` (default 30)

### Conditional Agents

The following agents are dispatched conditionally and receive data from the orchestrator only when their trigger conditions are met:

| Agent | Stage | Trigger | Receives | Outputs |
|-------|-------|---------|----------|---------|
| `fg-320-frontend-polisher` | 4 (IMPLEMENT) | `frontend_polish.enabled` in config AND frontend component detected | Changed frontend files, design theory, theme tokens | Polished files, `FE-*` findings in stage notes |
| `fg-650-preview-validator` | 8 (SHIP) | Preview/staging URL configured in `ship:` config | PR URL, preview URL | Validation results in stage notes |
| `fg-610-infra-deploy-verifier` | 8 (SHIP) | K8s/infra files in changeset | Changed infra files, Helm charts | Verification results in stage notes |
| `fg-130-docs-discoverer` | 0 (PREFLIGHT) | Always (part of preflight) | Project root, config | `stage_0_docs_discovery.md`, docs-index.json |
| `fg-140-deprecation-refresh` | 0 (PREFLIGHT) | Always (part of preflight) | Detected versions, known-deprecations.json | Updated deprecation rules |
| `fg-150-test-bootstrapper` | 0 (PREFLIGHT) | No test infrastructure detected | Project root, framework conventions | Bootstrapped test config, stage notes |
| `fg-418-docs-consistency-reviewer` | 6 (REVIEW) | Documentation exists in project | Changed files, docs-index.json, discovery summary | `DOC-*` findings |

## 7. PREEMPT Item Tracking

During implementation, agents that receive PREEMPT items in their dispatch prompt must report usage in stage notes. PREEMPT producers are: `fg-300-implementer` (primary — receives PREEMPT items for the implementation domain), `fg-310-scaffolder` (when PREEMPT items reference scaffold patterns), and `fg-320-frontend-polisher` (when PREEMPT items reference frontend patterns). If multiple agents report on the same PREEMPT item, the orchestrator uses the marker from the **last agent to complete** (since later agents may override earlier work).

    PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
    PREEMPT_SKIPPED: {item-id} — not applicable ({reason})

The orchestrator reads these markers from stage notes and populates `state.json.preempt_items_status`:
- `{ "applied": true, "false_positive": false }` — item was used and relevant
- `{ "applied": false, "false_positive": true }` — item was loaded but inapplicable

The retrospective agent reads `preempt_items_status` and:
1. Increments `hit_count` in `forge-log.md` for applied items
2. Records false positives for confidence decay acceleration (false positive = 3 unused runs toward decay)
3. Logs: "PREEMPT effectiveness: {applied}/{total} items used, {false_positives} false positives"

### Retry Handling

If a task fails and is retried (within `max_fix_loops`), the implementer may write PREEMPT markers for both the failed and successful attempts. To ensure reliable tracking:

**Implementer convention:** Write markers under attempt headers in stage notes:
```
## Attempt 1 (2026-03-22T14:30:00Z)
PREEMPT_APPLIED: check-openapi-before-controller — applied at api/UserController.kt:15
## Attempt 2 (2026-03-22T14:35:00Z)
PREEMPT_SKIPPED: check-openapi-before-controller — not applicable (controller was removed in refactor)
```

**Orchestrator convention:** When reading stage notes to populate `preempt_items_status`:
- Parse attempt sections by header (## Attempt N)
- Use markers from the **last attempt only** (the successful one, or the final failed attempt if all attempts failed)
- Earlier attempt markers are superseded — do not double-count
- If the same item is marked `PREEMPT_APPLIED` in attempt 1 and `PREEMPT_SKIPPED` in attempt 2, use the attempt 2 status

## 8. Plan Mode Integration

Planning agents (`fg-200-planner`, `fg-010-shaper`, `fg-160-migration-planner`, `fg-050-project-bootstrapper`) use `EnterPlanMode`/`ExitPlanMode` to present their designs for user approval in the Claude Code UI before implementation proceeds.

**When to use plan mode:**
- Interactive sessions where the user is present and can approve plans
- Complex plans with architectural decisions that benefit from user review

**When to skip plan mode:**
- Autonomous orchestrator runs (the validator `fg-210` serves as the approval gate)
- Replanning after a REVISE verdict (plan mode was already used for the initial plan)
- Simple, low-risk plans where the overhead is not justified

**Protocol:**
1. Agent calls `EnterPlanMode` at the start of its planning process
2. Agent explores the codebase, analyzes alternatives, designs the plan
3. Agent writes the plan to stage notes (or spec file for shaper)
4. Agent calls `ExitPlanMode` — user sees the plan and approves or requests changes
5. On approval, the orchestrator proceeds to the next stage

## 9. Convention File Composition

When an agent receives a convention stack with both generic and framework-binding files for the same layer (e.g., `modules/persistence/exposed.md` + `modules/frameworks/spring/persistence/exposed.md`), compose them as follows:

- **Additive sections** (Dos, Don'ts, Patterns, Architecture Patterns): binding entries are appended to generic entries. Both apply.
- **Override sections** (Configuration, Integration Setup, Scaffolder Patterns): binding content replaces generic content for that section.
- **Contradiction rule:** when the binding explicitly contradicts the generic (e.g., different implementation strategy), the binding wins. When the binding adds without contradicting, both apply.

Agents read BOTH files: generic first (for foundational patterns), then binding (for framework-specific adaptations).
