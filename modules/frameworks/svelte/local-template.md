---
project_type: frontend
components:
  language: typescript
  framework: svelte
  variant: typescript
  testing: vitest
  # build_system: bun           # bun
  # ci: github-actions           # github-actions | gitlab-ci
  # container: docker            # docker
  # orchestrator: ~              # N/A for standalone SPA
  code_quality: []
  code_quality_recommended: [eslint, prettier, istanbul, npm-audit]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "npm run build"
  lint: "npx eslint . && npx svelte-check --tsconfig ./tsconfig.json"
  test: "npx vitest run"
  test_single: "npx vitest run"
  format: "npx prettier --write ."
  type_check: "npx svelte-check --tsconfig ./tsconfig.json"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 90

scaffolder:
  enabled: true
  patterns:
    page: "src/pages/{Name}.svelte"
    component: "src/components/{feature}/{Name}.svelte"
    shared_component: "src/components/shared/{Name}.svelte"
    store: "src/stores/{name}.svelte.ts"
    service: "src/services/{name}.service.ts"
    test: "src/components/{feature}/{Name}.test.ts"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: frontend-reviewer
      focus: "Svelte 5 rune usage, callback props, no legacy syntax"
    - agent: frontend-performance-reviewer
      focus: "Bundle size, lazy loading, keyed each blocks, $derived vs $effect"
    - agent: security-reviewer
      focus: "XSS via {@html}, token storage, secrets in VITE_* env vars"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: frontend-design-reviewer
      focus: "CSS custom property tokens, spatial hierarchy, responsive, dark mode, visual coherence"
    - agent: frontend-a11y-reviewer
      focus: "WCAG 2.2 AA deep audit, color contrast, ARIA tree, focus management, touch targets"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
    - agent: docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"

test_gate:
  command: "npx vitest run"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/svelte/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/svelte/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/svelte/testing/${components.testing}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/svelte/code-quality/"
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
  - "svelte"
  - "@sveltejs/vite-plugin-svelte"
  - "typescript"
  - "vitest"
  - "@testing-library/svelte"
  - "vite"

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
  archive_after_days: 90  # Auto-archive done/ tickets (30-365, 0=disabled)
  # enabled: true  # Set to false to disable tracking
---

## Svelte 5 Standalone SPA Context

Standalone Svelte 5 with Vite — no SvelteKit, no SSR, no file-based routing.
Runes (`$state`, `$derived`, `$effect`, `$props`) for all reactive state.
Shared state in `.svelte.ts` files with getter/setter pattern.
Client-side routing via `svelte-routing` or `svelte-navigator`.
Data fetching via service modules + TanStack Query (`@tanstack/svelte-query`) for server state.

Customize the commands above to match your project's package manager (npm, yarn, pnpm, or bun).
Use `svelte-package` in library mode when building a publishable component library.
