---
mode: standard
convergence:
  max_iterations: ~    # Uses forge-config.md value (default 15)
  plateau_threshold: ~  # Uses forge-config.md value (default 3)
  plateau_patience: ~   # Uses forge-config.md value (default 3)
  max_quality_cycles: ~ # Uses forge-config.md value (default 3)
stages: {}
---

## Standard Mode

Default pipeline behavior. No stage overrides. All stages run with their default agents and configurations. Convergence parameters use forge-config.md values (no mode-level overrides).

Output compression uses the default per-stage levels from `shared/output-compression.md` (no mode-level overrides).
