---
project_type: backend
components:
  language: go
  framework: gin
  variant: go
  testing: go-testing
  persistence: gorm

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "go build ./..."
  lint: "golangci-lint run"
  lint_alt: "go vet ./..."
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
    router: "internal/router/router.go"
    migration: "migrations/{N}_{description}.up.sql"
    test: "internal/{layer}/{area}_{layer}_test.go"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "handler/service/repository layering, interface boundaries, no global state"
    - agent: security-reviewer
      focus: "input validation, SQL injection, JWT auth, CORS, rate limiting"
    - agent: backend-performance-reviewer
      focus: "connection pooling, context timeouts, N+1 queries, goroutine leaks"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/gin/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/gin/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/gin/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/gin/persistence/${components.persistence}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "gin"
  - "go-std"
  - "testify"
  - "testcontainers-go"
  # Persistence — uncomment based on components.persistence:
  # gorm (default):
  - "gorm"
  - "golang-migrate"
  # sqlx (uncomment and remove gorm):
  # - "sqlx"          # uncomment if persistence: sqlx
---

## Go + Gin Backend Context

Handler/Service/Repository layering with interface-driven design. gin.New() with explicit middleware
(never gin.Default()). ShouldBindJSON for all request parsing. Typed request/response structs.
Centralized error handling via middleware. No global state; all dependencies wired in main().

Customize the commands above to match your project's Go version and available linters.
