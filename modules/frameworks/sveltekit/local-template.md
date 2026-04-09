---
project_type: frontend
components:
  language: typescript
  framework: sveltekit
  variant: typescript
  testing: vitest
  # build_system: bun           # bun
  # ci: github-actions           # github-actions | gitlab-ci
  # container: docker            # docker | docker-compose | docker-swarm | podman
  # orchestrator: helm           # helm
  code_quality: []
  code_quality_recommended: [eslint, prettier, istanbul, npm-audit]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "npm run build"
  lint: "npx eslint ."
  test: "npx vitest run"
  test_single: "npx vitest run"
  format: "npx prettier --write ."
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    page: "src/routes/{path}/+page.svelte"
    page_server: "src/routes/{path}/+page.server.ts"
    page_load: "src/routes/{path}/+page.ts"
    layout: "src/routes/{path}/+layout.svelte"
    layout_server: "src/routes/{path}/+layout.server.ts"
    component: "src/lib/components/{Name}.svelte"
    store: "src/lib/stores/{name}.svelte.ts"
    api_route: "src/routes/api/{path}/+server.ts"
    test: "src/lib/components/{Name}.test.ts"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: fg-413-frontend-reviewer
    - agent: fg-413-frontend-reviewer
      mode: a11y-only
      focus: "WCAG 2.2 AA deep audit, color contrast, ARIA tree, touch targets"
    - agent: fg-411-security-reviewer
      focus: "server-side auth, input validation, data exposure"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
    - agent: fg-418-docs-consistency-reviewer
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/sveltekit/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/sveltekit/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/sveltekit/testing/${components.testing}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/sveltekit/code-quality/"
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
  - "sveltekit"
  - "typescript"
  - "tailwindcss"
  - "zod"

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

## SvelteKit Frontend Context

SvelteKit file-based routing with Svelte 5 runes ($state, $derived, $effect, $props).
Server-side data loading via +page.server.ts load functions.
Form actions for progressive enhancement. Shared state in .svelte.ts files.

Customize the commands above to match your project's package manager (npm, yarn, pnpm, or bun).
