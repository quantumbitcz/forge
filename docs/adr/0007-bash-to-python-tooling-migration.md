# ADR-0007: Bash-to-Python tooling migration

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Forge ships with a growing body of shell scripts (`shared/forge-*.sh`, hooks,
graph builders). Shell is fine for process glue, but as the plugin has grown it
has absorbed real logic (JSON manipulation, cache invalidation, check engine).
Bash is hard to test, hard to type-check, and cross-platform behavior (macOS
Bash 3 vs 4, Git Bash path translation) is a recurring source of bugs.

## Decision

New non-trivial tooling is written in Python 3.10+. Shell glue remains for hook
entry points and trivial wrappers. A pinned `requirements.txt` (introduced in
Phase 02) is the canonical dependency set. Existing shell scripts migrate to
Python only when they need non-trivial changes — no wholesale rewrite.

## Consequences

- **Positive:** Unit-testable modules; type hints; richer stdlib (YAML, JSON Schema, pathlib); consistent behavior across macOS/Linux/Windows-WSL.
- **Negative:** Python 3.10+ becomes a soft dependency for any feature needing the new tooling. Users without Python see degraded functionality for those features (e.g. learnings-index freshness check is CI-only).
- **Neutral:** Bilingual codebase — contributors need both; docs must flag which is which.

## Alternatives Considered

- **Option A — Stay pure bash:** Rejected — see context.
- **Option B — Rewrite everything in Python now:** Rejected — too large a blast radius; incremental migration is safer.

## References

- `requirements.txt`
- `scripts/gen-learnings-index.py`
- ADR-0008 (no back-compat makes incremental migration cheaper)
