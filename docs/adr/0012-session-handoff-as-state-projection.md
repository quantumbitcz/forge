# ADR-0012: Session handoff as a thin state projection, not an LLM summarisation

- **Status:** Accepted
- **Date:** 2026-04-21
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Long Claude Code sessions accumulate context from forge pipeline activity,
multi-stage reports, AskUserQuestion dialogs, and accumulated tool output. When
context approaches the model window limit, users need a way to transfer state
into a fresh session without losing progress. Existing `compact_check.py` emits
a stderr hint at 180K tokens and `context_guard.py` triggers F08 inner-loop
condensation during convergence — but neither addresses the *user's outer
Claude Code session* running out of context.

Industry convention (softaworks, LangGraph, Cursor) centres on structured
markdown handoff files. The design choice that sets forge apart: handoff
generation is a *projection over existing state* — not a new LLM summarisation
pass.

## Decision

Handoff generation is **deterministic Python**, not an LLM subagent.

- **Frontmatter** is rendered from `state.json` + `parse_frontmatter`
  round-trip discipline.
- **Body sections** are projections from F08 retention tags
  (`active_findings`, `acceptance_criteria`, `user_decisions`,
  `convergence_trajectory`, `test_status`, `active_errors`) and
  `decisions.jsonl`.
- **Resume prompt block** is a fixed template appended verbatim.
- **No LLM call**, no new subagent in `agents/`, zero token cost per write.

## Consequences

- **Positive:**
  - Sub-second, zero-token, reproducible output. Same inputs → same bytes.
  - No hallucination risk. Handoff content cannot claim facts that aren't in
    state.
  - Deterministic output unlocks FTS5 indexing, staleness checks, chain
    rotation, and cross-run search without worrying about non-deterministic
    content.
  - Writer can fire from a PostToolUse hook (sub-second budget).
  - If we later want richer prose, we can layer an optional enrichment agent
    without touching the core.
- **Negative:**
  - Body section prose is mechanical — terse, template-like — rather than
    freshly-summarised narrative. This is a quality/cost tradeoff; F08 already
    did the summarisation work upstream, so we reuse rather than redo.
  - Any new section type requires code change (not just a prompt tweak).
  - Autonomy is limited to what the retention tags capture; sections that
    would benefit from synthesis (e.g., "what's surprising") are not possible
    without an LLM pass.
- **Neutral:** If we ever need non-deterministic enrichment, it can be layered
  as an optional post-processing step without disturbing the deterministic
  core.

## Alternatives Considered

- **Option A — LLM subagent (`fg-xyz-handoff-writer`):** Rejected —
  non-deterministic, costs tokens on every write, cannot run from a
  PostToolUse hook sub-second budget. The richness isn't worth the complexity
  for a forge run state transfer.
- **Option B — Stderr hint + manual capture:** Rejected — users won't
  consistently do it; half-captured handoffs break resume.
- **Option C — Delegate entirely to `/compact`:** Rejected — compact is lossy
  summarisation controlled by the model, not steered by pipeline state. Can't
  carry run_id, checkpoint SHA, or chain lineage.

## References

- Spec: `docs/superpowers/specs/2026-04-21-session-handoff-design.md`
  (will be removed at feature ship)
- Modules: `hooks/_py/handoff/` (writer, resumer, triggers, milestones,
  alerts, search, auto_memory)
- Skill: `/forge-admin handoff`
- Config: `handoff.*` in `shared/preflight-constraints.md`
- Related ADR: `0008-no-backwards-compatibility-stance.md` (informs schema
  v1.0 rejection of v2.0)
