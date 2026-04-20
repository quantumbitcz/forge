---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Feature Flags — Learnings

Cross-cutting learnings for feature flag lifecycle management.

## Patterns

- Flags should have owners and expiration dates to prevent staleness
- Dual-path testing (flag on + flag off) required for critical features
- Flag cleanup after rollout completion prevents technical debt accumulation

## Common Issues

- Stale flags left in code after full rollout create confusion
- Missing fallback values cause crashes when flag service is unreachable
- Hardcoded flag values bypass the flag management system

## Evolution

Items below evolve via retrospective agent feedback loops.
