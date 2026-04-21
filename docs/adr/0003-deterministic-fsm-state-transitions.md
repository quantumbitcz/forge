# ADR-0003: Deterministic FSM for state transitions

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Early versions of the pipeline let the orchestrator LLM decide stage transitions
in prose ("you should now move to IMPLEMENT"). This produced non-determinism:
the same inputs routed differently across runs, recovery was hard to reason about,
and regression tests could not pin behavior. Meanwhile, the *content* of each
stage genuinely benefits from LLM judgment (what to implement, what to review).

## Decision

Pipeline state transitions follow a formal transition table in
`shared/state-transitions.md`, executed by a shell FSM (`shared/forge-state.sh`,
57+ transitions). LLM judgment is reserved for stage *content* — review,
implementation, architecture — and NOT for deciding which stage comes next.
Decisions are logged to `.forge/decisions.jsonl`. Recovery uses circuit breakers
with deterministic thresholds.

## Consequences

- **Positive:** Reproducible runs; unit-testable transitions (`tests/unit/state-transitions.bats`); simpler recovery reasoning; auditable decision log.
- **Negative:** Adding a new stage requires editing the transition table and FSM script; the abstraction has a learning curve.
- **Neutral:** Token cost of transition logic moves from model calls to shell execution (cheaper but less flexible).

## Alternatives Considered

- **Option A — LLM decides transitions with structured output:** Rejected because even with JSON schemas, LLMs occasionally skip stages or loop; tests failed to pin behavior.
- **Option B — Python-backed state machine:** Deferred. Python tooling has since arrived and future sweeps may migrate `forge-state.sh` there, but that is a refactor, not a new decision.

## References

- `shared/state-transitions.md`
- `shared/forge-state.sh`
- `shared/convergence-engine.md`
