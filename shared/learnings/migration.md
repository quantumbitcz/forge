---
schema_version: 2
items:
---
# Migration Learnings

Per-project cumulative learnings for `fg-506-migration-verifier` and `fg-160-migration-planner`.

## Discovered patterns

(auto-populated by `fg-700-retrospective`)

## Calibration

| Rule | Default cap | Override path |
|---|---|---|
| `MIGRATION-ROLLBACK-MISSING` | CRITICAL | Lower to WARNING for forward-only projects via `.forge/migration-policy.json` |
| `MIGRATION-DATA-LOSS` | CRITICAL | Cannot be lowered — data loss is always CRITICAL |
| `MIGRATION-NOT-IDEMPOTENT` | CRITICAL | Lower to WARNING only in greenfield (no production snapshot) |
