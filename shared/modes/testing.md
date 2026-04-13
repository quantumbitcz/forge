---
mode: testing
convergence:
  max_iterations: 10      # Tests should converge quickly
  plateau_threshold: 3     # Standard sensitivity
  plateau_patience: 2      # Less patience -- test code is simpler
  max_quality_cycles: 2    # Fewer review cycles for test-only changes
stages:
  implement:
    focus: test_files_only
  review:
    batch_override:
      batch_1: [fg-410-code-reviewer]
    target_score: pass_threshold
---

## Testing Mode

Focused on test files. Implementation only modifies test files. Reduced review batch. Target score is pass_threshold.
