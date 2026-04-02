---
project_type: backend
components:
  language: kotlin          # kotlin | java
  framework: spring
  variant: kotlin           # kotlin | java (matches language)
  testing: kotest           # kotest | junit5
  web: mvc                  # mvc | webflux
  persistence: hibernate    # hibernate | r2dbc | jooq | exposed
  # build_system: gradle      # gradle | maven
  # ci: github-actions         # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines | tekton
  # container: docker          # docker | docker-compose | podman
  # orchestrator: helm         # helm | k3s | microk8s | openshift | rancher | argocd | fluxcd
  code_quality: []
  code_quality_recommended: [detekt, ktlint, jacoco, dokka, owasp-dependency-check, spotless, pitest]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "./gradlew build -x test"
  lint: "./gradlew lintKotlin detekt"
  test: "./gradlew test"
  test_single: "./gradlew :app:test --tests"
  format: "./gradlew formatKotlin"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    domain_model: "core/domain/{area}/{Entity}.kt"
    use_case: "core/input/usecase/{area}/I{Operation}{Entity}UseCase.kt"
    use_case_impl: "core/impl/{area}/I{Operation}{Entity}UseCaseImpl.kt"
    port: "core/output/port/{area}/I{Operation}{Entity}Port.kt"
    entity: "adapter/output/persistence/entity/{area}/{Entity}Entity.kt"
    mapper: "adapter/output/persistence/mapper/{area}/{Entity}Mapper.kt"
    repository: "adapter/output/persistence/repository/{area}/{Entity}Repository.kt"
    adapter: "adapter/output/persistence/adapter/{area}/{Operation}{Entity}PersistenceAdapter.kt"
    controller: "adapter/input/api/controller/{Entity}Controller.kt"
    api_mapper: "adapter/input/api/mapper/{Entity}Mapper.kt"
    migration: "adapter/output/persistence/resources/db/migration/V{N}__{description}.sql"
    test: "app/src/test/api/{Entity}ApiTests.kt"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "architecture pattern violations"
    - agent: security-reviewer
      focus: "auth, ownership, injection, data exposure"
    - agent: backend-performance-reviewer
      focus: "N+1 queries, blocking I/O, algorithm complexity, DB efficiency"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
    - agent: docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "./gradlew test"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/testing/${components.testing}.md"
conventions_web: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/web/${components.web}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/code-quality/"
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
  - "spring-boot"
  - "kotlin"
  # Web stack — uncomment ONE:
  # mvc (default):
  - "spring-web"
  # webflux (uncomment and remove spring-web):
  # - "spring-webflux"
  # - "kotlinx-coroutines"
  # Persistence — uncomment ONE:
  # hibernate (default):
  - "spring-data-jpa"
  # r2dbc (uncomment and remove spring-data-jpa):
  # - "spring-data-r2dbc"

graph:
  enabled: true           # set to false if Docker is unavailable
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
---

## Spring Boot Backend Context

Spring Boot with hexagonal / clean architecture. Transaction boundaries owned by services/use cases.
DTOs at controller boundary; entities never leak to API. Constructor injection only.

Web stack and persistence are independent choices configured via `components.web` and
`components.persistence`. Customize these along with `components.language`, `components.variant`,
`components.testing`, commands, and scaffolder patterns to match your project.

### Common Stack Combinations

| Stack | `web:` | `persistence:` | Notes |
|-------|--------|----------------|-------|
| Traditional | mvc | hibernate | Blocking, JPA, thread-per-request |
| Reactive | webflux | r2dbc | Non-blocking, coroutines (Kotlin) or Reactor (Java) |
| Type-safe SQL | mvc | jooq | Blocking, generated DSL, no ORM |
| Kotlin DSL | mvc | exposed | Blocking, Kotlin-native table DSL |
| Mixed | webflux | jooq | Reactive web + blocking DB on boundedElastic |
