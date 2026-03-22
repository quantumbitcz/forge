# Agent Communication Protocol

Agents in the pipeline do not communicate directly. All inter-agent data flows through the orchestrator via defined mechanisms.

## 1. Stage Notes (async, persistent)

Each stage writes `.pipeline/stage_N_notes_{storyId}.md`. Downstream stages can read upstream notes via the orchestrator's dispatch prompt.

- Written by: the agent completing a stage
- Read by: the orchestrator (always), downstream agents (when orchestrator includes relevant context in dispatch)
- Format: markdown with structured sections (findings, decisions, metrics)
- Lifetime: per-run (cleared on `/pipeline-reset`)

### What goes in stage notes
- Decisions made and reasoning (for downstream agents and recap)
- Findings with file:line references (for quality gate and implementer)
- Metrics (time, files, test counts — for retrospective)
- Errors encountered and recovery actions taken

### What does NOT go in stage notes
- Full file contents (reference by path instead)
- Raw tool output (extract structured data)
- Conversation history or reasoning traces

## 2. Shared Findings Context (within REVIEW stage)

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

## 3. State.json (orchestrator-managed)

The orchestrator is the sole writer of state.json. Agents read it (for integrations, conventions_hash, etc.) but never write to it.

## 4. What Agents CANNOT Do

- Agents cannot dispatch other agents (only the orchestrator dispatches)
- Agents cannot write to state.json (only the orchestrator writes state)
- Agents cannot read other agents' in-progress work (isolation enforced by separate dispatch)
- Agents cannot send messages to the user (only the orchestrator presents to user)
- Agents cannot modify shared contracts (scoring.md, state-schema.md, etc.)

## 5. Data Flow Summary

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
                                                ↘ DOCS inline
    SHIP agent → stage_8_notes → orchestrator → LEARN dispatch prompt
                                              ↘ Linear: PR link, status
    FEEDBACK agent → classification → orchestrator → route to PLAN or IMPLEMENT
    LEARN (retro) → stage_9_notes → pipeline-log.md (PREEMPT hit counts)
                                  → pipeline-config.md (auto-tuning)
    LEARN (recap) → recap report ↘ Linear: summary comment

All data flows through the orchestrator. Agents are isolated. The orchestrator curates what each agent receives.

## 6. PREEMPT Item Tracking

During implementation, agents that receive PREEMPT items in their dispatch prompt must report usage in stage notes:

    PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
    PREEMPT_SKIPPED: {item-id} — not applicable ({reason})

The orchestrator reads these markers from stage notes and populates `state.json.preempt_items_status`:
- `{ "applied": true, "false_positive": false }` — item was used and relevant
- `{ "applied": false, "false_positive": true }` — item was loaded but inapplicable

The retrospective agent reads `preempt_items_status` and:
1. Increments `hit_count` in `pipeline-log.md` for applied items
2. Records false positives for confidence decay acceleration (false positive = 3 unused runs toward decay)
3. Logs: "PREEMPT effectiveness: {applied}/{total} items used, {false_positives} false positives"

### Retry Handling

If a task fails and is retried (within `max_fix_loops`), the implementer may write PREEMPT markers for both the failed and successful attempts. When the orchestrator reads stage notes to populate `preempt_items_status`:

- Use markers from the **last attempt only** (the successful one, or the final failed attempt if all attempts failed)
- Earlier attempt markers are superseded — do not double-count
- If the same item is marked `PREEMPT_APPLIED` in attempt 1 and `PREEMPT_SKIPPED` in attempt 2, use the attempt 2 status
