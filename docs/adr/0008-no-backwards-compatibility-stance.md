# ADR-0008: No backwards compatibility stance

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Forge is in active pre-1.0 evolution (v3.0.0 but with frequent structural
changes). Historically we kept file paths stable, added deprecation layers, and
shipped aliases. The cost: every refactor carried legacy baggage, rules had
escape hatches, and the code base grew faster than its clarity did.

## Decision

We do not carry backwards compatibility across phases. Deleted files stay
deleted. Renamed flags land with the new name only. Consumers track `master` or
pin a version; there is no long-lived deprecation window. CI is the enforcement
mechanism for sweeps, not deprecation shims. Phase 06 is the canonical example:
three agent docs are merged and the originals are deleted in the same PR.

## Consequences

- **Positive:** Refactors are cheap; no alias bloat; anchors and paths describe today, not history.
- **Negative:** External bookmarks, forks, and copy-pasted snippets break on each phase. Users pinning a version is the mitigation.
- **Neutral:** ADRs and `CHANGELOG.md` become the memory of past decisions, since files themselves don't carry transitional state.

## Alternatives Considered

- **Option A — 1-release deprecation cycle:** Rejected — slowed refactor cadence and accumulated alias files.
- **Option B — SemVer breaking-change markers only:** Rejected — version bumps were not disciplined enough to rely on.

## References

- `CONTRIBUTING.md`
