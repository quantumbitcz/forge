---
project_type: android
components:
  language: kotlin
  framework: jetpack-compose
  variant: kotlin
  testing: junit5        # junit5 (default for Android)

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "./gradlew assembleDebug"
  lint: "./gradlew lintDebug detekt"
  test: "./gradlew testDebugUnitTest"
  test_single: "./gradlew testDebugUnitTest --tests"
  format: "./gradlew formatKotlin"
  build_timeout: 180
  test_timeout: 300
  lint_timeout: 90

scaffolder:
  enabled: true
  patterns:
    screen: "ui/screens/{feature}/{Feature}Screen.kt"
    content: "ui/screens/{feature}/{Feature}Content.kt"
    viewmodel: "ui/viewmodels/{Feature}ViewModel.kt"
    uistate: "ui/viewmodels/{Feature}UiState.kt"
    route: "navigation/routes/{Feature}Route.kt"
    repository: "data/repository/{Feature}Repository.kt"
    repository_impl: "data/repository/{Feature}RepositoryImpl.kt"
    datasource: "data/datasource/{Feature}RemoteDataSource.kt"
    di_module: "di/{Feature}Module.kt"
    test: "src/test/java/{package}/{Feature}ViewModelTest.kt"
    ui_test: "src/androidTest/java/{package}/{Feature}ScreenTest.kt"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "MVVM boundaries, no repository calls from composables, no business logic in UI"
    - agent: security-reviewer
      focus: "data handling, PII in logs, insecure storage"
    - agent: frontend-reviewer
      focus: "Compose best practices, recomposition efficiency, accessibility"
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
  command: "./gradlew testDebugUnitTest"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/jetpack-compose/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/jetpack-compose/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/jetpack-compose/testing/${components.testing}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "jetpack-compose"
  - "compose-navigation"
  - "hilt"
  - "kotlin"
  - "kotlinx-coroutines"
  - "material3"
---

## Jetpack Compose Android Context

Jetpack Compose with MVVM architecture and unidirectional data flow. ViewModels expose `StateFlow<UiState>`
collected via `collectAsStateWithLifecycle()`. Composables are stateless — all meaningful state lives in ViewModel.
Hilt for DI throughout. Navigation Compose with type-safe serializable routes.

### Variant: Kotlin (default)
Kotlin coroutines for async operations. `viewModelScope.launch` for ViewModel work.
`StateFlow` updated via `_uiState.update { it.copy(...) }`. Sealed `UiEvent` for one-shot navigation/snackbar events.

Customize `components.variant`, `components.testing`, commands, and scaffolder patterns to match your project.
