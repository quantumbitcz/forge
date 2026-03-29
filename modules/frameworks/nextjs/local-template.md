---
project_type: frontend
components:
  language: typescript
  framework: nextjs
  variant: typescript
  testing: vitest
  persistence: prisma
  # build_system: npm          # npm | yarn | pnpm | bun
  # ci: github-actions         # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines
  # container: docker          # docker | docker-compose | podman
  # orchestrator: helm         # helm | docker-swarm | argocd | fluxcd

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
    - agent: frontend-design-reviewer
      focus: "design tokens, spatial hierarchy, responsive, dark mode, visual coherence"
    - agent: frontend-a11y-reviewer
      focus: "WCAG 2.2 AA deep audit, color contrast, ARIA tree, touch targets"
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
    - agent: docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
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
  perspectives: [architecture, security, edge_cases, test_strategy, conventions, approach_quality, documentation_consistency]
  max_validation_retries: 2

implementation:
  parallel_threshold: 3
  max_fix_loops: 3
  tdd: true
  scaffolder_before_impl: true

frontend_polish:
  enabled: true
  aesthetic_direction: ""
  viewport_targets: [375, 768, 1280]

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
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/nextjs/persistence/${components.persistence}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
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
  - "next"
  - "react"
  - "react-dom"
  - "zod"
  # Persistence (depends on components.persistence):
  - "prisma"
  - "msw"
---

## Next.js Frontend Context

Next.js App Router with TypeScript. Default to Server Components; add `"use client"` only when interactivity is required.
Server Actions for mutations (always validate with Zod). `next/image` for all images. Metadata API (never `next/head`).

Customize the commands above to match your project's package manager and scripts.

graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
