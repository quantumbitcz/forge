---
mode: performance
convergence:
  max_iterations: 12      # Performance changes may need tuning
  plateau_threshold: 3     # Standard sensitivity
  plateau_patience: 3      # Standard patience
  max_quality_cycles: 4    # Extra review cycles -- performance review is measurement-heavy
stages:
  explore:
    include_profiling: true
  review:
    mandatory_reviewers: [fg-416-performance-reviewer]
output_compression:
  verifying: terse
---

## Performance Mode

Includes profiling/benchmarking context in exploration. Performance reviewer mandatory in review batch.

Output compression overrides VERIFYING from `minimal` to `terse` — performance verification benefits from more detailed output for benchmark analysis.
