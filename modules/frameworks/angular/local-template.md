---
project_type: frontend
components:
  language: typescript
  framework: angular
  variant: typescript
  testing: vitest
  # build_system: bun           # bun
  # ci: github-actions           # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines
  # container: docker            # docker | docker-compose
  # orchestrator: ~              # N/A for standalone frontend

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "npm run build"
  lint: "npm run lint"
  test: "npm run test"
  test_single: "npx vitest run"
  format: "npm run format"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    component: "src/app/features/{feature}/components/{ComponentName}.component.ts"
    page: "src/app/features/{feature}/pages/{feature-name}.page.ts"
    service: "src/app/features/{feature}/{feature-name}.service.ts"
    store: "src/app/features/{feature}/{feature-name}.store.ts"
    model: "src/app/shared/models/{feature-name}.model.ts"
    test: "src/app/features/{feature}/components/{ComponentName}.component.spec.ts"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: frontend-reviewer
    - agent: security-reviewer
      focus: "XSS, injection, secrets exposure, prototype pollution, DomSanitizer bypass"
    - agent: frontend-performance-reviewer
      focus: "OnPush violations, change detection, bundle size, code splitting, @defer usage"
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  batch_2:
    - agent: "Security Engineer"
      source: builtin
      focus: "XSS, injection, localStorage token storage, prototype pollution"
    - agent: "Accessibility Auditor"
      source: builtin
      focus: "WCAG 2.2 AA, keyboard nav, screen reader"
    - agent: frontend-design-reviewer
      focus: "design tokens, spatial hierarchy, responsive, dark mode, visual coherence"
    - agent: frontend-a11y-reviewer
      focus: "WCAG 2.2 AA deep audit, color contrast, ARIA tree, touch targets"
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
  aesthetic_direction: "" # optional: "brutalist", "editorial", "luxury", "playful", etc. Empty = "professional and distinctive"
  viewport_targets: [375, 768, 1280]

risk:
  auto_proceed: MEDIUM

linear:
  enabled: false
  team: ""
  project: ""
  labels: ["pipeline-managed"]

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/angular/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/angular/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/angular/testing/${components.testing}.md"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

context7_libraries:
  - "angular"
  - "@angular/core"
  - "@angular/router"
  - "@angular/forms"
  - "@angular/common/http"
  - "@ngrx/signals"
  - "@ngrx/store"
  - "@angular/cdk"
---

## Angular Frontend Context

Angular 17+ + TypeScript (strict). Standalone components with OnPush change detection.
Signal APIs: `input()`, `output()`, `model()`, `signal()`, `computed()`, `toSignal()`.
NgRx SignalStore for feature state. Lazy-loaded routes via `loadComponent`/`loadChildren`.
`@defer` for below-fold and heavy UI sections.

Customize the commands above to match your project's package manager and scripts.

graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
