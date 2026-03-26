---
project_type: backend
components:
  language: rust
  framework: axum
  variant: rust
  testing: rust-test
  persistence: sqlx        # sqlx (default) | diesel

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "cargo build"
  lint: "cargo clippy"
  test: "cargo test"
  test_single: "cargo test --test"
  format: "cargo fmt"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    handler: "src/handler/{area}.rs"
    service: "src/service/{area}.rs"
    model: "src/model/{area}.rs"
    migration: "migrations/{timestamp}_{description}.sql"
    middleware: "src/middleware/{name}.rs"
    test: "tests/{area}_test.rs"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "handler/service layering, state management, error handling"
    - agent: security-reviewer
      focus: "auth, unsafe usage, input validation, error leaking"
    - agent: backend-performance-reviewer
      focus: "N+1 queries, blocking I/O, algorithm complexity, DB efficiency"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"

test_gate:
  command: "cargo test"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [architecture, security, edge_cases, test_strategy, conventions, approach_quality]
  max_validation_retries: 2

implementation:
  parallel_threshold: 3
  max_fix_loops: 3
  tdd: true
  scaffolder_before_impl: true

risk:
  auto_proceed: MEDIUM

linear:
  enabled: false
  team: ""
  project: ""
  labels: ["pipeline-managed"]

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/axum/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/axum/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/axum/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/axum/persistence/${components.persistence}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "axum"
  - "tokio"
  - "serde"
  - "tower"
  - "thiserror"
  # Persistence (depends on components.persistence):
  - "sqlx"              # sqlx (default)
  # - "diesel"          # uncomment if persistence: diesel
---

## Rust/Axum Backend Context

Handler functions with typed extractors, Tower middleware, shared state via Arc<AppState>.
Error handling with thiserror + IntoResponse. Persistence layer configurable via `components.persistence`.
All I/O is async on Tokio runtime -- no blocking calls in handlers.

Customize the commands above to match your project's workspace and feature flags.
