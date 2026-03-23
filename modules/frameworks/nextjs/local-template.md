---
project_type: frontend
components:
  language: typescript
  framework: nextjs
  variant: typescript
  testing: vitest

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "npm run build"
  lint: "npm run lint"
  test: "npm run test"
  test_single: "npx vitest run"
  format: "npm run format"
  build_timeout: 180
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    page: "app/{route}/page.tsx"
    layout: "app/{route}/layout.tsx"
    loading: "app/{route}/loading.tsx"
    error: "app/{route}/error.tsx"
    route_handler: "app/api/{resource}/route.ts"
    server_action: "actions/{domain}.ts"
    component: "app/components/{feature}/{ComponentName}.tsx"
    hook: "app/components/{feature}/use-{hook-name}.ts"
    types: "app/types/{domain}.ts"
    test: "tests/{feature}/{ComponentName}.test.tsx"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: frontend-reviewer
      focus: "Server vs Client component boundaries, SSR/SSG correctness, metadata"
    - agent: security-reviewer
      focus: "Server Action input validation, NEXT_PUBLIC_ secrets, CSRF, XSS"
    - agent: frontend-performance-reviewer
      focus: "Client Component boundaries, bundle size, image optimization, streaming"
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  batch_2:
    - agent: "Security Engineer"
      source: builtin
      focus: "Server Action authorization, Route Handler auth, env var exposure"
    - agent: "Accessibility Auditor"
      source: builtin
      focus: "WCAG 2.2 AA, keyboard nav, screen reader"
    - agent: "pr-review-toolkit:silent-failure-hunter"
      source: plugin
      focus: "swallowed errors, empty catch, missing error.tsx boundaries"
  batch_3:
    - agent: "pr-review-toolkit:code-simplifier"
      source: plugin
      focus: "unnecessary Client Components, over-engineering"
    - agent: "pr-review-toolkit:type-design-analyzer"
      source: plugin
      focus: "Server Action types, page prop types, discriminated unions"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "npm run test"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nextjs/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nextjs/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nextjs/testing/${components.testing}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "next"
  - "react"
  - "react-dom"
  - "zod"
  - "msw"
---

## Next.js Frontend Context

Next.js App Router with TypeScript. Default to Server Components; add `"use client"` only when interactivity is required.
Server Actions for mutations (always validate with Zod). `next/image` for all images. Metadata API (never `next/head`).

Customize the commands above to match your project's package manager and scripts.
