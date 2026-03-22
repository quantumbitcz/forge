---
project_type: frontend
framework: sveltekit
module: typescript-svelte

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
    server_load: "src/routes/{path}/+page.server.ts"
    action: "src/routes/{path}/+page.server.ts"
    store: "src/lib/stores/{name}.svelte.ts"
    api_route: "src/routes/api/{path}/+server.ts"
    test: "src/lib/components/{Name}.test.ts"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: frontend-reviewer
    - agent: frontend-performance-reviewer
      focus: "re-renders, bundle size, code splitting, asset optimization"
      focus: "Svelte 5 rune usage, component patterns, reactivity"
    - agent: security-reviewer
      focus: "server-side auth, input validation, data exposure"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"

test_gate:
  command: "npx vitest run"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/typescript-svelte/conventions.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "svelte"
  - "sveltekit"
  - "typescript"
  - "tailwindcss"
  - "zod"
---

## TypeScript/SvelteKit Frontend Context

SvelteKit file-based routing with Svelte 5 runes ($state, $derived, $effect, $props).
Server-side data loading via +page.server.ts load functions.
Form actions for progressive enhancement. Shared state in .svelte.ts files.

Customize the commands above to match your project's package manager (npm, yarn, pnpm, or bun).
