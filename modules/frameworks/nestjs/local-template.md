---
project_type: backend
components:
  language: typescript
  framework: nestjs
  variant: typescript
  testing: vitest
  persistence: typeorm       # typeorm | prisma | mongoose

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "npm run build"
  lint: "npx eslint ."
  test: "npm test"
  test_single: "npx vitest run"
  format: "npx prettier --write ."
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    module: "src/{entity}/{entity}.module.ts"
    controller: "src/{entity}/{entity}.controller.ts"
    service: "src/{entity}/{entity}.service.ts"
    guard: "src/common/guards/{name}.guard.ts"
    interceptor: "src/common/interceptors/{name}.interceptor.ts"
    filter: "src/common/filters/{name}.filter.ts"
    pipe: "src/common/pipes/{name}.pipe.ts"
    middleware: "src/common/middleware/{name}.middleware.ts"
    dto_create: "src/{entity}/dto/create-{entity}.dto.ts"
    dto_update: "src/{entity}/dto/update-{entity}.dto.ts"
    dto_response: "src/{entity}/dto/{entity}-response.dto.ts"
    entity: "src/{entity}/{entity}.entity.ts"
    test_unit: "src/{entity}/{entity}.service.spec.ts"
    test_e2e: "test/{entity}.e2e-spec.ts"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "module boundaries, dependency direction, DI patterns, single responsibility"
    - agent: security-reviewer
      focus: "auth guards, injection, input sanitization, data exposure via DTOs"
    - agent: backend-performance-reviewer
      focus: "N+1 queries, blocking I/O, missing indexes, algorithm complexity"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability, NestJS idioms"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"

test_gate:
  command: "npm test"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/persistence/${components.persistence}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "nestjs"
  - "nestjs/config"
  - "nestjs/swagger"
  - "nestjs/passport"
  - "class-validator"
  - "class-transformer"
  - "typescript"
  # Persistence — uncomment based on components.persistence:
  # typeorm (default):
  - "nestjs/typeorm"
  # prisma (uncomment and remove nestjs/typeorm):
  # - "prisma"
  # mongoose (uncomment and remove nestjs/typeorm):
  # - "nestjs/mongoose"
---

## NestJS Backend Context

Module-based architecture with explicit DI wiring. Controllers are thin request/response adapters;
all business logic lives in services. Validation via `ValidationPipe` with `class-validator` DTOs.
Never read `process.env` directly — always use `ConfigService`. Never use `console.log` — use NestJS `Logger`.

Persistence layer is configurable via `components.persistence` (typeorm, prisma, mongoose).
Customize the commands above to match your project's package manager (npm, yarn, pnpm, or bun).
