---
project_type: backend
components:
  language: typescript
  framework: express
  variant: typescript
  testing: vitest
  persistence: prisma        # prisma | typeorm | drizzle | mongoose
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
    - agent: fg-412-architecture-reviewer
      focus: "architecture pattern violations, dependency direction"
    - agent: fg-411-security-reviewer
      focus: "auth, injection, input sanitization, data exposure"
    - agent: fg-416-performance-reviewer
      focus: "N+1 queries, blocking I/O, algorithm complexity, DB efficiency"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/express/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/express/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/express/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/express/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/express/code-quality/"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/forge-log.md"
config_file: ".claude/forge-admin config.md"

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
  - "express"
  - "typescript"
  - "zod"
  # Persistence — uncomment based on components.persistence:
  # prisma (default):
  - "prisma"
  # typeorm (uncomment and remove prisma):
  # - "typeorm"
  # drizzle (uncomment and remove prisma):
  # - "drizzle-orm"
  # mongoose (uncomment and remove prisma):
  # - "mongoose"

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

## TypeScript/Node.js Backend Context

Layered architecture (routes -> controllers -> services -> models) with Express.
Services own business logic. Input validation at middleware/DTO layer.
ESM imports only -- no CommonJS require() in TypeScript files.

Persistence layer is configurable via `components.persistence` (prisma, typeorm, drizzle, mongoose).
Customize the commands above to match your project's package manager (npm, yarn, pnpm, or bun).
