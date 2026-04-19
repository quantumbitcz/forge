# Pipeline Configuration

Tunable parameters read by the orchestrator at the start of each run.
Updated by the retrospective agent based on run metrics. Manual edits welcome.

## Orchestration

| Parameter | Value | Description |
|-----------|-------|-------------|
| max_fix_loops | 3 | Max VERIFY fix attempts before escalating to user |
| max_review_loops | 2 | Max REVIEW iterations before escalating to user |
| auto_proceed_risk | MEDIUM | Highest risk level at which pipeline proceeds without asking (LOW, MEDIUM, HIGH, ALL) |
| parallel_impl_threshold | 3 | Dispatch parallel sub-agents when >= N independent implementation steps |
| total_retries_max | 10 | Global retry budget across all loops (5-30) |
| oscillation_tolerance | 5 | Score regression tolerance for quality cycles (0-20) |

## Review Agents

| Agent | Enabled | Weight | Notes |
|-------|---------|--------|-------|
| quality-gate | true | primary | GO/NO-GO verdict — orchestrator uses this for ship decision |
| fg-410-code-reviewer | true | secondary | Architecture violations — findings merged into quality-gate |
| fg-411-security-reviewer | true | secondary | Auth/data exposure — findings merged into quality-gate |
| fg-413-frontend-reviewer | true | secondary | Conventions, framework patterns, design system — findings merged into quality-gate |
| fg-419-infra-deploy-reviewer | conditional | secondary | Build, CI/CD, container & orchestration review — dispatched when `build_system`, `ci`, `container`, or `orchestrator` is configured |

<!-- Applicable build-system bindings: bun -->

## Domain Hotspots

Domains that frequently cause issues. Pipeline applies extra verification to these.
Updated automatically by the retrospective.

| Domain | Issue Count | Last Issue | Common Failure |
|--------|-------------|------------|----------------|
| — | 0 | — | — |

## Metrics

Cross-run metrics computed by the retrospective. Used for trend analysis and self-tuning.

| Metric | Value | Trend |
|--------|-------|-------|
| total_runs | 0 | — |
| successful_runs | 0 | — |
| avg_fix_loops | 0.0 | — |
| avg_review_loops | 0.0 | — |
| success_rate | — | — |
| preempt_effectiveness | — | — |

## Auto-Tuning Rules

Applied by the retrospective when updating this config:

1. If `avg_fix_loops` > `max_fix_loops - 0.5` for 3+ consecutive runs -> increment `max_fix_loops` by 1
2. If `avg_fix_loops` < 1.0 for 5+ consecutive runs -> decrement `max_fix_loops` by 1 (min: 2)
3. If a domain appears in hotspots 3+ times -> add a domain-specific PREEMPT to forge-log.md
4. If `success_rate` drops below 60% over last 5 runs -> set `auto_proceed_risk` to LOW (more cautious)
5. If `success_rate` is 100% over last 5 runs -> set `auto_proceed_risk` to HIGH (more autonomous)

To prevent auto-tuning from overwriting a parameter, wrap it in a locked fence:
`<!-- locked -->` ... `<!-- /locked -->`. Locked parameters are skipped by the retrospective.

# Scoring customization (uncomment to override defaults)
# scoring:
#   critical_weight: 20
#   warning_weight: 5
#   info_weight: 2
#   pass_threshold: 80
#   concerns_threshold: 60
#   oscillation_tolerance: 5  # Score regression tolerance for quality cycles (0-20)

# Convergence engine (defaults work for most projects)
# convergence:
#   max_iterations: 8       # Hard safety valve across both phases (3-20)
#   plateau_threshold: 2    # Score delta <= this = "no progress" (0-10)
#   plateau_patience: 2     # Consecutive plateaus before convergence (1-5)
#   target_score: 90        # Score target (80-100, must be >= pass_threshold). Default 90.
#   safety_gate: true       # Run VERIFY after Phase 2

# Sprint orchestration (only relevant for /forge-run --sprint)
# sprint:
#   poll_interval_seconds: 30    # How often to poll per-feature state (10-120)
#   dependency_timeout_minutes: 60  # Max wait for a dependency feature (5-180)

# Shipping gate (evidence-based verification before PR creation)
# shipping:
#   min_score: 90                     # Minimum quality score to ship (pass_threshold-100). Default 90.
#   evidence_review: true             # Dispatch code reviewer in fg-590 (true/false)
#   evidence_max_age_minutes: 30      # Evidence staleness threshold (5-60)

# Config-driven agent selection (per-stage defaults and mode overrides)
# mode_config:
#   stages:
#     explore:
#       agent: "${explore_agents.primary}"
#     plan:
#       agent: "fg-200-planner"
#     implement:
#       agent: "fg-300-implementer"
#     docs:
#       agent: "fg-350-docs-generator"
#   mode_overlays:
#     bugfix:
#       plan:
#         agent: "fg-020-bug-investigator"
#     migration:
#       plan:
#         agent: "fg-160-migration-planner"
#     bootstrap:
#       plan:
#         agent: "fg-050-project-bootstrapper"
#       implement:
#         skip: true

sla:
  stage_defaults:
    explore: 120
    plan: 300
    validate: 120
    implement: 600
    verify: 600
    review: 300
    docs: 180
    ship: 300
    learn: 60
  warn_threshold: 0.8

# Model routing (multi-tier model selection)
model_routing:
  enabled: true
  default_tier: standard
  overrides:
    tier_1_fast:
      - fg-101-worktree-manager
      - fg-102-conflict-resolver
      - fg-130-docs-discoverer
      - fg-135-wiki-generator
      - fg-140-deprecation-refresh
      - fg-310-scaffolder
      - fg-350-docs-generator
      - fg-505-build-verifier
      - fg-710-post-run
    tier_3_premium:
      - fg-010-shaper
      - fg-015-scope-decomposer
      - fg-020-bug-investigator
      - fg-050-project-bootstrapper
      - fg-090-sprint-orchestrator
      - fg-100-orchestrator
      - fg-103-cross-repo-coordinator
      - fg-150-test-bootstrapper
      - fg-160-migration-planner
      - fg-200-planner
      - fg-210-validator
      - fg-300-implementer
      - fg-320-frontend-polisher
      - fg-412-architecture-reviewer

# Explore cache
explore:
  cache_enabled: true
  max_cache_age_runs: 10

# Plan cache
plan_cache:
  enabled: true
  similarity_threshold: 0.6
  max_entries: 20
  max_age_days: 30

# Mutation testing (v1.18+)
mutation_testing:
  enabled: false
  scope: changed_files_only
  max_mutants_per_file: 5
  severity_on_surviving: WARNING
  max_mutants_total: 30
  timeout_multiplier: 2
  categories:
    - boundary_conditions
    - null_handling
    - error_paths
    - logic_inversions

# Deliberation (v1.18+)
quality_gate:
  deliberation: false
  deliberation_threshold: WARNING
  deliberation_timeout: 60

# Visual verification (v1.18+)
visual_verification:
  enabled: false
  dev_server_url: ""
  breakpoints: [375, 768, 1440]
  pages: []

# LSP integration (v1.18+)
lsp:
  enabled: true
  languages: []

# Observability (v1.19+)
observability:
  enabled: true
  export: local
  otel_endpoint: ""
  trace_all_agents: true
  metrics_in_recap: true

# Data classification (v1.19+)
data_classification:
  enabled: true
  redact_artifacts: true
  custom_patterns: []
  pii_detection: true
  block_restricted: true

# Security (v1.19+)
security:
  input_sanitization: true
  tool_call_budget:
    default: 50
    overrides: {}
  anomaly_detection:
    max_calls_per_minute: 30
    max_session_cost_usd: 10
  convention_signatures: true

# Automations (v1.19+)
automations: []

# Background execution (v1.19+)
background:
  alert_timeout_minutes: 60
  poll_interval_seconds: 5
  slack_notifications: true
  progress_update_interval_seconds: 30

# Wiki generation (v1.20+)
wiki:
  enabled: true
  auto_update: true
  include_api_surface: true
  include_data_model: true
  max_module_depth: 3

# Memory discovery (v1.20+)
memory_discovery:
  enabled: true
  max_discoveries_per_run: 5
  min_evidence_files: 3
  auto_promote_after_runs: 3

# Codebase Q&A (v1.20+)
forge_ask:
  enabled: true
  deep_mode: false
  max_source_files: 20
  cache_answers: true

# Implementer inner loop (v2.0+)
implementer:
  inner_loop:
    enabled: true           # Enable/disable inner-loop validation after each TDD cycle. Default: true.
    max_fix_cycles: 3       # Max fix attempts per task within the inner loop. Default: 3. Range: 1-5.
    run_lint: true          # Run lint on changed files after each TDD cycle. Default: true.
    run_tests: true         # Run affected tests after each TDD cycle. Default: true.
    affected_test_cap: 20   # Max test files to run per inner loop invocation. Default: 20. Range: 5-50.
    affected_test_strategy: auto  # Test detection: auto | explore | graph | directory. Default: auto.

    # Check Engine (L0 syntax validation)
    check_engine:
      l0_enabled: true
      l0_languages: [auto]           # auto = detect from file extension
      l0_timeout_ms: 500             # Per-file tree-sitter parse timeout
      l0_block_on_error: true        # Block edits with syntax errors

    # Code Graph (SQLite-based AST graph)
    code_graph:
      enabled: true
      backend: auto                  # auto = SQLite always, Neo4j when available
      incremental: true
      max_file_size_kb: 512
      exclude_patterns: [node_modules, .git, vendor, build, dist, __pycache__]

# Flaky test management (v2.0+)
test_history:
  enabled: true
  flaky_threshold: 0.2          # Flip rate to trigger quarantine
  quarantine_passes: 5          # Consecutive passes to unquarantine
  history_window: 10            # Number of recent results to track
  predictive_selection: true    # Use file associations for test ordering

# Confidence Scoring (v2.0+)
confidence:
  planning_gate: true              # Enable pre-execution gating at PLAN
  autonomous_threshold: 0.7        # HIGH confidence threshold (0.3-0.95)
  pause_threshold: 0.4             # MEDIUM/LOW boundary (0.1-0.7)
  initial_trust: 0.5               # Starting trust level for new projects (0.0-1.0)
  trust_decay: 0.05                # Trust decay per run without interaction (0.0-0.2)

# Context Condensation (v2.0+)
condensation:
  enabled: true
  threshold_pct: 60             # Trigger at this % of context window
  summary_target_tokens: 2000   # Target summary length
  model_tier: fast              # Use fast tier for summarization
  preserve_last_n_findings: 20  # Keep N most recent findings verbatim

# Playbooks (v2.0+)
playbooks:
  enabled: true
  directory: .claude/forge-playbooks
  suggestion_confidence_threshold: MEDIUM

# Living Specifications (v2.0+)
living_specs:
  enabled: true
  drift_detection: true
  auto_update_at_learn: true

# Event Log (v2.0+)
events:
  enabled: true
  retention_days: 90

# Property-Based Testing (v2.0+)
property_testing:
  enabled: false                 # Opt-in
  max_properties_per_function: 5
  timeout_per_property_ms: 10000

# Monorepo (v2.0+)
monorepo:
  tool: auto                     # auto | nx | turborepo | none
  affected_base: origin/main
  scope_to_affected: true

# Accessibility Automation (v2.0+)
accessibility:
  dynamic_checks: true
  cross_browser: false           # Opt-in (adds latency)

# i18n Validation (v2.0+)
i18n:
  enabled: false                 # Opt-in
  source_locale: en
  frameworks: [auto]

# Performance Regression Tracking (v2.0+)
performance_tracking:
  enabled: false                 # Opt-in
  thresholds:
    build_time_pct: 20
    test_duration_pct: 30
    bundle_size_pct: 10

# Next-Task Prediction (v2.0+)
predictions:
  enabled: true
  max_suggestions: 5

# Developer Experience Metrics (v2.0+)
dx_metrics:
  enabled: true

# A2A Protocol (v2.0+)
a2a:
  transport: filesystem          # filesystem (default) | http
  http_port: 9473
  auth_mode: token

# Deployment Strategies (v2.0+)
deployment:
  default_strategy: rolling
  canary_steps: [5, 25, 50, 100]
  metric_threshold:
    error_rate_pct: 1
    latency_p99_ms: 500

# Consumer-Driven Contracts (v2.0+)
contract_testing:
  provider: auto
  can_i_deploy: true

# AI/ML Pipeline (v2.0+)
ml_ops:
  enabled: false                 # Opt-in
  frameworks: [auto]

# Feature Flags (v2.0+)
feature_flags:
  enabled: false                 # Opt-in
  provider: auto
  stale_threshold_days: 30

# Output Compression (v2.0+)
output_compression:
  enabled: true
  default_level: terse
  auto_clarity: true

security:
  untrusted_envelope:
    enabled: true                # FORCED. Setting false emits SEC-INJECTION-DISABLED CRITICAL at PREFLIGHT.
    sources: {}                  # Per-source tier override. Only tightening permitted.
    max_envelope_bytes: 65536    # 64 KiB
    max_aggregate_bytes: 262144  # 256 KiB
  injection_detection:
    enabled: true                # FORCED (same PREFLIGHT rule).
    patterns_file: shared/prompt-injection-patterns.json
    custom_patterns: []
  injection_events:
    retention_runs: 50
