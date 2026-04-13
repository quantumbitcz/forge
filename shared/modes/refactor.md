---
mode: refactor
convergence:
  max_iterations: 12      # Slightly fewer than standard
  plateau_threshold: 2     # Tighter sensitivity -- refactors should improve steadily
  plateau_patience: 3      # Standard patience -- refactors may have complex interactions
  max_quality_cycles: 3    # Full review depth -- behavior preservation is critical
stages:
  plan:
    constraints: [preserve_behavior, no_new_features, maintain_tests]
  review:
    mandatory_reviewers: [fg-410-code-reviewer]
---

## Refactor Mode

Preserves existing behavior. Planner uses refactor constraints. Architecture reviewer mandatory in review batch.
