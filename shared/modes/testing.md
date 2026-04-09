---
mode: testing
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
