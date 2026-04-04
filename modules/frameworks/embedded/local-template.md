---
project_type: embedded
components:
  language: c
  framework: embedded
  variant: c
  testing: ~
  # build_system: cmake          # cmake
  # ci: github-actions           # github-actions | gitlab-ci
  # container: ~                 # N/A for embedded firmware
  # orchestrator: ~              # N/A for embedded firmware
  code_quality: []
  code_quality_recommended: [clang-tidy, cppcheck, llvm-cov, doxygen]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "make"
  build_alt: "cmake --build build"
  lint: "clang-tidy src/*.c"
  test: "make test"
  test_alt: "ctest --test-dir build"
  format: "clang-format -i src/**/*.c src/**/*.h"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    module: "src/{layer}/{module}/{module}.c + include/{module}/{module}.h"
    test: "test/test_{module}.c"
    driver: "src/drivers/{device}/{device}.c + include/drivers/{device}.h"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: security-reviewer
      focus: "buffer overflows, format strings, integer overflows, use-after-free"
    - agent: backend-performance-reviewer
      focus: "ISR allocation, cache-friendly access, busy-wait loops, volatile usage"
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, memory safety, const correctness"
  batch_2:
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
    - agent: docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
  inline_checks: []

test_gate:
  command: "make test"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [architecture, memory_safety, real_time, test_strategy, conventions, approach_quality, documentation_consistency]
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/embedded/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/embedded/variants/${components.variant}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/embedded/code-quality/"
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
  - "posix"
  - "cmsis"

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
  # enabled: true  # Set to false to disable tracking
---

## Embedded C Context

POSIX / bare-metal hybrid with static allocation preferred. Fixed-size buffers,
errno checking, const correctness, header guards, and real-time safety constraints.
Cross-compiled for target hardware; tests run on host via Unity/CMock.

Customize the commands above to match your project's build system (make or cmake).
