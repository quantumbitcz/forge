---
mode: bugfix
convergence:
  max_iterations: 10      # Bugfixes should converge quickly
  plateau_threshold: 3     # Same sensitivity as standard
  plateau_patience: 2      # Less patience -- fix should be targeted
  max_quality_cycles: 2    # Fewer review cycles for focused changes
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
output_compression:
  verifying: terse
impl_voting:
  trigger_on_risk_tags: ["high", "bugfix"]  # every bugfix task is high-risk
---

## Bugfix Mode

Focused pipeline for bug fixes. Uses bug investigator for exploration and planning. Reduced validation (4 perspectives). Reduced review batch. Target score is pass_threshold, not target_score.

Output compression overrides VERIFYING from `minimal` to `terse` — bugfix verification needs more context than structured data alone.
