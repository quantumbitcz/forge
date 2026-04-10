---
project_type: backend
components:
  language: typescript
  framework: nestjs
  variant: typescript
  testing: vitest
  persistence: typeorm       # typeorm | prisma | mongoose
  # build_system: npm          # npm | yarn | pnpm | bun
  # ci: github-actions         # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines | tekton
  # container: docker          # docker | docker-compose | podman
  # orchestrator: helm         # helm | docker-swarm | argocd | fluxcd
  code_quality: []
  code_quality_recommended: [eslint, prettier, istanbul, typedoc, npm-audit, stryker]

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
    - agent: fg-412-architecture-reviewer
      focus: "module boundaries, dependency direction, DI patterns, single responsibility"
    - agent: fg-411-security-reviewer
      focus: "auth guards, injection, input sanitization, data exposure via DTOs"
    - agent: fg-416-backend-performance-reviewer
      focus: "N+1 queries, blocking I/O, missing indexes, algorithm complexity"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "general correctness, maintainability, error handling, DRY/KISS"
    - agent: fg-420-dependency-reviewer
      condition: manifest_changed
      focus: "vulnerable, outdated, unmaintained dependencies"
    - agent: fg-418-docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "npm test"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nestjs/code-quality/"
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

graph:
  enabled: true           # set to false if Docker is unavailable
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474

# Git conventions (auto-detected or configured by /forge-init)
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

## NestJS Backend Context

Module-based architecture with explicit DI wiring. Controllers are thin request/response adapters;
all business logic lives in services. Validation via `ValidationPipe` with `class-validator` DTOs.
Never read `process.env` directly — always use `ConfigService`. Never use `console.log` — use NestJS `Logger`.

Persistence layer is configurable via `components.persistence` (typeorm, prisma, mongoose).
Customize the commands above to match your project's package manager (npm, yarn, pnpm, or bun).
