---
project_type: backend
framework: spring-boot
module: java-spring

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "./gradlew build -x test"
  lint: "./gradlew checkstyleMain"
  test: "./gradlew test"
  test_single: "./gradlew test --tests"
  format: ""

scaffolder:
  enabled: true
  patterns:
    entity: "src/main/java/com/example/{app}/entity/{Entity}.java"
    repository: "src/main/java/com/example/{app}/repository/{Entity}Repository.java"
    service: "src/main/java/com/example/{app}/service/{Entity}Service.java"
    service_impl: "src/main/java/com/example/{app}/service/impl/{Entity}ServiceImpl.java"
    controller: "src/main/java/com/example/{app}/controller/{Entity}Controller.java"
    dto_request: "src/main/java/com/example/{app}/dto/Create{Entity}Request.java"
    dto_response: "src/main/java/com/example/{app}/dto/{Entity}Response.java"
    mapper: "src/main/java/com/example/{app}/mapper/{Entity}Mapper.java"
    migration: "src/main/resources/db/migration/V{N}__{description}.sql"
    test: "src/test/java/com/example/{app}/controller/{Entity}ControllerTest.java"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "architecture pattern violations, dependency direction"
    - agent: be-security-reviewer
      focus: "auth, ownership, injection, data exposure"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"

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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/java-spring/conventions.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "spring-boot"
  - "spring-data-jpa"
  - "spring-security"
  - "hibernate"
---

## Java/Spring Boot Backend Context

Layered architecture (controller -> service -> repository) with Spring Data JPA.
Services own transaction boundaries. DTOs at controller boundary; entities never leak to API.
Constructor injection only — no field @Autowired.

Customize the commands above to match your project's build tool (Gradle or Maven).
