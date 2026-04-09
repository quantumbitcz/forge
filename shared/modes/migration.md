---
mode: migration
stages:
  plan:
    agent: fg-160-migration-planner
  implement:
    states: [MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY]
---

## Migration Mode

Uses migration planner at Stage 2. Implementation stage cycles through migration-specific states.
