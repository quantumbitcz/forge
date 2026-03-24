---
project_type: backend
components:
  language: swift
  framework: vapor
  variant: swift
  testing: xctest

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
    - agent: architecture-reviewer
      focus: "repository pattern adherence, layer boundaries"
    - agent: security-reviewer
      focus: "auth, input validation, secrets exposure"
    - agent: backend-performance-reviewer
      focus: "EventLoop blocking, Fluent eager loading, resource management"
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, repository pattern adherence"
  batch_2:
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vapor/conventions.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "swift"
  - "vapor"
  - "fluent"
  - "swift-nio"
---

## Swift/Vapor Backend Context

Server-side Swift with Vapor framework. Repository pattern for data access,
Fluent ORM for persistence, async/await throughout. DTOs conform to Content protocol.
Middleware handles cross-cutting concerns.

Customize the commands above to match your project's package structure.
