# ADR-0006: 87-category scoring model

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Review findings need a consistent category system so scoring is comparable across
runs, agents, and projects. Early attempts used free-form categories, which made
dedup impossible and score drift routine. The space is large but not unbounded:
architecture, security, performance, testing, conventions, docs, quality, a11y,
deps, infra, AI-generated bug patterns, etc.

## Decision

Review findings use 87 shared categories: 27 wildcard prefixes (e.g. `ARCH-*`,
`SEC-*`) + 60 discrete. Registry: `shared/checks/category-registry.json`. Dedup
key: `(component, file, line, category)`. Scoring formula:
`max(0, 100 − 20×CRITICAL − 5×WARNING − 2×INFO)`. SCOUT-* findings are excluded
from the score (two-point filtering).

## Consequences

- **Positive:** Stable comparison across runs; dedup works; new categories can be added by extending the registry without changing the formula.
- **Negative:** 87 is a lot to browse; the registry file is the source of truth and must be kept in sync with reviewer prompts.
- **Neutral:** Wildcard prefixes allow domain-specific subcategories (e.g. `AI-LOGIC-*`) without registry churn.

## Alternatives Considered

- **Option A — Free-form categories:** Rejected — dedup broke.
- **Option B — Single flat score without categories:** Rejected — can't route findings to the right reviewer batch.

## References

- `shared/scoring.md`
- `shared/checks/category-registry.json`
