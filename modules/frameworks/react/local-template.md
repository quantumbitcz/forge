---
project_type: frontend
components:
  language: typescript
  framework: react
  variant: typescript
  testing: vitest

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "bun run build"
  lint: "bun run lint"
  test: "bun run test"
  test_single: "bunx vitest run"
  format: "bun run format"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    component: "src/app/components/{feature}/{ComponentName}.tsx"
    hook: "src/app/components/{feature}/use-{hook-name}.ts"
    api_module: "src/app/api/{module}.ts"
    types: "src/app/components/{feature}/types.ts"
    test: "src/tests/{feature}/{ComponentName}.test.tsx"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: frontend-reviewer
    - agent: security-reviewer
      focus: "XSS, injection, secrets exposure, prototype pollution"
    - agent: frontend-performance-reviewer
      focus: "re-renders, bundle size, code splitting, asset optimization"
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  batch_2:
    - agent: "Security Engineer"
      source: builtin
      focus: "XSS, injection, localStorage, prototype pollution"
    - agent: "Accessibility Auditor"
      source: builtin
      focus: "WCAG 2.2 AA, keyboard nav, screen reader"
    - agent: "pr-review-toolkit:silent-failure-hunter"
      source: plugin
      focus: "swallowed errors, empty catch, bad fallbacks"
  batch_3:
    - agent: "pr-review-toolkit:code-simplifier"
      source: plugin
      focus: "over-engineering, unnecessary abstractions"
    - agent: "pr-review-toolkit:type-design-analyzer"
      source: plugin
      focus: "type encapsulation, branded types, discriminated unions"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "bun run test"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin
    - agent: "codebase-audit-suite:ln-634-test-coverage-auditor"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/react/conventions.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "react"
  - "recharts"
  - "react-day-picker"
  - "react-dnd"
  - "react-router"
---

## React Frontend Context

React + Vite + TypeScript + shadcn/ui. Theme tokens via CSS custom properties.
Inline fontSize (never Tailwind text-* classes). Radix/shadcn composition pattern.

Customize the commands above to match your project's package manager and scripts.
