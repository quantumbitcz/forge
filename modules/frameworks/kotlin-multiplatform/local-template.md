---
project_type: multiplatform
components:
  shared:
    path: "shared/"
    language: kotlin
    framework: kotlin-multiplatform
    variant: kotlin
    testing: kotest
    persistence: sqldelight
    # build_system: gradle       # gradle
    # ci: github-actions         # github-actions | gitlab-ci
    # container: ~               # N/A for multiplatform library
    # orchestrator: ~            # N/A for multiplatform library
  code_quality: []
  code_quality_recommended: [detekt, ktlint, jacoco, dokka, owasp-dependency-check, spotless]
    commands:
      build: "./gradlew :shared:build"
      test: "./gradlew :shared:allTests"
      lint: "./gradlew :shared:lintKotlin detekt"
  android:
    path: "androidApp/"
    language: kotlin
    framework: jetpack-compose
    variant: kotlin
    testing: junit5
    commands:
      build: "./gradlew :androidApp:assembleDebug"
      test: "./gradlew :androidApp:testDebugUnitTest"
      lint: "./gradlew :androidApp:lintDebug"
  ios:
    path: "iosApp/"
    language: swift
    framework: swiftui
    variant: swift
    testing: xctest
    commands:
      build: "xcodebuild build -scheme iosApp -sdk iphonesimulator"
      test: "xcodebuild test -scheme iosApp -destination 'platform=iOS Simulator,name=iPhone 15'"

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "./gradlew build"
  lint: "./gradlew lintKotlin detekt"
  test: "./gradlew allTests"
  test_single: "./gradlew :shared:allTests --tests"
  format: "./gradlew formatKotlin"
  build_timeout: 300
  test_timeout: 600
  lint_timeout: 90

scaffolder:
  enabled: true
  patterns:
    domain_model: "shared/src/commonMain/kotlin/{package}/domain/{Entity}.kt"
    repository_interface: "shared/src/commonMain/kotlin/{package}/data/repository/{Entity}Repository.kt"
    repository_impl: "shared/src/commonMain/kotlin/{package}/data/repository/{Entity}RepositoryImpl.kt"
    api_service: "shared/src/commonMain/kotlin/{package}/data/remote/{Entity}ApiService.kt"
    koin_module: "shared/src/commonMain/kotlin/{package}/di/{feature}Module.kt"
    expect_class: "shared/src/commonMain/kotlin/{package}/platform/{Platform}.kt"
    actual_android: "shared/src/androidMain/kotlin/{package}/platform/{Platform}.kt"
    actual_ios: "shared/src/iosMain/kotlin/{package}/platform/{Platform}.kt"
    test: "shared/src/commonTest/kotlin/{package}/{Entity}Test.kt"
    fake: "shared/src/commonTest/kotlin/{package}/fakes/Fake{Entity}.kt"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "source set boundary violations, JVM-only imports in commonMain, actual/expect misuse"
    - agent: security-reviewer
      focus: "data handling, key storage, certificate pinning"
    - agent: backend-performance-reviewer
      focus: "coroutine scope management, blocking calls on wrong dispatcher, SQLDelight query efficiency"
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
  command: "./gradlew allTests"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/kotlin-multiplatform/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/kotlin-multiplatform/variants/${components.shared.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/kotlin-multiplatform/testing/${components.shared.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/kotlin-multiplatform/persistence/${components.shared.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/kotlin-multiplatform/code-quality/"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.shared.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

documentation:
  enabled: true
  output_dir: docs/
  auto_generate:
    readme: true
    architecture: true
    adrs: true
    api_docs: false
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
  - "kotlin-multiplatform"
  - "ktor-client"
  - "kotlinx-serialization"
  - "kotlinx-coroutines"
  - "koin"
  # Persistence (depends on components.persistence):
  - "sqldelight"
---

## Kotlin Multiplatform Context

KMP project with shared business logic in `commonMain`. Platform UIs (Android/iOS/Web) consume shared
repositories, use cases, and view models. Ktor for networking, `kotlinx.serialization` for JSON,
cross-platform persistence (configurable via `components.persistence`), Koin for DI.

### Shared Module (default)
`commonMain` contains domain models, repository interfaces, implementations, Ktor API services,
and Koin modules. `expect`/`actual` for platform-specific capabilities (logging, crypto, file I/O).

### Platform Modules
Android and iOS apps consume `shared` as a Gradle dependency / XCFramework respectively.
Each platform provides `actual` implementations and wires Koin platform modules at startup.

Customize `components`, `commands`, and `scaffolder.patterns` to match your project layout.

graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
