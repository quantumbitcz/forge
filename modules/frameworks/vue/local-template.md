---
project_type: frontend
components:
  language: typescript
  framework: vue
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
    page: "pages/{route}.vue"
    layout: "layouts/{name}.vue"
    component: "components/{Feature}/{ComponentName}.vue"
    composable: "composables/use{Name}.ts"
    store: "stores/{domain}.ts"
    server_route: "server/api/{resource}.{method}.ts"
    middleware: "middleware/{name}.ts"
    plugin: "plugins/{name}.ts"
    test: "{directory}/{ComponentName}.test.ts"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: frontend-reviewer
      focus: "Composition API usage, SSR safety, useFetch patterns, Pinia store structure"
    - agent: security-reviewer
      focus: "Server route input validation, runtimeConfig secrets, v-html usage, auth middleware"
    - agent: frontend-performance-reviewer
      focus: "useLazyFetch for non-critical data, NuxtImg, shallowRef for large data, bundle size"
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  batch_2:
    - agent: "Security Engineer"
      source: builtin
      focus: "Server route authorization, runtimeConfig public exposure, XSS via v-html"
    - agent: "Accessibility Auditor"
      source: builtin
      focus: "WCAG 2.2 AA, keyboard nav, screen reader"
    - agent: frontend-design-reviewer
      focus: "design tokens, spatial hierarchy, responsive, dark mode, visual coherence"
    - agent: frontend-a11y-reviewer
      focus: "WCAG 2.2 AA deep audit, color contrast, ARIA tree, touch targets"
    - agent: "pr-review-toolkit:silent-failure-hunter"
      source: plugin
      focus: "swallowed errors, empty catch, missing error handling in useFetch"
  batch_3:
    - agent: "pr-review-toolkit:code-simplifier"
      source: plugin
      focus: "unnecessary complexity, Options API remnants, over-engineered composables"
    - agent: "pr-review-toolkit:type-design-analyzer"
      source: plugin
      focus: "defineProps generics, defineEmits types, Pinia store types, composable return types"
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
  perspectives: [architecture, security, edge_cases, test_strategy, conventions, approach_quality]
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vue/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vue/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/vue/testing/${components.testing}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "nuxt"
  - "vue"
  - "@pinia/nuxt"
  - "zod"
  - "@nuxt/image"
  - "@vue/test-utils"
---

## Vue 3 / Nuxt 3 Frontend Context

Nuxt 3 with TypeScript. Use `<script setup lang="ts">` exclusively — no Options API. Leverage Nuxt auto-imports (do not manually import Vue/Nuxt core APIs). `useFetch` with stable keys for SSR-safe data fetching. Pinia Setup Stores for global state. Zod validation in all server routes. `<NuxtImg>` for images, `<NuxtLink>` for internal navigation.

Customize the commands above to match your project's package manager and scripts.
