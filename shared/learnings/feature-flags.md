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
