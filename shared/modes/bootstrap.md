---
mode: bootstrap
convergence:
  max_iterations: 5       # Scaffolding rarely needs many iterations
  plateau_threshold: 5     # Generous -- scaffolding scores may fluctuate
  plateau_patience: 1      # No patience -- scaffold works or it doesn't
  max_quality_cycles: 1    # Single review pass for scaffolded code
stages:
  plan:
    agent: fg-050-project-bootstrapper
  validate:
    perspectives: [build_compiles, tests_pass, docker_valid, architecture_matches]
    challenge_brief_required: false
  implement:
    skip: true
  review:
    batch_override:
      batch_1: [fg-412-architecture-reviewer, fg-410-code-reviewer, fg-411-security-reviewer]
    target_score: pass_threshold
---

## Bootstrap Mode

Scaffolds new projects. Uses project bootstrapper at Stage 2. Stage 4 (IMPLEMENT) is skipped (scaffolding done in Stage 2). Reduced validation and review.
