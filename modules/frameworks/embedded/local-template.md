---
project_type: embedded
components:
  language: c
  framework: embedded
  variant: c
  testing: ~

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
  inline_checks: []

test_gate:
  command: "make test"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [architecture, memory_safety, real_time, test_strategy, conventions, approach_quality]
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
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "posix"
  - "cmsis"
---

## Embedded C Context

POSIX / bare-metal hybrid with static allocation preferred. Fixed-size buffers,
errno checking, const correctness, header guards, and real-time safety constraints.
Cross-compiled for target hardware; tests run on host via Unity/CMock.

Customize the commands above to match your project's build system (make or cmake).

graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
