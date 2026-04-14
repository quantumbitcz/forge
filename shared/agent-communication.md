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

### Domain-Scoped Deduplication Hints

When dispatching batch 2+ agents, the quality gate filters dedup hints by **category affinity** (defined in `shared/checks/category-registry.json`, `affinity` field). Each reviewer only sees findings from categories relevant to its domain:

- `fg-411-security-reviewer` receives: `SEC-*`, `QUAL-ERR-*` (error handling has security implications)
- `fg-412-architecture-reviewer` receives: `ARCH-*`, `STRUCT-*`, `QUAL-COMPLEX`
- `fg-413-frontend-reviewer` receives: `FE-PERF-*`, `A11Y-*`, `CONV-*` (frontend conventions), `DESIGN-*`
- `fg-416-performance-reviewer` receives: `PERF-*`
- `fg-417-dependency-reviewer` receives: `DEP-*`
- `fg-418-docs-consistency-reviewer` receives: `DOC-*`
- `fg-419-infra-deploy-reviewer` receives: `INFRA-*`
- `fg-410-code-reviewer` receives: `TEST-*`, `CONV-*`, `QUAL-*`

**Affinity resolution:** For each finding in the dedup hints:
1. Look up the finding's category prefix in `category-registry.json`
2. Check the `affinity` array for the target reviewer's agent ID
3. If the reviewer is in the affinity list, OR if affinity is `[]` (empty — send to all): include the finding
4. Otherwise: exclude the finding from this reviewer's dedup hints

**Subcategory affinity:** Subcategories (e.g., `QUAL-ERR-*`) may have different affinity than their parent (`QUAL-*`). When a subcategory has explicit affinity documented here, use the subcategory's affinity. Otherwise, fall through to the parent category's affinity in `category-registry.json`.

Subcategory affinity overrides:
- `QUAL-ERR-*`: `["fg-410-code-reviewer", "fg-411-security-reviewer"]` (error handling is a security concern)
- `QUAL-COMPLEX`: `["fg-410-code-reviewer", "fg-412-architecture-reviewer"]` (complexity is an architecture concern)

**Backward compatibility:** If `affinity` is missing for a category in the registry, the finding is sent to ALL reviewers (pre-v1.17 behavior).

**Registry unavailability fallback:** If `category-registry.json` is unavailable or corrupted, fall back to sending all findings to all reviewers (conservative deduplication). Log as WARNING: "Category registry unavailable, broadcasting all findings."

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

### Deliberation Protocol (v1.18+)

When `quality_gate.deliberation` is enabled, the quality gate may re-dispatch reviewers for a deliberation round on conflicting findings. This is an extension of the conflict reporting protocol — not a replacement.

**Flow:**
1. Quality gate detects conflict per the reporting protocol above
2. If deliberation enabled AND conflict involves >= WARNING: quality gate re-dispatches both agents
3. Each agent receives the deliberation prompt (format in `shared/agent-defaults.md` §Deliberation Response Format)
4. Agents respond with MAINTAIN/REVISE/WITHDRAW
5. Quality gate applies results before scoring

**Key constraints:**
- Max 1 deliberation round (no recursive re-dispatch)
- Only for >= WARNING severity conflicts (INFO-vs-INFO uses priority ordering)
- 60-second timeout per agent (configurable: `quality_gate.deliberation_timeout`)
- Deliberation adds at most 2 sub-agent dispatches per conflict cluster
- Reviewers in deliberation mode are read-only — they cannot modify files or produce new findings, only respond to the deliberation prompt

**This does NOT change the conflict reporting protocol.** Agents still report conflicts in the same format. Deliberation is an additional resolution step that the quality gate performs after collection.

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

### A2A Cross-Repo Communication

When a target repository exposes `.forge/agent-card.json`, the cross-repo coordinator (fg-103) switches from file-based polling to the A2A (Agent-to-Agent) protocol for inter-repo coordination.

**Activation criteria:**
- `.forge/agent-card.json` exists in the target repo root
- The agent card declares supported capabilities (streaming, pushNotifications)
- The coordinator has filesystem access to the target repository

**Communication flow:**
1. fg-103 discovers the agent card during `setup-worktrees` or `coordinate-implementation`
2. Tasks are created via A2A `tasks/send` instead of dispatching a local fg-100 instance
3. State synchronization uses A2A task state transitions (`working`, `completed`, `failed`) rather than polling `sprint-state.json`
4. Artifacts returned by the remote agent (PR URLs, test results) are written to sprint-state.json

**Fallback:** If the agent card is missing or unreadable, fg-103 falls back to the standard file-based polling described above (reading per-run `state.json` files).

**Protocol reference:** See `shared/a2a-protocol.md` for the full A2A message format, agent card schema, and error handling conventions.

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

See **PREEMPT Marker Format** below for the exact format specification and parsing regex.

### PREEMPT Marker Format

Markers are written to stage notes under `## Attempt N` headers.

**Format:**
```
PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
PREEMPT_SKIPPED: {item-id} — not applicable ({reason})
```

**Parsing regex:** `^PREEMPT_(APPLIED|SKIPPED): (\S+) — (.+)$`

**Rules:**
- Only markers from the **last attempt** in a stage are authoritative
- Earlier attempt markers are superseded (the fix may have changed applicability)
- Orchestrator counts APPLIED/SKIPPED per item-id for decay tracking

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

### PREEMPT Confidence Decay

Items decay toward archival based on usage patterns. Decay is tracked per item in `forge-log.md`:

**Decay score formula:** `decay_score = unused_runs + (false_positives * 3)`

Where:
- `unused_runs` — consecutive runs where the item was loaded but neither APPLIED nor SKIPPED (item was in scope but the domain area didn't trigger it)
- `false_positives` — times the item was marked `PREEMPT_SKIPPED` with reason indicating inapplicability (each false positive counts as 3 unused runs toward decay)

**Confidence tiers:** HIGH (decay_score 0-3) → MEDIUM (4-6) → LOW (7-9) → ARCHIVED (10+)

### PREEMPT Decay Counting Rules

Three states a PREEMPT item can be in during a pipeline run:

| State | Counts as | Decay effect |
|-------|-----------|-------------|
| Loaded + checked + finding reported | "Used" | Resets decay counter to 0 |
| Loaded + checked + no match in changeset | "Loaded but not reported" | +1 decay unit |
| Not loaded (agent context too small) | Not counted | No decay change |

**Example 1: Item loaded, checked, finding reported (resets decay)**

PREEMPT item: "Always use `@Transactional(readOnly = true)` for query-only service methods."

Run N: The implementer writes a new service method with `@Transactional`. The code reviewer loads this PREEMPT item, checks the new method, and finds it has `@Transactional` without `readOnly = true` on a query method. Finding reported: `CONV-TX-READONLY | WARNING`. Decay counter resets to 0.

**Example 2: Item loaded, checked, no match found (+1 decay unit)**

PREEMPT item: "Never use `Thread.sleep()` in production code."

Run N: The implementer writes a new REST controller. The code reviewer loads this PREEMPT item and checks all new/modified files. No `Thread.sleep()` calls found in the changeset. The item was loaded and checked but produced no finding. Decay counter increments by 1.

After 10 such runs (loaded but never triggered), the item decays: HIGH -> MEDIUM -> LOW -> ARCHIVED.

**Example 3: Item not loaded, agent context too small (no decay change)**

PREEMPT item: "Prefer `kotlinx.serialization` over `Jackson` for Kotlin multiplatform modules."

Run N: The pipeline runs in bugfix mode with reduced review (3 agents). The code reviewer's context is filled with bugfix-specific findings and the PREEMPT item list exceeds the agent's context window. This item is not included in the dispatch prompt. The decay counter is unchanged -- the item was not given a chance to prove relevance.

**Detection mechanism:** The orchestrator tracks which PREEMPT items were included in each agent dispatch prompt via `preempt_items_loaded[]` in stage notes. Items not in `preempt_items_loaded` for any agent in the run are classified as "not loaded." Items in `preempt_items_loaded` but not in any agent's `findings[]` are classified as "loaded but not reported."

**Auto-discovered items:** Items with `source: auto-discovered` follow the same rules with these modifications:
- Auto-discovered items start at MEDIUM confidence (not HIGH)
- Auto-discovered items decay 2x faster — each unused run increments `decay_score` by 2 instead of 1
- Auto-discovered items archive at `decay_score >= 5` (faster than the standard threshold of 10)
- Auto-discovered items promote to HIGH after 3 successful applications (3 runs where the item was APPLIED)

**Tier transitions:**
- Items start at HIGH when first recorded in `forge-log.md`
- Tier decreases when `decay_score` crosses thresholds
- A single APPLIED resets `decay_score` to 0 and restores HIGH confidence
- ARCHIVED items are excluded from PREEMPT loading at PREFLIGHT (but remain in `forge-log.md` for historical reference)

**Retrospective update logic:**
1. For each PREEMPT item in `preempt_items_status`:
   - If `applied: true` → reset `decay_score = 0`, set tier = HIGH
   - If `applied: false, false_positive: true` → increment `decay_score += 3`
2. For items in `preempt_items_applied` but NOT in `preempt_items_status` (loaded but not reported) → increment `decay_score += 1`

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

## 10. Structured Output Standard

Coordinator agents (fg-400-quality-gate, fg-500-test-gate, fg-700-retrospective) embed machine-readable JSON within their Markdown output. The JSON is wrapped in an HTML comment so it is invisible in rendered Markdown but trivially extractable by downstream consumers (orchestrator, retrospective, post-run agent, `/forge-insights`).

### Format

```markdown
<!-- FORGE_STRUCTURED_OUTPUT
{
  "schema": "coordinator-output/v1",
  "agent": "<agent-id>",
  "timestamp": "<ISO-8601>",
  ...agent-specific fields...
}
-->
```

The block MUST appear at the end of the coordinator's Markdown output, after all human-readable sections. This ensures the Markdown is complete and readable even if the structured block is stripped.

### Schema Versioning

The `schema` field (`coordinator-output/v1`) enables forward compatibility. Consumers MUST check the schema version before parsing. Unknown schema versions trigger fallback to Markdown parsing.

### Extraction Algorithm

Consumers extract the structured block using a regex with DOTALL (single-line) mode:

**Python:**
```python
import re, json

def extract_structured_output(markdown_text):
    """Extract FORGE_STRUCTURED_OUTPUT from coordinator Markdown output."""
    pattern = r'<!-- FORGE_STRUCTURED_OUTPUT\n(.*?)\n-->'
    match = re.search(pattern, markdown_text, re.DOTALL)
    if match:
        return json.loads(match.group(1))
    return None  # Trigger fallback to Markdown parsing
```

**Bash:**
```bash
extract_structured_output() {
  local text="$1"
  echo "$text" | sed -n '/<!-- FORGE_STRUCTURED_OUTPUT/,/-->/{ /<!-- FORGE_STRUCTURED_OUTPUT/d; /-->/d; p; }'
}
```

### Backward Compatibility

If the `FORGE_STRUCTURED_OUTPUT` block is missing from a coordinator's output, consumers MUST fall back to their existing Markdown parsing logic. This ensures the pipeline continues to function during rollout and when agents truncate output due to token limits.

When falling back, consumers SHOULD log a WARNING:

```
WARNING: {agent-id} did not include structured output, using Markdown fallback
```

This makes fallback events observable for monitoring and migration tracking.

### Producing Agents

| Agent | Schema Fields | Consumers |
|-------|--------------|-----------|
| `fg-400-quality-gate` | verdict, score, findings_summary, batches, dedup_stats, cycle_info, reviewer_agreement, coverage_gaps | fg-100 (convergence), fg-700 (trends), fg-710 (timeline) |
| `fg-500-test-gate` | phase_a, phase_b, mutation_testing, verdict | fg-100 (convergence), fg-700 (trends) |
| `fg-700-retrospective` | run_summary, learnings, config_changes, agent_effectiveness, trend_comparison, approach_accumulations | fg-710 (timeline), `/forge-insights` |

### Token Budget Impact

The structured block adds approximately 500-2000 tokens per coordinator invocation. This is within the stage notes budget (2,000 tokens per stage). If the combined Markdown + JSON exceeds the budget, the coordinator MUST compress the Markdown prose (shorter descriptions, fewer examples) rather than omitting the structured block. The structured block carries higher priority than verbose Markdown because downstream consumers depend on it.

---

## Design Context in Stage Notes

When Figma MCP is available and the requirement references a Figma URL, the planner extracts design context and stores it in stage notes:

```yaml
design_context:
  source: figma
  file_key: "abc123"
  node_id: "1:2"
  tokens:
    colors: [{name: "primary", value: "#1a73e8"}]
    spacing: [{name: "gap-md", value: "16px"}]
    typography: [{name: "heading-lg", size: "24px", weight: 600}]
  screenshot_taken: true
  code_connect_available: false
```

Downstream agents (polisher, reviewer) read this from stage notes to ground their work in the design.
