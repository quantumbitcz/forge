---
project_type: backend
framework: kotlin-spring-boot
module: kotlin-spring

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
  perspectives: [architecture, security, edge_cases, test_strategy, conventions]
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/kotlin-spring/conventions.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "spring-boot"
  - "spring-webflux"
  - "spring-data-r2dbc"
  - "kotlin"
  - "kotlinx-coroutines"
---

## Kotlin/Spring Backend Context

Hexagonal architecture (ports & adapters) with reactive stack (WebFlux + R2DBC).
All use cases and ports are suspend functions. Domain uses typed IDs (kotlin.uuid.Uuid).
Persistence uses Spring Data CoroutineCrudRepository.

Customize the commands above to match your project's Gradle module names.
