---
mode: migration
convergence:
  max_iterations: 15      # Migrations may need many attempts
  plateau_threshold: 3     # Standard sensitivity
  plateau_patience: 3      # Standard patience
  max_quality_cycles: 3    # Standard review depth
stages:
  plan:
    agent: fg-160-migration-planner
  implement:
    states: [MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY]
---

## Migration Mode

Uses migration planner at Stage 2. Implementation stage cycles through migration-specific states.

Output compression uses the default per-stage levels (no mode-level overrides).
