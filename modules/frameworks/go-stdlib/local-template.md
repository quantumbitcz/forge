---
project_type: backend
components:
  language: go
  framework: go-stdlib
  variant: go
  testing: go-testing
  persistence: gorm

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "go build ./..."
  lint: "staticcheck ./..."
  lint_alt: "golangci-lint run"
  test: "go test ./..."
  test_single: "go test -run"
  format: "gofmt -w ."
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    handler: "internal/handler/{area}_handler.go"
    service: "internal/service/{area}_service.go"
    repository: "internal/repository/{area}_repository.go"
    model: "internal/model/{area}.go"
    middleware: "internal/middleware/{name}.go"
    test: "internal/{layer}/{area}_{layer}_test.go"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "handler/service/repository layering, interface boundaries"
    - agent: security-reviewer
      focus: "auth, injection, error leaking, input validation"
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
  command: "go test ./..."
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/go-stdlib/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/go-stdlib/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/go-stdlib/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/go-stdlib/persistence/${components.persistence}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "go-std"
  - "testify"
  # Persistence — uncomment based on components.persistence:
  # gorm (default):
  - "gorm"
  # sqlx (uncomment and remove gorm):
  # - "sqlx"
---

## Go/Stdlib Backend Context

Handler/Service/Repository layering with interface-driven design and context propagation.
All exported I/O functions accept context.Context as the first parameter.
Persistence layer configurable via components.persistence.
Error wrapping with %w, table-driven tests, no global mutable state.

Customize the commands above to match your project's router library and build configuration.

graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
