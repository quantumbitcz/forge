# ADR-0005: Composition precedence ordering

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Agents load convention files from multiple layers (variant, framework binding,
framework, language, code-quality, generic layer, testing). When two layers
disagree — e.g. a framework says `@Transactional` at service layer and a variant
says at repository layer — the agent needs an unambiguous rule for which wins.

## Decision

Composition follows the precedence **variant > framework-binding > framework >
language > code-quality > generic-layer > testing**. "Most specific wins." The
algorithm is specified in `shared/composition.md`. Soft cap: 12 convention files
per component.

## Consequences

- **Positive:** Every conflict has a rule; no per-case arbitration; modules can override upstream defaults without touching the upstream file.
- **Negative:** A new contributor needs to internalize the order before editing conventions; mistakes in which file to put a rule in can invert behavior.
- **Neutral:** Binding layers (e.g. `frameworks/spring/persistence/`) exist specifically to slot between framework and language; they cost one more directory but repay it in clarity.

## Alternatives Considered

- **Option A — Flat "last-write wins":** Rejected — agents load in parallel, order is undefined.
- **Option B — Explicit per-rule priority field:** Rejected — verbose, and 95% of cases are cleanly resolved by layer ordering alone.

## References

- `shared/composition.md`
- `modules/frameworks/*/conventions.md`
