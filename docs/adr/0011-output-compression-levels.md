# ADR-0011: Output compression levels

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Agent outputs accumulated prose that the orchestrator (and user) didn't need:
greetings, restating the task, verbose reasoning traces. Token budgets grew;
user-facing output became harder to skim. We wanted a single knob to trade
verbosity for tokens, per stage.

## Decision

Four compression levels: `verbose` | `standard` (default) | `terse` | `minimal`,
set per stage via `output_compression.*`. Expected reduction: 20–65% against
`verbose` baseline. Caveman input compression (S01) is a separate, orthogonal
input-side knob: `lite` | `full` | `ultra` | `off`.

## Consequences

- **Positive:** Clear contract for agent prose density; measurable savings; users can dial up verbosity when debugging.
- **Negative:** Four levels is more than some teams want; per-stage override adds config surface.
- **Neutral:** Benchmarks live in `shared/caveman-benchmark.sh`.

## Alternatives Considered

- **Option A — Single global terseness flag:** Rejected — some stages (e.g. planning) benefit from verbose; others (e.g. post-run) shouldn't.
- **Option B — Let the model self-adjust:** Rejected — inconsistent across runs; hard to benchmark.

## References

- `shared/output-compression.md`
- `shared/input-compression.md`
