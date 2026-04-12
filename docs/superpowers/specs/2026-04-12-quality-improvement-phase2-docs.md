# Phase 2: Documentation Tightening

**Parent:** [Umbrella Spec](./2026-04-12-quality-improvement-umbrella-design.md)
**Priority:** Medium — cross-reference accuracy and spec completeness.
**Approach:** Test-gated where applicable. Prose clarifications have no test but are verified by self-review + agent review.

## Item 2.1: Complete MCP provisioning documentation

**Rationale:** CLAUDE.md lists 7 detected MCPs (Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j). `shared/mcp-provisioning.md` documents 5 (Linear, Playwright, Figma, Excalidraw, Neo4j partially). Slack and Context7 are missing entirely.

**Category:** Documentation completeness.

**Change:** Add two new sections to `shared/mcp-provisioning.md` following the existing pattern:

**Slack section:**
- Tool name prefix: `mcp__claude_ai_Slack__`
- Detection: Check for `mcp__claude_ai_Slack__slack_send_message` tool availability
- Capability when available: Channel messaging, search, canvas operations
- Degradation when unavailable: Skip Slack notifications; Linear/console-based tracking only
- Provisioning: User-configured via Claude AI MCP settings (not auto-installable)

**Context7 section:**
- Tool name prefix: `mcp__plugin_context7_context7__`
- Detection: Check for `mcp__plugin_context7_context7__resolve-library-id` tool availability
- Capability when available: Live documentation lookup for libraries/frameworks, version-aware API references
- Degradation when unavailable: Fall back to training data knowledge + WebSearch; log INFO finding
- Provisioning: Plugin-installed MCP (auto-detected)

**New test:** `tests/contract/mcp-provisioning-completeness.bats`
- Reads MCP list from CLAUDE.md by grepping for the "MCP detection:" line (format: `Detects Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j.`)
- Parsing: extract comma-separated names after "Detects " and before the period, trim whitespace
- For each MCP name, asserts a section header (e.g., `## Linear`, `### Linear`, or `**Linear**` pattern) exists in `shared/mcp-provisioning.md`
- Dynamically discovers MCPs so new additions are automatically caught

## Item 2.2: Clarify convergence plateau exemption

**Rationale:** `shared/convergence-engine.md` line 107 says "The first 2 cycles always count as IMPROVING" and line 157 says "first two cycles are exempt from plateau counting." The algorithm guard in `state-transitions.md` is `phase_iterations >= 2`. These are consistent but the prose creates ambiguity about exactly when plateau detection activates.

**Category:** Prose clarification.

**Change:** In `shared/convergence-engine.md`, add a clarifying note after the existing "first 2 cycles" text:

> **Clarification:** Cycles 1-2 establish a baseline — `plateau_count` remains 0 and convergence state is IMPROVING regardless of the smoothed delta value. Starting from cycle 3 (`phase_iterations >= 2` in state-transitions.md), the smoothed delta is evaluated against `oscillation_tolerance`. If `|smoothed_delta| <= oscillation_tolerance`, `plateau_count` increments. Escalation occurs when `plateau_count >= plateau_patience`.

**New test:** None — prose clarification. Existing `convergence-engine.bats` validates the arithmetic behavior.

## Item 2.3: Add forward pointer in state-schema.md

**Rationale:** `state-transitions.md` row 52 references `evidence_refresh_count` in the state.json evidence object, and `verification-evidence.md` documents the 3-retry cap. But `state-schema.md` (the canonical field reference) does not list this field, making it hard for agents to find initialization and increment rules.

**Category:** Cross-reference completeness.

**Change:** In `shared/state-schema.md`, add to the `evidence` object field list:

```markdown
| `evidence_refresh_count` | int | 0 | Tracks stale-evidence refresh attempts at SHIPPING entry. Capped at 3 before user escalation. See `verification-evidence.md` §Staleness and `state-transitions.md` row 52. |
```

**New test:** `tests/contract/state-schema-field-coverage.bats`
- Scans `state-transitions.md` for field references matching `state.json` paths (e.g., `evidence_refresh_count`, `feedback_loop_count`)
- For each field, asserts it appears in `state-schema.md`
- Catches future field additions to transitions that forget to update the schema

## Item 2.4: Inline `analysis_pass` definition in stage-contract.md

**Rationale:** Stage 5 (VERIFY) in `shared/stage-contract.md` references `analysis_pass` as an exit condition but doesn't define it. Agents must cross-reference `convergence-engine.md` to understand the condition.

**Category:** Prose clarification.

**Change:** In the Stage 5 section of `shared/stage-contract.md`, add inline definition after the `analysis_pass` reference:

> "(where `analysis_pass` = no CRITICAL findings from review agents AND quality gate verdict != FAIL — see `convergence-engine.md` Phase B exit condition)"

**New test:** None — prose clarification within existing stage documentation.

## Item 2.5: Strengthen PREEMPT marker format specification

**Rationale:** `shared/agent-communication.md` lines 175-176 define PREEMPT markers:
```
PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
PREEMPT_SKIPPED: {item-id} — not applicable ({reason})
```
This format exists but is embedded in prose without a dedicated subsection. Agents parsing these markers need a clear, findable specification.

**Category:** Specification formalization.

**Change:** In `shared/agent-communication.md`, promote the PREEMPT marker format to a dedicated subsection:

```markdown
### PREEMPT Marker Format

Markers are written to stage notes under `## Attempt N` headers.

Format:
```
PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
PREEMPT_SKIPPED: {item-id} — not applicable ({reason})
```

Parsing regex: `^PREEMPT_(APPLIED|SKIPPED): (\S+) — (.+)$`

Rules:
- Only markers from the **last attempt** in a stage are authoritative
- Earlier attempt markers are superseded (the fix may have changed applicability)
- Orchestrator counts APPLIED/SKIPPED per item-id for decay tracking
```

**New test:** None — formalization of existing format. PREEMPT decay logic is tested in existing convergence tests.

## Phase 2 Verification Checklist

- [ ] 2 new BATS tests written and failing (red)
- [ ] MCP provisioning sections added (Slack, Context7)
- [ ] Convergence clarification added
- [ ] state-schema.md field added
- [ ] stage-contract.md inline definition added
- [ ] PREEMPT marker subsection created
- [ ] 2 new BATS tests passing (green)
- [ ] All existing tests passing (`./tests/run-all.sh`)
- [ ] `/requesting-code-review` passes
