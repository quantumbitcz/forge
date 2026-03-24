---
project_type: backend
components:
  language: kotlin          # kotlin | java
  framework: spring
  variant: kotlin           # kotlin | java (matches language)
  testing: kotest           # kotest | junit5-assertj

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
    entity: "adapter/output/postgresql/entity/{area}/{Entity}Entity.kt"
    mapper: "adapter/output/postgresql/mapper/{area}/{Entity}Mapper.kt"
    repository: "adapter/output/postgresql/repository/{area}/{Entity}Repository.kt"
    adapter: "adapter/output/postgresql/adapter/{area}/{Operation}{Entity}PersistenceAdapter.kt"
    controller: "adapter/input/api/controller/{Entity}Controller.kt"
    api_mapper: "adapter/input/api/mapper/{Entity}Mapper.kt"
    migration: "adapter/output/postgresql/resources/db/migration/V{N}__{description}.sql"
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
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "./gradlew test"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/spring/testing/${components.testing}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "spring-boot"
  - "spring-webflux"
  - "spring-data-r2dbc"
  - "kotlin"
  - "kotlinx-coroutines"
---

## Spring Boot Backend Context

Spring Boot with hexagonal / clean architecture. Transaction boundaries owned by services/use cases.
DTOs at controller boundary; entities never leak to API. Constructor injection only.

### Variant: Kotlin (default)
Reactive stack (WebFlux + R2DBC). All use cases and ports are suspend functions.
Domain uses typed IDs (`kotlin.uuid.Uuid`). Persistence uses `CoroutineCrudRepository`.

### Variant: Java
Blocking stack (WebMVC + JPA). Services own `@Transactional` boundaries.
Records for DTOs. `Optional<T>` for nullable repository returns.

Customize `components.language`, `components.variant`, `components.testing`, commands,
and scaffolder patterns to match your project.
