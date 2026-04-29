---
project_type: backend
components:
  language: swift
  framework: vapor
  variant: swift
  testing: xctest
  persistence: fluent
  # build_system: spm           # spm (Swift Package Manager)
  # ci: github-actions         # github-actions | gitlab-ci
  # container: docker          # docker | docker-compose | podman
  # orchestrator: helm         # helm
  code_quality: []
  code_quality_recommended: [swiftlint, swift-format, xcov, docc]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "swift build"
  lint: "swiftlint lint"
  test: "swift test"
  test_single: "swift test --filter"
  format: "swiftlint lint --autocorrect"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    controller: "Sources/App/Controllers/{Entity}Controller.swift"
    model: "Sources/App/Models/{Entity}.swift"
    migration: "Sources/App/Migrations/Create{Entity}.swift"
    middleware: "Sources/App/Middleware/{Name}Middleware.swift"
    dto: "Sources/App/DTOs/{Entity}DTO.swift"
    test: "Tests/AppTests/{Entity}Tests.swift"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: fg-412-architecture-reviewer
      focus: "repository pattern adherence, layer boundaries"
    - agent: fg-411-security-reviewer
      focus: "auth, input validation, secrets exposure"
    - agent: fg-416-performance-reviewer
      focus: "EventLoop blocking, Fluent eager loading, resource management"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "general correctness, maintainability, error handling, DRY/KISS"
    - agent: fg-417-dependency-reviewer
      condition: manifest_changed
      focus: "vulnerable, outdated, unmaintained dependencies"
    - agent: fg-418-docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  inline_checks: []

test_gate:
  command: "swift test"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [architecture, security, edge_cases, test_strategy, conventions, approach_quality, documentation_consistency]
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vapor/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vapor/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vapor/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vapor/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vapor/code-quality/"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/forge-log.md"
config_file: ".claude/forge-config.md"

documentation:
  enabled: true
  output_dir: docs/
  auto_generate:
    readme: true
    architecture: true
    adrs: true
    api_docs: true
    onboarding: true
    changelogs: true
    diagrams: true
    domain_docs: true
    runbooks: false
    user_guides: false
    migration_guides: true
  discovery:
    max_files: 500
    max_file_size_kb: 512
    exclude_patterns: []
  external_sources: []
  export:
    confluence:
      enabled: false
    notion:
      enabled: false
  user_maintained_marker: "<!-- user-maintained -->"

context7_libraries:
  - "swift"
  - "vapor"
  # Persistence (depends on components.persistence):
  - "fluent"
  - "swift-nio"

graph:
  enabled: true           # set to false if Docker is unavailable
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474

# Git conventions (auto-detected or configured by /forge)
git:
  branch_template: "{type}/{ticket}-{slug}"
  branch_types: [feat, fix, refactor, chore]
  slug_max_length: 40
  ticket_source: auto
  commit_format: conventional
  commit_types: [feat, fix, test, refactor, docs, chore, perf, ci]
  commit_scopes: auto
  max_subject_length: 72
  require_scope: false
  sign_commits: false
  # commit_enforcement: external  # Uncomment if project has its own hooks

# Kanban tracking
tracking:
  prefix: FG
  archive_after_days: 90  # Auto-archive done/ tickets (30-365, 0=disabled)
  # enabled: true  # Set to false to disable tracking
---

## Swift/Vapor Backend Context

Server-side Swift with Vapor framework. Repository pattern for data access,
persistence configurable via `components.persistence`, async/await throughout.
DTOs conform to Content protocol. Middleware handles cross-cutting concerns.

Customize the commands above to match your project's package structure.
