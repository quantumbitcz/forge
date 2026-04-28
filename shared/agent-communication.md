# Agent Communication Protocols

> **Agent model, UI tiers, dispatch, registry:** see [`agents.md`](agents.md).
> This document specifies the *runtime protocols* agents use to exchange
> information: stage notes, findings dedup, conflict resolution, PREEMPT
> tracking, and structured output.

Agents in the pipeline do not communicate directly. All inter-agent data flows through the orchestrator via defined mechanisms.

<a id="stage-notes"></a>
## Stage Notes (async, persistent)

Each stage writes `.forge/stage_N_notes_{storyId}.md`. Downstream stages can read upstream notes via the orchestrator's dispatch prompt.

- Written by: the agent completing a stage
- Read by: the orchestrator (always), downstream agents (when orchestrator includes relevant context in dispatch)
- Format: markdown with structured sections (findings, decisions, metrics)
- Lifetime: per-run (cleared on `/forge-admin recover reset`)

<a id="stage-notes-contents"></a>
### What goes in stage notes
- Decisions made and reasoning (for downstream agents and recap)
- Findings with file:line references (for quality gate and implementer)
- Metrics (time, files, test counts — for retrospective)
- Errors encountered and recovery actions taken

<a id="stage-notes-exclusions"></a>
### What does NOT go in stage notes
- Full file contents (reference by path instead)
- Raw tool output (extract structured data)
- Conversation history or reasoning traces

<a id="stage-notes-size-budget"></a>
### Stage Notes Size Budget

Stage notes should stay under **2,000 tokens** to prevent context cascading in downstream dispatch prompts. If a stage produces more content:

1. **Findings:** Deduplicate by `(component, file, line, category)` before writing. Include total count and severity breakdown. Include **all** previous batch findings with domain affinity for the next reviewer (severity-weighted, no fixed cap) so cross-batch dedup is exact, not lossy. If counts exceed 50, compress to `(category, file, severity, count)` tuples — preserving every entry while shrinking the payload.
2. **File listings:** Reference by directory pattern (e.g., `src/domain/**`) instead of listing every file.
3. **Metrics:** Use a compact table format, not prose.

The retrospective (Stage 9) reads all stage notes (0-8). With the 2K cap, 9 stage notes total ~18K tokens — within dispatch limits. Feedback files are read separately (not included in orchestrator dispatch). With many feedback entries (>20), the retrospective reads only `feedback/summary.md` (the consolidated file).

<a id="findings-store-protocol"></a>
## Findings Store Protocol (within REVIEW stage)

During REVIEW, qualifying reviewers fan out in parallel and append findings to per-reviewer JSONL files under `.forge/runs/<run_id>/findings/`. Dedup is read-time, not write-time: each reviewer reads peer files before emitting, skipping duplicates via `seen_by` annotations. The aggregator (fg-400) reduces the store to a canonical finding set.

**Authoritative contract:** `shared/findings-store.md` (path convention, line schema, read-before-write protocol, concurrency, annotation inheritance, reducer contract).

**Key rules (summary):**

- Each reviewer appends to its own file — no write contention.
- Before emitting, read all peer JSONL files and compute `seen_keys`.
- Duplicate found → append a `seen_by` annotation to your OWN file; skip full emission.
- Duplicate race (two reviewers emit simultaneously) → aggregator applies tiebreaker (severity → confidence → ASCII reviewer).
- Schema: `shared/checks/findings-schema.json`. Supports Phase 7 fg-540 writer (nullable file/line, INTENT categories require ac_id).

The aggregator collapses all `fg-41*.jsonl` lines during §7 dedup, producing a single canonical list for scoring. Dispatch prompts contain no inter-batch finding hints — dedup is read-time inside each reviewer.

<a id="conflict-resolution"></a>
### Conflict Reporting Protocol

When a review agent produces a finding that contradicts another agent's known output (observed via the findings store or aggregator-mediated cross-agent references), it MUST report the conflict explicitly:

```
CONFLICT: {category} at {file}:{line}
  Agent A: {finding_A_description} (severity: {sev_A})
  Agent B: {finding_B_description} (severity: {sev_B})
```

Resolution priority lives in `shared/checks/category-registry.json` (`priority` field). Lower number = higher priority; unlisted categories default to 5 (CONV-level). Bands:

1. **Security** (SEC-*) — priority 1
2. **Architecture** (ARCH-*, STRUCT-*) — priority 2
3. **Code Quality** (QUAL-*, TEST-*, CONTRACT-*) — priority 3
4. **Performance** (PERF-*, FE-PERF-*, INFRA-*) — priority 4
5. **Convention** (CONV-*, DOC-*, A11Y-*, DESIGN-*) — priority 5
6. **Style** (APPROACH-*, SCOUT-*) — priority 6

At equal priority, higher severity wins; at equal priority AND severity, both are escalated via the quality gate report with a CONFLICT annotation. Agents must NOT self-resolve — report and let the quality gate arbitrate.

<a id="deliberation-protocol"></a>
### Deliberation Protocol (v1.18+)

When `quality_gate.deliberation` is enabled, the quality gate may re-dispatch reviewers for a deliberation round on conflicting findings. This extends — not replaces — the conflict reporting protocol.

**Flow:** (1) Quality gate detects conflict; (2) if deliberation enabled AND conflict ≥ WARNING, re-dispatch both agents with the deliberation prompt (format in `shared/agent-defaults.md` §Deliberation Response Format); (3) agents respond MAINTAIN/REVISE/WITHDRAW; (4) quality gate applies results before scoring.

**Constraints:** max 1 deliberation round (no recursive re-dispatch); only for ≥ WARNING conflicts (INFO-vs-INFO uses priority ordering); 60-second timeout per agent (configurable: `quality_gate.deliberation_timeout`); at most 2 sub-agent dispatches per conflict cluster; reviewers are read-only in deliberation mode.

Agents still report conflicts in the same format — deliberation is an additional resolution step the quality gate performs after collection.

<a id="state-json"></a>
## State.json (orchestrator-managed)

The orchestrator is the sole writer of state.json. Agents read it (for integrations, conventions_hash, etc.) but never write to it.

<a id="agent-limits"></a>
## What Agents CANNOT Do

- Agents cannot dispatch agents in other stages (all inter-stage data flows through the orchestrator via stage notes). However, coordinator agents (quality gate, test gate, PR builder, planner, scaffolder) may dispatch sub-agents within their own stage for specialized analysis or feedback capture.
- Agents cannot write to state.json (only the orchestrator writes state)
- Agents cannot read other agents' in-progress work (isolation enforced by separate dispatch)
- Agents cannot send messages to the user (only the orchestrator presents to user)
- Agents cannot modify shared contracts (scoring.md, state-schema.md, etc.)
- Agents cannot undo, revert, or overwrite work produced by another agent — if an agent detects a conflict with another agent's output, it MUST report the conflict in stage notes and let the orchestrator decide the resolution strategy.

<a id="data-flow"></a>
## Data Flow Summary

    EXPLORE → stage_1_notes → orchestrator → PLAN dispatch
    PLAN → stage_2_notes → orchestrator → VALIDATE dispatch  ↘ Linear: Epic/Stories/Tasks
    VALIDATE → stage_3_notes → orchestrator → IMPLEMENT dispatch  ↘ Linear: verdict comment
    IMPLEMENT → stage_4_notes → orchestrator → state.json (preempt_items_status)
                                             → checkpoint.json (preempt_items_used)
    VERIFY (test gate) → stage_5_notes → orchestrator → REVIEW dispatch
    REVIEW fan-out → all qualifying fg-41* reviewers in parallel
                 → each appends to .forge/runs/<run_id>/findings/<reviewer>.jsonl
                 → aggregator (fg-400) reduces via dedup_key + seen_by merging
    REVIEW final → stage_6_notes → orchestrator → state.json (score_history)
    DOCS → stage_7_notes → orchestrator → state.json (documentation)
         ← changed files, quality verdict, plan notes, stage_0_docs_discovery.md
    SHIP → stage_8_notes → orchestrator → LEARN dispatch  ↘ Linear: PR link, status
    FEEDBACK → classification → orchestrator → route to PLAN or IMPLEMENT
    LEARN (retro) → stage_final_notes → forge-log.md (PREEMPT hit counts)
                                      → forge-config.md (auto-tuning)
    LEARN (post-run) → recap ↘ Linear: summary comment

All data flows through the orchestrator. Agents are isolated. The orchestrator curates what each agent receives.

**Checkpoint persistence:** The orchestrator writes `checkpoint-{storyId}.json` after each Stage 4 task completion for resume. Checkpoints are orchestrator-internal — agents do not read or write them directly.

<a id="sprint-communication"></a>
## Sprint ↔ Feature Communication

The sprint orchestrator (fg-090) communicates with feature orchestrators (fg-100) through:

1. **Sprint state file:** `.forge/sprint-state.json` — read by all, written only by fg-090
2. **Per-run state files:** `.forge/runs/{feature-id}/state.json` — written by each fg-100 instance
3. **Agent dispatch:** fg-090 dispatches fg-100 instances as sub-agents

Feature orchestrators do NOT write to `sprint-state.json`. The sprint orchestrator polls per-run state files and updates sprint state.

<a id="wait-mechanism"></a>
### Wait Mechanism

When `--wait-for <project_id>` is set, the feature orchestrator:
1. Reads `sprint-state.json` for the dependency project's status
2. Blocks at PREFLIGHT until dependency status >= `verifying`
3. Poll interval: 30 seconds
4. Timeout: `cross_repo.timeout_minutes` (default 30)

<a id="a2a-cross-repo"></a>
### A2A Cross-Repo Communication

When a target repo exposes `.forge/agent-card.json`, the cross-repo coordinator (fg-103) switches from file-based polling to the A2A (Agent-to-Agent) protocol for inter-repo coordination.

**Activation:** `.forge/agent-card.json` exists in the target repo root, declares supported capabilities (streaming, pushNotifications), and the coordinator has filesystem access.

**Flow:** fg-103 discovers the agent card during `setup-worktrees` or `coordinate-implementation`; tasks are created via A2A `tasks/send` instead of dispatching a local fg-100; state sync uses A2A task state transitions (`working`/`completed`/`failed`) rather than polling `sprint-state.json`; remote artifacts (PR URLs, test results) are written back to `sprint-state.json`.

**Fallback:** If the agent card is missing or unreadable, fg-103 falls back to file-based polling of per-run `state.json` files.

See `shared/a2a-protocol.md` for the full message format, agent card schema, and error handling.

<a id="preempt-tracking"></a>
## PREEMPT Item Tracking

During implementation, agents that receive PREEMPT items in their dispatch prompt must report usage in stage notes. Producers: `fg-300-implementer` (primary), `fg-310-scaffolder` (scaffold-pattern items), and `fg-320-frontend-polisher` (frontend-pattern items). When multiple agents report on the same item, the orchestrator uses the marker from the **last agent to complete**.

<a id="preempt-marker-format"></a>
### PREEMPT Marker Format

Markers are written to stage notes under `## Attempt N` headers.

**Format:**
```
PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
PREEMPT_SKIPPED: {item-id} — not applicable ({reason})
```

**Parsing regex:** `^PREEMPT_(APPLIED|SKIPPED): (\S+) — (.+)$`

**Rules:** Only markers from the **last attempt** in a stage are authoritative. Earlier attempt markers are superseded. Orchestrator counts APPLIED/SKIPPED per item-id for decay tracking.

The orchestrator populates `state.json.preempt_items_status`:
- `{ "applied": true, "false_positive": false }` — item was used and relevant
- `{ "applied": false, "false_positive": true }` — item was loaded but inapplicable

The retrospective reads `preempt_items_status` and (1) increments `hit_count` in `forge-log.md` for applied items, (2) records false positives for confidence decay (`base_confidence *= 0.80`, resets elapsed-time clock per `shared/learnings/decay.md`), and (3) logs: "PREEMPT effectiveness: {applied}/{total} items used, {false_positives} false positives".

<a id="preempt-retry"></a>
### Retry Handling

If a task fails and is retried (within `max_fix_loops`), the implementer may write PREEMPT markers for both failed and successful attempts.

**Implementer convention:** Write markers under attempt headers (e.g., `## Attempt 1 (ISO-8601)` then `PREEMPT_APPLIED: ...` / `PREEMPT_SKIPPED: ...`, then `## Attempt 2` with updated markers).

**Orchestrator convention:** Parse attempt sections by header (`## Attempt N`). Use markers from the **last attempt only** (successful one, or final failed attempt if all failed). Earlier markers are superseded — do not double-count. If the same item is APPLIED in attempt 1 and SKIPPED in attempt 2, use attempt 2's status.

<a id="preempt-decay"></a>
### PREEMPT Confidence Decay

Items decay toward archival on a time-aware Ebbinghaus exponential curve. The canonical contract — formula, per-type half-lives, thresholds, reinforcement, and false-positive penalty — lives in `shared/learnings/decay.md`. Quick summary:

- `confidence(t) = base_confidence × 2^(-Δt_days / half_life_days)` where `Δt_days = (now - last_success_at) / 86 400` clamped to `[0, 365]`.
- Half-lives: auto-discovered 14d, cross-project 30d, canonical 90d.
- Thresholds: `c ≥ 0.75` HIGH, `0.50 ≤ c < 0.75` MEDIUM, `0.30 ≤ c < 0.50` LOW, `c < 0.30` ARCHIVED.
- Success: `base_confidence = min(0.95, base + 0.05)`, `last_success_at = now`.
- False positive (`PREEMPT_SKIPPED` with reason marking inapplicability): `base_confidence *= 0.80`, `last_success_at = now`, `last_false_positive_at = now`.

No `decay_score` counter and no "N unused runs" rule — time elapses "for free" between runs and the loader recomputes effective confidence on read. PREFLIGHT performs lazy reads (`memory_decay.effective_confidence`); LEARN (`fg-700-retrospective`) is the authoritative writer that applies success/false-positive transforms and archives items whose computed tier is ARCHIVED.

<a id="preempt-decay-rules"></a>
### PREEMPT Decay Counting Rules

Three observable states per pipeline run:

| State | Effect on `base_confidence` / timestamps |
|-------|------------------------------------------|
| Loaded + checked + finding reported (`PREEMPT_APPLIED`) | `base += 0.05` (capped at 0.95), `last_success_at = now` |
| Loaded + checked + no match in changeset | No state change (time-based decay handles staleness) |
| Loaded + `PREEMPT_SKIPPED` with inapplicability reason | `base *= 0.80`, `last_false_positive_at = now`, `last_success_at = now` |
| Not loaded (agent context too small) | No state change |

**Detection mechanism:** The orchestrator tracks which PREEMPT items were included in each agent dispatch via `preempt_items_loaded[]` in stage notes. Items in `preempt_items_loaded` but missing from `preempt_items_status` are "loaded but not reported" and trigger no write.

**Source-derived defaults** (see `shared/learnings/decay.md` §2 for full type resolution):
- `source: auto-discovered` → 14-day half-life, starts at `base_confidence = 0.75` (MEDIUM on day 0).
- `source: user-confirmed` or `state: ACTIVE` → canonical, 90-day half-life.
- Path under `shared/learnings/` → cross-project, 30-day half-life.
- Otherwise → cross-project (default).

ARCHIVED items are excluded from PREEMPT loading at PREFLIGHT but remain in `forge-log.md` for historical reference.

**Retrospective update logic** (executed by `fg-700-retrospective` per item in `preempt_items_status`):
1. `applied: true` → `apply_success(item, now)` (additive 0.05, capped 0.95).
2. `applied: false, false_positive: true` → `apply_false_positive(item, now)` (`base *= 0.80`, stamp both `last_success_at` and `last_false_positive_at`).
3. After per-item updates, `effective_confidence` + `tier` are recomputed and the item is archived if tier = ARCHIVED.

See `shared/learnings/decay.md` for worked examples covering applied/loaded-no-match/not-loaded scenarios.

---

## Learning Markers (Phase 4)

Subagents may emit these markers in stage notes (free-form line prefix):

| Marker                                   | Kind         | Effect on retrospective           |
|------------------------------------------|--------------|-----------------------------------|
| `LEARNING_APPLIED: <id>`                 | reinforcement| `apply_success(item, now)`        |
| `PREEMPT_APPLIED: <id>`                  | reinforcement| identical to the above            |
| `LEARNING_FP: <id> reason=<text>`        | penalty      | `apply_false_positive(item, now)` |
| `PREEMPT_SKIPPED: <id> reason=<text>`    | penalty      | identical to the above            |
| `LEARNING_VINDICATED: <id> reason=<text>`| restoration  | `apply_vindication(item, now)`    |

A reviewer raising a CRITICAL in the same domain as a shown learning is
**not** a false-positive signal (spec Phase 4 §3.1). The retrospective
responds only to explicit markers.

Agent-to-role mapping (authoritative in `hooks/_py/agent_role_map.py`):

```
planner               → fg-200-planner
implementer           → fg-300-implementer
quality_gate          → fg-400-quality-gate
reviewer.code         → fg-410-code-reviewer
reviewer.security     → fg-411-security-reviewer
reviewer.architecture → fg-412-architecture-reviewer
reviewer.frontend     → fg-413-frontend-reviewer
reviewer.license      → fg-414-license-reviewer
reviewer.performance  → fg-416-performance-reviewer
reviewer.dependency   → fg-417-dependency-reviewer
reviewer.docs         → fg-418-docs-consistency-reviewer
reviewer.infra        → fg-419-infra-deploy-reviewer
```

Unknown agent → orchestrator skips injection (empty selector filter).

<a id="structured-output"></a>
## Structured Output Standard

Coordinator agents (fg-400-quality-gate, fg-500-test-gate, fg-700-retrospective) embed machine-readable JSON inside their Markdown output, wrapped in an HTML comment so it is invisible when rendered but trivially extractable by consumers (orchestrator, retrospective, post-run agent, `/forge-ask insights`).

<a id="structured-output-format"></a>
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

The block MUST appear at the end of the coordinator's Markdown output so the human-readable sections remain complete even if the structured block is stripped.

<a id="structured-output-versioning"></a>
### Schema Versioning

The `schema` field (`coordinator-output/v1`) enables forward compatibility. Consumers MUST check the schema version before parsing; unknown schema versions trigger fallback to Markdown parsing.

<a id="structured-output-extraction"></a>
### Extraction Algorithm

Consumers extract the structured block using a regex with DOTALL (single-line) mode:

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

<a id="structured-output-compat"></a>
### Backward Compatibility

If the `FORGE_STRUCTURED_OUTPUT` block is missing from a coordinator's output, consumers MUST fall back to their existing Markdown parsing logic. This ensures the pipeline continues to function during rollout and when agents truncate output due to token limits. Consumers SHOULD log `WARNING: {agent-id} did not include structured output, using Markdown fallback` — making fallback events observable for monitoring and migration tracking.

<a id="structured-output-producers"></a>
### Producing Agents

| Agent | Schema Fields | Consumers |
|-------|--------------|-----------|
| `fg-400-quality-gate` | verdict, score, findings_summary, batches, dedup_stats, cycle_info, reviewer_agreement, coverage_gaps | fg-100 (convergence), fg-700 (trends), fg-710 (timeline) |
| `fg-500-test-gate` | phase_a, phase_b, mutation_testing, verdict | fg-100 (convergence), fg-700 (trends) |
| `fg-700-retrospective` | run_summary, learnings, config_changes, agent_effectiveness, trend_comparison, approach_accumulations | fg-710 (timeline), `/forge-ask insights` |

<a id="structured-output-tokens"></a>
### Token Budget Impact

The structured block adds approximately 500-2000 tokens per coordinator invocation, within the stage notes budget (2,000 tokens/stage). If the combined Markdown + JSON exceeds the budget, the coordinator MUST compress Markdown prose (shorter descriptions, fewer examples) rather than omit the structured block — downstream consumers depend on it.

## risk_tags Contract (Phase 7 F36)

Producer: `fg-200-planner` emits `task.risk_tags: string[]` in the structured
plan output during §3.4 per-task planning. Closed vocabulary:
`{"high", "data-mutation", "auth", "payment", "concurrency", "migration"}`.

Mode overlays may extend the vocabulary — the **bugfix** overlay adds
`"bugfix"`. Extensions must be declared in the overlay's `stages.plan` block
or this section; unknown tags in plan output emit a WARNING at Stage 3 VALIDATE.

Consumer: `fg-100-orchestrator` reads `task.risk_tags` at Stage 4 IMPLEMENT
before dispatching `fg-300-implementer`. The voting gate (see
`shared/intent-verification.md` § Voting Gate) triggers N=2 dispatch when:

1. `impl_voting.enabled == true`, AND
2. Budget permits: `state.cost.remaining_usd / state.cost.ceiling_usd >=
   impl_voting.skip_if_budget_remaining_below_pct / 100`, AND
3. At least one of:
   - `state.confidence.effective_confidence <
     impl_voting.trigger_on_confidence_below`, OR
   - `any(t in task.risk_tags for t in impl_voting.trigger_on_risk_tags)`, OR
   - `file_has_recent_regression(task.files,
     impl_voting.trigger_on_regression_history_days)` via
     `.forge/run-history.db`.

No other agent consumes `task.risk_tags`. Retrospective aggregates them via
`fg-100-orchestrator`'s `impl_vote_history[].trigger` field, not via the raw
tags.
