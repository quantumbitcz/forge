---
mode: bugfix
stages:
  explore:
    agent: fg-020-bug-investigator
    prompt_suffix: "Execute Phase 1 — INVESTIGATE"
  plan:
    agent: fg-020-bug-investigator
    prompt_suffix: "Execute Phase 2 — REPRODUCE"
  validate:
    perspectives: [root_cause_validity, fix_scope, regression_risk, test_coverage]
    max_retries: 1
  review:
    batch_override:
      batch_1: [fg-412-architecture-reviewer, fg-410-code-reviewer, fg-411-security-reviewer]
    conditional:
      - agent: fg-413-frontend-reviewer
        condition: frontend_files_in_diff
    target_score: pass_threshold
  ship:
    target_score: pass_threshold
---

## Bugfix Mode

Focused pipeline for bug fixes. Uses bug investigator for exploration and planning. Reduced validation (4 perspectives). Reduced review batch. Target score is pass_threshold, not target_score.
