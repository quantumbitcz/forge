---
project_type: backend
framework: node
module: typescript-node

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "npm run build"
  lint: "npx eslint ."
  test: "npm test"
  test_single: "npx vitest run"
  format: "npx prettier --write ."

scaffolder:
  enabled: true
  patterns:
    router: "src/routes/{entity}.routes.ts"
    controller: "src/controllers/{entity}.controller.ts"
    service: "src/services/{entity}.service.ts"
    middleware: "src/middleware/{name}.middleware.ts"
    model: "src/models/{entity}.model.ts"
    dto: "src/dto/{entity}.dto.ts"
    migration: "src/migrations/{N}-{description}.ts"
    test: "src/__tests__/{entity}.test.ts"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: be-hex-reviewer
      focus: "layered architecture violations, dependency direction"
    - agent: be-security-reviewer
      focus: "auth, injection, input sanitization, data exposure"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
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
  perspectives: [architecture, security, edge_cases, test_strategy, conventions]
  max_validation_retries: 2

implementation:
  parallel_threshold: 3
  max_fix_loops: 3
  tdd: true
  scaffolder_before_impl: true

risk:
  auto_proceed: MEDIUM

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/typescript-node/conventions.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "express"
  - "nestjs"
  - "prisma"
  - "typescript"
  - "zod"
---

## TypeScript/Node.js Backend Context

Layered architecture (routes -> controllers -> services -> models) with Express or NestJS.
Services own business logic. Input validation at middleware/DTO layer.
ESM imports only — no CommonJS require() in TypeScript files.

Customize the commands above to match your project's package manager (npm, yarn, pnpm, or bun).
